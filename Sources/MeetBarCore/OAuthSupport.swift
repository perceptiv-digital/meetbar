import CryptoKit
import Foundation
import Security

public enum PKCE {
    public static func makeVerifier(byteCount: Int = 64) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw MeetBarError.keychainError(status)
        }
        return Data(bytes).base64URLEncodedString()
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

public extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum OAuthRequestBuilder {
    public static let calendarEventsOwnedScope = "https://www.googleapis.com/auth/calendar.events.owned"

    public static let scopes = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/meetings.space.created"
    ]

    public static func scopes(includeCalendar: Bool) -> [String] {
        includeCalendar ? scopes + [calendarEventsOwnedScope] : scopes
    }

    public static func authorizationURL(
        credentials: OAuthCredentials,
        redirectURI: URL,
        state: String,
        codeChallenge: String,
        loginHint: String? = nil,
        requestedScopes: [String] = scopes
    ) -> URL {
        var components = URLComponents(url: credentials.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: requestedScopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if let loginHint, !loginHint.isEmpty {
            items.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components.queryItems = items
        return components.url!
    }
}

public enum FormEncoding {
    public static func data(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}
