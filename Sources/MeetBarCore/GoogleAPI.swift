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
        credentials: OAuthCredentials,
        requestedScopes: [String] = OAuthRequestBuilder.scopes,
        existingRefreshToken: String? = nil
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
        guard let refreshToken = response.refreshToken ?? existingRefreshToken, !refreshToken.isEmpty else {
            throw MeetBarError.missingRefreshToken
        }
        let grantedScopes = response.scope.map {
            Set($0.split(separator: " ").map(String.init))
        } ?? Set(requestedScopes)
        return OAuthTokenSet(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            grantedScopes: grantedScopes
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
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            grantedScopes: response.scope.map {
                Set($0.split(separator: " ").map(String.init))
            } ?? tokens.grantedScopes
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

    public func createCalendarMeeting(
        summary: String?,
        durationMinutes: Int,
        accessToken: String
    ) async throws -> CalendarMeeting {
        let eventID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let requestID = UUID().uuidString
        let start = Date()
        let end = start.addingTimeInterval(TimeInterval(max(durationMinutes, 1) * 60))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let body = CalendarEventInsertRequest(
            id: eventID,
            summary: summary,
            start: .init(dateTime: formatter.string(from: start)),
            end: .init(dateTime: formatter.string(from: end)),
            conferenceData: .init(
                createRequest: .init(
                    requestID: requestID,
                    conferenceSolutionKey: .init(type: "hangoutsMeet")
                )
            )
        )

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [URLQueryItem(name: "conferenceDataVersion", value: "1")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var insertedEvent: CalendarEventResponse?
        for attempt in 0..<2 {
            do {
                insertedEvent = try await send(request)
                break
            } catch {
                if let existingEvent = try? await calendarEvent(
                    eventID: eventID,
                    accessToken: accessToken
                ) {
                    insertedEvent = existingEvent
                    break
                }
                if attempt == 1 { throw error }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        guard var event = insertedEvent else {
            throw MeetBarError.apiError(statusCode: 0, message: "Google Calendar did not return the created event.")
        }
        if let meeting = event.calendarMeeting {
            return meeting
        }

        let pollDelays: [UInt64] = [150, 250, 400, 600, 800, 1_000, 1_200]
        for milliseconds in pollDelays {
            if event.conferenceData?.createRequest?.status?.statusCode == "failure" {
                throw MeetBarError.apiError(statusCode: 0, message: "Google Calendar could not create the Meet conference.")
            }
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            event = try await calendarEvent(eventID: eventID, accessToken: accessToken)
            if let meeting = event.calendarMeeting {
                return meeting
            }
        }

        throw MeetBarError.calendarConferenceTimedOut(event.htmlLink)
    }

    private func calendarEvent(
        eventID: String,
        accessToken: String
    ) async throws -> CalendarEventResponse {
        var request = URLRequest(
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventID)")!
        )
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
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct CalendarEventInsertRequest: Encodable {
    struct DateTime: Encodable {
        let dateTime: String
    }

    struct ConferenceData: Encodable {
        struct CreateRequest: Encodable {
            struct ConferenceSolutionKey: Encodable {
                let type: String
            }

            let requestID: String
            let conferenceSolutionKey: ConferenceSolutionKey

            enum CodingKeys: String, CodingKey {
                case requestID = "requestId"
                case conferenceSolutionKey
            }
        }

        let createRequest: CreateRequest
    }

    let id: String
    let summary: String?
    let start: DateTime
    let end: DateTime
    let conferenceData: ConferenceData
}

private struct CalendarEventResponse: Decodable {
    struct ConferenceData: Decodable {
        struct CreateRequest: Decodable {
            struct Status: Decodable {
                let statusCode: String?
            }
            let status: Status?
        }

        struct EntryPoint: Decodable {
            let entryPointType: String?
            let uri: URL?
        }

        let createRequest: CreateRequest?
        let entryPoints: [EntryPoint]?
    }

    let id: String
    let htmlLink: URL?
    let hangoutLink: URL?
    let conferenceData: ConferenceData?

    var calendarMeeting: CalendarMeeting? {
        guard
            let eventURI = htmlLink,
            let meetingURI = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri
                ?? hangoutLink
        else { return nil }
        return CalendarMeeting(meetingURI: meetingURI, eventURI: eventURI, eventID: id)
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
