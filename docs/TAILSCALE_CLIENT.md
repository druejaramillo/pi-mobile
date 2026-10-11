# Embedded Tailscale client

Pi Mobile has its own foreground-only userspace Tailscale node, named **pi-mobile**. The user signs in through an in-app Safari sheet; this registers a separate tailnet device. It does not read the installed VPN app's private state, require an administrative API token, configure a host, or change tailnet policy.

## Source and build

Official upstream: <https://github.com/tailscale/libtailscale>, pinned to `019b925b989a2d1bbf3d750f14c740a20078c98b`, which uses `tailscale.com v1.104.1` and Go 1.27.1. The upstream `TailscaleKit` is an Xcode framework, not a ready-to-use remote SwiftPM package. We use the same official Go/C archive with a narrow app-owned Swift wrapper rather than importing its entire framework or incomplete LocalAPI model.

`tools/prepare-tailscale-client.sh` verifies the upstream checkout, adds `tools/tailscale-client/pi_mobile.go`, and builds the archive. No upstream source is patched. The additions expose nonblocking node startup, bounded in-memory LocalAPI status/login operations, a 15-second userspace dial, and node shutdown. Both diagnostic loggers and Tailscale log uploads are disabled. No login is performed by build/test scripts.

- Linux device: `./tools/prepare-tailscale-client.sh iphoneos` (also called by `build-ios-linux.sh`). Uses the user's installed Apple SDK and Clang.
- Mac Simulator: `./tools/prepare-tailscale-client.sh iphonesimulator` (also called by `build-ios.sh`). Builds the selected Mac's arm64 or x86_64 Simulator archive.
- Mac physical device: prepare `iphoneos` before a device build. The local archive is destination-specific; prepare again when switching Simulator/device destinations. Preparation and Xcode builds must not run concurrently against different destinations.

Go's normal verified toolchain/module downloads are allowed; no Apple SDK is downloaded. Generated dependencies, archives and node state are not committed.

## Trust and routing

A connection reads `ipnstate.Status` through the embedded node's **in-memory LocalAPI**, not a loopback HTTP address or remote server. Destination matching uses an exact MagicDNS name or tailnet IP. A short name is expanded only within the authenticated current tailnet's DNS suffix; arbitrary `HostName` aliases, prefix matching and ambiguous peers are rejected. The node must be Running; the peer must be present in the current network map, nonexpired, and advertise host keys.

The same node dials the matched peer's numeric tailnet IP on port 22. libtailscale returns a socketpair; the existing NIO/Citadel transport adopts that socket with reads paused until its event-loop-confined authentication observer is installed. The SSH validator accepts only supported, parsed keys advertised for that exact peer. All advertised supported key types are accepted, allowing SSH's negotiated Ed25519/ECDSA preference without manual selection. Missing, malformed, unsupported-only or mismatched identity fails closed. No network scan, TOFU, permissive validator, VPN-route fallback or credential fallback exists.

The tailnet policy must allow **pi-mobile's identity** to reach the host and SSH into the requested username with an `accept` rule. In-app tailnet sign-in is implemented; SSH `check`-mode interactive reauthorization is still unsupported.

## Saved state and lifecycle

New Tailscale profiles need only name, destination and host username. Save validates lookup and the complete transport settings before persistence. Existing Tailscale profiles retain their stored fields; their old manually copied host pin is no longer the authority for Tailscale connections. It is not overwritten by automatic lookup. Legacy key/password/dual-auth profiles retain their exact saved pin, port, UUID and device-only Keychain credential. Switching a legacy profile remains explicit; Cancel and failed lookup do not save a migration.

The embedded node's private login state is under Application Support/Tailscale, with directory permissions 0700, iOS data protection until first unlock, and backup exclusion. Login URLs stay temporary UI state and are never written to profiles or logs. Backgrounding closes mobile SSH sessions and stops the embedded node without logging out or deleting its identity. Foreground creates a new local node using the same stored identity; no SSH mutations are replayed. No background task or monitoring is introduced.

## Verification

The official upstream archive cross-compiles to arm64 iPhone with the installed Linux toolchain. Two custom socket relay/closure and missing-node boundary tests pass under Go's race detector; Go vet passes (`./tools/test-tailscale-client.sh`). Twenty-six Core tests pass, including ten trusted-lookup matching/rejection/schema/preservation tests. The existing actual-transport loopback SSH regression and six build-metadata tests pass. Initial and source-change native arm64 compile/link/package builds pass (`ios/TestResults/xtool-build-20261011T172546Z.log`, `xtool-build-20261011T172826Z.log`). The actual SSH socket-adoption, multi-key and automatic-identity rejection regressions pass; a real tailnet sign-in, actual iPhone SSH connection, foreground/background behavior, and native appearance still require device verification. No test logs into the user's tailnet.

Integration `02eaf97` was subsequently signed and successfully installed **once, in place** on the selected iPhone running iOS 26.6.2 after explicit user authorization. No uninstall/data reset, credential deletion, host/policy change or app launch was performed. Final build: `ios/TestResults/xtool-build-20261011T173354Z.log`; actual deployment-result summary: `ios/TestResults/tailscale-device-install-20261011.md`. The user still needs to complete in-app sign-in and verify a real saved-machine connection.
