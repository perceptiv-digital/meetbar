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

            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["summary"] as? String, "Design review")
            XCTAssertNotNil(json["start"])
            XCTAssertNotNil(json["end"])
            XCTAssertNotNil(json["conferenceData"])

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
            accessToken: "access"
        )
        XCTAssertEqual(meeting.meetingURI.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(meeting.eventID, "calendar-event-id")
    }
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
