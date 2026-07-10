# Releasing MeetBar

## Community build

The default release workflow creates a universal Apple silicon and Intel, ad-hoc-signed DMG. It is functional but macOS displays a Gatekeeper warning on first launch.

1. Update the version in `Resources/Info.plist` and `CHANGELOG.md`.
2. Run `./scripts/test.sh` and `./scripts/package.sh`.
3. Push a tag matching the app version, such as `v0.1.1`.
4. GitHub Actions creates the release and uploads the DMG.

## Developer ID build

For a normal public install experience, add these GitHub Actions secrets:

- `APPLE_CERTIFICATE_P12_BASE64`: Developer ID Application certificate exported as P12 and base64 encoded
- `APPLE_CERTIFICATE_PASSWORD`: P12 export password
- `APPLE_SIGNING_IDENTITY`: full Developer ID Application identity
- `APPLE_ID`: notarization Apple ID
- `APPLE_TEAM_ID`: Apple Developer team ID
- `APPLE_APP_PASSWORD`: app-specific Apple ID password

The release workflow imports the certificate into a temporary keychain, signs with the hardened runtime, submits the DMG to Apple's notary service, and staples the result. If the secrets are absent, it falls back to an ad-hoc community build. Never store a certificate, password, OAuth client JSON, or Keychain file in the repository.

## Verification

After downloading the release asset:

```sh
codesign --verify --deep --strict --verbose=2 /Applications/MeetBar.app
spctl --assess --type execute --verbose=2 /Applications/MeetBar.app
```

A notarized release should report `accepted` from `spctl`.
