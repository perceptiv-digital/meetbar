import SwiftUI

struct MeetBarPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("meetbar.show-recent-meetings") private var showRecentMeetings = false
    @AppStorage("meetbar.create-calendar-event") private var createCalendarEvent = false
    @AppStorage("meetbar.allow-guest-invites") private var allowGuestInvites = false
    @AppStorage("meetbar.show-duration-override") private var showDurationOverride = false
    @FocusState private var isLabelFocused: Bool
    @FocusState private var isGuestFocused: Bool

    private var calendarModeEnabled: Bool {
        createCalendarEvent || ProcessInfo.processInfo.arguments.contains("--preview-calendar")
    }

    private var guestInvitesEnabled: Bool {
        calendarModeEnabled && allowGuestInvites
    }

    private var durationOverrideEnabled: Bool {
        calendarModeEnabled && showDurationOverride
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
                minHeight: formMinimumHeight,
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
            model.resetMeetingOptionsFromDefaults()
            Task { await model.warmContactSearchIfNeeded() }
        }
        .onChange(of: model.meetingLabel) {
            if case .failed = model.creationState {
                model.resetCreationState()
            }
        }
        .onChange(of: model.selectedAccountID) {
            Task { await model.warmContactSearchIfNeeded() }
        }
    }

    private var formMinimumHeight: CGFloat {
        var height: CGFloat = calendarModeEnabled && !model.selectedAccountHasCalendarAccess ? 192 : 150
        if guestInvitesEnabled || durationOverrideEnabled { height += 47 }
        if guestInvitesEnabled && !model.meetingGuests.isEmpty { height += 33 }
        if !model.contactSuggestions.isEmpty { height += CGFloat(min(model.contactSuggestions.count, 5)) * 42 + 8 }
        return height
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

            if guestInvitesEnabled || durationOverrideEnabled {
                HStack(alignment: .top, spacing: 9) {
                    if guestInvitesEnabled {
                        guestComposer
                    }

                    if durationOverrideEnabled {
                        durationMenu
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
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

    private var guestComposer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !model.meetingGuests.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.meetingGuests) { guest in
                            HStack(spacing: 5) {
                                Text(guest.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? guest.email)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                Button {
                                    model.removeGuest(guest)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(guest.email)")
                            }
                            .padding(.leading, 9)
                            .padding(.trailing, 7)
                            .frame(height: 25)
                            .background(Color.accentColor.opacity(0.11), in: Capsule())
                            .help(guest.email)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField(
                    model.selectedAccountHasContactsAccess ? "Add guests by name or email" : "Add guest email",
                    text: $model.guestQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isGuestFocused)
                .onChange(of: model.guestQuery) { model.scheduleContactSearch() }
                .onSubmit { _ = model.commitGuestQuery() }
                .onKeyPress(.downArrow) {
                    model.moveContactSuggestionSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveContactSuggestionSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.clearGuestQuery()
                    return .handled
                }

                if model.selectedAccountHasContactsAccess {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.green)
                        .help("Suggestions from this Google account")
                } else if let account = model.selectedAccount {
                    Button {
                        Task { await model.authorizeContactsAccess(for: account) }
                    } label: {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(model.isWorking)
                    .help("Enable Google contact suggestions")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 39)
            .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isGuestFocused ? Color.accentColor.opacity(0.62) : Color.primary.opacity(0.06), lineWidth: isGuestFocused ? 1.4 : 1)
            }

            if !model.contactSuggestions.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(model.contactSuggestions.prefix(5).enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            model.chooseContactSuggestion(suggestion)
                            isGuestFocused = true
                        } label: {
                            HStack(spacing: 9) {
                                ZStack {
                                    Circle().fill(Color.accentColor.opacity(0.11))
                                    Text(suggestion.displayName?.first.map { String($0).uppercased() } ?? String(suggestion.email.prefix(1)).uppercased())
                                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 0) {
                                    if let name = suggestion.displayName, !name.isEmpty {
                                        Text(name)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    Text(suggestion.email)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if index == model.selectedContactSuggestionIndex {
                                    Image(systemName: "return")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                index == model.selectedContactSuggestionIndex
                                    ? Color.accentColor.opacity(0.09)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 9, y: 4)
            }

            if let message = model.guestValidationMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var durationMenu: some View {
        Menu {
            ForEach([15, 30, 45, 60], id: \.self) { duration in
                Button {
                    model.meetingDurationMinutes = duration
                } label: {
                    if model.meetingDurationMinutes == duration {
                        Label("\(duration) minutes", systemImage: "checkmark")
                    } else {
                        Text("\(duration) minutes")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("\(model.meetingDurationMinutes) min")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 39)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Override this meeting's duration")
        .accessibilityLabel("Meeting duration, \(model.meetingDurationMinutes) minutes")
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
                if guestInvitesEnabled && model.selectedAccountHasContactsAccess {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.green)
                        .help("Contact suggestions enabled")
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
                successDetail,
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
            outcome.invitedGuestCount > 0
                ? "Meet ready. Calendar event added, \(outcome.invitedGuestCount) guest\(outcome.invitedGuestCount == 1 ? "" : "s") invited, and link copied to clipboard. Opening Google Meet."
                : outcome.createdCalendarEvent
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

    private var successDetail: String {
        if outcome.invitedGuestCount > 0 {
            return "Event added · \(outcome.invitedGuestCount) guest\(outcome.invitedGuestCount == 1 ? "" : "s") invited · Link copied"
        }
        return outcome.createdCalendarEvent ? "Event added · Link copied" : "Link copied to clipboard"
    }
}
