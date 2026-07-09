import AppKit
import Foundation
import MeetBarCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [MeetAccount] = []
    @Published private(set) var recentMeetings: [MeetingRecord] = []
    @Published var selectedAccountID: String = "" {
        didSet { defaults.set(selectedAccountID, forKey: selectedAccountKey) }
    }
    @Published var meetingLabel: String = ""
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastMeetingURL: URL?
    @Published private(set) var hasOAuthConfiguration = false

    private let api = GoogleAPI()
    private let vault = KeychainVault()
    private let defaults = UserDefaults.standard
    private let accountsKey = "meetbar.accounts"
    private let selectedAccountKey = "meetbar.selected-account"
    private let recentMeetingsKey = "meetbar.recent-meetings"
    private let credentialsKey = "google-oauth-credentials"

    init() {
        loadPersistedState()
    }

    var selectedAccount: MeetAccount? {
        accounts.first { $0.id == selectedAccountID }
    }

    func importOAuthConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "Choose Google OAuth client JSON"
        panel.message = "Choose credentials for a Google OAuth Desktop app with the Google Meet REST API enabled."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let credentials = try OAuthCredentials.parseGoogleDesktopJSON(Data(contentsOf: url))
            try vault.save(credentials, key: credentialsKey)
            hasOAuthConfiguration = true
            statusMessage = "Google OAuth configuration imported."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addGoogleAccount() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Opening Google sign-in…"
        defer { isWorking = false }

        do {
            guard let credentials = try vault.load(OAuthCredentials.self, key: credentialsKey) else {
                throw MeetBarError.invalidOAuthConfiguration
            }
            let verifier = try PKCE.makeVerifier()
            let state = try PKCE.makeVerifier(byteCount: 32)
            let server = LoopbackOAuthServer()
            let redirectURI = try await server.start()
            let callbackTask = Task { try await server.waitForCallback() }
            await Task.yield()
            let authorizationURL = OAuthRequestBuilder.authorizationURL(
                credentials: credentials,
                redirectURI: redirectURI,
                state: state,
                codeChallenge: PKCE.challenge(for: verifier)
            )
            NSWorkspace.shared.open(authorizationURL)

            let callback = try await callbackTask.value
            guard callback.state == state else { throw MeetBarError.oauthStateMismatch }
            let tokens = try await api.exchangeAuthorizationCode(
                callback.code,
                codeVerifier: verifier,
                redirectURI: redirectURI,
                credentials: credentials
            )
            let account = try await api.profile(accessToken: tokens.accessToken)
            try vault.save(tokens, key: tokenKey(for: account.id))

            accounts.removeAll { $0.id == account.id }
            accounts.append(account)
            accounts.sort { $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending }
            selectedAccountID = account.id
            persistAccounts()
            statusMessage = "Connected \(account.email)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func removeAccount(_ account: MeetAccount) {
        do {
            try vault.delete(key: tokenKey(for: account.id))
            accounts.removeAll { $0.id == account.id }
            if selectedAccountID == account.id {
                selectedAccountID = accounts.first?.id ?? ""
            }
            persistAccounts()
            statusMessage = "Removed \(account.email)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createMeeting() async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Creating Google Meet…"
        lastMeetingURL = nil
        defer { isWorking = false }

        do {
            guard let account = selectedAccount else { throw MeetBarError.missingAccount }
            guard let credentials = try vault.load(OAuthCredentials.self, key: credentialsKey) else {
                throw MeetBarError.invalidOAuthConfiguration
            }
            guard var tokens = try vault.load(OAuthTokenSet.self, key: tokenKey(for: account.id)) else {
                throw MeetBarError.missingRefreshToken
            }
            if tokens.needsRefresh() {
                tokens = try await api.refresh(tokens, credentials: credentials)
                try vault.save(tokens, key: tokenKey(for: account.id))
            }

            let meeting = try await api.createMeeting(accessToken: tokens.accessToken)
            let label = meetingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = MeetingRecord(
                label: label,
                meetingURL: meeting.meetingURI,
                accountEmail: account.email
            )
            recentMeetings.insert(record, at: 0)
            recentMeetings = Array(recentMeetings.prefix(5))
            persistRecentMeetings()

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(meeting.meetingURI.absoluteString, forType: .string)
            NSWorkspace.shared.open(meeting.meetingURI)
            lastMeetingURL = meeting.meetingURI
            meetingLabel = ""
            statusMessage = "Meeting opened and link copied."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        statusMessage = "Meeting link copied."
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func loadPersistedState() {
        if let data = defaults.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([MeetAccount].self, from: data) {
            accounts = decoded
        }
        if let data = defaults.data(forKey: recentMeetingsKey),
           let decoded = try? JSONDecoder().decode([MeetingRecord].self, from: data) {
            recentMeetings = decoded
        }
        selectedAccountID = defaults.string(forKey: selectedAccountKey) ?? accounts.first?.id ?? ""
        hasOAuthConfiguration = (try? vault.load(OAuthCredentials.self, key: credentialsKey)) != nil

        if !hasOAuthConfiguration,
           let bundledURL = Bundle.main.url(forResource: "GoogleOAuthConfig", withExtension: "json"),
           let data = try? Data(contentsOf: bundledURL),
           let credentials = try? OAuthCredentials.parseGoogleDesktopJSON(data) {
            try? vault.save(credentials, key: credentialsKey)
            hasOAuthConfiguration = true
        }
    }

    private func persistAccounts() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: accountsKey)
        defaults.set(selectedAccountID, forKey: selectedAccountKey)
    }

    private func persistRecentMeetings() {
        defaults.set(try? JSONEncoder().encode(recentMeetings), forKey: recentMeetingsKey)
    }

    private func tokenKey(for accountID: String) -> String {
        "google-oauth-tokens.\(accountID)"
    }
}
