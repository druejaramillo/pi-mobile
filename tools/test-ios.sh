#!/usr/bin/env bash
# Run only the approved native tests, on an explicitly selected Simulator, never a physical device.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then
  printf '%s\n' 'Pi Mobile: native tests require macOS and Xcode 26+; run host tests on Linux.' >&2
  exit 2
fi
if [[ $# != 1 ]]; then
  printf '%s\n' "Usage: ./tools/test-ios.sh 'platform=iOS Simulator,id=<UDID>'" >&2
  printf '%s\n' 'Choose a fresh Simulator using: xcrun simctl list devices available' >&2
  exit 2
fi
destination=$1
case "$destination" in
  "platform=iOS Simulator,"*) ;;
  *) printf '%s\n' 'Pi Mobile: this test script accepts only an iOS Simulator destination.' >&2; exit 2 ;;
esac
"$root/tools/build-ios.sh"
xcrun swift test --package-path "$root/ios/PiMobileCore"
mkdir -p "$root/ios/TestResults"
results="$root/ios/TestResults/native-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
xcodebuild -project "$root/ios/PiMobile.xcodeproj" -scheme PiMobile \
  -destination "$destination" \
  -derivedDataPath "$root/ios/DerivedData" \
  -resultBundlePath "$results" \
  CODE_SIGNING_ALLOWED=NO test
printf 'Native test evidence: %s\n' "$results"
