import Foundation


@main struct SessionRegression {
    @MainActor static func main() async throws {
        let sharedAPI = AIAPIClient()
        let sharedState = AIChatState(apiClient: sharedAPI, authSession: CognitoAuthSession(), configurationErrorMessage: nil)
        await sharedState.loadList()
        sharedState.choose(sharedAPI.model)
        let saved = await sharedState.saveSharing(AISharing(enabled: true, modelId: sharedAPI.model.id, contextLength: 65536, revision: 1))
        precondition(saved && sharedState.sharedMode)
        sharedState.saveSettings(AISettings(contextLength: 131072, maxOutputTokens: 1024, reasoningEffort: "low"))
        precondition(sharedState.settings?.contextLength == 65536)
        sharedState.composerText = "shared draft"
        sharedAPI.sharingValue.enabled = false; sharedAPI.sharingValue.revision += 1
        let changed = await sharedState.send(conversationId: nil)
        precondition(changed == nil && sharedState.composerText == "shared draft")
        precondition(sharedAPI.details.isEmpty, "Remote setting change must not submit a run")
        let api = AIAPIClient()
        let state = AIChatState(apiClient: api, authSession: CognitoAuthSession(), configurationErrorMessage: nil)
        await state.loadList(); state.choose(api.model)
        _ = try await api.create(id: "a", title: "A")
        _ = try await api.create(id: "b", title: "B")
        state.composerText = "new draft"
        await state.openConversation(id: "a"); state.composerText = "draft A"
        await state.openConversation(id: "b"); state.composerText = "draft B"
        await state.openConversation(id: "a")
        precondition(state.composerText == "draft A", "A's draft must survive switching")
        state.newChat(); precondition(state.composerText == "new draft")

        // A's older GET returns after B is open: neither title nor input changes.
        api.pausedLoads.insert("a")
        let delayedOpen = Task { await state.openConversation(id: "a") }
        while api.loadWaiters["a"] == nil { await Task.yield() }
        await state.openConversation(id: "b")
        api.loadWaiters.removeValue(forKey: "a")!.resume(); api.pausedLoads.remove("a")
        await delayedOpen.value
        precondition(state.detail?.id == "b" && state.composerText == "draft B")

        // The HTTP submission for A is still pending when B is opened.
        await state.openConversation(id: "a"); api.pauseSend = true
        let delayedSend = Task { await state.send(conversationId: "a") }
        while api.sendWaiter == nil { await Task.yield() }
        api.pausedLoads.insert("a")
        let staleRefresh = Task { await state.openConversation(id: "a") }
        while api.loadWaiters["a"] == nil { await Task.yield() }
        await state.openConversation(id: "b")
        precondition(!state.isSending && state.canSend, "A's submission must not lock B")
        api.sendWaiter!.resume(); api.sendWaiter = nil; api.pauseSend = false
        let navigation = await delayedSend.value
        precondition(navigation == nil && state.detail?.id == "b", "A must not steal focus")
        api.loadWaiters.removeValue(forKey: "a")!.resume(); api.pausedLoads.remove("a")
        await staleRefresh.value
        precondition(state.activity("a") == "待機中", "An old empty snapshot must not erase A's accepted run")
        let runA = api.details["a"]!.runs.last!.id
        let b = await state.send(conversationId: "b")
        precondition(b == "b")
        let runB = api.details["b"]!.runs.last!.id
        while api.listeners[runA] == nil || api.listeners[runB] == nil { await Task.yield() }
        precondition(state.activity("a") == "待機中" && state.activity("b") == "待機中")
        try api.emit(runA, type: "run.started", data: [:])
        try api.emit(runA, type: "text.delta", data: ["text": .string("only A")])
        try api.emit(runB, type: "run.started", data: [:])
        try api.emit(runB, type: "text.delta", data: ["text": .string("only B")])
        while state.detail?.runs.last?.outputText != "only B" { await Task.yield() }
        precondition(state.detail?.id == "b")
        await state.openConversation(id: "a")
        precondition(state.detail?.runs.last?.outputText == "only A")

        // Reopening immediately displays cached output while its refresh is pending.
        api.pausedLoads.insert("a")
        let reopening = Task { await state.openConversation(id: "a") }
        while api.loadWaiters["a"] == nil { await Task.yield() }
        precondition(state.isLoading && state.detail?.runs.last?.outputText == "only A")
        try api.emit(runA, type: "text.delta", data: ["text": .string(" while reopening")])
        while state.detail?.runs.last?.outputText != "only A while reopening" { await Task.yield() }
        api.loadWaiters.removeValue(forKey: "a")!.resume(); api.pausedLoads.remove("a")
        await reopening.value
        precondition(state.detail?.runs.last?.outputText == "only A while reopening")

        // Foreground recovery obtains missed events without moving focus away from B.
        await state.openConversation(id: "b")
        let detached = api.listeners.removeValue(forKey: runA)
        try api.emit(runA, type: "text.delta", data: ["text": .string(" after background")])
        await state.restoreAfterForeground()
        precondition(state.detail?.id == "b" && state.detail?.runs.last?.outputText == "only B")
        await state.openConversation(id: "a")
        precondition(state.detail?.runs.last?.outputText == "only A while reopening after background")
        api.listeners[runA] = detached
        await state.cancel(); precondition(api.cancelled == [runA], "Stop targets the visible run only")
        try api.emit(runA, type: "run.completed", data: ["responseId": .string("response-a")])
        try api.emit(runB, type: "run.completed", data: ["responseId": .string("response-b")])
        while !state.canDelete("a") || !state.canDelete("b") { await Task.yield() }
        await state.openConversation(id: "b"); state.composerText = "B remains"
        let deleted = await state.delete("a")
        precondition(deleted && state.detail?.id == "b" && state.composerText == "B remains")
        api.hideModel = true
        await state.loadList()
        precondition(state.selectedModel == nil && !state.canSend && !state.errorMessage.isEmpty)
        api.hideModel = false
        await state.loadList()
        precondition(state.selectedModel == nil, "A removed model requires explicit reselection")
        for listener in api.listeners.values { listener.finish() }
        print("PASS: draft isolation, delayed navigation, concurrent streams, cached reopen, foreground recovery, targeted stop and deletion")
    }
}
