# Pi Mobile

A native iPhone companion to **existing Herdr and Pi sessions**, reached directly over SSH/Tailscale. Local Parakeet v3 dictation. Actual Plannotator reviews inside the app. **No notifications or push service.**

This repository contains an integrated source checkpoint, **not a device-verified release**. The Mac lane uses **Xcode 26+ / Swift 6.2+**. The parallel **Linux/xtool** lane now compiles and links the real arm64 iPhone app with an Apple-supplied SDK. Signing is configured locally; installation and device behavior remain unverified. See [PRODUCT.md](PRODUCT.md) for the approved behavior and [bridge protocol](docs/BRIDGE_PROTOCOL.md) for the shared interface.

## Start on your Mac

```sh
gh repo clone druejaramillo/pi-mobile
cd pi-mobile
./tools/build-ios.sh
```

Follow [Mac setup](docs/MAC_SETUP.md) for signing/device verification and [host setup](docs/HOST_SETUP.md) for deliberate installation. Nothing is installed or restarted automatically.

The launch **Agents** tab indexes existing agents across your machines, with status and machine/workspace/tab/pane context. Search and tap to open the exact running pane. Machines also provides ordinary workspace/tab/terminal browsing. Cached locations are marked stale; unavailable hosts are not treated as empty.

## Build on Linux with xtool

```sh
./tools/setup-ios-linux.sh
./tools/setup-ios-linux.sh --sdk /absolute/path/Xcode_27.xip
./tools/build-ios-linux.sh
```

Follow [Linux setup](docs/LINUX_SETUP.md) for the Apple-provided SDK, private toolchain, signing and explicit USB deployment. Seven Core XCTest methods pass on this Linux machine, and full/repeated unsigned app builds succeed. The app has **not** been installed or run on a phone. The Mac build remains available.

## Layout

- `ios/`: native app, shared Swift protocol models, SSH transport, terminal, review and dictation integration.
- `host/`: SSH stdio adapter and a Pi extension for attaching to the same live process.
- `tools/`: development and safe VoxType profile import utilities.
- `docs/`: setup, compatibility and verification notes.

## Security boundaries

SSH host keys are explicitly trusted; secrets belong in iOS Keychain, never Git. No public listener, cloud transcription or APNs. No automatic terminal takeover, approval, remote installation or host process restart. A phone disconnect stops only its own channels.

## Current verification

**23 host protocol tests pass**, alongside TypeScript/JavaScript and importer checks. Seven Core XCTest methods compile and pass on Linux; eighteen app-hosted XCTest methods remain uncompiled/unrun; [testing instructions](docs/TESTING.md) describe exact coverage and limits. See [build status](docs/BUILD_STATUS.md) for exact checks, compatibility boundaries and unresolved gates. The Linux iOS compile/link/package pass is verified; Mac/Xcode validation and a physical iPhone pass remain required before calling this usable on-device. Compilation is not runtime proof.
