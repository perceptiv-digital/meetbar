import SwiftUI

struct MeetBarPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("meetbar.show-recent-meetings") private var showRecentMeetings = false
    @AppStorage("meetbar.create-calendar-event") private var createCalendarEvent = false
    @FocusState private var isLabelFocused: Bool

    private var calendarModeEnabled: Bool {
        createCalendarEvent || ProcessInfo.processInfo.arguments.contains("--preview-calendar")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Group {
                if model.accounts.isEmpty {
                    onboarding
                } else if case .ready(let outcome) = model.creationState {
                    MeetSuccessView(outcome: outcome)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else {
                    meetingForm
                        .transition(.opacity)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: calendarModeEnabled && !model.selectedAccountHasCalendarAccess ? 192 : 150,
                alignment: .top
            )
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84), value: model.creationState)

            if showRecentMeetings && !model.recentMeetings.isEmpty && !model.isWorking {
                recentMeetings
                    .padding(.top, 14)
            }

            footer
                .padding(.top, 14)
        }
        .padding(18)
        .frame(width: 372)
        .background(.ultraThinMaterial)
        .onAppear {
            isLabelFocused = !model.accounts.isEmpty
            model.resetCreationState()
        }
        .onChange(of: model.meetingLabel) {
            if case .failed = model.creationState {
                model.resetCreationState()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            MeetBarBrandMark(size: 36)
                .shadow(color: Color.indigo.opacity(0.18), radius: 7, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("MeetBar")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Start a room in one keystroke")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.creationState == .creating || (model.isWorking && model.accounts.isEmpty) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            }
        }
        .padding(.bottom, 17)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Google to start creating instant meetings.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            MeetPrimaryButton(title: model.hasOAuthConfiguration ? "Add Google Account" : "Import Google OAuth Client", icon: "person.crop.circle.badge.plus", isLoading: model.isWorking) {
                if model.hasOAuthConfiguration {
                    Task { await model.addGoogleAccount() }
                } else {
                    model.importOAuthConfiguration()
                }
            }
        }
    }

    private var meetingForm: some View {
        VStack(alignment: .leading, spacing: 11) {
            accountMenu

            if calendarModeEnabled && !model.selectedAccountHasCalendarAccess {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Calendar access needed")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Button("Grant") {
                        guard let account = model.selectedAccount else { return }
                        Task { await model.authorizeCalendarAccess(for: account) }
                    }
                    .buttonStyle(.link)
                    .disabled(model.isWorking)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 9) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField("Name this meet (optional)", text: $model.meetingLabel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .focused($isLabelFocused)
                    .onSubmit { Task { await model.createMeeting() } }

                if !model.meetingLabel.isEmpty {
                    Button {
                        model.meetingLabel = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear meeting name")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isLabelFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.07), lineWidth: isLabelFocused ? 1.5 : 1)
            }

            MeetPrimaryButton(
                title: model.creationState == .creating
                    ? (calendarModeEnabled ? "Creating event & Meet…" : "Creating your Meet…")
                    : (calendarModeEnabled ? "Create Meet + Event" : "Create instant Meet"),
                icon: calendarModeEnabled ? "calendar.badge.plus" : "video.fill",
                isLoading: model.creationState == .creating
            ) {
                Task { await model.createMeeting() }
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(
                model.isWorking
                    || model.selectedAccount == nil
                    || (calendarModeEnabled && !model.selectedAccountHasCalendarAccess)
            )

            if case .failed(let message) = model.creationState {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            ForEach(model.accounts) { account in
                Button {
                    model.selectedAccountID = account.id
                } label: {
                    if account.id == model.selectedAccountID {
                        Label(account.email, systemImage: "checkmark")
                    } else {
                        Text(account.email)
                    }
                }
            }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                    Text(model.selectedAccount?.email.first.map { String($0).uppercased() } ?? "G")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 25, height: 25)

                Text(model.selectedAccount?.email ?? "Choose account")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
                if calendarModeEnabled && model.selectedAccountHasCalendarAccess {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                        .help("Calendar event enabled")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .accessibilityLabel("Google account")
    }

    private var recentMeetings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.bottom, 10)

            HStack {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Saved on this Mac")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 5)

            ForEach(model.recentMeetings.prefix(3)) { meeting in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meeting.label.isEmpty ? meeting.meetingURL.lastPathComponent : meeting.label)
                            .font(.system(size: 12.5, weight: .medium))
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
                .padding(.vertical, 5)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            Spacer()

            if !model.accounts.isEmpty {
                Text("RETURN")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                Image(systemName: "return")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            Button { model.quit() } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit MeetBar")
            .padding(.leading, 7)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct MeetPrimaryButton: View {
    let title: String
    let icon: String
    let isLoading: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))

                Spacer()

                if !isLoading {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.72)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 43)
            .background(
                LinearGradient(
                    colors: isHovering
                        ? [Color(red: 0.19, green: 0.49, blue: 1), Color(red: 0.42, green: 0.28, blue: 0.96)]
                        : [Color(red: 0.16, green: 0.42, blue: 0.96), Color(red: 0.36, green: 0.23, blue: 0.89)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .shadow(color: Color.indigo.opacity(isHovering ? 0.28 : 0.18), radius: isHovering ? 10 : 6, y: 3)
        }
        .buttonStyle(MeetPressButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { isHovering = hovering }
        }
        .accessibilityHint("Creates a Google Meet, copies its link, and opens it in your browser")
    }
}

private struct MeetPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct MeetSuccessView: View {
    let outcome: AppModel.MeetingCreationOutcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false
    private let burstColors: [Color] = [.blue, .indigo, .mint, .cyan]

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(burstColors[index % burstColors.count])
                        .frame(width: 3, height: 9)
                        .rotationEffect(.degrees(Double(index) * 30))
                        .offset(y: burst ? -42 : -22)
                        .opacity(burst ? 0 : 0.9)
                        .scaleEffect(burst ? 0.7 : 0.25)
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.17, green: 0.77, blue: 0.55), Color(red: 0.10, green: 0.62, blue: 0.48)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.green.opacity(0.25), radius: 12, y: 4)

                Image(systemName: "checkmark")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .scaleEffect(burst ? 1 : 0.55)
            }
            .frame(height: 70)

            Text("Meet ready")
                .font(.system(size: 17, weight: .bold, design: .rounded))

            Label(
                outcome.createdCalendarEvent ? "Event added · Link copied" : "Link copied to clipboard",
                systemImage: outcome.createdCalendarEvent ? "calendar.badge.checkmark" : "doc.on.doc.fill"
            )
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Opening \(outcome.meetingURL.host ?? "Google Meet")…")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            outcome.createdCalendarEvent
                ? "Meet ready. Calendar event added and link copied to clipboard. Opening Google Meet."
                : "Meet ready. Link copied to clipboard. Opening Google Meet."
        )
        .onAppear {
            guard !reduceMotion else {
                burst = true
                return
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.68)) {
                burst = true
            }
        }
    }
}
