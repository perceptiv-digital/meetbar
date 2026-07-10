# MeetBar

MeetBar is a small, open-source macOS menu-bar app for creating an instant Google Meet in one keystroke.

Click the video icon, optionally add a local label, and press Return. MeetBar creates the meeting with your selected Google account, copies the URL to the clipboard, and opens it in your default browser.

## Features

- Native SwiftUI menu-bar app with no third-party runtime dependencies
- Multiple Google accounts with a quick account picker
- Google profile avatars with an automatic initials fallback
- Google OAuth 2.0 installed-app flow with PKCE and a loopback callback
- Refresh tokens stored in macOS Keychain
- Least-privilege `meetings.space.created` Google scope
- Automatic clipboard copy and default-browser launch
- Animated “Meet ready” reinforcement with tactile feedback
- Optional primary-calendar event with the same native Google Meet link
- Opt-in Calendar permission per Google account and configurable event duration
- Optional guest invitations with direct email entry and native Calendar notifications
- Read-only, per-account suggestions from Google Contacts and previously emailed contacts
- Optional compact per-meeting duration override that resets to the configured default
- Floating contact autocomplete that does not resize or shift the main popover
- Right-click menu-bar shortcuts for a new meeting, the last link, Settings, version, and Quit
- Optional local recent-meeting history, off by default
- Shared spark-camera identity across the menu bar and app icon
- Universal DMG packaging for Apple silicon and Intel Macs
- XCTest suite, portable smoke tests, and GitHub Actions CI

## Install

1. Download the latest DMG from [Releases](https://github.com/perceptiv-digital/meetbar/releases).
2. Open the DMG and drag MeetBar into Applications.
3. Open MeetBar. Its video icon appears in the macOS menu bar; it does not appear in the Dock.

The initial community build is ad-hoc signed. On first launch, macOS may require you to Control-click MeetBar and choose **Open**, or allow it in **System Settings → Privacy & Security**. A Developer ID certificate and Apple notarization are required to remove this warning.

MeetBar supports macOS 14 Sonoma or later. The supplied universal DMG runs natively on Apple silicon and Intel Macs.

## Connect Google

MeetBar does not ship someone else's Google OAuth credentials. Each user controls their own Google Cloud client:

1. Create or select a project in [Google Cloud Console](https://console.cloud.google.com/).
2. [Enable the Google Meet REST API](https://console.cloud.google.com/apis/library/meet.googleapis.com). For optional Calendar events, also [enable the Google Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com). For name and email suggestions, [enable the People API](https://console.cloud.google.com/apis/library/people.googleapis.com).
3. Configure the [OAuth consent screen](https://console.cloud.google.com/auth/overview). Add `calendar.events.owned` for Calendar mode and the two read-only Contacts scopes for suggestions. During testing, add your Google accounts as test users.
4. Create an OAuth client with application type **Desktop app**.
5. Download its JSON file.
6. In MeetBar, choose **Import Google OAuth Client…**, select that JSON, then choose **Add Google Account**.

The OAuth client JSON is stored in your Keychain. It is never copied into the repository.

## Meeting labels

Google's instant Meet Spaces API does not provide a meeting-title field. In instant-only mode, MeetBar treats the optional name as a local label for recent history. When Calendar mode is enabled, the same name becomes the Calendar event title; leaving it blank lets Google use its normal untitled-event behavior.

## Build locally

Command Line Tools are enough to compile and package MeetBar:

```sh
./scripts/check-environment.sh
./scripts/test.sh
./scripts/package.sh
open dist/MeetBar.app
```

By default, the DMG is written to `dist/MeetBar-0.4.1-arm64.dmg`. Use `ARCH=universal ./scripts/package.sh` to make the public dual-architecture build.

Full Xcode is recommended and required for the complete XCTest workflow:

```sh
xcode-select --install  # Command Line Tools only, if missing
# Install Xcode from the Mac App Store, then:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
./scripts/test.sh
```

You can open `Package.swift` directly in Xcode. The project targets macOS 14+ and uses Swift 5 language mode for compatibility with modern Xcode releases.

## Embed an OAuth configuration

Maintainers can create a build with a project-owned Desktop OAuth client embedded in the app bundle:

```sh
GOOGLE_OAUTH_CONFIG=/absolute/path/to/client_secret.json ./scripts/package.sh
```

Desktop client IDs are public identifiers, but publishing an app-owned client also makes the maintainer responsible for Google's OAuth consent-screen configuration, brand verification, test-user limits, and API compliance. Never commit the JSON file.

## Signed and notarized releases

Local builds use ad-hoc signing. For a public zero-warning release, set `SIGNING_IDENTITY` to a **Developer ID Application** identity when packaging, then notarize the DMG:

```sh
SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" ./scripts/package.sh
xcrun notarytool submit dist/MeetBar-0.4.1-universal.dmg \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple dist/MeetBar-0.3.0-universal.dmg
```

The release workflow supports the same process through GitHub Actions secrets; see [RELEASING.md](docs/RELEASING.md).

## Privacy and security

- OAuth and refresh tokens are stored as generic-password items in macOS Keychain.
- Account metadata and up to five meeting links/labels are stored locally in `UserDefaults`.
- MeetBar requests identity (`openid`, `email`, `profile`) and meeting-space creation access. The owned-calendar-events scope is requested only when Calendar events are enabled. Read-only Contacts and Other contacts scopes are requested separately only when the user enables suggestions for an account.
- Contact search results are held in memory for the open session and are never written to disk.
- OAuth uses PKCE, a random state value, the system browser, and a callback listener bound to `127.0.0.1`.
- MeetBar has no analytics, advertising, backend, or telemetry.

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Contributing

Issues and pull requests are welcome. Run `./scripts/test.sh` before submitting changes. Please keep dependencies minimal and avoid broadening Google scopes without a documented product need and privacy review.

## License

MIT © Perceptiv Digital
