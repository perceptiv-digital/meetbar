import AppKit
import Foundation
import MeetBarCore

@MainActor
final class AppModel: ObservableObject {
    struct MeetingCreationOutcome: Equatable {
        let meetingURL: URL
        let calendarEventURL: URL?
        let invitedGuestCount: Int

        var createdCalendarEvent: Bool { calendarEventURL != nil }
    }

    enum MeetingCreationState: Equatable {
        case idle
        case creating
        case ready(MeetingCreationOutcome)
        case failed(String)
    }

    @Published private(set) var accounts: [MeetAccount] = []
    @Published private(set) var recentMeetings: [MeetingRecord] = []
    @Published var selectedAccountID: String = "" {
        didSet {
            defaults.set(selectedAccountID, forKey: selectedAccountKey)
            if oldValue != selectedAccountID {
                clearMeetingGuests()
            }
        }
    }
    @Published var meetingLabel: String = ""
    @Published var guestQuery: String = ""
    @Published private(set) var meetingGuests: [MeetingGuest] = []
    @Published private(set) var contactSuggestions: [ContactSuggestion] = []
    @Published private(set) var selectedContactSuggestionIndex = 0
    @Published private(set) var guestValidationMessage: String?
    @Published var meetingDurationMinutes = 30
    @Published private(set) var isWorking = false
    @Published private(set) var creationState: MeetingCreationState = .idle
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
    private let calendarEventsKey = "meetbar.create-calendar-event"
    private let calendarDurationKey = "meetbar.calendar-event-duration"
    private let allowGuestInvitesKey = "meetbar.allow-guest-invites"
    private let showDurationOverrideKey = "meetbar.show-duration-override"
    private var contactSearchTask: Task<Void, Never>?
    private var contactWarmupAccountIDs = Set<String>()
    private let isSuccessPreview = ProcessInfo.processInfo.arguments.contains("--preview-success")
    private let isCalendarPreview = ProcessInfo.processInfo.arguments.contains("--preview-calendar")

    init() {
        loadPersistedState()
        if isSuccessPreview {
            creationState = .ready(
                MeetingCreationOutcome(
                    meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")!,
                    calendarEventURL: isCalendarPreview
                        ? URL(string: "https://calendar.google.com/calendar/event?eid=preview")!
                        : nil,
                    invitedGuestCount: 0
                )
            )
        }
    }

    var selectedAccount: MeetAccount? {
        accounts.first { $0.id == selectedAccountID }
    }

    var createsCalendarEvents: Bool {
        defaults.bool(forKey: calendarEventsKey)
    }

    var allowsGuestInvites: Bool {
        createsCalendarEvents && defaults.bool(forKey: allowGuestInvitesKey)
    }

    var showsDurationOverride: Bool {
        createsCalendarEvents && defaults.bool(forKey: showDurationOverrideKey)
    }

    var selectedAccountHasCalendarAccess: Bool {
        selectedAccount.map(hasCalendarAccess) ?? false
    }

    var selectedAccountHasContactsAccess: Bool {
        selectedAccount.map(hasContactsAccess) ?? false
    }

    func hasCalendarAccess(_ account: MeetAccount) -> Bool {
        account.grantedScopes.contains(OAuthRequestBuilder.calendarEventsOwnedScope)
    }

    func hasContactsAccess(_ account: MeetAccount) -> Bool {
        account.grantedScopes.contains(OAuthRequestBuilder.contactsReadOnlyScope)
            && account.grantedScopes.contains(OAuthRequestBuilder.otherContactsReadOnlyScope)
    }

    func importOAuthConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "Choose Google OAuth client JSON"
        panel.message = "Choose credentials for a Google OAuth Desktop app with the Meet API enabled. Calendar and People APIs are optional."
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
            let requestedScopes = OAuthRequestBuilder.scopes(
                includeCalendar: createsCalendarEvents,
                includeContacts: allowsGuestInvites
            )
            let (account, tokens) = try await authorizeGoogleAccount(requestedScopes: requestedScopes)
            try vault.save(tokens, key: tokenKey(for: account.id))
            upsertAccount(account)
            selectedAccountID = account.id
            persistAccounts()
            statusMessage = "Connected \(account.email)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func authorizeCalendarAccess(for account: MeetAccount) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        statusMessage = "Opening Google Calendar permission…"
        defer { isWorking = false }

