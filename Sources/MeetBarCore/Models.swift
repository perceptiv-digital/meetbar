import Foundation

public struct OAuthCredentials: Codable, Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL

    public init(
        clientID: String,
        clientSecret: String?,
        authorizationEndpoint: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
    }

    public static func parseGoogleDesktopJSON(_ data: Data) throws -> OAuthCredentials {
        struct Envelope: Decodable {
            struct Installed: Decodable {
                let clientID: String
                let clientSecret: String?
                let authURI: String?
                let tokenURI: String?

                enum CodingKeys: String, CodingKey {
                    case clientID = "client_id"
                    case clientSecret = "client_secret"
                    case authURI = "auth_uri"
                    case tokenURI = "token_uri"
                }
            }

            let installed: Installed?
        }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let installed = envelope.installed, !installed.clientID.isEmpty else {
            throw MeetBarError.invalidOAuthConfiguration
        }

        return OAuthCredentials(
            clientID: installed.clientID,
            clientSecret: installed.clientSecret,
            authorizationEndpoint: URL(string: installed.authURI ?? "")
                ?? URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: installed.tokenURI ?? "")
                ?? URL(string: "https://oauth2.googleapis.com/token")!
        )
    }
}

public struct OAuthTokenSet: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var grantedScopes: Set<String>

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        grantedScopes: Set<String> = []
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.grantedScopes = grantedScopes
    }

    public func needsRefresh(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt <= now.addingTimeInterval(leeway)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
        case grantedScopes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        grantedScopes = try container.decodeIfPresent(Set<String>.self, forKey: .grantedScopes) ?? []
    }
}

public struct MeetAccount: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let email: String
    public let displayName: String
    public let grantedScopes: Set<String>

    public init(
        id: String,
        email: String,
        displayName: String,
        grantedScopes: Set<String> = []
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.grantedScopes = grantedScopes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName
        case grantedScopes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        grantedScopes = try container.decodeIfPresent(Set<String>.self, forKey: .grantedScopes) ?? []
    }
}

public struct MeetingRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let meetingURL: URL
    public let accountEmail: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        meetingURL: URL,
        accountEmail: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.meetingURL = meetingURL
        self.accountEmail = accountEmail
        self.createdAt = createdAt
    }
}

public struct MeetingSpace: Codable, Equatable, Sendable {
    public let name: String
    public let meetingURI: URL
    public let meetingCode: String?

    enum CodingKeys: String, CodingKey {
        case name
        case meetingURI = "meetingUri"
        case meetingCode
    }
}

public struct CalendarMeeting: Equatable, Sendable {
    public let meetingURI: URL
    public let eventURI: URL
    public let eventID: String

    public init(meetingURI: URL, eventURI: URL, eventID: String) {
        self.meetingURI = meetingURI
        self.eventURI = eventURI
        self.eventID = eventID
    }
}

public enum MeetBarError: LocalizedError, Equatable {
    case invalidOAuthConfiguration
    case oauthCallbackFailed(String)
    case oauthStateMismatch
    case missingAuthorizationCode
    case missingRefreshToken
    case missingAccount
    case calendarPermissionRequired
    case calendarAccountMismatch
    case calendarConferenceTimedOut(URL?)
    case invalidMeetingURL
    case apiError(statusCode: Int, message: String)
    case keychainError(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidOAuthConfiguration:
            return "That file is not a Google OAuth desktop client configuration."
        case .oauthCallbackFailed(let message):
            return "Google authorization failed: \(message)"
        case .oauthStateMismatch:
            return "The OAuth response could not be verified. Please try again."
        case .missingAuthorizationCode:
            return "Google did not return an authorization code."
        case .missingRefreshToken:
            return "Google did not return a refresh token. Remove the account and authorize it again."
        case .missingAccount:
            return "Choose or add a Google account first."
        case .calendarPermissionRequired:
            return "Grant Calendar access for this Google account in Settings first."
        case .calendarAccountMismatch:
            return "Google authorized a different account. Choose the same account shown in MeetBar and try again."
        case .calendarConferenceTimedOut:
            return "The Calendar event was created, but Google Meet is still preparing its link. Open the event in Google Calendar and try again shortly."
        case .invalidMeetingURL:
            return "Google returned an invalid meeting URL."
        case .apiError(let statusCode, let message):
            return "Google API error \(statusCode): \(message)"
        case .keychainError(let status):
            return "Keychain error \(status)."
        }
    }
}
