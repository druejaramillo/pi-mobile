#!/usr/bin/env bash
# Explicitly sign/install the existing app on one caller-selected USB iPhone, once.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/tools/xtool-environment.sh"
[[ $(uname -s) == Linux ]] || {
	printf '%s\n' 'Pi Mobile Linux: this is the Linux USB-deployment lane; use the Xcode project on a Mac.' >&2
	exit 2
}
[[ $# == 1 && $1 =~ ^[A-Fa-f0-9-]{16,64}$ ]] || {
	printf '%s\n' 'Usage: tools/deploy-ios-linux.sh <chosen-iPhone-UDID>' >&2
	exit 2
}
udid=$1
command -v xtool >/dev/null || {
	printf '%s\n' 'Pi Mobile Linux: run tools/setup-ios-linux.sh first.' >&2
	exit 2
}
[[ $(xtool --version) == 'xtool 1.21.0' ]] || {
	printf '%s\n' 'Pi Mobile Linux: deployment is pinned to xtool 1.21.0.' >&2
	exit 2
}
app="$root/ios/xtool/PiMobile.app"
[[ -f $app/Info.plist && -f $app/PiMobile ]] || {
	printf '%s\n' 'Pi Mobile Linux: no built app; run tools/build-ios-linux.sh first.' >&2
	exit 2
}
python3 - "$app" <<'PY'
import pathlib, plistlib, sys
app=pathlib.Path(sys.argv[1])
info=plistlib.loads((app/'Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != 'com.druejaramillo.pi-mobile':
    raise SystemExit('Pi Mobile Linux: unexpected app identity; refusing deployment.')
if not (app/'voxtype-profile.json').is_file():
    raise SystemExit('Pi Mobile Linux: missing bundled dictation profile; refusing deployment.')
PY
# Compiling new APIs is not enough: refuse a stale executable that still opts into legacy UI.
python3 "$root/tools/check-iphone-build-metadata.py" "$app"
auth_status=$(xtool auth status)
if [[ $auth_status != 'Logged in.'$'\n'* ]]; then
	printf '%s\n' 'Pi Mobile Linux: signing is not configured. Run source tools/xtool-environment.sh, then xtool auth login --mode key in your terminal.' >&2
	exit 2
fi
command -v idevice_id >/dev/null || {
	printf '%s\n' 'Pi Mobile Linux: install libimobiledevice and usbmuxd, then connect/trust the iPhone.' >&2
	exit 2
}
idevice_id -l | grep -Fxq -- "$udid" || {
	printf '%s\n' 'Pi Mobile Linux: the selected USB iPhone is not visible. Connect/unlock/trust it and enable Developer Mode.' >&2
	exit 2
}
# xtool stages a copy, provisions/signs it, and installs it. Certificate revocation
# remains xtool's explicit interactive prompt; do not answer it automatically.
# No captured auth transcript and no automatic retry after an uncertain install.
xtool install --usb --udid "$udid" "$app"
printf '%s\n' 'Pi Mobile Linux: installer returned successfully. Open Pi Mobile on that iPhone and run the real-device checklist; installation alone is not runtime verification.'
