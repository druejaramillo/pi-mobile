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

## Native models and legacy machine credentials — Swift package on Linux or Mac

```sh
# Linux, using the prepared private compiler:
source tools/xtool-environment.sh
swift test --package-path ios/PiMobileCore --jobs 4
# Mac alternative:
xcrun swift test --package-path ios/PiMobileCore
```

**Twenty-six XCTest methods compiled and passed on Linux with Swift 6.4.** Ten additionally cover authenticated Tailscale status schemas, exact DNS/IP matching, tailnet-scoped short names, ambiguous/missing/expired/historical/unready rejection, local-node identity checks and saved-profile preservation. Seven cover public command identity/Unicode, UUID uniqueness, null JSON values, action text capabilities, cross-machine location identity, terminal bytes and safe integer conversion. Three cover keyless Tailscale defaults, profile round-trip/host-pin preservation and decoding existing key/password/dual-auth profiles without changing their credential requirement or port. Six exercise the retained public `MachineKeyCredential` preparation seam used for legacy private-key normalization: line endings, public/truncated/malformed input rejection, exact passphrase preservation, UTF-8 byte limits, credential-bundle limits and JSON escaping. These use synthetic armor/base64, not real private keys; Ed25519 parsing and decryption remain transport checks. The credential-entry UI has been removed.

Current evidence: `ios/TestResults/core-tailscale-identity.log`. This proves the platform-neutral Core package, not Keychain, UIKit/SSH/audio or iOS execution. See [LINUX_SETUP.md](LINUX_SETUP.md) for setup.

## Embedded Tailscale C/Go boundary

```sh
./tools/test-tailscale-client.sh
```

Two tests pass under Go's race detector, and Go vet passes. They exercise the actual full-duplex libtailscale socket relay and native-close teardown using `net.Pipe`/socketpairs, plus fail-closed missing-node calls at the exported C boundary. No test starts or signs into a tailnet node. The script verifies/prepares the same pinned archive used by the app, then runs host-native Go tests; evidence is `ios/TestResults/tailscale-client-regression.log`. This is not proof of real iPhone sign-in, node shutdown/resume, policy evaluation or actual tailnet routing.

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

## SSH setup — real loopback regression

```sh
./tools/test-ssh-transport.sh
```

The save/launch crash investigation adds this standalone connection-boundary fixture. It compiles the app's actual `SSHOwnedClient`, `SSHBridgeConfiguration`, `SSHChannelOwnership` and `SSHBridgeExec` sources, without `@testable`, mocked transport or inspection of private state. Servers bind only to `127.0.0.1` on ephemeral ports, use freshly generated host keys and accept either a synthetic password or `none` for a single fixture username. This models the keyless SSH protocol, not real tailnet identity or policy evaluation. No saved machine, Keychain, Tailscale settings, host bridge or live agent is accessed.

**Passed on Linux with Swift 6.4:** three fresh password-authenticated connections and clean closes, prompt password rejection, mismatched host-key rejection and closing owned sockets during a stalled login. The keyless extension also passes repeated `none` logins without a secret, ignoring a supplied old secret, denied usernames, rejection of password-only SSH without credential fallback, missing/mismatched host pins and retaining the legacy credential requirement. Citadel's one-shot custom delegate initially replaced the expected rejection with `allAuthenticationOptionsFailed`; the app now maps that keyless-only failure to an actionable Tailscale error. The automatic-lookup extension also verifies supported advertised key sets over an adopted AF_UNIX socketpair, without a manual profile pin or OS DNS resolution; wrong, empty, unsupported-only and malformed sets fail closed. Legacy pins cannot be overridden by a coordination set. A mismatch now exposes an actionable `hostIdentityMismatch`, not a raw Citadel error number. Current evidence: `ios/TestResults/ssh-transport-regression.log`. The unpatched code failed with the exact device assertion in `EventLoop.preconditionInEventLoop` (exit 132). Applying only the event-loop patch exposed a readiness timeout; placing the observer before Citadel's handshake handler and observing the raw close future resolved it. Evidence: `ios/TestResults/ssh-transport-red.log`, `ssh-transport-loop-fix.log` and `ssh-transport-final.log`.

The exec-lifecycle extension passes **ten cases**, five over the adopted socketpair and five over raw TCP: bidirectional stdin/stdout, immediate exits 127 and 1 with actionable status-preserving errors, clean EOF/status 0 without a spurious `alreadyClosed`, and original callback-error preservation after remote close. Ten additional socketpair-suite repeats pass fifty cases. Before the exec-close patch, immediate exit 127 produced the user's exact `NIOCore.ChannelError error 6`; a direct command-stream control preserved 127. Repro/control/final logs are `ios/TestResults/ssh-exec-channel-error-{minimal-red,tcp-red,stream-control,final}.log`. This synthetic responder does not run the installed host bridge or identify the cause on the user's machine.

To isolate the immediate-exit regression:

```sh
./tools/test-ssh-transport.sh --exec-only --early-exit-only
./tools/test-ssh-transport.sh --exec-only --early-exit-only --raw-tcp
```

