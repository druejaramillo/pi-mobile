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
swift_version=$(xcrun swift -version)
if [[ $swift_version =~ Swift\ version\ ([0-9]+)\.([0-9]+) ]]; then
  major=${BASH_REMATCH[1]}
  minor=${BASH_REMATCH[2]}
  if (( major < 6 || (major == 6 && minor < 2) )); then
    printf '%s\n' 'Pi Mobile: pinned SwiftTerm requires Swift 6.2 or newer (Xcode 26+).' >&2
    exit 2
  fi
else
  printf '%s\n' 'Pi Mobile: could not determine the selected Xcode Swift version.' >&2
  exit 2
fi
"$root/tools/prepare-ssh-dependency.sh"
"$root/tools/prepare-tailscale-client.sh" iphonesimulator
cd "$root/ios"
xcodegen generate --spec project.yml
xcodebuild -project PiMobile.xcodeproj -scheme PiMobile \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$root/ios/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build
