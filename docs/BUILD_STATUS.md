# Build status

## Approved scope

Native iPhone app, direct SSH over always-available Tailscale, existing Herdr/Pi sessions, native permissions and conversation, terminal escape hatch, SSH-forwarded Plannotator, on-device Parakeet TDT v3 with deterministic VoxType rules. No notifications.

## Checkpoints

1. Protocol and product scaffolding: committed and pushed (`c2e6c3c`).
2. Native UI scaffold: global agent directory, machine/workspace/tab navigation, native conversation/composer, live-dialog controls, terminal control affordances, review sheet, Keychain storage and foreground-only lifecycle authored. SSH/dictation helpers are completing their implementations.

## Checks run so far

- Swift tree-sitter grammar parse: 12 coordinator-owned Swift files, no syntax errors. This is **not** a Swift typecheck or Xcode build.
- Info.plist, project YAML and asset JSON parse: passed.
- `git diff --check`: passed.
- `tools/build-ios.sh` correctly refused Linux with an actionable Mac prerequisite message.
- Code intelligence reported no Swift lint/typecheck mapping; no clean native-build result is claimed.

## Verification limits

The authoring machine is Linux and has no Swift/Xcode toolchain. Mac builds, Simulator screenshots, device SSH/terminal interaction and physical iPhone Parakeet inference are not yet run. No global Pi, Herdr, SSH, Tailscale or VoxType settings have been changed.

Public test seams (bridge protocol and native session/dictation interfaces) were proposed to the user; approval is pending. Do not write tests at other seams without agreement.