        do {
            guard let existingTokens = try vault.load(OAuthTokenSet.self, key: tokenKey(for: account.id)) else {
                throw MeetBarError.missingRefreshToken
            }
            let requestedScopes = OAuthRequestBuilder.scopes(
                includeCalendar: true,
                includeContacts: hasContactsAccess(account)
            )
            let (authorizedAccount, tokens) = try await authorizeGoogleAccount(
                requestedScopes: requestedScopes,
                loginHint: account.email,
                existingTokens: existingTokens
            )
            guard authorizedAccount.id == account.id else {
                throw MeetBarError.calendarAccountMismatch
            }

            try vault.save(tokens, key: tokenKey(for: account.id))
            upsertAccount(authorizedAccount)
            persistAccounts()
            statusMessage = "Calendar access granted for \(account.email)."
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func authorizeContactsAccess(for account: MeetAccount) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        statusMessage = "Opening Google Contacts permission…"
        defer { isWorking = false }

        do {
            guard let existingTokens = try vault.load(OAuthTokenSet.self, key: tokenKey(for: account.id)) else {
                throw MeetBarError.missingRefreshToken
            }
            let requestedScopes = OAuthRequestBuilder.scopes(
                includeCalendar: hasCalendarAccess(account) || createsCalendarEvents,
                includeContacts: true
            )
            let (authorizedAccount, tokens) = try await authorizeGoogleAccount(
                requestedScopes: requestedScopes,
                loginHint: account.email,
                existingTokens: existingTokens
            )
            guard authorizedAccount.id == account.id else {
                throw MeetBarError.calendarAccountMismatch
            }

            try vault.save(tokens, key: tokenKey(for: account.id))
            upsertAccount(authorizedAccount)
            persistAccounts()
            statusMessage = "Contact suggestions enabled for \(account.email)."
            await warmContactSearchIfNeeded()
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
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
        if allowsGuestInvites, !guestQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard commitGuestQuery() else { return }
        }
        isWorking = true
        creationState = .creating
        statusMessage = nil
        lastMeetingURL = nil

        do {
            guard let account = selectedAccount else { throw MeetBarError.missingAccount }
            let accessToken = try await validAccessToken(for: account)

            let label = meetingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let outcome: MeetingCreationOutcome
            if createsCalendarEvents {
                guard hasCalendarAccess(account) else {
                    throw MeetBarError.calendarPermissionRequired
                }
                let configuredDuration = defaults.integer(forKey: calendarDurationKey)
                let duration = showsDurationOverride
                    ? meetingDurationMinutes
                    : (configuredDuration > 0 ? configuredDuration : 30)
                let guests = allowsGuestInvites ? meetingGuests : []
                let calendarMeeting = try await api.createCalendarMeeting(
                    summary: label.isEmpty ? nil : label,
                    durationMinutes: duration,
                    guests: guests,
                    accessToken: accessToken
                )
                outcome = MeetingCreationOutcome(
                    meetingURL: calendarMeeting.meetingURI,
                    calendarEventURL: calendarMeeting.eventURI,
                    invitedGuestCount: guests.count
                )
            } else {
                let meeting = try await api.createMeeting(accessToken: accessToken)
                outcome = MeetingCreationOutcome(
                    meetingURL: meeting.meetingURI,
                    calendarEventURL: nil,
                    invitedGuestCount: 0
                )
            }

            let record = MeetingRecord(
                label: label,
                meetingURL: outcome.meetingURL,
                accountEmail: account.email
            )
            recentMeetings.insert(record, at: 0)
            recentMeetings = Array(recentMeetings.prefix(5))
            persistRecentMeetings()

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(outcome.meetingURL.absoluteString, forType: .string)
            lastMeetingURL = outcome.meetingURL
            meetingLabel = ""
            clearMeetingGuests()
            resetDurationOverride()
            if outcome.invitedGuestCount > 0 {
                statusMessage = "Calendar event added, \(outcome.invitedGuestCount) guest\(outcome.invitedGuestCount == 1 ? "" : "s") invited, and meeting link copied."
            } else {
                statusMessage = outcome.createdCalendarEvent
                    ? "Calendar event added and meeting link copied."
                    : "Meeting opened and link copied."
            }
            creationState = .ready(outcome)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

            try? await Task.sleep(nanoseconds: 650_000_000)
            NSWorkspace.shared.open(outcome.meetingURL)
            try? await Task.sleep(nanoseconds: 900_000_000)

            if case .ready = creationState {
                creationState = .idle
            }
        } catch {
            statusMessage = error.localizedDescription
            creationState = .failed(error.localizedDescription)
        }
        isWorking = false
    }

    func resetCreationState() {
        guard !isWorking, !isSuccessPreview else { return }
        creationState = .idle
    }

    func resetMeetingOptionsFromDefaults() {
        guard !isWorking else { return }
        resetDurationOverride()
    }

