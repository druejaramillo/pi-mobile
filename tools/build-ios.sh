#!/usr/bin/env bash
# Generate and compile the native app on a Mac; never change provisioning or install tools.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then
  printf '%s\n' 'Pi Mobile: iOS compilation requires macOS and Xcode. Host checks can run on Linux.' >&2
  exit 2
fi
command -v xcodegen >/dev/null || { printf '%s\n' 'Pi Mobile: install XcodeGen on your Mac, then run this command again.' >&2; exit 2; }
xcrun --find swift >/dev/null
cd "$root/ios"
xcodegen generate --spec project.yml
xcodebuild -project PiMobile.xcodeproj -scheme PiMobile \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$root/ios/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build
