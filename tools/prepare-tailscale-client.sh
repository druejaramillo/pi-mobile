#!/usr/bin/env bash
# Build the pinned official libtailscale C archive with bounded Pi Mobile entry points.
# Never authenticate a node, read personal Tailscale state, or download an Apple SDK.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
destination=${1:-iphoneos}
case "$destination" in iphoneos|iphonesimulator|linux) ;; *) printf '%s\n' 'Pi Mobile Tailscale: destination must be iphoneos, iphonesimulator or linux.' >&2; exit 2 ;; esac
command -v go >/dev/null || { printf '%s\n' 'Pi Mobile Tailscale: Go 1.27.1+ is required (Go toolchain auto-download is supported).' >&2; exit 2; }
revision=019b925b989a2d1bbf3d750f14c740a20078c98b
artifacts="$root/ios/TailscaleClient/.artifacts"
checkout="$artifacts/libtailscale"
mkdir -p "$artifacts/library"
# mkdir is portable to the Mac lane; an active build lock is never removed by another caller.
mkdir "$artifacts/prepare.lock" 2>/dev/null || { printf '%s\n' 'Pi Mobile Tailscale: preparation is already running.' >&2; exit 2; }
trap 'rmdir "$artifacts/prepare.lock"' EXIT
if [[ ! -e $checkout ]]; then
    stage=$(mktemp -d "$artifacts/checkout.XXXXXX")
    git -C "$stage" init --quiet
    git -C "$stage" remote add origin https://github.com/tailscale/libtailscale.git
    git -C "$stage" fetch --quiet --depth 1 origin "$revision"
    git -C "$stage" checkout --quiet --detach FETCH_HEAD
    mv "$stage" "$checkout"
fi
[[ $(git -C "$checkout" rev-parse HEAD) == "$revision" && -z $(git -C "$checkout" diff HEAD --) ]] || {
    printf '%s\n' 'Pi Mobile Tailscale: cached upstream source differs from the pin; refusing to overwrite it.' >&2; exit 2;
}
while IFS= read -r file; do
    case "$file" in pi_mobile.go|pi_mobile_test.go) ;; *) printf 'Pi Mobile Tailscale: unexpected cached file: %s\n' "$file" >&2; exit 2 ;; esac
done < <(git -C "$checkout" ls-files --others --exclude-standard)
for file in pi_mobile.go pi_mobile_test.go; do cp "$root/tools/tailscale-client/$file" "$checkout/$file"; done
export CGO_ENABLED=1
case "$destination" in
    iphoneos|iphonesimulator)
        if [[ $(uname -s) == Darwin ]]; then
            sdk=$(xcrun --sdk "$destination" --show-sdk-path)
            compiler=$(xcrun --find clang)
        else
            [[ $destination == iphoneos ]] || { printf '%s\n' 'Pi Mobile Tailscale: the Linux lane has only the physical-iPhone SDK.' >&2; exit 2; }
            source "$root/tools/xtool-environment.sh"
            bundle=$(xtool sdk status | awk '/^  Path: / { sub(/^  Path: /, ""); print; exit }')
            sdk="$bundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
            compiler=$(command -v clang)
        fi
        [[ -d $sdk ]] || { printf '%s\n' 'Pi Mobile Tailscale: Apple SDK is missing.' >&2; exit 2; }
        export GOOS=ios GOARCH=arm64
        target=arm64-apple-ios17.0
        if [[ $destination == iphonesimulator ]]; then
            case $(uname -m) in arm64) ;; x86_64) GOARCH=amd64; target=x86_64-apple-ios17.0 ;; *) exit 2 ;; esac
            target+=-simulator
        fi
        # Go's CC is word-split; use a wrapper to preserve SDK/compiler paths containing spaces.
        export PI_TAILSCALE_CC="$compiler" PI_TAILSCALE_TARGET="$target" PI_TAILSCALE_SDK="$sdk"
        export CC="$root/tools/tailscale-client/clang-apple.sh"
        ;;
    linux) export GOOS=linux GOARCH=amd64; export CC=clang ;;
esac
fingerprint=$( { printf '%s\n' "$revision" "$destination" "$GOARCH" "${target:-linux}"; (cd "$checkout" && go version); git -C "$root" hash-object "$root/tools/tailscale-client/pi_mobile.go"; if [[ -n ${sdk:-} ]]; then git hash-object "$sdk/SDKSettings.json"; "$compiler" --version; fi; } | git hash-object --stdin)
if [[ -f $artifacts/library/libtailscale.a && -f $artifacts/library/fingerprint && $(<"$artifacts/library/fingerprint") == "$fingerprint" ]]; then
    printf 'Pi Mobile Tailscale: verified cached %s archive.\n' "$destination"
    exit 0
fi
cd "$checkout"
stage=$(mktemp -d "$artifacts/archive.XXXXXX")
go build -mod=readonly -trimpath -buildmode=c-archive -ldflags=-w -o "$stage/libtailscale.a" .
mv "$stage/libtailscale.a" "$artifacts/library/libtailscale.a"
# The package uses its narrow checked-in header, not the generated full Go ABI header.
printf '%s\n' "$fingerprint" > "$artifacts/library/fingerprint"
printf 'Pi Mobile Tailscale: built %s archive from %s (tailscale.com v1.104.1).\n' "$destination" "$revision"
