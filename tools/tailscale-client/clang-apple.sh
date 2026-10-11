#!/usr/bin/env bash
# Go C compiler seam for both the supplied Linux SDK and Xcode SDKs.
set -euo pipefail
exec "$PI_TAILSCALE_CC" -target "$PI_TAILSCALE_TARGET" -isysroot "$PI_TAILSCALE_SDK" "$@"
