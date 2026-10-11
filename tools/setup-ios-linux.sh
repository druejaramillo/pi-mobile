#!/usr/bin/env bash
# Install verified build tools privately; only --sdk installs an Apple SDK supplied by you.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/tools/xtool-environment.sh"
sdk_path=''
if [[ $# -gt 0 ]]; then
	[[ $# == 2 && $1 == --sdk && -f $2 ]] || {
		printf '%s\n' 'Usage: tools/setup-ios-linux.sh [--sdk /absolute/path/Xcode.xip]' >&2
		exit 2
	}
	sdk_path=$(realpath "$2")
fi
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
	printf '%s\n' 'Pi Mobile Linux: this private toolchain bootstrap supports Linux x86_64.' >&2
	exit 2
}
for tool in curl sha256sum tar bsdtar flock python3; do command -v "$tool" >/dev/null; done
mkdir -p "$pi_mobile_toolchain_root/downloads" "$pi_mobile_toolchain_root/bin"
exec 9>"$pi_mobile_toolchain_root/setup.lock"
flock -n 9 || {
	printf '%s\n' 'Pi Mobile Linux: toolchain setup is already running.' >&2
	exit 2
}
# Download to an owned staging file and publish only after the pinned hash matches.
download_verified_tool() {
	local url=$1 hash=$3 output="$pi_mobile_toolchain_root/downloads/$2"
	if [[ ! -f $output ]]; then
		curl --fail --location --compressed --retry 2 --connect-timeout 20 --max-time 900 "$url" -o "$output.part"
		printf '%s  %s\n' "$hash" "$output.part" | sha256sum --check
		mv "$output.part" "$output"
	fi
	printf '%s  %s\n' "$hash" "$output" | sha256sum --check
}
download_verified_tool https://github.com/xtool-org/xtool/releases/download/1.21.0/xtool-x86_64.AppImage \
	xtool-1.21.0-x86_64.AppImage e2277e59bb2fda9b487cbc77ad080ea2b0370bb740ac0f02cc42fa28a272d3a5
chmod 755 "$pi_mobile_toolchain_root/downloads/xtool-1.21.0-x86_64.AppImage"
if [[ ! -e "$pi_mobile_toolchain_root/bin/xtool" && ! -L "$pi_mobile_toolchain_root/bin/xtool" ]]; then
	ln -s ../downloads/xtool-1.21.0-x86_64.AppImage "$pi_mobile_toolchain_root/bin/xtool"
fi
download_verified_tool https://download.swift.org/swift-6.4.0-release/ubuntu2204/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-ubuntu22.04.tar.gz \
	swift-6.4.0.tar.gz bce85ea80f1471b85f39993f9285dbc798ec8e1eac5f677e24b2ac693856f9f8
if [[ ! -d "$pi_mobile_toolchain_root/swift-6.4.0-RELEASE-ubuntu22.04" ]]; then
	staging=$(mktemp -d "$pi_mobile_toolchain_root/swift-install.XXXXXX")
	tar -xzf "$pi_mobile_toolchain_root/downloads/swift-6.4.0.tar.gz" --no-same-owner -C "$staging"
	mv "$staging/swift-6.4.0-RELEASE-ubuntu22.04" "$pi_mobile_toolchain_root/"
	rmdir "$staging"
fi
# Arch's current ncurses/xml ABI differs from Ubuntu 22.04. Use real, verified
# compatibility libraries in this compiler's RUNPATH, not system symlink guesses.
if [[ -e /etc/arch-release ]]; then
	download_verified_tool https://security.ubuntu.com/ubuntu/pool/main/n/ncurses/libncurses6_6.3-2ubuntu0.3_amd64.deb \
		libncurses6_6.3-2ubuntu0.3_amd64.deb 38f97a45931ab6f296be017344afc45e5ccbf83f24896f79625318691a9bebf8
	download_verified_tool https://security.ubuntu.com/ubuntu/pool/main/n/ncurses/libtinfo6_6.3-2ubuntu0.3_amd64.deb \
		libtinfo6_6.3-2ubuntu0.3_amd64.deb 3b8dff43a31168f5020928f2ab9a97324c5b47ae708311781f6bd01306c96214
	download_verified_tool https://stable-mirror.omarchy.org/extra/os/x86_64/libxml2-legacy-2.13.9-2-x86_64.pkg.tar.zst \
		libxml2-legacy-2.13.9-2-x86_64.pkg.tar.zst aac28a52e81422935e3bfa44044030640c5d525ad8f65a9672a3ab7139974652
	mkdir -p "$pi_mobile_toolchain_root/compat"
	for pkg in libncurses6 libtinfo6; do
		staging=$(mktemp -d "$pi_mobile_toolchain_root/compat-deb.XXXXXX")
		bsdtar -xf "$pi_mobile_toolchain_root/downloads/${pkg}_6.3-2ubuntu0.3_amd64.deb" -C "$staging"
		for payload in "$staging"/data.tar.*; do bsdtar -xf "$payload" -C "$pi_mobile_toolchain_root/compat"; done
		# Small extraction receipts are retained; never recursively delete user paths.
	done
	bsdtar -xf "$pi_mobile_toolchain_root/downloads/libxml2-legacy-2.13.9-2-x86_64.pkg.tar.zst" -C "$pi_mobile_toolchain_root/compat" usr/lib
	runtime="$pi_mobile_toolchain_root/swift-6.4.0-RELEASE-ubuntu22.04/usr/lib/swift/linux"
	for pair in libncurses.so.6:lib/x86_64-linux-gnu/libncurses.so.6 libtinfo.so.6:lib/x86_64-linux-gnu/libtinfo.so.6 libxml2.so.2:usr/lib/libxml2.so.2; do
		library=${pair%%:*}
		target=${pair#*:}
		if [[ ! -e "$runtime/$library" && ! -L "$runtime/$library" ]]; then
			ln -s "../../../../../compat/$target" "$runtime/$library"
		fi
	done
fi
source "$root/tools/xtool-environment.sh"
swift --version
xtool --version
if [[ -n $sdk_path ]]; then
	sdk_status=$(xtool sdk status)
	if [[ $sdk_status == 'Darwin SDK is installed'$'\n'* ]]; then
		printf '%s\n' 'Pi Mobile Linux: an SDK already exists; refusing to replace it automatically.' >&2
		exit 2
	fi
	xtool sdk install --slim "$sdk_path"
else
	printf '%s\n' 'Build tools ready. Apple SDK installation is a separate step: tools/setup-ios-linux.sh --sdk /absolute/path/Xcode.xip'
fi
