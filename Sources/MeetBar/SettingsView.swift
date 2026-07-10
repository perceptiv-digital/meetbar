import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("meetbar.show-recent-meetings") private var showRecentMeetings = false
    @AppStorage("meetbar.create-calendar-event") private var createCalendarEvent = false
    @AppStorage("meetbar.calendar-event-duration") private var calendarEventDuration = 30
    @AppStorage("meetbar.allow-guest-invites") private var allowGuestInvites = false
    @AppStorage("meetbar.show-duration-override") private var showDurationOverride = false

    var body: some View {
        Form {
            Section("Google API") {
                HStack {
                    Image(systemName: model.hasOAuthConfiguration ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.hasOAuthConfiguration ? .green : .orange)
                    Text(model.hasOAuthConfiguration ? "OAuth desktop client configured" : "OAuth desktop client required")
                    Spacer()
                    Button(model.hasOAuthConfiguration ? "Replace…" : "Import…") {
                        model.importOAuthConfiguration()
                    }
                }
                Text("Create a Desktop OAuth client in Google Cloud, enable the Google Meet REST API, and optionally enable the Calendar and People APIs before importing the JSON file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Google Accounts") {
                if model.accounts.isEmpty {
                    Text("No accounts connected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.displayName)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                model.removeAccount(account)
                            }
                        }
                    }
                }

                Button("Add Google Account") {
                    Task { await model.addGoogleAccount() }
                }
                .disabled(!model.hasOAuthConfiguration || model.isWorking)

                if let message = model.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Experience") {
                Toggle("Show recent meetings in the menu", isOn: $showRecentMeetings)
                Text("Off by default for a faster, more focused create flow. When enabled, MeetBar shows up to three recent meeting links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Create a Google Calendar event", isOn: $createCalendarEvent)
                    .onChange(of: createCalendarEvent) {
                        guard
                            createCalendarEvent,
                            let account = model.selectedAccount,
                            !model.hasCalendarAccess(account)
                        else { return }
                        Task { await model.authorizeCalendarAccess(for: account) }
                    }

                if createCalendarEvent {
                    Picker("Default event duration", selection: $calendarEventDuration) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Show a duration override in MeetBar", isOn: $showDurationOverride)
                    Text("Adds a compact duration control to the menu. Each meeting starts at the default above; an override applies only to that meeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Allow guest invites", isOn: $allowGuestInvites)
                        .onChange(of: allowGuestInvites) {
                            guard
                                allowGuestInvites,
                                let account = model.selectedAccount,
                                !model.hasContactsAccess(account)
                            else { return }
                            Task { await model.authorizeContactsAccess(for: account) }
                        }

                    if allowGuestInvites {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.accounts) { account in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(account.email)
                                            .lineLimit(1)
                                        Text(model.hasContactsAccess(account) ? "Google suggestions enabled" : "Manual email invites available")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if model.hasContactsAccess(account) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .help("Read-only contact suggestions enabled")
                                    } else {
                                        Button("Enable Suggestions") {
                                            Task { await model.authorizeContactsAccess(for: account) }
                                        }
                                        .disabled(model.isWorking)
                                    }
                                }
                            }
                        }

                        Text("Guest emails are added directly to the Calendar event. Suggestions use read-only access to this account's Google Contacts and Other contacts; MeetBar never saves the contact list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.accounts) { account in
                            HStack {
                                Label(
                                    account.email,
                                    systemImage: model.hasCalendarAccess(account)
                                        ? "checkmark.circle.fill"
                                        : "calendar.badge.exclamationmark"
                                )
                                .foregroundStyle(model.hasCalendarAccess(account) ? .green : .secondary)

                                Spacer()

                                if !model.hasCalendarAccess(account) {
                                    Button("Grant Access") {
                                        Task { await model.authorizeCalendarAccess(for: account) }
                                    }
                                    .disabled(model.isWorking)
                                }
                            }
                        }
                    }

                    Text("Calendar access is opt-in per Google account. MeetBar creates events only on that account's primary calendar and never lists, changes, or deletes existing events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Text("OAuth tokens stay in your macOS Keychain. Calendar and read-only Contacts permissions are requested only when their features are enabled. Contact results are kept in memory only; meeting links and labels stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 680)
        .navigationTitle("MeetBar Settings")
    }
}
