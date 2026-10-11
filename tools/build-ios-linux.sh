#!/usr/bin/env bash
# Build an unsigned physical-iPhone app; never log in, sign, deploy or download an SDK.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/tools/xtool-environment.sh"
[[ $(uname -s) == Linux ]] || {
	printf '%s\n' 'Pi Mobile Linux: this command is the Linux device-build lane; use build-ios.sh on a Mac.' >&2
	exit 2
}
command -v swift >/dev/null || {
	printf '%s\n' 'Pi Mobile Linux: run tools/setup-ios-linux.sh to install the private compiler.' >&2
	exit 2
}
command -v xtool >/dev/null || {
	printf '%s\n' 'Pi Mobile Linux: run tools/setup-ios-linux.sh to install xtool.' >&2
	exit 2
}
[[ $(xtool --version) == 'xtool 1.21.0' ]] || {
	printf '%s\n' 'Pi Mobile Linux: this build lane is pinned to xtool 1.21.0.' >&2
	exit 2
}
swift_version=$(swift --version)
[[ $swift_version =~ Swift\ version\ ([0-9]+)\.([0-9]+) ]] && ((BASH_REMATCH[1] == 6 && BASH_REMATCH[2] == 4)) || {
	printf '%s\n' 'Pi Mobile Linux: this build lane requires Swift 6.4.' >&2
	exit 2
}
sdk_status=$(xtool sdk status)
if [[ $sdk_status != 'Darwin SDK is installed'$'\n'* ]]; then
	printf '%s\n' 'Pi Mobile Linux: missing Apple SDK. Download Xcode 27.xip from Apple, then run tools/setup-ios-linux.sh --sdk /absolute/path/Xcode.xip.' >&2
	exit 2
fi
sdk_bundle=$(printf '%s\n' "$sdk_status" | awk '/^  Path: / { sub(/^  Path: /, ""); print; exit }')
export PI_MOBILE_IOS_SDK_SETTINGS="$sdk_bundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/SDKSettings.json"
PI_MOBILE_IOS_SDK_VERSION=$(python3 - "$PI_MOBILE_IOS_SDK_SETTINGS" <<'PY'
import json, pathlib, re, sys
settings = json.loads(pathlib.Path(sys.argv[1]).read_text())
version = settings['Version']
if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', version) or int(version.split('.')[0]) < 26:
    raise SystemExit('Pi Mobile Linux: native Liquid Glass requires an Apple iPhone SDK version 26 or newer.')
print(version)
PY
)
export PI_MOBILE_IOS_SDK_VERSION
"$root/tools/prepare-ios-linux.sh"
export SWIFTTERM_TARGET_APPLE=1
mkdir -p "$root/ios/TestResults"
log="$root/ios/TestResults/xtool-build-$(date -u +%Y%m%dT%H%M%SZ).log"
cd "$root/ios"
# xtool's supported custom-bin seam bypasses SwiftPM's broken cross-target manifest cache.
SWIFTPM_CUSTOM_BIN_DIR="$root/tools/xtool-swiftpm" xtool dev build --configuration debug 2>&1 | tee "$log"
python3 - "$root" <<'PY'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
app = root / 'ios/xtool/PiMobile.app'
info = plistlib.loads((app / 'Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != 'com.druejaramillo.pi-mobile' or info.get('UIDeviceFamily') != [1]:
    raise SystemExit('Pi Mobile Linux: built app identity/device family differs from the contract.')
if not (app / 'PiMobile').is_file() or not (app / 'AppIcon.png').is_file():
    raise SystemExit('Pi Mobile Linux: built app is missing its executable or icon.')
if (app / 'voxtype-profile.json').read_bytes() != (root / 'ios/PiMobile/Resources/voxtype-profile.json').read_bytes():
    raise SystemExit('Pi Mobile Linux: built app dictation profile differs from the source profile.')
PY
python3 "$root/tools/check-iphone-build-metadata.py" "$root/ios/xtool/PiMobile.app" --sdk-settings "$PI_MOBILE_IOS_SDK_SETTINGS"
printf 'Unsigned app: %s\nBuild evidence: %s\n' "$root/ios/xtool/PiMobile.app" "$log"
