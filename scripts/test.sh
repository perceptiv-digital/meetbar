#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

echo "Running portable smoke tests..."
swift run MeetBarSmokeTests

if [[ -d /Applications/Xcode.app ]]; then
  echo "Running XCTest suite with Xcode..."
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --parallel
else
  echo "Full Xcode is not installed; XCTest suite skipped. Install Xcode to run the complete suite."
fi
