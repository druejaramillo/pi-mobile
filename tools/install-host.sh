#!/usr/bin/env bash
# Explicit user-wide host snapshot and Pi opt-in; never install dependencies, reload agents or start sessions.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
[[ $# == 0 ]] || { printf '%s\n' 'Usage: tools/install-host.sh (no sudo; installs for the current account)' >&2; exit 2; }
[[ ${HOME:-} == /* && $HOME != / ]] || { printf '%s\n' 'Pi Mobile host install: HOME must be an absolute account directory.' >&2; exit 2; }
[[ ${PI_CODING_AGENT_DIR:-$HOME/.pi/agent} == "$HOME/.pi/agent" ]] || {
    printf '%s\n' 'Pi Mobile host install: this loader targets the default ~/.pi/agent; review a custom agent directory separately.' >&2
    exit 2
}
base="$HOME/.local/share/pi-mobile"
extensions="$HOME/.pi/agent/extensions"
host="$base/host"
loader="$extensions/pi-mobile.ts"
template="$root/tools/pi-mobile-global-extension.ts.in"
for path in "$HOME" "$HOME/.local" "$HOME/.local/share" "$base" "$HOME/.pi" "$HOME/.pi/agent" "$extensions"; do
    if [[ -L $path || ( -e $path && ( ! -d $path || ! -O $path ) ) ]]; then
        printf 'Pi Mobile host install: refusing non-directory, symlink or foreign-owned parent: %s\n' "$path" >&2
        exit 2
    fi
done
[[ ! -L $host && ! -L $loader ]] || { printf '%s\n' 'Pi Mobile host install: refusing a symlink target.' >&2; exit 2; }
if [[ -d $host && -f $loader ]] && cmp -s "$template" "$loader" &&
    cmp -s "$root/host/bridge-cli.mjs" "$host/bridge-cli.mjs" &&
    cmp -s "$root/host/pi-mobile-extension.ts" "$host/pi-mobile-extension.ts" &&
    cmp -s "$root/host/package.json" "$host/package.json" && diff -qr "$root/host/lib" "$host/lib" >/dev/null; then
    printf '%s\n' 'Pi Mobile host install: matching runtime and user-wide extension already installed; nothing changed.'
    exit 0
fi
[[ ! -e $host && ! -e $loader ]] || {
    printf '%s\n' 'Pi Mobile host install: target already exists and differs; back it up and review replacement explicitly. Nothing overwritten.' >&2
    exit 2
}
[[ -z $(find "$root/host/lib" -type l -print -quit) ]] || { printf '%s\n' 'Pi Mobile host install: refusing symlinked runtime sources.' >&2; exit 2; }
umask 077
mkdir -p "$base" "$extensions"
lock="$base/.install-host.lock"
mkdir "$lock" || { printf '%s\n' 'Pi Mobile host install: another install or a retained lock exists; inspect before retrying.' >&2; exit 2; }
stage=''
loader_stage=''
cleanup_host_install() {
    [[ -z $stage ]] || rm -rf -- "$stage"
    [[ -z $loader_stage ]] || rm -f -- "$loader_stage"
    rmdir "$lock"
}
trap cleanup_host_install EXIT
stage=$(mktemp -d "$base/.host-install.XXXXXXXX")
loader_stage=$(mktemp "$extensions/.pi-mobile-install.XXXXXXXX")
mkdir "$stage/host"
cp "$root/host/bridge-cli.mjs" "$root/host/pi-mobile-extension.ts" "$root/host/package.json" "$stage/host/"
cp -R "$root/host/lib" "$stage/host/lib"
cp "$template" "$loader_stage"
# Recheck after acquiring the lock; publish complete files, never a partially copied runtime.
[[ ! -e $host && ! -L $host && ! -e $loader && ! -L $loader ]] || {
    printf '%s\n' 'Pi Mobile host install: target changed during preparation; nothing overwritten.' >&2
    exit 2
}
mv "$stage/host" "$host"
ln "$loader_stage" "$loader"
printf 'Installed bridge: %s/bridge-cli.mjs\nInstalled Pi opt-in: %s\n' "$host" "$loader"
printf '%s\n' 'No agent reloaded or session started. Remove duplicate project opt-ins deliberately; run /reload only in the existing Pi processes you choose.'
printf '%s\n' 'Phone bridge path relative to home: .local/share/pi-mobile/host/bridge-cli.mjs'
