#!/usr/bin/env bash
# Prepare owned SwiftTerm source and derive xtool's plist without Xcode variable literals.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/tools/xtool-environment.sh"
command -v swift >/dev/null || {
	printf '%s\n' 'Pi Mobile Linux: Swift is missing; run tools/setup-ios-linux.sh.' >&2
	exit 2
}
command -v git >/dev/null
swiftterm_revision=4dcf5278fde40af60c36f667d8a472a90b38b247
swiftterm_dir="$root/ios/.xtool-dependencies/SwiftTerm"
patch="$root/tools/patches/swiftterm-linux-ios.patch"
mkdir -p "$root/ios/.xtool-dependencies" "$root/ios/.xtool-support"
# A single lock protects dependency preparation; never discard an active owner's lock.
exec 9>"$root/ios/.xtool-dependencies/prepare.lock"
flock -n 9 || {
	printf '%s\n' 'Pi Mobile Linux: dependency preparation is already running.' >&2
	exit 2
}
if [[ ! -e "$swiftterm_dir" ]]; then
	checkout=$(mktemp -d "$root/ios/.xtool-dependencies/swiftterm.XXXXXX")
	# Failed checkouts are retained for diagnosis; no recursive cleanup of user files.
	git -C "$checkout" init --quiet
	git -C "$checkout" remote add origin https://github.com/migueldeicaza/SwiftTerm.git
	git -C "$checkout" fetch --quiet --depth 1 origin "$swiftterm_revision"
	git -C "$checkout" checkout --quiet --detach FETCH_HEAD
	git -C "$checkout" apply --check "$patch"
	git -C "$checkout" apply "$patch"
	mv "$checkout" "$swiftterm_dir"
fi
[[ $(git -C "$swiftterm_dir" rev-parse HEAD) == "$swiftterm_revision" ]] || {
	printf '%s\n' 'Pi Mobile Linux: cached SwiftTerm revision differs from the pin; refusing to overwrite it.' >&2
	exit 2
}
[[ $(git -C "$swiftterm_dir" status --porcelain --untracked-files=all) == ' M Package.swift' ]] || {
	printf '%s\n' 'Pi Mobile Linux: cached SwiftTerm has unexpected changes; refusing to overwrite it.' >&2
	exit 2
}
git -C "$swiftterm_dir" diff --no-ext-diff --no-color --src-prefix=a/ --dst-prefix=b/ -- Package.swift | cmp -s - "$patch" || {
	printf '%s\n' 'Pi Mobile Linux: cached SwiftTerm patch differs from the approved patch.' >&2
	exit 2
}
python3 - "$root" <<'PY'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
info = plistlib.loads((root / "ios/PiMobile/Info.plist").read_bytes())
# Let xtool populate executable/name/identifier from the selected library product.
for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleName"):
    del info[key]
info["UIDeviceFamily"] = [1]
output = root / "ios/.xtool-support/Info.plist"
output.write_bytes(plistlib.dumps(info, sort_keys=False))
PY
printf '%s\n' 'Pi Mobile Linux: pinned dependency and app metadata prepared.'
