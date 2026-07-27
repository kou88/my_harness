import Foundation
import Observation

@MainActor
@Observable
final class BlogPostState {
    enum LoadState<T: Hashable>: Hashable {
        case idle
        case loading
        case loaded(T)
        case failed(String)
    }

    var listState: LoadState<[BlogPost]> = .idle
    var detailState: LoadState<BlogPost> = .idle

    private let authSession: CognitoAuthSession?
    private let apiClient: ActionInboxAPIClient?
    private let configurationErrorMessage: String?

    init(
        authSession: CognitoAuthSession?,
        apiClient: ActionInboxAPIClient?,
        configurationErrorMessage: String?
    ) {
        self.authSession = authSession
        self.apiClient = apiClient
        self.configurationErrorMessage = configurationErrorMessage
    }

    var isConfigured: Bool {
        apiClient != nil && authSession != nil && configurationErrorMessage == nil
    }

    var isSignedIn: Bool {
        authSession?.isSignedIn == true
    }

    var posts: [BlogPost] {
        guard case .loaded(let posts) = listState else { return [] }
        return posts
    }

    func loadIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await load()
    }

    func load() async {
        guard let apiClient else {
            listState = .failed(configurationErrorMessage ?? "API設定を読み込めません。")
            return
        }
        guard isSignedIn else {
            listState = .failed("記事を読むには「次にやる」タブからログインしてください。")
            return
        }

        listState = .loading
        do {
            listState = .loaded(try await apiClient.fetchBlogPosts())
        } catch is CancellationError {
            return
        } catch {
            listState = .failed("記事の読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func loadDetail(id: String) async {
        guard let apiClient else {
            detailState = .failed(configurationErrorMessage ?? "API設定を読み込めません。")
            return
        }
        guard isSignedIn else {
            detailState = .failed("記事を読むにはログインしてください。")
            return
        }

        detailState = .loading
        do {
            detailState = .loaded(try await apiClient.fetchBlogPost(id: id))
        } catch is CancellationError {
            return
        } catch {
            detailState = .failed("記事の読み込みに失敗しました: \(error.localizedDescription)")
        }
    }
}
