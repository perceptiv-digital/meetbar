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
            displayName: response.name ?? response.email,
            profileImageURL: response.picture
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
        guests: [MeetingGuest] = [],
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
            attendees: guests.isEmpty ? nil : guests.map { .init(email: $0.email) },
            conferenceData: .init(
                createRequest: .init(
                    requestID: requestID,
                    conferenceSolutionKey: .init(type: "hangoutsMeet")
                )
            )
        )

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [URLQueryItem(name: "conferenceDataVersion", value: "1")]
        if !guests.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "sendUpdates", value: "all"))
        }
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

    public func warmContactSearch(accessToken: String) async {
        async let contacts: Void = warmContactEndpoint(
            URL(string: "https://people.googleapis.com/v1/people:searchContacts")!,
            accessToken: accessToken
        )
        async let otherContacts: Void = warmContactEndpoint(
            URL(string: "https://people.googleapis.com/v1/otherContacts:search")!,
            accessToken: accessToken
        )
        _ = await (contacts, otherContacts)
    }

    public func searchContactSuggestions(
        query: String,
        accessToken: String,
        limit: Int = 8
    ) async throws -> [ContactSuggestion] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        async let contactsResult = searchContactEndpoint(
            URL(string: "https://people.googleapis.com/v1/people:searchContacts")!,
            query: trimmedQuery,
            source: .contact,
            accessToken: accessToken,
            limit: limit
        )
        async let otherContactsResult = searchContactEndpoint(
            URL(string: "https://people.googleapis.com/v1/otherContacts:search")!,
            query: trimmedQuery,
            source: .otherContact,
            accessToken: accessToken,
            limit: limit
        )

        let contacts = try await contactsResult
        let otherContacts = try await otherContactsResult
        var seenEmails = Set<String>()
        return (contacts + otherContacts).filter { suggestion in
            seenEmails.insert(suggestion.email.lowercased()).inserted
        }.prefix(limit).map { $0 }
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

    private func warmContactEndpoint(_ endpoint: URL, accessToken: String) async {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: ""),
            URLQueryItem(name: "readMask", value: "names,emailAddresses"),
            URLQueryItem(name: "pageSize", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let _: PeopleSearchResponse? = try? await send(request)
    }

    private func searchContactEndpoint(
        _ endpoint: URL,
        query: String,
        source: ContactSuggestion.Source,
        accessToken: String,
        limit: Int
    ) async throws -> [ContactSuggestion] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "readMask", value: "names,emailAddresses"),
            URLQueryItem(name: "pageSize", value: String(min(max(limit, 1), 30)))
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: PeopleSearchResponse = try await send(request)
        return response.results.flatMap { result -> [ContactSuggestion] in
            let name = result.person.names?.first?.displayName
            return (result.person.emailAddresses ?? []).compactMap { value -> ContactSuggestion? in
                guard let email = value.value, EmailAddressValidator.isValid(email) else { return nil }
                return ContactSuggestion(email: email, displayName: name, source: source)
            }
        }
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

    struct Attendee: Encodable {
        let email: String
    }

    let id: String
    let summary: String?
    let start: DateTime
    let end: DateTime
    let attendees: [Attendee]?
    let conferenceData: ConferenceData
}

private struct PeopleSearchResponse: Decodable {
    struct Result: Decodable {
        struct Person: Decodable {
            struct Name: Decodable {
                let displayName: String?
            }

            struct EmailAddress: Decodable {
                let value: String?
            }

            let names: [Name]?
            let emailAddresses: [EmailAddress]?
        }

        let person: Person
    }

    let results: [Result]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([Result].self, forKey: .results) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case results
    }
}

public enum EmailAddressValidator {
    public static func isValid(_ value: String) -> Bool {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard email.count <= 254, parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard
            !local.isEmpty,
            local.count <= 64,
            !domain.isEmpty,
            !domain.hasPrefix("."),
            !domain.hasSuffix("."),
            domain.contains(".")
        else { return false }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>,;"))
        return email.rangeOfCharacter(from: forbidden) == nil
    }
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
    let picture: URL?
}

private struct GoogleErrorEnvelope: Decodable {
    struct GoogleError: Decodable {
        let message: String
    }

    let error: GoogleError
}
