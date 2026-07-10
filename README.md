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

MeetBar does not include a shared Google OAuth client. Each user creates a free Google Cloud project and remains in control of the credentials and Google data the app can access. Allow about 10 minutes for the initial setup.

### 1. Create a Google Cloud project

1. Open the [Google Cloud Console](https://console.cloud.google.com/) and sign in with the Google account you want to administer the project.
2. Use the project picker at the top of the page to select **New Project**.
3. Give it a name such as `MeetBar`, create it, and make sure it remains selected for every step below.

### 2. Enable the Google APIs

Open **APIs & Services → Library** and enable the APIs for the MeetBar features you intend to use:

| Google API | Required for | Setup |
| --- | --- | --- |
| **Google Meet REST API** | Creating every instant meeting | **Required** — [enable it](https://console.cloud.google.com/apis/library/meet.googleapis.com) |
| **Google Calendar API** | Creating a corresponding event, setting its duration, and inviting guests | Optional — [enable it](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com) |
| **People API** | Autocompleting guests from saved contacts and Google's “Other contacts” | Optional — [enable it](https://console.cloud.google.com/apis/library/people.googleapis.com) |

Manual guest email entry only needs the Calendar API. Enable the People API only if you want contact suggestions.

### 3. Configure the Google Auth Platform

Open [Google Auth Platform](https://console.cloud.google.com/auth/overview) for the selected project.

#### Branding

On **Branding**, set an app name such as `MeetBar`, choose a user-support email, and add a developer contact email. A logo and public website are optional for a private installation.

#### Audience

Choose the audience that matches your account:

- **Internal** is available to Google Workspace organisations and limits sign-in to accounts in that organisation.
- **External** works with personal Gmail accounts and accounts outside your Workspace organisation. While the app is in **Testing**, add every Google account you will connect under **Test users**.

Google limits an External app in Testing to 100 test users. Because MeetBar requests non-identity scopes, a Testing authorisation and its refresh token expire after seven days; if that happens, use **Add Google Account** or the relevant **Grant Access** button again. For a long-lived personal setup, Google permits a personal-use project with fewer than 100 users to run In Production without mandatory verification, but users will see the unverified-app warning and the project remains subject to the 100-new-user cap. A shared OAuth client intended for general public use should complete Google's OAuth verification for its sensitive scopes. See Google's current [Audience rules](https://support.google.com/cloud/answer/15549945?hl=en) and [verification exceptions](https://support.google.com/cloud/answer/13464323?hl=en).

#### Data Access

Open **Data Access → Add or remove scopes**. Search for or manually paste the scopes below, add them to the table, then choose **Update** and **Save**.

| Feature | Exact OAuth scope requested by MeetBar | Add when |
| --- | --- | --- |
| Identify the connected Google account | `openid` | **Always** |
| Read the account's primary email address | `email` | **Always** |
| Read the account's name and profile picture | `profile` | **Always** |
| Create an instant Meet | `https://www.googleapis.com/auth/meetings.space.created` | **Always** |
| Create events on calendars you own | `https://www.googleapis.com/auth/calendar.events.owned` | Using Calendar events or guest invites |
| Read saved Google Contacts | `https://www.googleapis.com/auth/contacts.readonly` | Using contact suggestions |
| Read automatically saved “Other contacts” | `https://www.googleapis.com/auth/contacts.other.readonly` | Using contact suggestions |

Google may show `openid`, `email`, and `profile` separately as standard OpenID Connect scopes, or display the email and profile entries using their equivalent `https://www.googleapis.com/auth/userinfo.*` names. Select those standard identity entries when the picker offers them. MeetBar never requests full Calendar access, contact write access, Gmail access, or Google Drive access.

If an API scope is missing from the picker, first confirm its API is enabled, then use the manual scope field. For the full feature set, declare all seven scopes above; for instant meetings only, declare the three identity scopes and `meetings.space.created`.

These values come directly from Google's documentation for [Meet spaces](https://developers.google.com/workspace/meet/api/reference/rest/v2/spaces/create), [Calendar scopes](https://developers.google.com/workspace/calendar/api/auth), [saved-contact search](https://developers.google.com/people/api/rest/v1/people/searchContacts), [Other contacts search](https://developers.google.com/people/api/rest/v1/otherContacts/search), and [OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect).

### 4. Create a Desktop OAuth client

1. Open **Google Auth Platform → Clients**.
2. Choose **Create Client**.
3. Select **Desktop app** as the application type and name it `MeetBar for Mac`.
4. Create the client and download its JSON file.

Do not create a **Web application** client and do not add a redirect URI manually. MeetBar uses Google's [OAuth flow for Desktop apps](https://developers.google.com/identity/protocols/oauth2/native-app) with PKCE, the system browser, and a temporary loopback callback on `127.0.0.1`; Google continues to support loopback redirects for Desktop app clients.

### 5. Import the client and connect accounts

1. Open MeetBar from Applications and click its video icon in the menu bar.
2. Choose **Import Google OAuth Client**, select the downloaded JSON file, and authenticate to macOS Keychain if prompted.
3. Choose **Add Google Account** and approve the Meet creation permission in your browser.
4. Repeat **Add Google Account** for each additional account you want to use.
5. To use Calendar, open **Settings**, enable Calendar events, and choose **Grant Access** for each account.
6. To use contact autocomplete, enable guest invites and choose **Enable Suggestions** for each account. Direct email invites work without this extra Contacts permission.

Optional permissions are granted per account. Enabling a feature in Settings does not silently broaden access for accounts you have already connected.

The OAuth client configuration and refresh tokens are stored as macOS Keychain items and are never copied into this repository. You can delete the downloaded JSON after importing it, although keeping an encrypted backup makes reinstalling easier.

### Google setup troubleshooting

| Problem | What to check |
| --- | --- |
| **Access blocked**, **Error 403: access_denied**, or the account cannot continue | On **Google Auth Platform → Audience**, add that exact email address as a test user. Workspace users should also confirm whether the app is Internal or External. |
| **API has not been used**, **SERVICE_DISABLED**, or a feature fails immediately | Enable the Meet, Calendar, or People API required by that feature in the same project as the OAuth client. Wait a few minutes after enabling it, then retry. |
| A scope does not appear under Data Access | Enable its API first, or paste the full scope URL manually. Use the exact strings in the table above. |
| **redirect_uri_mismatch** | Recreate the OAuth client as **Desktop app**. A Web application client is not compatible with MeetBar's local callback. |
| Meetings work but Calendar or suggestions do not | Open MeetBar **Settings** and grant the optional permission for the currently selected Google account. |
| Google asks for access again after about seven days | The External app is probably still in Testing. Reauthorise the account, or review Google's Production and verification requirements for a longer-lived shared client. |
| macOS repeatedly asks for the login Keychain password | Enter your Mac login password and choose **Always Allow** for that installed build. Ad-hoc-signed community builds can prompt again after an app update; stable cross-version trust requires a Developer ID-signed release. |

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
xcrun stapler staple dist/MeetBar-0.4.1-universal.dmg
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
