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
    private var ownerID = ""
    private var generation = 0
    private var requestGeneration = 0
    private(set) var themes: [ExperimentThemeSummary] = []
    private(set) var tasks: [ExperimentTask] = []
    private(set) var notes: [ExperimentNote] = []
    private(set) var hypotheses: [ExperimentHypothesis] = []
    private(set) var phase: Phase = .idle
    private(set) var hasMore = false
    private var nextOffset = 0
    var focus: ExperimentFocus = .themes
    var query = ""

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
    func clearSession() {
        generation += 1; requestGeneration += 1; ownerID = ""
        themes = []; tasks = []; notes = []; hypotheses = []
        nextOffset = 0; hasMore = false; phase = .idle
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
        if current != ownerID { clearSession(); ownerID = current }
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
    func refresh() async { await load(append: false) }
    func loadMore() async { if hasMore { await load(append: true) } }
    private func load(append: Bool) async {
        if append, case .loading = phase { return }
        do {
            let api = try client(); let stamp = try sessionStamp()
            requestGeneration += 1; let request = requestGeneration
            let selected = focus; let search = query; let offset = append ? nextOffset : 0
            if !append { themes = []; tasks = []; notes = []; hypotheses = [] }
            phase = .loading
            var more = false; var following = offset
            switch selected {
            case .themes:
                var parameters = [URLQueryItem(name: "archived", value: "exclude")]
                if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parameters.append(URLQueryItem(name: "q", value: search)) }
                let page = try await api.page("themes", offset: offset, query: parameters, as: ExperimentThemeSummary.self)
                guard isCurrent(stamp), request == requestGeneration else { return }
                themes = append ? themes + page.items : page.items; more = page.hasMore; following += page.items.count
            case .timeline:
                let page = try await api.page("timeline", offset: offset, query: [], as: ExperimentNote.self)
                guard isCurrent(stamp), request == requestGeneration else { return }
                notes = append ? notes + page.items : page.items; more = page.hasMore; following += page.items.count
            case .review:
                let page = try await api.page("review-queue", offset: offset, query: [], as: ExperimentHypothesis.self)
                guard isCurrent(stamp), request == requestGeneration else { return }
                hypotheses = append ? hypotheses + page.items : page.items; more = page.hasMore; following += page.items.count
            case .today, .week, .overdue, .noDue, .paused:
                let page = try await api.page("next", offset: offset, query: [URLQueryItem(name: "view", value: selected.rawValue), URLQueryItem(name: "asOf", value: Date().ISO8601Format())], as: ExperimentTask.self)
                guard isCurrent(stamp), request == requestGeneration else { return }
                tasks = append ? tasks + page.items : page.items; more = page.hasMore; following += page.items.count
            }
            guard isCurrent(stamp), request == requestGeneration else { return }
            nextOffset = following; hasMore = more; phase = .loaded
        } catch is CancellationError { }
        catch { phase = .failed(error.localizedDescription) }
    }
}
