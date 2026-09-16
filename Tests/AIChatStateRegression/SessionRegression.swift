import Foundation


@main struct SessionRegression {
    @MainActor static func main() async throws {
        // Switching from W8/128K must use Flash-Next's server policy, not the old context or its maximum.
        func flashModel(online: Bool, context: Int) -> AIModel {
            AIModel(id: "flash", hostId: "host", hostName: "PC-02", model: "flash", name: "Flash-Next", online: online,
                contextLengths: [8192, 16384, 32768], maxOutputTokens: 16384, reasoningEfforts: ["medium"],
                reasoningBudgets: ["medium": 1024], initialSettings: AISettings(contextLength: context,
                    maxOutputTokens: 4096, reasoningEffort: "medium"), inputModalities: [.text])
        }
        let flash = flashModel(online: true, context: 32768)
        var sharingDraft = AISharing(enabled: true, modelId: "w8", contextLength: 131072, maxConcurrentRuns: 1, revision: 4)
        sharingDraft.modelId = flash.id
        precondition(!sharingDraft.validationMessage(models: [flash]).isEmpty)
        sharingDraft.selectModel(flash)
        precondition(sharingDraft.contextLength == 32768 && sharingDraft.revision == 4)
        precondition(sharingDraft.validationMessage(models: [flash]).isEmpty)
        let smallerPolicy = flashModel(online: true, context: 16384)
        sharingDraft.selectModel(smallerPolicy)
        precondition(sharingDraft.contextLength == 16384, "Use configured chat context, not maximum capacity")
        let offline = flashModel(online: false, context: 32768)
        precondition(sharingDraft.validationMessage(models: [offline]).contains("OS Agent"))
        sharingDraft.enabled = false
        precondition(sharingDraft.validationMessage(models: [offline]).isEmpty, "Turning sharing off does not require an online PC")

        // AI failure does not mean the powered host is off. Catalog refresh is
        // independent from draft/sharing refresh and must expose fetch failures.
        let presenceAPI = AIAPIClient()
        presenceAPI.catalog = [offline]
        presenceAPI.powerHostValues = [AIPowerHost(hostId: "host", hostName: "PC-02", relayOnline: true,
            online: true, state: "online", aiReady: false, capturedAt: "test", activeRuns: 0, queuedRuns: 0,
            blockers: [], error: "推論サービスが停止しています。", operations: [])]
        let presence = AIChatState(apiClient: presenceAPI, authSession: CognitoAuthSession(), configurationErrorMessage: nil,
            reconciliationInterval: .milliseconds(20))
        await presence.loadList()
        let savedSharing = presence.sharing
        await presence.refreshSharingStatus()
        let stoppedAI = presence.sharingConnection(for: presence.models[0])
        precondition(stoppedAI.pc == "稼働中" && stoppedAI.agent == "未接続" && stoppedAI.ai == "準備中・要確認")
        precondition(stoppedAI.message == "推論サービスが停止しています。")
        presenceAPI.catalog = [flash]
        await presence.refreshSharingStatus()
        precondition(presence.models[0].online && presence.sharing == savedSharing)
        precondition(presence.sharingConnection(for: presence.models[0]).agent == "接続中")
        presenceAPI.failCatalog = true; presenceAPI.failPower = true
        await presence.refreshSharingStatus()
        precondition(!presence.sharingStatusError.isEmpty)
        let failedPresence = presence.sharingConnection(for: presence.models[0])
        precondition(failedPresence.pc == "状態未取得" && failedPresence.agent == "確認できません")
        presenceAPI.failCatalog = false; presenceAPI.failPower = false
        await presence.refreshSharingStatus()
        precondition(presence.sharingStatusError.isEmpty && presence.powerError.isEmpty)

        // Saving the chat policy refreshes both the shared value and the next request settings.
        let contextAPI = AIAPIClient()
        contextAPI.catalog = [flash]
        contextAPI.sharingValue = AISharing(enabled: true, modelId: flash.id, contextLength: 32768, maxConcurrentRuns: 1, revision: 4)
        let originalPolicy = AIInferencePolicy(revision: 4, maxConcurrentInferences: 3, models: [
            AIInferenceModelPolicy(model: flash.model, chatContextLength: 32768, apiContextLength: 16384,
                scheduledContextLength: 8192, auxiliaryContextLength: 16384)])
        let capability = AIInferenceCapability(model: flash.model, contextLengths: flash.contextLengths,
            totalContextTokens: 32768, maxConcurrentInferences: 1, maxOutputTokens: 16384, initialOutputTokens: 4096)
        contextAPI.inferenceHostValues = [AIInferenceHost(hostId: flash.hostId, hostName: flash.hostName, online: true,
            capturedAt: "test", desiredPolicy: originalPolicy, state: AIInferenceSnapshot(policy: originalPolicy,
                capabilities: [capability], loadedModel: flash.model, phase: "idle", error: "",
                reservedContextTokens: 0, active: [], queued: []))]
        let contextState = AIChatState(apiClient: contextAPI, authSession: CognitoAuthSession(), configurationErrorMessage: nil,
            reconciliationInterval: .milliseconds(20))
        await contextState.loadList(); await contextState.refreshInference()
        var updatedPolicy = originalPolicy
        updatedPolicy.models[0].chatContextLength = 16384
        let contextSaved = await contextState.saveInference(hostId: flash.hostId, policy: updatedPolicy)
        precondition(contextSaved && contextState.sharing?.contextLength == 16384 && contextState.settings?.contextLength == 16384)
        precondition(contextState.models.first?.initialSettings.contextLength == 16384)
        updatedPolicy.revision += 1
        precondition(contextState.inferenceHosts.first?.desiredPolicy == updatedPolicy,
                     "Changing chat context must preserve API, scheduled, auxiliary, and concurrency settings")

        // A coding chat fixes its harness/repository at creation, independently of model choice.
        let codingAPI = AIAPIClient()
        let repository = AIRepository(id: "repository", hostId: "host", hostName: "host", online: true, repository: "test/repo", branches: ["main", "develop"], defaultBranch: "main")
        codingAPI.repositoryValues = [repository]
        let coding = AIChatState(apiClient: codingAPI, authSession: CognitoAuthSession(), configurationErrorMessage: nil,
            reconciliationInterval: .milliseconds(20))
        await coding.loadList(); coding.choose(codingAPI.model); coding.chooseHarness(.opencode)
        coding.composerText = "テストを追加してください"; coding.delivery = .draftPR
        precondition(!coding.canSend, "A coding request needs an explicit repository")
        coding.chooseRepository(repository, branch: "develop")
        precondition(coding.canSend)
        let codingId = await coding.send(conversationId: nil)
        precondition(codingId != nil)
        await coding.openConversation(id: codingId!)
        coding.chooseHarness(.hermes); coding.chooseRepository(repository, branch: "main"); coding.delivery = .changes
        guard case .opencode(let context) = coding.detail!.context else { fatalError("Harness changed") }
        precondition(context.baseBranch == "develop" && context.workBranch == "agent/" + codingId!)
        precondition(coding.harness == .opencode && coding.detail!.runs[0].delivery == .draftPR && coding.delivery == .draftPR)
        let codingRun = coding.detail!.runs[0].id
        while codingAPI.listeners[codingRun] == nil { await Task.yield() }
        let request = AIRequest(id: "permission", runId: codingRun, kind: "permission", payload: [:], status: "pending", createdAt: "test", updatedAt: "test")
        codingAPI.requestValues[codingRun] = [request]
        try codingAPI.emit(codingRun, type: "request.created", data: [:])
        while coding.requestsByRun[codingRun]?.count != 1 { await Task.yield() }
        coding.newChat()
        await coding.answer(request, reply: .permission(allow: false))
        precondition(coding.detail == nil && coding.harness == .hermes && codingAPI.replies == ["permission"])
        precondition(coding.requestsByRun[codingRun]?.first?.status == "applied")
        try codingAPI.emit(codingRun, type: "run.completed", data: ["responseId": .string("native-session")])
        await coding.openConversation(id: codingId!)
        while coding.activeRun != nil { await Task.yield() }
        coding.delivery = .changes
        precondition(coding.delivery == .changes && coding.harness == .opencode)
        for listener in codingAPI.listeners.values { listener.finish() }

        let sharedAPI = AIAPIClient()
        let sharedState = AIChatState(apiClient: sharedAPI, authSession: CognitoAuthSession(), configurationErrorMessage: nil,
            reconciliationInterval: .milliseconds(20))
        await sharedState.loadList()
        sharedState.choose(sharedAPI.model)
        let saved = await sharedState.saveSharing(AISharing(enabled: true, modelId: sharedAPI.model.id, contextLength: 65536, maxConcurrentRuns: 2, revision: 1))
        precondition(saved && sharedState.sharedMode)
        sharedState.saveSettings(AISettings(contextLength: 131072, maxOutputTokens: 1024, reasoningEffort: "low"))
        precondition(sharedState.settings?.contextLength == 65536)
        sharedState.composerText = "shared draft"
        sharedAPI.sharingValue.enabled = false; sharedAPI.sharingValue.revision += 1
        let changed = await sharedState.send(conversationId: nil)
        precondition(changed == nil && sharedState.composerText == "shared draft")
        precondition(sharedAPI.details.isEmpty, "Remote setting change must not submit a run")

        let mediaAPI = AIAPIClient()
        let mediaState = AIChatState(apiClient: mediaAPI, authSession: CognitoAuthSession(), configurationErrorMessage: nil,
            reconciliationInterval: .milliseconds(20))
        await mediaState.loadList(); mediaState.choose(mediaAPI.model)
        let imageId = UUID().uuidString.lowercased()
        mediaState.addComposerAttachments([AIComposerAttachment(id: imageId, kind: .image, groupId: imageId, fileName: "sample.jpg",
            contentType: "image/jpeg", frameIndex: 1, frameCount: 1, data: Data([0xff, 0xd8, 0xff, 0xd9]))])
        precondition(mediaState.canSend, "A capable model must accept an image without mandatory text")
        let mediaConversation = await mediaState.send(conversationId: nil)
        precondition(mediaConversation != nil && mediaAPI.details[mediaConversation!]!.runs[0].attachments.first?.id == imageId)
        precondition(mediaState.composerAttachments.isEmpty, "Accepted media must leave the composer")
        for listener in mediaAPI.listeners.values { listener.finish() }

        let api = AIAPIClient()
        let state = AIChatState(apiClient: api, authSession: CognitoAuthSession(), configurationErrorMessage: nil,
            reconciliationInterval: .milliseconds(20))
        await state.loadList(); state.choose(api.model)
        _ = try await api.create(id: "a", title: "A", context: .hermes)
        _ = try await api.create(id: "b", title: "B", context: .hermes)
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
        precondition(state.displayedOutput(for: state.detail!.runs.last!).count < "only B".count,
                     "A live delta should be paced instead of appearing as one UI burst")
        try await Task.sleep(for: .milliseconds(350))
        precondition(state.displayedOutput(for: state.detail!.runs.last!) == "only B",
                     "The presentation must catch up without an artificial typing delay")
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

        // A dropped WebSocket can remain suspended after the network returns. The
        // authoritative run snapshot must still recover output and completion.
        await state.openConversation(id: "b")
        let stalled = api.listeners.removeValue(forKey: runB)
        try api.emit(runB, type: "reasoning.delta", data: ["text": .string("network recovery reasoning")])
        try api.emit(runB, type: "tool.call", data: ["id": .string("lookup"), "name": .string("search"), "arguments": .string("{}")])
        // A later socket event arrives first; HTTP replay must fill the gap.
        if let later = api.history[runB]?.last { stalled?.yield(later) }
        let progressDeadline = ContinuousClock.now + .seconds(1)
        while !state.trace(runB).reasoning.contains("network recovery reasoning") && ContinuousClock.now < progressDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(state.activeRun != nil && state.trace(runB).reasoning.contains("network recovery reasoning"),
                     "Stalled streams must recover reasoning before the run completes")
        precondition(state.trace(runB).tools.contains(where: { $0.id == "lookup" && !$0.completed }))
        try api.emit(runB, type: "text.delta", data: ["text": .string(" after network")])
        try api.emit(runB, type: "run.completed", data: ["responseId": .string("response-b")])
        let recoveryDeadline = ContinuousClock.now + .seconds(1)
        while state.activeRun != nil && ContinuousClock.now < recoveryDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(state.activeRun == nil && state.detail?.runs.last?.outputText == "only B after network",
                     "A silently stalled stream must reconcile to the terminal server run")
        precondition(api.runRequestCount > 0, "Active runs must be reconciled while WebSocket is suspended")
        stalled?.finish()

        // Foreground recovery obtains missed events without moving focus away from B.
        let detached = api.listeners.removeValue(forKey: runA)
        try api.emit(runA, type: "text.delta", data: ["text": .string(" after background")])
        await state.restoreAfterForeground()
        precondition(state.detail?.id == "b" && state.detail?.runs.last?.outputText == "only B after network")
        await state.openConversation(id: "a")
        precondition(state.detail?.runs.last?.outputText == "only A while reopening after background")
        api.listeners[runA] = detached
        await state.cancel(); precondition(api.cancelled == [runA], "Stop targets the visible run only")
        try api.emit(runA, type: "run.completed", data: ["responseId": .string("response-a")])
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
        print("PASS: draft isolation, delayed navigation, concurrent streams, network and foreground recovery, targeted stop and deletion")
    }
}
