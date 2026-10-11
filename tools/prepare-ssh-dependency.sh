#!/usr/bin/env bash
# Prepare the pinned Citadel event-loop fix for both Xcode and xtool, without changing shared checkouts.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
command -v git >/dev/null
revision=ae8562f895de06ccb86fdb1cbb65fd99c8976e12
parent="$root/ios/.patched-dependencies"
dependency="$parent/Citadel"
patch="$root/tools/patches/citadel-existing-channel-eventloop.patch"
mkdir -p "$parent"
lock="$parent/prepare.lock"
mkdir "$lock" 2>/dev/null || {
  printf '%s\n' 'Pi Mobile SSH: dependency preparation is already running; no cache was changed.' >&2
  exit 2
}
trap 'rmdir "$lock"' EXIT
if [[ ! -e "$dependency" ]]; then
  checkout=$(mktemp -d "$parent/citadel.XXXXXX")
  # Retain interrupted checkouts for diagnosis; never recursively remove a caller's dependency cache.
  git -C "$checkout" init --quiet
  git -C "$checkout" remote add origin https://github.com/orlandos-nl/Citadel.git
  git -C "$checkout" fetch --quiet --depth 1 origin "$revision"
  git -C "$checkout" checkout --quiet --detach FETCH_HEAD
  mv "$checkout" "$dependency"
fi
[[ $(git -C "$dependency" rev-parse HEAD) == "$revision" ]] || {
  printf '%s\n' 'Pi Mobile SSH: cached Citadel revision differs from the pin; refusing to overwrite it.' >&2
  exit 2
}
if [[ -z $(git -C "$dependency" status --porcelain --untracked-files=all) ]]; then
  git -C "$dependency" apply --check "$patch"
  git -C "$dependency" apply "$patch"
fi
[[ $(git -C "$dependency" status --porcelain --untracked-files=all) == ' M Sources/Citadel/Client.swift' ]] || {
  printf '%s\n' 'Pi Mobile SSH: cached Citadel has unexpected changes; refusing to overwrite it.' >&2
  exit 2
}
git -C "$dependency" diff --no-ext-diff --no-color --src-prefix=a/ --dst-prefix=b/ -- Sources/Citadel/Client.swift | cmp -s - "$patch" || {
  printf '%s\n' 'Pi Mobile SSH: cached Citadel differs from the checked-in event-loop patch.' >&2
  exit 2
}
printf '%s\n' 'Pi Mobile SSH: pinned Citadel event-loop fix prepared.'
