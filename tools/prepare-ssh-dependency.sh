#!/usr/bin/env bash
# Prepare pinned Citadel event-loop and exec-cleanup fixes on both build lanes, without shared-cache edits.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
command -v git >/dev/null
revision=ae8562f895de06ccb86fdb1cbb65fd99c8976e12
parent="$root/ios/.patched-dependencies"
dependency="$parent/Citadel"
patch="$root/tools/patches/citadel-existing-channel-eventloop.patch"
exec_patch="$root/tools/patches/citadel-exec-close.patch"
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
  git -C "$dependency" apply --check "$patch" "$exec_patch"
  git -C "$dependency" apply "$patch" "$exec_patch"
fi
# Upgrade only an exact previously prepared cache; never overwrite unrelated dependency edits.
if [[ $(git -C "$dependency" status --porcelain --untracked-files=all) == ' M Sources/Citadel/Client.swift' ]] &&
   git -C "$dependency" diff --no-ext-diff --no-color --src-prefix=a/ --dst-prefix=b/ -- Sources/Citadel/Client.swift | cmp -s - "$patch"; then
  git -C "$dependency" apply --check "$exec_patch"
  git -C "$dependency" apply "$exec_patch"
fi
[[ $(git -C "$dependency" status --porcelain --untracked-files=all) == $' M Sources/Citadel/Client.swift\n M Sources/Citadel/TTY/Client/TTY.swift' ]] || {
  printf '%s\n' 'Pi Mobile SSH: cached Citadel has unexpected changes; refusing to overwrite it.' >&2
  exit 2
}
git -C "$dependency" diff --no-ext-diff --no-color --src-prefix=a/ --dst-prefix=b/ -- Sources/Citadel/Client.swift | cmp -s - "$patch" || {
  printf '%s\n' 'Pi Mobile SSH: cached Citadel differs from the checked-in event-loop patch.' >&2
  exit 2
}
git -C "$dependency" diff --no-ext-diff --no-color --src-prefix=a/ --dst-prefix=b/ -- Sources/Citadel/TTY/Client/TTY.swift | cmp -s - "$exec_patch" || {
  printf '%s\n' 'Pi Mobile SSH: cached Citadel differs from the checked-in exec-close patch.' >&2
  exit 2
}
printf '%s\n' 'Pi Mobile SSH: pinned Citadel event-loop and exec-close fixes prepared.'
