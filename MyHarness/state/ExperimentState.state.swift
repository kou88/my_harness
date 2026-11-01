import Foundation
import Observation

@MainActor
@Observable
final class ExperimentState {
    enum Connection {
        case connected(ExperimentAPIClient, CognitoAuthSession)
        case unavailable(String)
    }
    enum Phase {
        case idle, loading, loaded, failed(String)
    }
    private let connection: Connection
    private let cache = ExperimentThemePageCache(directory: .cachesDirectory)
    private var ownerID = ""
    private var generation = 0
    private var requestGeneration = 0
    @ObservationIgnored private var pending: Task<Void, Never>?
    private var pendingOffset: Int?
    private var failedOffset = 0
    var returnThemeID: String?
    private var listing = ExperimentThemeList()
    private(set) var phase: Phase = .idle
    var themes: [ExperimentThemeSummary] { listing.items }

    init(api: ActionInboxAPIClient?, auth: CognitoAuthSession?, configurationError: String?) {
        if let api, let auth { connection = .connected(ExperimentAPIClient(transport: api), auth) }
        else { connection = .unavailable(configurationError ?? "仮説検証APIが設定されていません") }
    }
    var isSignedIn: Bool {
        if case .connected(_, let auth) = connection { return auth.isSignedIn }
        return false
    }
    func signIn() async {
        do {
            guard case .connected(_, let auth) = connection else { throw unavailableError() }
            try await auth.signIn()
            await refresh()
        } catch { phase = .failed(error.localizedDescription) }
    }
    private func cancelRequest() {
        requestGeneration += 1
        pending?.cancel()
        pending = nil
        pendingOffset = nil
    }
    private func resetMemory() {
        cancelRequest()
        generation += 1
        ownerID = ""
        listing = ExperimentThemeList()
        returnThemeID = nil
        failedOffset = 0
        phase = .idle
    }
    func clearSession() {
        resetMemory()
        cache.clear()
    }
    private func unavailableError() -> NSError {
        let message: String
        switch connection {
        case .unavailable(let reason): message = reason
        case .connected: message = "ログインしてください"
        }
        return NSError(domain: "Experiments", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    func client() throws -> ExperimentAPIClient {
        guard case .connected(let api, let auth) = connection else { throw unavailableError() }
        let current = try auth.bookOwnerID()
        if current != ownerID {
            resetMemory()
            ownerID = current
            if let page = cache.read(owner: current, now: Date()) {
                listing.restore(page)
                phase = .loaded
            }
        }
        return api
    }
    func sessionStamp() throws -> String {
        _ = try client()
        return ownerID + ":" + String(generation)
    }
    func isCurrent(_ stamp: String) -> Bool {
        guard case .connected(_, let auth) = connection, let current = try? auth.bookOwnerID() else { return false }
        return stamp == current + ":" + String(generation) && current == ownerID
    }
    func loadIfNeeded(keeping themeID: String?) async {
        do { _ = try client() }
        catch { clearSession(); phase = .failed(error.localizedDescription); return }
        if !listing.isFresh(at: Date()) { await load(offset: 0, keeping: themeID) }
    }
    func refresh() async { await load(offset: 0, keeping: returnThemeID) }
    func loadMore(after id: String) async {
        guard case .loaded = phase, listing.hasMore, listing.items.last?.id == id else { return }
        await load(offset: listing.nextOffset, keeping: nil)
    }
    func retry() async { await load(offset: failedOffset, keeping: returnThemeID) }

    func createTheme(_ request: ExperimentThemeCreateRequest, session stamp: String) async throws -> ExperimentTheme {
        let theme = try await create("themes", request: request, session: stamp, as: ExperimentTheme.self)
        await refresh()
        guard isCurrent(stamp) else { throw sessionChangedError() }
        return theme
    }

    func currentAssigneeID() throws -> String {
        _ = try client()
        return ownerID
    }

    func create<Input: Encodable, Value: Decodable>(_ path: String, request: Input, session stamp: String, as type: Value.Type) async throws -> Value {
        guard isCurrent(stamp) else { throw sessionChangedError() }
        let value = try await client().create(path, input: request, as: type)
        guard isCurrent(stamp) else { throw sessionChangedError() }
        cancelRequest()
        listing.invalidate()
        cache.clear()
        return value
    }

    private func sessionChangedError() -> NSError {
        NSError(domain: "Experiments", code: 2, userInfo: [NSLocalizedDescriptionKey: "ログインが変更されました。画面を開き直してください。"])
    }

    private func load(offset: Int, keeping themeID: String?) async {
        let api: ExperimentAPIClient
        let stamp: String
        do { api = try client(); stamp = try sessionStamp() }
        catch { clearSession(); phase = .failed(error.localizedDescription); return }
        if let pending, pendingOffset == offset || offset != 0 { await pending.value; return }
        cancelRequest()
        let request = requestGeneration
        pendingOffset = offset
        phase = .loading
        let task = Task {
            defer {
                if request == requestGeneration { pending = nil; pendingOffset = nil }
            }
            do {
                @MainActor func fetch(_ offset: Int) async throws -> ExperimentPage<ExperimentThemeSummary> {
                    try Task.checkCancellation()
                    guard isCurrent(stamp), request == requestGeneration else { throw CancellationError() }
                    return try await api.page("themes", limit: ExperimentThemeList.pageSize, offset: offset,
                                              query: [URLQueryItem(name: "archived", value: "exclude")], as: ExperimentThemeSummary.self)
                }
                let now = Date()
                if offset == 0 {
                    let refreshed = try await listing.refreshed(keeping: themeID, at: now, fetch: fetch)
                    guard isCurrent(stamp), request == requestGeneration else { return }
                    listing = refreshed.list
                    do { try cache.write(.init(ownerID: ownerID, fetchedAt: now, items: refreshed.first.items, total: refreshed.first.total)) }
                    catch { cache.clear() }
                } else {
                    let page = try await fetch(offset)
                    guard isCurrent(stamp), request == requestGeneration else { return }
                    try listing.accept(page, offset: offset, at: now)
                }
                phase = .loaded
            } catch {
                guard isCurrent(stamp), request == requestGeneration else { return }
                if case ActionInboxAPIClient.ClientError.requestFailed(let status, _) = error, [401, 403].contains(status) {
                    clearSession()
                }
                failedOffset = listing.items.isEmpty ? 0 : offset
                phase = .failed(error.localizedDescription)
            }
        }
        pending = task
        await task.value
    }
}
