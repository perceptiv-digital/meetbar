# Security policy

## Supported versions

Security fixes are applied to the latest release of MeetBar.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting feature in the Security tab of this repository. Include reproduction steps, affected versions, and likely impact.

MeetBar stores Google refresh tokens in macOS Keychain. Its baseline authorization requests only identity and Google Meet meeting-space creation access; owned-calendar-events and read-only contact scopes are requested incrementally when users enable those features. Changes that broaden OAuth scopes or move credentials or contact data outside their current Keychain/in-memory boundaries require explicit security review.