    func scheduleContactSearch() {
        guestValidationMessage = nil
        contactSearchTask?.cancel()
        let query = guestQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, selectedAccountHasContactsAccess else {
            contactSuggestions = []
            selectedContactSuggestionIndex = 0
            return
        }

        let accountID = selectedAccountID
        contactSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self, let account = self.selectedAccount, account.id == accountID else { return }
            do {
                let accessToken = try await self.validAccessToken(for: account)
                let suggestions = try await self.api.searchContactSuggestions(
                    query: query,
                    accessToken: accessToken
                )
                guard !Task.isCancelled, self.guestQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                let existingEmails = Set(self.meetingGuests.map { $0.email.lowercased() })
                self.contactSuggestions = suggestions.filter { !existingEmails.contains($0.email.lowercased()) }
                self.selectedContactSuggestionIndex = 0
            } catch {
                guard !Task.isCancelled else { return }
                self.contactSuggestions = []
            }
        }
    }

    func warmContactSearchIfNeeded() async {
        guard
            allowsGuestInvites,
            let account = selectedAccount,
            hasContactsAccess(account),
            !contactWarmupAccountIDs.contains(account.id)
        else { return }

        do {
            let accessToken = try await validAccessToken(for: account)
            contactWarmupAccountIDs.insert(account.id)
            await api.warmContactSearch(accessToken: accessToken)
        } catch {
            contactWarmupAccountIDs.remove(account.id)
        }
    }

    func moveContactSuggestionSelection(by offset: Int) {
        guard !contactSuggestions.isEmpty else { return }
        selectedContactSuggestionIndex = min(
            max(selectedContactSuggestionIndex + offset, 0),
            contactSuggestions.count - 1
        )
    }

    func chooseContactSuggestion(_ suggestion: ContactSuggestion) {
        _ = addGuest(suggestion.guest)
    }

    @discardableResult
    func commitGuestQuery() -> Bool {
        if contactSuggestions.indices.contains(selectedContactSuggestionIndex) {
            return addGuest(contactSuggestions[selectedContactSuggestionIndex].guest)
        }

        let email = guestQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddressValidator.isValid(email) else {
            guestValidationMessage = MeetBarError.invalidGuestEmail.localizedDescription
            return false
        }
        return addGuest(MeetingGuest(email: email))
    }

    func removeGuest(_ guest: MeetingGuest) {
        meetingGuests.removeAll { $0.id == guest.id }
        guestValidationMessage = nil
    }

    func clearGuestQuery() {
        guestQuery = ""
        contactSuggestions = []
        selectedContactSuggestionIndex = 0
        guestValidationMessage = nil
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

    private func authorizeGoogleAccount(
        requestedScopes: [String],
        loginHint: String? = nil,
        existingTokens: OAuthTokenSet? = nil
    ) async throws -> (MeetAccount, OAuthTokenSet) {
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
            codeChallenge: PKCE.challenge(for: verifier),
            loginHint: loginHint,
            requestedScopes: requestedScopes
        )
        NSWorkspace.shared.open(authorizationURL)

        let callback = try await callbackTask.value
        guard callback.state == state else { throw MeetBarError.oauthStateMismatch }
        var tokens = try await api.exchangeAuthorizationCode(
            callback.code,
            codeVerifier: verifier,
            redirectURI: redirectURI,
            credentials: credentials,
            requestedScopes: requestedScopes,
            existingRefreshToken: existingTokens?.refreshToken
        )
        tokens.grantedScopes.formUnion(existingTokens?.grantedScopes ?? [])
        let profile = try await api.profile(accessToken: tokens.accessToken)
        let account = MeetAccount(
            id: profile.id,
            email: profile.email,
            displayName: profile.displayName,
            grantedScopes: tokens.grantedScopes
        )
        return (account, tokens)
    }

    private func validAccessToken(for account: MeetAccount) async throws -> String {
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
        return tokens.accessToken
    }

    @discardableResult
    private func addGuest(_ guest: MeetingGuest) -> Bool {
        guard meetingGuests.count < 20 else {
            guestValidationMessage = MeetBarError.guestLimitReached.localizedDescription
            return false
        }
        let normalizedEmail = guest.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddressValidator.isValid(normalizedEmail) else {
            guestValidationMessage = MeetBarError.invalidGuestEmail.localizedDescription
            return false
        }
        if !meetingGuests.contains(where: { $0.email.caseInsensitiveCompare(normalizedEmail) == .orderedSame }) {
            meetingGuests.append(MeetingGuest(email: normalizedEmail, displayName: guest.displayName))
        }
        clearGuestQuery()
        return true
    }

    private func clearMeetingGuests() {
        contactSearchTask?.cancel()
        meetingGuests = []
        clearGuestQuery()
    }

    private func resetDurationOverride() {
        let configuredDuration = defaults.integer(forKey: calendarDurationKey)
        meetingDurationMinutes = configuredDuration > 0 ? configuredDuration : 30
    }

    private func upsertAccount(_ account: MeetAccount) {
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        accounts.sort { $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending }
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
        resetDurationOverride()
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
