#!/usr/bin/env bash
# Exercise the app's real SSH setup against a disposable loopback server; no Keychain or host agents.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/tools/xtool-environment.sh"
command -v swift >/dev/null || {
  printf '%s\n' 'Pi Mobile SSH regression: Swift 6+ is required.' >&2
  exit 2
}
"$root/tools/prepare-ssh-dependency.sh"
fixture="$root/.build/ssh-transport-regression"
mkdir -p "$fixture/Sources/SSHTransportRegression" "$root/ios/TestResults"
cp "$root/tools/ssh-transport-regression/Package.swift" "$fixture/Package.swift"
cp "$root/ios/Package.resolved" "$fixture/Package.resolved"
for source in SSHOwnedClient SSHBridgeConfiguration SSHChannelOwnership; do
  ln -sfn "$root/ios/PiMobile/Transport/$source.swift" "$fixture/Sources/SSHTransportRegression/$source.swift"
done
ln -sfn "$root/tools/ssh-transport-regression/SSHTransportRegression.swift" "$fixture/Sources/SSHTransportRegression/SSHTransportRegression.swift"
swift package --package-path "$fixture" resolve
if [[ $(uname -s) == Linux ]]; then
  # Swift 6.4 requires the defining Dispatch C module for timespec; fixture-only import, no runtime change.
  nio="$fixture/.build/checkouts/swift-nio-ssh"
  patch="$root/tools/patches/nio-ssh-linux-cdispatch.patch"
  if git -C "$nio" apply --check "$patch" 2>/dev/null; then
    git -C "$nio" apply "$patch"
  elif ! git -C "$nio" apply --reverse --check "$patch" 2>/dev/null; then
    printf '%s\n' 'Pi Mobile SSH regression: unexpected NIOSSH checkout; refusing to patch.' >&2
    exit 2
  fi
fi
# A precondition failure must fail the command, not become a silently ignored core dump.
ulimit -c 0
swift run --package-path "$fixture" --jobs 4 SSHTransportRegression 2>&1 | tee "$root/ios/TestResults/ssh-transport-regression.log"
