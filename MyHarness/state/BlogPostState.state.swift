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

    enum ImportRequestState: Hashable {
        case idle
        case submitting
        case submitted(XArticleImportTask)
        case failed(String)
    }

    var listState: LoadState<[BlogPost]> = .idle
    var detailState: LoadState<BlogPost> = .idle
    var importHostsState: LoadState<[XArticleImportHost]> = .idle
    var importRequestState: ImportRequestState = .idle

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

    var importHosts: [XArticleImportHost] {
        guard case .loaded(let hosts) = importHostsState else { return [] }
        return hosts.sorted {
            if $0.canImportXArticle != $1.canImportXArticle {
                return $0.canImportXArticle
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
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

    func loadImportHosts() async {
        guard let apiClient else {
            importHostsState = .failed(configurationErrorMessage ?? "API設定を読み込めません。")
            return
        }
        guard isSignedIn else {
            importHostsState = .failed("記事の読み取りを依頼するにはログインしてください。")
            return
        }

        importHostsState = .loading
        do {
            importHostsState = .loaded(try await apiClient.fetchXArticleImportHosts())
        } catch is CancellationError {
            return
        } catch {
            importHostsState = .failed("実行PCの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func submitImportRequest(
        hostId: String,
        sourceURL: String,
        translationMode: XArticleTranslationMode
    ) async {
        guard let apiClient else {
            importRequestState = .failed(configurationErrorMessage ?? "API設定を読み込めません。")
            return
        }
        guard isSignedIn else {
            importRequestState = .failed("記事の読み取りを依頼するにはログインしてください。")
            return
        }
        guard let host = importHosts.first(where: { $0.id == hostId }) else {
            importRequestState = .failed("実行PCを選択してください。")
            return
        }

        importRequestState = .submitting
        do {
            let input = try XArticleImportRequest.make(
                host: host,
                sourceURL: sourceURL,
                translationMode: translationMode
            )
            importRequestState = .submitted(try await apiClient.createXArticleImportTask(input))
        } catch is CancellationError {
            importRequestState = .idle
        } catch {
            importRequestState = .failed(
                error.localizedDescription.isEmpty
                    ? "記事の読み取りリクエストを送信できませんでした。"
                    : error.localizedDescription
            )
        }
    }

    func resetImportRequest() {
        importHostsState = .idle
        importRequestState = .idle
    }
}
