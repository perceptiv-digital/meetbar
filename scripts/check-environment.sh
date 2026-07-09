#!/bin/zsh
set -u

failures=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "✓ $label"
  else
    echo "✗ $label"
    failures=$((failures + 1))
  fi
}

check "Swift compiler" command -v swift
check "Swift Package Manager" command -v swift
check "macOS SDK" xcrun --sdk macosx --show-sdk-path
check "DMG tooling" command -v hdiutil
check "Code signing tooling" command -v codesign
check "GitHub CLI" command -v gh

if [[ -d /Applications/Xcode.app ]]; then
  echo "✓ Full Xcode (recommended for XCTest, UI tests, and archives)"
else
  echo "! Full Xcode is not installed. Command Line Tools can build MeetBar, but full test and archive workflows require Xcode."
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  echo "✓ Developer ID Application certificate"
else
  echo "! No Developer ID Application certificate. Local ad-hoc DMGs work, but public zero-warning installs require signing and notarization."
fi

exit "$failures"
