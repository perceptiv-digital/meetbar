import SwiftUI

struct MeetBarPopover: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isLabelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("New Google Meet", systemImage: "video.fill")
                    .font(.headline)
                Spacer()
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if model.accounts.isEmpty {
                onboarding
            } else {
                meetingForm
                recentMeetings
            }

            if let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit") { model.quit() }
                    .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { isLabelFocused = !model.accounts.isEmpty }
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect a Google account to create instant meetings.")
                .foregroundStyle(.secondary)

            if !model.hasOAuthConfiguration {
                Button("Import Google OAuth Client…") {
                    model.importOAuthConfiguration()
                }
            } else {
                Button("Add Google Account") {
                    Task { await model.addGoogleAccount() }
                }
                .disabled(model.isWorking)
            }
        }
    }

    private var meetingForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Account", selection: $model.selectedAccountID) {
                ForEach(model.accounts) { account in
                    Text(account.email).tag(account.id)
                }
            }

            TextField("Meeting label (optional)", text: $model.meetingLabel)
                .textFieldStyle(.roundedBorder)
                .focused($isLabelFocused)
                .onSubmit { Task { await model.createMeeting() } }

            Button {
                Task { await model.createMeeting() }
            } label: {
                Label("Create & Open Meet", systemImage: "video.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(model.isWorking || model.selectedAccount == nil)

            Text("The label is kept only in MeetBar history; Google Meet does not expose titles for instant meeting spaces.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var recentMeetings: some View {
        if !model.recentMeetings.isEmpty {
            Divider()
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.recentMeetings.prefix(3)) { meeting in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.label.isEmpty ? meeting.meetingURL.lastPathComponent : meeting.label)
                            .lineLimit(1)
                        Text(meeting.accountEmail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.copy(meeting.meetingURL) } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy link")
                    Button { model.open(meeting.meetingURL) } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help("Open meeting")
                }
            }
        }
    }
}
