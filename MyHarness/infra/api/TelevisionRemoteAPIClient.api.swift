import Foundation

enum TelevisionRemoteAccessConfiguration {
    case available(apiBaseURL: URL, authSession: CognitoAuthSession)
    case unavailable(message: String)
}

enum TelevisionRemoteAPIError: LocalizedError {
    case unavailable(String)
    case authenticationRequired
    case invalidResponse
    case unexpectedAPIStatus(Int)
    case unexpectedGatewayStatus(Int)
    case sessionReleaseFailed(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return "LAN外から視聴するための設定を読み込めませんでした。\n\(message)"
        case .authenticationRequired:
            return "LAN外からのテレビ視聴にはログインが必要です。設定からログインして再試行してください。"
        case .invalidResponse:
            return "テレビの認証サーバーから正しい応答を取得できませんでした。"
        case .unexpectedAPIStatus(let statusCode):
            return "テレビの認証を開始できませんでした（HTTP \(statusCode)）。"
        case .unexpectedGatewayStatus(let statusCode):
            return "テレビゲートウェイへ接続できませんでした（HTTP \(statusCode)）。"
        case .sessionReleaseFailed(let statusCode):
            return "テレビゲートウェイのセッションを解放できませんでした（HTTP \(statusCode)）。"
        }
    }
}

extension KonomiTVAPIClient {
    @MainActor
    static func automatic(
        localServerURL: URL,
        expectedGatewayBaseURL: URL,
        remoteAccess: TelevisionRemoteAccessConfiguration
    ) -> KonomiTVAPIClient {
        let localConfiguration = URLSessionConfiguration.ephemeral
        localConfiguration.timeoutIntervalForRequest = 4
        localConfiguration.timeoutIntervalForResource = 10

        let remoteConfiguration = URLSessionConfiguration.ephemeral
        remoteConfiguration.timeoutIntervalForRequest = 15
        remoteConfiguration.timeoutIntervalForResource = 30

        let coordinator = TelevisionConnectionCoordinator(
            localClient: .live(
                serverURL: localServerURL,
                session: URLSession(configuration: localConfiguration)
            ),
            expectedGatewayBaseURL: expectedGatewayBaseURL,
            remoteAccess: remoteAccess,
            session: URLSession(
                configuration: remoteConfiguration,
                delegate: TelevisionAuthenticatedRequestSessionDelegate(),
                delegateQueue: nil
            )
        )

        return KonomiTVAPIClient(
            fetchChannels: {
                try await coordinator.fetchChannels()
            },
            fetchChannelLogo: { channel in
                try await coordinator.fetchChannelLogo(for: channel)
            },
            startLiveStream: { channel, quality in
                try await coordinator.startLiveStream(channel: channel, quality: quality)
            },
            stopLiveStream: { liveStreamSession in
                try await coordinator.stopLiveStream(liveStreamSession)
            },
            connectionKind: {
                await coordinator.connectionKind
            },
            release: {
                await coordinator.releaseBrowsingSession()
            }
        )
    }
}

