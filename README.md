# Pi Mobile

A native iPhone companion to **existing Herdr and Pi sessions**, reached directly over SSH/Tailscale. Local Parakeet v3 dictation. Actual Plannotator reviews inside the app. **No notifications or push service.**

This repository contains an integrated source checkpoint, **not a device-verified release**. The Mac lane uses **Xcode 26+ / Swift 6.2+**. The parallel **Linux/xtool** lane now compiles and links the real arm64 iPhone app with an Apple-supplied SDK. The signed app has been installed successfully over USB on an iPhone. The user reports successful Tailscale sign-in and machine creation, followed by a connection failure. The SSH error-masking fix has now been installed in place after authorization; retry on the retained machine is pending. Successful end-to-end device behavior remains unverified. See [PRODUCT.md](PRODUCT.md) for the approved behavior and [bridge protocol](docs/BRIDGE_PROTOCOL.md) for the shared interface.

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

Follow [Linux setup](docs/LINUX_SETUP.md) for the Apple-provided SDK, private toolchain, signing and explicit USB deployment. Twenty-six Core XCTest methods pass on this Linux machine, and full/repeated unsigned app builds succeed. The signed app is **installed on an iPhone**; sign-in/setup are user-reported, but a successful SSH/bridge connection remains outstanding. The Mac build remains available.

## Layout

- `ios/`: native app, shared Swift protocol models, SSH transport, terminal, review and dictation integration.
- `host/`: SSH stdio adapter and a Pi extension for attaching to the same live process.
- `tools/`: development and safe VoxType profile import utilities.
- `docs/`: setup, compatibility and verification notes.

## Keyless Tailscale SSH

New machines use [Tailscale SSH](https://tailscale.com/docs/features/tailscale-ssh) on port 22: no private key, password or passphrase setup. Enable Tailscale SSH on each host and allow the host username in your tailnet's SSH policy. Pi Mobile currently requires an `accept` rule; interactive `check`-mode sign-in is not supported. Tailscale networking alone does not enable Tailscale SSH.

Sign in inside **Settings → Tailscale** once, then add the machine's Tailscale name/IP and host username. Pi Mobile registers its own **pi-mobile** tailnet device and automatically verifies the destination's advertised host keys. No public-key copying or administrative token is needed. Host bridge settings keep their defaults under a disclosure. See [host setup](docs/HOST_SETUP.md#enable-keyless-tailscale-ssh) for policy prerequisites and the [embedded client](docs/TAILSCALE_CLIENT.md) for the trust/build boundary.

Existing saved profiles and device-only Keychain items are preserved. Tailscale profiles now use coordination keys without rewriting old stored pins. Legacy SSH still uses its saved pin/credential until you explicitly choose **Switch to Tailscale SSH** and Save; automatic lookup must succeed first. Cancel changes nothing.

## Security boundaries

SSH host keys come from authenticated Tailscale coordination data, or an existing legacy pin—never an unverified network scan. Legacy SSH secrets stay in device-only Keychain; embedded Tailscale login state uses protected, backup-excluded app storage. Neither belongs in Git. No public listener, cloud transcription or APNs. No automatic terminal takeover, approval, remote installation or host process restart. A phone disconnect stops only its own channels.

## Current verification

**23 host protocol tests pass**, alongside TypeScript/JavaScript and importer checks. Twenty-six Core XCTest methods compile and pass on Linux; nineteen app-hosted XCTest methods remain uncompiled/unrun; [testing instructions](docs/TESTING.md) describe exact coverage and limits. See [build status](docs/BUILD_STATUS.md) for exact checks, compatibility boundaries and unresolved gates. The Linux iOS compile/link/package pass is verified; Mac/Xcode validation and a physical iPhone pass remain required before calling this usable on-device. Compilation is not runtime proof.
