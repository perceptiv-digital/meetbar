import Foundation
import MeetBarCore

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        failures += 1
        print("✗ \(message)")
    }
}

let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
check(
    PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
    "PKCE challenge matches RFC 7636"
)

let desktopJSON = """
{"installed":{"client_id":"client.apps.googleusercontent.com","client_secret":"secret"}}
"""
do {
    let credentials = try OAuthCredentials.parseGoogleDesktopJSON(Data(desktopJSON.utf8))
    check(credentials.clientID == "client.apps.googleusercontent.com", "Desktop OAuth credentials parse")
} catch {
    failures += 1
    print("✗ Desktop OAuth credentials parse: \(error)")
}

let responseJSON = #"{"name":"spaces/abc","meetingUri":"https://meet.google.com/abc-defg-hij","meetingCode":"abc-defg-hij"}"#
do {
    let meeting = try JSONDecoder().decode(MeetingSpace.self, from: Data(responseJSON.utf8))
    check(meeting.meetingURI.host == "meet.google.com", "Meet API response decodes")
} catch {
    failures += 1
    print("✗ Meet API response decodes: \(error)")
}

let authorizationURL = OAuthRequestBuilder.authorizationURL(
    credentials: OAuthCredentials(clientID: "client", clientSecret: nil),
    redirectURI: URL(string: "http://127.0.0.1:54321/oauth/callback")!,
    state: "state",
    codeChallenge: "challenge"
)
let queryItems = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
check(query["scope"]?.contains("meetings.space.created") == true, "Authorization uses Meet create-only scope")
check(query["code_challenge_method"] == "S256", "Authorization requires PKCE")

if failures > 0 {
    print("\n\(failures) smoke test(s) failed.")
    exit(1)
}

print("\nAll MeetBar smoke tests passed.")