private actor TelevisionConnectionCoordinator {
    private struct ActiveGatewaySession: Sendable {
        let credential: TelevisionGatewaySessionCredential
        let playbackBaseURL: URL
        let expiresAt: Date
    }

    private let localClient: KonomiTVAPIClient
    private let expectedGatewayBaseURL: URL
    private let remoteAccess: TelevisionRemoteAccessConfiguration
    private let session: URLSession
    private var browsingSession: ActiveGatewaySession?
    private var gatewaySessionsPendingRelease: [TelevisionGatewaySessionCredential] = []
    private(set) var connectionKind: TelevisionConnectionKind?

    init(
        localClient: KonomiTVAPIClient,
        expectedGatewayBaseURL: URL,
        remoteAccess: TelevisionRemoteAccessConfiguration,
        session: URLSession
    ) {
        self.localClient = localClient
        self.expectedGatewayBaseURL = expectedGatewayBaseURL
        self.remoteAccess = remoteAccess
        self.session = session
    }

    func fetchChannels() async throws -> TelevisionChannelGroups {
        do {
            let groups = try await localClient.fetchChannels()
            connectionKind = .localNetwork
            await releaseBrowsingSession()
            return groups
        } catch {
            guard Self.isLocalConnectivityFailure(error) else { throw error }
        }

        let gatewaySession = try await activeBrowsingSession()
        do {
            let client = KonomiTVAPIClient.live(
                serverURL: gatewaySession.playbackBaseURL,
                session: session
            )
            let groups = try await client.fetchChannels()
            connectionKind = .internet
            return groups
        } catch {
            await releaseOrRemember(gatewaySession.credential)
            browsingSession = nil
            throw error
        }
    }

    func fetchChannelLogo(for channel: TelevisionChannel) async throws -> Data {
        switch connectionKind {
        case .localNetwork:
            return try await localClient.fetchChannelLogo(channel)
        case .internet:
            let gatewaySession = try await activeBrowsingSession()
            let client = KonomiTVAPIClient.live(
                serverURL: gatewaySession.playbackBaseURL,
                session: session
            )
            return try await client.fetchChannelLogo(channel)
        case nil:
            throw TelevisionRemoteAPIError.invalidResponse
        }
    }

    func startLiveStream(
        channel: TelevisionChannel,
        quality: TelevisionStreamQuality
    ) async throws -> TelevisionLiveStreamSession {
        if connectionKind != .internet {
            do {
                connectionKind = .localNetwork
                return try await localClient.startLiveStream(channel, quality)
            } catch {
                guard Self.isLocalConnectivityFailure(error) else { throw error }
                connectionKind = .internet
            }
        }

        let gatewaySession = try await createGatewaySession()
        let client = KonomiTVAPIClient.live(
            serverURL: gatewaySession.playbackBaseURL,
            session: session
        )

        do {
            let liveStreamSession = try await client.startLiveStream(channel, quality)
            return TelevisionLiveStreamSession(
                clientID: liveStreamSession.clientID,
                playlistURL: liveStreamSession.playlistURL,
                disconnectURL: liveStreamSession.disconnectURL,
                transport: .gateway(gatewaySession.credential)
            )
        } catch {
            await releaseOrRemember(gatewaySession.credential)
            throw error
        }
    }

    func stopLiveStream(_ liveStreamSession: TelevisionLiveStreamSession) async throws {
        switch liveStreamSession.transport {
        case .localNetwork:
            try await localClient.stopLiveStream(liveStreamSession)
        case .gateway(let credential):
            // 個別ストリームの切断が失敗しても、ゲートウェイセッションの
            // 削除が成功すれば上流接続もまとめて解放される。
            let client = KonomiTVAPIClient.live(
                serverURL: credential.gatewayBaseURL,
                session: session
            )
            try? await client.stopLiveStream(liveStreamSession)

            do {
                try await deleteGatewaySession(credential)
            } catch {
                rememberForRelease(credential)
                throw error
            }
        }
    }

    func releaseBrowsingSession() async {
        if let browsingSession {
            self.browsingSession = nil
            await releaseOrRemember(browsingSession.credential)
        }
        try? await releasePendingGatewaySessions()
    }

    private func activeBrowsingSession() async throws -> ActiveGatewaySession {
        if let browsingSession, browsingSession.expiresAt.timeIntervalSinceNow > 30 {
            return browsingSession
        }
        await releaseBrowsingSession()
        let created = try await createGatewaySession()
        browsingSession = created
        return created
    }

    private func createGatewaySession() async throws -> ActiveGatewaySession {
        try await releasePendingGatewaySessions()

        let apiBaseURL: URL
        let authSession: CognitoAuthSession
        switch remoteAccess {
        case .available(let configuredAPIBaseURL, let configuredAuthSession):
            apiBaseURL = configuredAPIBaseURL
            authSession = configuredAuthSession
        case .unavailable(let message):
            throw TelevisionRemoteAPIError.unavailable(message)
        }
        try TelevisionRemoteEndpointValidator.validateAPIBaseURL(apiBaseURL)

        let accessToken: String
        do {
            accessToken = try await authSession.accessToken()
        } catch {
            throw TelevisionRemoteAPIError.authenticationRequired
        }

        var bootstrapRequest = URLRequest(
            url: TelevisionRemoteEndpointBuilder(apiBaseURL: apiBaseURL).bootstrapURL()
        )
        bootstrapRequest.httpMethod = "POST"
        bootstrapRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        bootstrapRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (bootstrapData, bootstrapResponse) = try await session.data(for: bootstrapRequest)
        guard let bootstrapHTTPResponse = bootstrapResponse as? HTTPURLResponse else {
            throw TelevisionRemoteAPIError.invalidResponse
        }
        guard bootstrapHTTPResponse.statusCode == 200 else {
            if bootstrapHTTPResponse.statusCode == 401 || bootstrapHTTPResponse.statusCode == 403 {
                throw TelevisionRemoteAPIError.authenticationRequired
            }
            throw TelevisionRemoteAPIError.unexpectedAPIStatus(bootstrapHTTPResponse.statusCode)
        }

        let bootstrap = try Self.decoder.decode(
            TelevisionGatewayBootstrapEnvelope.self,
            from: bootstrapData
        ).data
        try TelevisionRemoteEndpointValidator.validateBootstrap(
            bootstrap,
            expectedGatewayBaseURL: expectedGatewayBaseURL
        )

        var createRequest = URLRequest(
            url: TelevisionRemoteEndpointBuilder.createSessionURL(
                gatewayBaseURL: bootstrap.gatewayBaseURL
            )
        )
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(bootstrap.ticket)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (createData, createResponse) = try await session.data(for: createRequest)
        guard let createHTTPResponse = createResponse as? HTTPURLResponse else {
            throw TelevisionRemoteAPIError.invalidResponse
        }
        guard createHTTPResponse.statusCode == 200 || createHTTPResponse.statusCode == 201 else {
            throw TelevisionRemoteAPIError.unexpectedGatewayStatus(createHTTPResponse.statusCode)
        }

        let gatewaySession = try Self.decoder.decode(
            TelevisionGatewaySessionResponse.self,
            from: createData
        )
        try TelevisionRemoteEndpointValidator.validateSession(
            gatewaySession,
            gatewayBaseURL: bootstrap.gatewayBaseURL
        )

        return ActiveGatewaySession(
            credential: TelevisionGatewaySessionCredential(
                sessionID: gatewaySession.sessionID,
                sessionToken: gatewaySession.sessionToken,
                gatewayBaseURL: bootstrap.gatewayBaseURL
            ),
            playbackBaseURL: gatewaySession.playbackBaseURL,
            expiresAt: gatewaySession.expiresAt
        )
    }

    private func deleteGatewaySession(_ credential: TelevisionGatewaySessionCredential) async throws {
        var request = URLRequest(
            url: TelevisionRemoteEndpointBuilder.deleteSessionURL(
                gatewayBaseURL: credential.gatewayBaseURL,
                sessionID: credential.sessionID
            )
        )
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(credential.sessionToken)", forHTTPHeaderField: "Authorization")

        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(attempt == 1 ? 200 : 600))
            }
            do {
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TelevisionRemoteAPIError.invalidResponse
                }
                if TelevisionGatewaySessionDeletionPolicy.isTerminalSuccess(
                    statusCode: httpResponse.statusCode
                ) {
                    return
                }
                let error = TelevisionRemoteAPIError.sessionReleaseFailed(httpResponse.statusCode)
                if !(500..<600).contains(httpResponse.statusCode) {
                    throw error
                }
                lastError = error
            } catch {
                lastError = error
            }
        }
        throw lastError ?? TelevisionRemoteAPIError.invalidResponse
    }

    private func releaseOrRemember(_ credential: TelevisionGatewaySessionCredential) async {
        do {
            try await deleteGatewaySession(credential)
        } catch {
            rememberForRelease(credential)
        }
    }

    private func rememberForRelease(_ credential: TelevisionGatewaySessionCredential) {
        guard !gatewaySessionsPendingRelease.contains(credential) else { return }
        gatewaySessionsPendingRelease.append(credential)
    }

    private func releasePendingGatewaySessions() async throws {
        while let credential = gatewaySessionsPendingRelease.first {
            try await deleteGatewaySession(credential)
            gatewaySessionsPendingRelease.removeFirst()
        }
    }

    private static func isLocalConnectivityFailure(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .secureConnectionFailed,
             .serverCertificateUntrusted,
             .timedOut:
            return true
        default:
            return false
        }
    }

    private static let decoder: JSONDecoder = {
        KonomiTVJSONDecoder.make()
    }()
}
