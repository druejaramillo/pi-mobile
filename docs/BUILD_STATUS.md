# Build status

## Approved scope

Native iPhone app, direct SSH over always-available Tailscale, existing Herdr/Pi sessions, native permissions and conversation, terminal escape hatch, SSH-forwarded Plannotator, on-device Parakeet TDT v3 with deterministic VoxType rules. No notifications.

## Checkpoints

1. Protocol and product scaffolding: authored; implementation underway.

## Verification limits

The authoring machine is Linux and has no Swift/Xcode toolchain. Mac builds, Simulator screenshots, device SSH/terminal interaction and physical iPhone Parakeet inference are not yet run. No global Pi, Herdr, SSH, Tailscale or VoxType settings have been changed.

Public test seams (bridge protocol and native session/dictation interfaces) were proposed to the user; approval is pending. Do not write tests at other seams without agreement.
