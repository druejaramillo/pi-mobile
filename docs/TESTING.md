# Approved test interfaces

The user approved tests at the **bridge protocol and native session/dictation interfaces**. Tests stay at those boundaries; they do not import the product's private parser, ledger, permission-render, terminal-history or microphone helpers.

## Host protocol — runnable on Linux or macOS

```sh
npm --prefix host ci --ignore-scripts --legacy-peer-deps
npm --prefix host test
```

Node 22.19+ is required. Node's `--experimental-transform-types` runs the existing TypeScript extension; its experimental warning is expected. The test runner uses Node built-ins, not another Pi installation or a model client.

**23 tests passed on Node 24.20.0.** They run the real CLI, exported Pi extension entry, JSONL framing, private-socket connection, mutation guards and original UI wrappers. Test-only external peers provide the Herdr protocol and Pi SDK/TUI promises. No production module is mocked or private state inspected.

Coverage:

- Fragmented UTF-8/Unicode separators, exact 1 MiB records, byte-counted limits and malformed/partial input.
- Stable-terminal navigation after a pane move, constrained review advertisements and rejection of arbitrary socket metadata.
- Observe-before-control, a separate takeover choice, read-only input rejection, duplicate output chunks, grid changes and invalid bytes/dimensions.
- Same-generation reconnect without duplicate prompt submission; changed-payload id conflicts; stale identities after reload/session replacement; working host state surviving phone EOF.
- Stale/replaced dialogs, original promise completion, per-action text capability, custom-UI fallback, desktop draft/dialog guards, explicit delivery and abort.
- Unknown slash-command fallback, template expansion delegation and omission of raw tool/image/thinking payloads.

Fixtures create their own child processes, Herdr socket and temporary directories. Product sockets get unique owned tokens and normal extension shutdown removes them. The shared private socket directory is **never recursively removed**, and no live Herdr/Pi session, global setting or permission authority is changed.

These peers are not the installed Herdr/TUI implementation. In particular, **native permission-component parsing, double confirmation, scope/audit behavior and desktop races still need verification against the actual package**. A synthetic permission component is intentionally not used to manufacture that proof.

## Native models and machine credentials — Swift package on Linux or Mac

```sh
# Linux, using the prepared private compiler:
source tools/xtool-environment.sh
swift test --package-path ios/PiMobileCore --jobs 4
# Mac alternative:
xcrun swift test --package-path ios/PiMobileCore
```

**Thirteen XCTest methods compiled and passed on Linux with Swift 6.4.** Seven cover public command identity/Unicode, UUID uniqueness, null JSON values, action text capabilities, cross-machine location identity, terminal bytes and safe integer conversion. Six exercise the machine editor's public `MachineKeyCredential` preparation seam: imported/pasted line endings, public/truncated/malformed input rejection, exact passphrase preservation, UTF-8 byte limits, total credential-bundle limits and JSON escaping expansion. These use synthetic armor/base64, not real private keys; Ed25519 parsing and decryption remain transport checks.

Evidence: `ios/TestResults/core-key-credential.log`. This proves the platform-neutral Core package, not clipboard interaction, Keychain, UIKit/SSH/audio or iOS execution. See [LINUX_SETUP.md](LINUX_SETUP.md) for setup.

## Linux iPhone compile/link/package regression

```sh
./tools/build-ios-linux.sh
./tools/build-ios-linux.sh
```

Both real builds must exit zero and validate the unsigned app's identity, iPhone-only family, executable, icon and exact dictation profile. Repeating matters: Swift 6.4's default cached cross-target path reproduced a wrong-linker JSON-probe failure after a successful first build. The script now bypasses SwiftPM's affected manifest cache while retaining reusable SwiftBuild descriptions/objects. See [LINUX_SETUP.md](LINUX_SETUP.md) for the fix and retained failing/passing evidence. Four real builds passed, including a source-timestamp rebuild. This does not run iOS code or the app-hosted tests.

## Native session and dictation — Xcode Simulator

Use Xcode 26+ / Swift 6.2+, XcodeGen, and a **fresh Simulator with no saved machines**. The app-hosted test target launches the real app; a previously configured Simulator can otherwise trigger its normal foreground machine refresh.

```sh
xcrun simctl list devices available
./tools/test-ios.sh 'platform=iOS Simulator,id=<chosen-UDID>'
```

The script checks prerequisites, builds the app, runs the Core package tests, then runs the `PiMobileTests` target. It refuses physical-device destinations. `.xcresult` evidence is saved under ignored `ios/TestResults/` and its path is printed after success. It does not install tools, deploy to hosts or change signing/provisioning.

Eighteen XCTest methods cover the public SSH facade's disconnected/invalid-pin/unadvertised-review guards, dictation's unprepared/cancelled/invalid-profile paths, and literal offline-cleanup/draft-joining vectors. Tests use invalid or unprepared model profiles; successful microphone capture/inference and model downloads are not required. They import public modules without `@testable` access to internals.

**The eighteen app-hosted tests have only had source grammar/project-YAML checks here.** Their compilation/execution and Xcode project generation remain unrun; do not treat the passing Core package as an app-test pass. xtool's Linux lane does not run the iOS Simulator.

## Still outside automated proof

- Connected native SSH correlation/deadlines/cancellation, host-key rejection against an actual server, password/encrypted-key authentication and foreground/background reconnect.
- Cumulative/coalesced native terminal rendering, the 8 MiB cap, keyboard/cursor modes, input ownership and throughput/backpressure.
- Actual Plannotator forwarding, ATS, assets/WebSockets, navigation and tunnel lifetime.
- Successful Parakeet model preparation/cache, microphone routes, five-minute cap, repeated completion delivery, cancellation timing, offline inference and memory/thermal/privacy measurements.
- Native visual/accessibility inspection and actual permission-system compatibility.

Follow the real-device checklist in [MAC_SETUP.md](MAC_SETUP.md). The later xtool build/deploy request authorizes deliberate device installation, not automatic live-agent mutation or a claim of device readiness.
