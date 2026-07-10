# Changelog

All notable changes to MeetBar are documented here.

## 0.4.0 - 2026-07-10

- Add optional Calendar guest invitations with polished removable guest tokens
- Add fast name and email suggestions from the selected account's Google Contacts and Other contacts
- Keep manual email invitations available without granting Contacts access
- Request read-only Contacts permission separately for each Google account
- Add keyboard navigation, validation, deduplication, and a 20-guest safety limit
- Add an optional compact per-meeting duration override that resets to the configured default
- Send Google Calendar invitation updates only when an event has guests
- Expand the success state to confirm the number of invited guests and clipboard copy

## 0.3.0 - 2026-07-10

- Add an optional Settings mode that creates a primary Google Calendar event and native Meet together
- Use the meeting name as the event title and omit the title when the field is blank
- Add configurable 15, 30, 45, or 60-minute event duration
- Request owned-calendar-events permission only for accounts using the feature
- Add per-account Calendar permission status and a one-click grant flow
- Poll asynchronous Calendar conference creation and reuse its exact Meet URL
- Add idempotent event IDs to prevent duplicate events during retry handling
- Update create and success states to clearly show when a Calendar event is added

## 0.2.0 - 2026-07-10

- Redesign the popover around a faster, keyboard-first create flow
- Add animated success reinforcement, clipboard confirmation, and subtle haptic feedback
- Delay browser opening briefly so the success state is visible
- Hide recent meetings by default and add a Settings toggle
- Introduce a shared spark-camera menu-bar mark and app icon
- Improve hierarchy, spacing, account switching, hover states, and accessibility labels

## 0.1.1 - 2026-07-10

- Ship a universal DMG that runs natively on Apple silicon and Intel Macs

## 0.1.0 - 2026-07-10

- Initial native macOS menu-bar app
- Instant Google Meet space creation
- Multi-account Google OAuth with PKCE
- Keychain-backed token storage
- Automatic browser launch and clipboard copy
- Local labels and recent meeting history
- ARM64 DMG packaging and release automation
