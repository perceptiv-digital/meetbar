import Foundation
import XCTest
@testable import MeetBarCore

final class MeetBarCoreTests: XCTestCase {
    func testParsesDesktopCredentials() throws {
        let json = """
        {"installed":{"client_id":"client.apps.googleusercontent.com","client_secret":"secret","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
        """
        let credentials = try OAuthCredentials.parseGoogleDesktopJSON(Data(json.utf8))
        XCTAssertEqual(credentials.clientID, "client.apps.googleusercontent.com")
        XCTAssertEqual(credentials.clientSecret, "secret")
        XCTAssertEqual(credentials.tokenEndpoint.absoluteString, "https://oauth2.googleapis.com/token")
    }

    func testRejectsWebCredentials() {
        let json = #"{"web":{"client_id":"wrong-client"}}"#
        XCTAssertThrowsError(try OAuthCredentials.parseGoogleDesktopJSON(Data(json.utf8))) { error in
            XCTAssertEqual(error as? MeetBarError, .invalidOAuthConfiguration)
        }
    }

    func testProducesKnownPKCEChallenge() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(PKCE.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testTokenRefreshLeeway() {
        let now = Date(timeIntervalSince1970: 1_000)
        let token = OAuthTokenSet(accessToken: "access", refreshToken: "refresh", expiresAt: now.addingTimeInterval(30))
        XCTAssertTrue(token.needsRefresh(now: now))
        XCTAssertFalse(token.needsRefresh(now: now, leeway: 10))
    }

    func testOldTokenDataDecodesWithoutGrantedScopes() throws {
        let json = #"{"accessToken":"access","refreshToken":"refresh","expiresAt":1000}"#
        let token = try JSONDecoder().decode(OAuthTokenSet.self, from: Data(json.utf8))
        XCTAssertTrue(token.grantedScopes.isEmpty)
    }

    func testOldAccountDataDecodesWithoutGrantedScopes() throws {
        let json = #"{"id":"1","email":"person@example.com","displayName":"Person"}"#
        let account = try JSONDecoder().decode(MeetAccount.self, from: Data(json.utf8))
        XCTAssertTrue(account.grantedScopes.isEmpty)
    }

    func testDecodesMeetingSpace() throws {
        let json = #"{"name":"spaces/abc","meetingUri":"https://meet.google.com/abc-defg-hij","meetingCode":"abc-defg-hij"}"#
        let space = try JSONDecoder().decode(MeetingSpace.self, from: Data(json.utf8))
        XCTAssertEqual(space.meetingURI.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(space.meetingCode, "abc-defg-hij")
    }

    func testAuthorizationURLUsesNarrowScopeAndPKCE() {
        let url = OAuthRequestBuilder.authorizationURL(
            credentials: OAuthCredentials(clientID: "client", clientSecret: nil),
            redirectURI: URL(string: "http://127.0.0.1:9876/oauth/callback")!,
            state: "state",
            codeChallenge: "challenge"
        )
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertTrue(query["scope"]?.contains("meetings.space.created") == true)
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:9876/oauth/callback")
    }

    func testCalendarScopeIsOptIn() {
        XCTAssertFalse(OAuthRequestBuilder.scopes.contains(OAuthRequestBuilder.calendarEventsOwnedScope))
        XCTAssertTrue(
            OAuthRequestBuilder.scopes(includeCalendar: true)
                .contains(OAuthRequestBuilder.calendarEventsOwnedScope)
        )
    }

    func testContactScopesAreOptIn() {
        XCTAssertFalse(OAuthRequestBuilder.scopes.contains(OAuthRequestBuilder.contactsReadOnlyScope))
        XCTAssertFalse(OAuthRequestBuilder.scopes.contains(OAuthRequestBuilder.otherContactsReadOnlyScope))
        let scopes = OAuthRequestBuilder.scopes(includeCalendar: true, includeContacts: true)
        XCTAssertTrue(scopes.contains(OAuthRequestBuilder.contactsReadOnlyScope))
        XCTAssertTrue(scopes.contains(OAuthRequestBuilder.otherContactsReadOnlyScope))
        XCTAssertTrue(scopes.contains(OAuthRequestBuilder.calendarEventsOwnedScope))
    }

    func testEmailAddressValidation() {
        XCTAssertTrue(EmailAddressValidator.isValid("person@example.com"))
        XCTAssertTrue(EmailAddressValidator.isValid(" person+meet@example.co.uk "))
        XCTAssertFalse(EmailAddressValidator.isValid("person"))
        XCTAssertFalse(EmailAddressValidator.isValid("person@example"))
        XCTAssertFalse(EmailAddressValidator.isValid("person @example.com"))
        XCTAssertFalse(EmailAddressValidator.isValid("person@team@example.com"))
    }

    func testCreatesCalendarEventAndUsesReturnedMeetLink() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CalendarURLProtocolStub.self]
        let api = GoogleAPI(session: URLSession(configuration: configuration))

        CalendarURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/calendar/v3/calendars/primary/events")
            XCTAssertEqual(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "conferenceDataVersion" })?.value,
                "1"
            )
            XCTAssertEqual(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "sendUpdates" })?.value,
                "all"
            )

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["summary"] as? String, "Design review")
            XCTAssertNotNil(json["start"])
            XCTAssertNotNil(json["end"])
            XCTAssertNotNil(json["conferenceData"])
            let attendees = try XCTUnwrap(json["attendees"] as? [[String: String]])
            XCTAssertEqual(attendees, [["email": "guest@example.com"]])
            let start = try XCTUnwrap(json["start"] as? [String: String])
            let end = try XCTUnwrap(json["end"] as? [String: String])
            let formatter = ISO8601DateFormatter()
            let startDate = try XCTUnwrap(start["dateTime"].flatMap { formatter.date(from: $0) })
            let endDate = try XCTUnwrap(end["dateTime"].flatMap { formatter.date(from: $0) })
            XCTAssertEqual(endDate.timeIntervalSince(startDate), 30 * 60, accuracy: 1)

            let response = """
            {
              "id": "calendar-event-id",
              "htmlLink": "https://calendar.google.com/calendar/event?eid=calendar-event-id",
              "conferenceData": {
                "entryPoints": [
                  {"entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij"}
                ],
                "createRequest": {"status": {"statusCode": "success"}}
              }
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }

        let meeting = try await api.createCalendarMeeting(
            summary: "Design review",
            durationMinutes: 30,
            guests: [MeetingGuest(email: "guest@example.com", displayName: "Guest")],
            accessToken: "access"
        )
        XCTAssertEqual(meeting.meetingURI.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(meeting.eventID, "calendar-event-id")
    }

    func testCalendarEventWithoutGuestsOmitsAttendeesAndNotifications() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CalendarWithoutGuestsURLProtocolStub.self]
        let api = GoogleAPI(session: URLSession(configuration: configuration))

        CalendarWithoutGuestsURLProtocolStub.handler = { request in
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertNil(queryItems.first(where: { $0.name == "sendUpdates" }))
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(json["attendees"])

            let response = """
            {
              "id": "event-without-guests",
              "htmlLink": "https://calendar.google.com/calendar/event?eid=event-without-guests",
              "hangoutLink": "https://meet.google.com/no-guest-link"
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }

        _ = try await api.createCalendarMeeting(
            summary: nil,
            durationMinutes: 45,
            accessToken: "access"
        )
    }

    func testContactSearchMergesAndDeduplicatesSameAccountResults() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContactsURLProtocolStub.self]
        let api = GoogleAPI(session: URLSession(configuration: configuration))

        ContactsURLProtocolStub.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "query" })?.value
            XCTAssertEqual(query, "ali")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")

            let response: String
            if request.url?.path == "/v1/people:searchContacts" {
                response = """
                {"results":[
                  {"person":{"names":[{"displayName":"Alice Adams"}],"emailAddresses":[{"value":"alice@example.com"}]}},
                  {"person":{"names":[{"displayName":"Ali Cooper"}],"emailAddresses":[{"value":"ali@example.com"}]}}
                ]}
                """
            } else {
                response = """
                {"results":[
                  {"person":{"names":[{"displayName":"Alice Duplicate"}],"emailAddresses":[{"value":"ALICE@example.com"}]}},
                  {"person":{"names":[{"displayName":"Alison Other"}],"emailAddresses":[{"value":"alison@example.com"}]}}
                ]}
                """
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }

        let suggestions = try await api.searchContactSuggestions(query: "ali", accessToken: "access")
        XCTAssertEqual(suggestions.map(\.email), ["alice@example.com", "ali@example.com", "alison@example.com"])
        XCTAssertEqual(suggestions.first?.source, .contact)
    }
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { return nil }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}

private final class CalendarURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class CalendarWithoutGuestsURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class ContactsURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
