# Security policy

## Supported versions

Security fixes are applied to the latest release of MeetBar.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting feature in the Security tab of this repository. Include reproduction steps, affected versions, and likely impact.

MeetBar stores Google refresh tokens in macOS Keychain and intentionally requests only the Google Meet meeting-space creation scope. Changes that broaden OAuth scopes or move credentials outside Keychain require explicit security review.
