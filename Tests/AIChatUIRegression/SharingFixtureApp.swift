import SwiftUI

// The production sharing view/state use only in-memory responses. No PC, cloud,
// authentication or power operation is contacted by this Simulator host.
@main struct SharingFixtureApp: App {
    @State private var state: AIChatState
    @State private var api: AIAPIClient
    init() {
        let api = AIAPIClient()
        let model = AIModel(id: "flash", hostId: "host", hostName: "PC-02", model: "flash",
            name: "Qwen3.8 Flash-Next / IQ4_XS", online: false, contextLengths: [32768, 65536, 131072, 262144],
            maxOutputTokens: 16384, reasoningEfforts: ["medium"], reasoningBudgets: ["medium": 1024],
            initialSettings: AISettings(contextLength: 32768, maxOutputTokens: 4096, reasoningEffort: "medium"),
            inputModalities: [.text])
        api.catalog = [model]
        api.sharingValue = AISharing(enabled: true, modelId: model.id, contextLength: 32768, maxConcurrentRuns: 1, revision: 1)
        api.powerHostValues = [AIPowerHost(hostId: "host", hostName: "PC-02", relayOnline: true, online: true,
            state: "online", aiReady: false, capturedAt: "test", activeRuns: 0, queuedRuns: 0, blockers: [],
            error: "推論サービスが停止しています。PCの電源管理は利用できます。", operations: [])]
        _api = State(initialValue: api)
        _state = State(initialValue: AIChatState(apiClient: api, authSession: CognitoAuthSession(), configurationErrorMessage: nil,
            reconciliationInterval: .seconds(2)))
    }
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                HStack {
                    Text("検証用データ").font(.caption)
                    Button("Agent復旧") {
                        let m = api.catalog[0]
                        api.catalog = [AIModel(id: m.id, hostId: m.hostId, hostName: m.hostName, model: m.model,
                            name: m.name, online: true, contextLengths: m.contextLengths, maxOutputTokens: m.maxOutputTokens,
                            reasoningEfforts: m.reasoningEfforts, reasoningBudgets: m.reasoningBudgets,
                            initialSettings: m.initialSettings, inputModalities: m.inputModalities)]
                    }
                    Button("取得失敗") { api.failCatalog = true; api.failPower = true }
                }.padding(8)
                if state.sharing != nil { AISharingView(state: state, draft: api.sharingValue) }
            }.task { await state.loadList() }
        }
    }
}
// Unopened destinations are isolated from real APIs and power controls.
struct AIChatContextView: View {
    let state: AIChatState
    let model: AIModel
    var body: some View { Text("検証対象外") }
}
struct AIPowerView: View {
    let state: AIChatState
    let selectedHostId: String
    var body: some View { Text("検証対象外") }
}
