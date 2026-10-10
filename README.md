# Pi Mobile

A native iPhone companion to **existing Herdr and Pi sessions**, reached directly over SSH/Tailscale. Local Parakeet v3 dictation. Actual Plannotator reviews inside the app. **No notifications or push service.**

This repository is under active construction. Native compilation and device validation require your Mac; this Linux checkout cannot provide those checks. See [PRODUCT.md](PRODUCT.md) for the approved behavior and [bridge protocol](docs/BRIDGE_PROTOCOL.md) for the shared interface.

## Layout

- `ios/`: native app, shared Swift protocol models, SSH transport, terminal, review and dictation integration.
- `host/`: SSH stdio adapter and a Pi extension for attaching to the same live process.
- `tools/`: development and safe VoxType profile import utilities.
- `docs/`: setup, compatibility and verification notes.

## Security boundaries

SSH host keys are explicitly trusted; secrets belong in iOS Keychain, never Git. No public listener, cloud transcription or APNs. No automatic terminal takeover, approval, remote installation or host process restart. A phone disconnect stops only its own channels.

## Current verification

Host/static checks will be recorded in `docs/BUILD_STATUS.md`. An Xcode build and physical iPhone pass remain required before calling this usable on-device. Do not interpret source availability as a successful native build.
