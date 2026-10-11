#!/usr/bin/env bash
# Test the app-owned C/Go boundary using socketpairs and invalid handles, never tailnet login.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
"$root/tools/prepare-tailscale-client.sh" iphoneos
mkdir -p "$root/ios/TestResults"
cd "$root/ios/TailscaleClient/.artifacts/libtailscale"
{
    CGO_ENABLED=1 go test -race -timeout 30s -v -run '^TestPi' .
    go vet .
} 2>&1 | tee "$root/ios/TestResults/tailscale-client-regression.log"
