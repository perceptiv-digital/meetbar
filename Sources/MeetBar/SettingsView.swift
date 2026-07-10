import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("meetbar.show-recent-meetings") private var showRecentMeetings = false
    @AppStorage("meetbar.create-calendar-event") private var createCalendarEvent = false
    @AppStorage("meetbar.calendar-event-duration") private var calendarEventDuration = 30

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
                Text("Create a Desktop OAuth client in Google Cloud, enable the Google Meet REST API, and optionally enable the Google Calendar API before importing the JSON file.")
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
                    Picker("Event duration", selection: $calendarEventDuration) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                    .pickerStyle(.segmented)

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
                Text("OAuth tokens stay in your macOS Keychain. Calendar permission is requested only when you enable Calendar events. Meeting links and labels stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 590)
        .navigationTitle("MeetBar Settings")
    }
}
