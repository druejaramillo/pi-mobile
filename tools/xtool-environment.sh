#!/usr/bin/env bash
# Source only: expose the private Linux toolchain to this process, never shell profiles.
pi_mobile_toolchain_root=${PI_MOBILE_TOOLCHAIN_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/pi-mobile/toolchains}
pi_mobile_swift_bin="$pi_mobile_toolchain_root/swift-6.4.0-RELEASE-ubuntu22.04/usr/bin"
if [[ -x "$pi_mobile_swift_bin/swift" ]]; then
	export PATH="$pi_mobile_swift_bin:$PATH"
fi
if [[ -x "$pi_mobile_toolchain_root/bin/xtool" ]]; then
	export PATH="$pi_mobile_toolchain_root/bin:$PATH"
fi
