import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class GoogleAPI: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func exchangeAuthorizationCode(
        _ code: String,
        codeVerifier: String,
        redirectURI: URL,
        credentials: OAuthCredentials
    ) async throws -> OAuthTokenSet {
        var values = [
            "client_id": credentials.clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI.absoluteString
        ]
        if let secret = credentials.clientSecret, !secret.isEmpty {
            values["client_secret"] = secret
        }

        let response: TokenResponse = try await postForm(values, to: credentials.tokenEndpoint)
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw MeetBarError.missingRefreshToken
        }
        return OAuthTokenSet(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    public func refresh(
        _ tokens: OAuthTokenSet,
        credentials: OAuthCredentials
    ) async throws -> OAuthTokenSet {
        var values = [
            "client_id": credentials.clientID,
            "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token"
        ]
        if let secret = credentials.clientSecret, !secret.isEmpty {
            values["client_secret"] = secret
        }

        let response: TokenResponse = try await postForm(values, to: credentials.tokenEndpoint)
        return OAuthTokenSet(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    public func profile(accessToken: String) async throws -> MeetAccount {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: UserInfoResponse = try await send(request)
        return MeetAccount(
            id: response.id,
            email: response.email,
            displayName: response.name ?? response.email
        )
    }

    public func createMeeting(accessToken: String) async throws -> MeetingSpace {
        var request = URLRequest(url: URL(string: "https://meet.googleapis.com/v2/spaces")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func postForm<Response: Decodable>(
        _ values: [String: String],
        to url: URL
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = FormEncoding.data(values)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else {
            throw MeetBarError.apiError(statusCode: 0, message: "Invalid response")
        }
        guard (200..<300).contains(response.statusCode) else {
            let decoded = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data)
            let fallback = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MeetBarError.apiError(
                statusCode: response.statusCode,
                message: decoded?.error.message ?? fallback
            )
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct UserInfoResponse: Decodable {
    let id: String
    let email: String
    let name: String?
}

private struct GoogleErrorEnvelope: Decodable {
    struct GoogleError: Decodable {
        let message: String
    }

    let error: GoogleError
}