The script stages symlinks under ignored `.build/ssh-transport-regression`, uses the same pinned/patched Citadel as both app lanes, and disables crash core dumps. Its Linux-only NIOSSH patch adds the defining `CDispatch` import required by Swift 6.4; it changes no runtime behavior or iOS dependency source. First compilation builds the native dependencies; cached runs take seconds. macOS 15+ execution is supported by the fixture (matching Citadel's exec API) but unrun here.

This is actual loopback SSH authentication, not an app-hosted XCTest or an iPhone check. After updating the device app, confirm launch with the existing saved machine, connection/error presentation, background disconnect and foreground refresh without deleting its settings.

## Native session and dictation — Xcode Simulator

Use Xcode 26+ / Swift 6.2+, XcodeGen, and a **fresh Simulator with no saved machines**. The app-hosted test target launches the real app; a previously configured Simulator can otherwise trigger its normal foreground machine refresh.

```sh
xcrun simctl list devices available
./tools/test-ios.sh 'platform=iOS Simulator,id=<chosen-UDID>'
```

The script checks prerequisites, builds the app, runs the Core package tests, then runs the `PiMobileTests` target. It refuses physical-device destinations. `.xcresult` evidence is saved under ignored `ios/TestResults/` and its path is printed after success. It does not install tools, deploy to hosts or change signing/provisioning.

Nineteen XCTest methods cover the public SSH facade's disconnected/invalid-pin/unadvertised-review guards (including keyless rejection without an authenticated embedded node), dictation's unprepared/cancelled/invalid-profile paths, and literal offline-cleanup/draft-joining vectors. Tests use invalid or unprepared model profiles; successful microphone capture/inference and model downloads are not required. They import public modules without `@testable` access to internals.

**The nineteen app-hosted tests remain uncompiled/unrun here.** Their compilation/execution and Xcode project generation remain unrun; do not treat the passing Core package as an app-test pass. xtool's Linux lane does not run the iOS Simulator.

## Tailscale SSH setup — required native verification

The Linux lane compiles the simplified native form but cannot prove its iPhone behavior. Use a deliberately chosen disposable host/session and verify:

- Settings and Add machine offer in-app Tailscale sign-in, registering a separate pi-mobile device. Complete browser sign-in/Done and deliberate device approval; the existing VPN app must remain unchanged. Auth URLs and node secrets must not appear in diagnostics/backups.
- Add machine shows name, Tailscale address and host username, but no public-key field, auth picker, private-key import/paste, password/passphrase or port setting. Host bridge defaults remain under a disclosure.
- Save resolves the exact peer's advertised keys and validates all transport settings; connect through that same embedded node with an SSH `accept` policy and no Keychain item. Missing/ambiguous/expired/unready/invalid/mismatched identity fails closed; no network-scan or VPN-route fallback.
- A missing/unstartable bridge or immediate exec EOF presents a status-preserving host setup/disconnection error, not `NIOCore.ChannelError error 6`. Check the real path, noninteractive Node/Herdr environment and existing session. Do not reset the saved profile or automatically install/restart host software.
- A password-only SSH server, denied username or unmet Tailscale policy presents a recoverable error, never a credential prompt or automatic fallback. Interactive `check` sign-in is unsupported and must not be portrayed as working.
- Upgrade retains the existing saved machine, port, public key and Keychain login. Edit/cancel changes nothing. Saving an ordinary edit does not silently migrate it.
- **Switch to Tailscale SSH** clears only the draft pin, sets port 22 and requires successful automatic trusted lookup before Save. Cancel retains the old profile; Save keeps its UUID/drafts and leaves its old Keychain item intact but unused. Remove still deletes only the saved connection/credential, not host sessions.
- Inspect light/dark, largest Dynamic Type, VoiceOver and keyboard layout; sign-in browser/Done, connection status, legacy public-key input, disclosure, Save/Cancel and migration/remove actions remain readable and reachable.
- Relaunch with the saved profile, background/foreground and explicitly refresh: no crash, no secret lookup for keyless profiles and no mutation replay.

The user reports successful in-app sign-in and adding a machine on installed build `02eaf97`, followed by a connection failure. This is limited human evidence, not a successful connected/device/visual pass. The later exec-cleanup fix is built but not installed; the remaining checks above still need verification. Twenty-six Core tests, two Go/C regressions, the real loopback SSH regression and cross-build are not substitutes. The user subsequently authorized an in-place USB update of keyless build `440e66d`; installation and installer verification succeeded (`ios/TestResults/deploy-keyless-tailscale-20261011T090750Z.log`). No uninstall/data reset or launch verification was performed. Installation is not proof of the checks above.

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

- Full iPhone SSH/bridge correlation, deadlines/cancellation, encrypted-key authentication and foreground/background reconnect. Loopback password authentication, host-key rejection and raw socket teardown now have the separate automated proof above, not iOS execution proof.
- Cumulative/coalesced native terminal rendering, the 8 MiB cap, keyboard/cursor modes, input ownership and throughput/backpressure.
- Actual Plannotator forwarding, ATS, assets/WebSockets, navigation and tunnel lifetime.
- Successful Parakeet model preparation/cache, microphone routes, five-minute cap, repeated completion delivery, cancellation timing, offline inference and memory/thermal/privacy measurements.
- Native visual/accessibility inspection and actual permission-system compatibility.

Follow the real-device checklist in [MAC_SETUP.md](MAC_SETUP.md). The later xtool build/deploy request authorizes deliberate device installation, not automatic live-agent mutation or a claim of device readiness.
