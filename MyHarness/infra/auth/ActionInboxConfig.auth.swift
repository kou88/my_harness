import Foundation

enum ActionInboxConfigurationError: LocalizedError {
    case missingValue(String)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let key):
            return "\(key) が未設定です。XcodeのBuild SettingsまたはInfo.plistで設定してください。"
        case .invalidURL(let key):
            return "\(key) がURLとして解釈できません。"
        }
    }
}

struct ActionInboxConfig: Hashable {
    let apiBaseURL: URL
    let cognitoHostedUIBaseURL: URL
    let cognitoClientID: String
    let cognitoRedirectURI: String
    let cognitoScopes: [String]

    static func load(bundle: Bundle = .main) throws -> ActionInboxConfig {
        let apiBaseURL = try configuredURL(for: "ActionAPIBaseURL", bundle: bundle)
        let hostedUIBaseURL = try configuredURL(for: "CognitoHostedUIBaseURL", bundle: bundle, allowsHostOnly: true)
        let clientID = try configuredString(for: "CognitoClientID", bundle: bundle)
        let redirectURI = try configuredString(for: "CognitoRedirectURI", bundle: bundle)
        let scopes = try configuredString(for: "CognitoScopes", bundle: bundle)
            .split(separator: " ")
            .map(String.init)

        return ActionInboxConfig(
            apiBaseURL: apiBaseURL,
            cognitoHostedUIBaseURL: hostedUIBaseURL,
            cognitoClientID: clientID,
            cognitoRedirectURI: redirectURI,
            cognitoScopes: scopes
        )
    }

    private static func configuredString(for key: String, bundle: Bundle) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            throw ActionInboxConfigurationError.missingValue(key)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            throw ActionInboxConfigurationError.missingValue(key)
        }
        return trimmed
    }

    private static func configuredURL(
        for key: String,
        bundle: Bundle,
        allowsHostOnly: Bool = false
    ) throws -> URL {
        let string = try configuredString(for: key, bundle: bundle)
        let normalized = allowsHostOnly && !string.contains("://") ? "https://\(string)" : string
        guard let url = URL(string: normalized), url.scheme != nil, url.host != nil else {
            throw ActionInboxConfigurationError.invalidURL(key)
        }
        return url
    }
}
