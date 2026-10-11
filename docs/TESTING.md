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

### Linked SDK regression — native navigation compatibility

```sh
python3 tools/test-iphone-build-metadata.py
python3 tools/check-iphone-build-metadata.py ios/xtool/PiMobile.app
```

Six CLI tests pass. The actual pre-fix app failed with `linked SDK is 17.0.0`; after the app-scoped linker correction it passes with `linked SDK 27.0.0; minimum iOS 17.0.0`. The build pipeline additionally requires exact agreement with the supplied Apple's SDK settings and derived plist. Deployment refuses a stale legacy-SDK executable before signing. These checks do not execute UIKit or prove the rendered material; they prevent the specific packaging condition that kept native bars in compatibility styling.

## Native session and dictation — Xcode Simulator

Use Xcode 26+ / Swift 6.2+, XcodeGen, and a **fresh Simulator with no saved machines**. The app-hosted test target launches the real app; a previously configured Simulator can otherwise trigger its normal foreground machine refresh.

```sh
xcrun simctl list devices available
./tools/test-ios.sh 'platform=iOS Simulator,id=<chosen-UDID>'
```

The script checks prerequisites, builds the app, runs the Core package tests, then runs the `PiMobileTests` target. It refuses physical-device destinations. `.xcresult` evidence is saved under ignored `ios/TestResults/` and its path is printed after success. It does not install tools, deploy to hosts or change signing/provisioning.

Eighteen XCTest methods cover the public SSH facade's disconnected/invalid-pin/unadvertised-review guards, dictation's unprepared/cancelled/invalid-profile paths, and literal offline-cleanup/draft-joining vectors. Tests use invalid or unprepared model profiles; successful microphone capture/inference and model downloads are not required. They import public modules without `@testable` access to internals.

**The eighteen app-hosted tests have only had source grammar/project-YAML checks here.** Their compilation/execution and Xcode project generation remain unrun; do not treat the passing Core package as an app-test pass. xtool's Linux lane does not run the iOS Simulator.

## Machine credential paste — required native verification

The Linux lane compiles the real SwiftUI paste controls but cannot exercise iOS clipboard interaction. On a fresh Simulator or iPhone, use disposable test keys and verify:

- **Private key → Paste** accepts the complete OpenSSH text, including CRLF line endings; file import remains available. Only “Key ready to save” appears, never the private key itself.
- The passphrase row's **Paste** fills its secure field. Leading/trailing whitespace and Unicode are preserved; no secret appears in errors or machine settings.
- Pasting a public key, truncated key or oversized input shows a recoverable error without replacing an already-ready key. A valid retry clears the error.
- Replacing a key clears its prior passphrase. Changing authentication clears both draft values; editing without a replacement retains the saved credential.
- Save, reopen and connect with a disposable encrypted Ed25519 key to verify the actual Keychain/SSH path. Cancel leaves the saved credential unchanged.
- Inspect both appearances, large Dynamic Type and VoiceOver; the Paste controls have distinct private-key/passphrase accessibility labels.

These interaction and connected-path checks remain **unrun**; the Core tests and cross-build are not substitutes.

## Liquid Glass — required native inspection

The UI refresh compiles, links and packages for arm64 iPhone with the supplied Apple SDK. Evidence: `ios/TestResults/xtool-build-20261011T080147Z.log`. Native material and interaction quality remain unverified; the independent finish-review disposition is **recapture**, not ship. The separate source reviewer scored the two named accessory-containment/Follow-output findings resolved at source scope only.

On the Simulator or deliberately installed iPhone build, capture the actual screens in light/dark appearance, portrait/landscape, standard/largest Dynamic Type and with the keyboard visible. Also check Reduce Motion, Reduce Transparency and increased contrast:

- Agents, Machines and Settings retain native navigation and readable rows. Status includes text and a symbol; inaccessible/cached hosts never appear ready or empty merely because a check failed.
- The floating composer, separate Send control and terminal keys use native Liquid Glass on iOS 26. iOS 17–25 use native material/bordered fallbacks. Transcript and permission explanations remain opaque. Every control is reachable and at least 44pt.
- Narrow/large-text layouts keep the editor, delivery mode, dictation/cancel and Send usable. Very short keyboard-safe viewports let the complete accessory scroll rather than clip controls. Back gestures and interactive keyboard dismissal still work.
- Turn Follow output off while content grows: the transcript must not jump to the bottom. Turn it on again: the latest response becomes visible.
- Type a draft, open commands, select one, dictate editable text and cancel a recording. Transcription inserts once into the owning draft and never sends automatically. A successful send clears only the submitted draft and gives feedback after host acknowledgment; failed/uncertain delivery remains explicit and is not retried.
- A live supported dialog retains its exact action labels, original prompt, reason/value entry, grant widths and confirmation stages. All content and actions remain reachable with the keyboard and large text. Glass styling must not favor a permission outcome.
- Terminal observation stays read-only, control remains explicit and takeover/Stop retain their confirmations. Review dismissal returns to the same agent.

Use dedicated disposable sessions for mutation checks. The refreshed app was subsequently signed and successfully installed over USB after explicit user authorization. No screenshots or UI runtime checks have been captured for this refresh; installation, compilation and Core tests are not substitutes.

## Still outside automated proof

- Connected native SSH correlation/deadlines/cancellation, host-key rejection against an actual server, password/encrypted-key authentication and foreground/background reconnect.
- Cumulative/coalesced native terminal rendering, the 8 MiB cap, keyboard/cursor modes, input ownership and throughput/backpressure.
- Actual Plannotator forwarding, ATS, assets/WebSockets, navigation and tunnel lifetime.
- Successful Parakeet model preparation/cache, microphone routes, five-minute cap, repeated completion delivery, cancellation timing, offline inference and memory/thermal/privacy measurements.
- Native visual/accessibility inspection and actual permission-system compatibility.

Follow the real-device checklist in [MAC_SETUP.md](MAC_SETUP.md). The later xtool build/deploy request authorizes deliberate device installation, not automatic live-agent mutation or a claim of device readiness.
