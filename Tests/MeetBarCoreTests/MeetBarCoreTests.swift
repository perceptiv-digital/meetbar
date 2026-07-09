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
}
