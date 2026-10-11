# Build status

## Readiness

**Physical-install checkpoint, not a device-verified release.** The private Linux Swift 6.4/xtool 1.21 lane builds the real arm64 iPhone app with the user-supplied Xcode 27 slim SDK; full and repeated builds pass. One deliberate USB deployment successfully provisioned, signed, installed and verified Pi Mobile on an iPhone running iOS 26.6.2. Pairing and Developer Mode were verified first; no certificate-revocation prompt appeared. App launch/runtime behavior, app-hosted tests, Mac/Xcode validation, rendering and actual permission compatibility remain unverified.

## Approved scope

Native iPhone app, direct SSH over Tailscale, existing Herdr/Pi sessions, global agent directory, native conversation and supported dialogs, terminal escape hatch, actual SSH-forwarded Plannotator, on-device Parakeet TDT v3 and deterministic VoxType cleanup. No notifications or background monitoring.

## Checkpoints

1. Protocol/product scaffold: committed and pushed (`c2e6c3c`).
2. Native UI/session navigation scaffold: committed and pushed (`55f681d`).
3. Host and native integration: committed and pushed (`93ae84e`) with pinned dependencies and setup documentation.
4. Approved-boundary test suite: committed/pushed (`1c0ee29`), with 23 host tests and 25 XCTest methods.
5. Linux xtool build/deploy lane (`376f3df`): private verified toolchain, resolved graph, exact SwiftTerm cross-target manifest patch and explicit USB deployment scripts.
6. Linux build-failure fix: private LLVM XML runtime link plus a scoped SwiftPM manifest-cache bypass. The original/repeat failures are retained as controls; four real builds now pass, including a source-timestamp rebuild. Unsigned iPhone app produced at this checkpoint (`a96d1e3`). Seven Core tests pass; eighteen app-hosted tests remain uncompiled/unrun.
7. Physical USB installation (2026-10-11): reconnect made the Apple device visible; a scoped `usbmuxd` restart resolved its startup/descriptor failure. Existing pairing validated. `idevicedevmodectl reveal` exposed Developer Mode; the user enabled it and completed the reboot/confirmation. The explicit deployment script ran once and returned `Successfully installed!`. First app launch remains a human verification gate.

## Machine credential paste checkpoint

Private keys can now be pasted with a native system Paste control or imported from a file; encrypted-key passphrases have a separate Paste control and remain masked. Preparation checks OpenSSH armor/base64, normalizes key line endings, preserves passphrases verbatim and enforces the serialized credential limit. Keys remain device-only Keychain items; host-key verification is unchanged. Keyless Tailscale SSH setup is not added.

Thirteen Core tests pass (`ios/TestResults/core-key-paste-final.log`), and initial/repeated iPhone compile/link/package builds pass (`xtool-build-20261011T075224Z.log`, `xtool-build-20261011T075250Z.log`). Native clipboard/Keychain/SSH interaction remains unrun. The inline native visual review's disposition is **recapture** because iPhone screenshots are unavailable; no visual approval is claimed. See the [paste verification checklist](TESTING.md#machine-credential-paste--required-native-verification).

## Implemented in source

- Launch Agents tab: recognized agents across machines, search, machine/workspace/tab/pane context and direct stable-terminal navigation. Unreachable hosts are not treated as empty. In-memory cached locations are explicitly stale.
- Machine/workspace/tab browsing, device-only nonsynchronizable Keychain credentials, OpenSSH private-key file import/paste and encrypted Ed25519-key passphrase entry/paste, trusted host-key setup and per-terminal persisted drafts.
- Same-process Pi extension with a private Unix socket; no replacement agent or model client. Bounded JSONL adapter, generation checks, duplicate suppression, command expansion and unsupported-UI terminal fallback.
- Original generic UI promise wrappers and version/shape/render-gated permission actions. Text-taking actions are advertised individually; reason Append, Enter and Back remain separate. No new authorizer or fabricated verdict.
- Direct SSH exec, request deadlines, foreground-only socket ownership, no mutation replay, read-only terminal observation and explicit control/takeover.
- Real loopback Plannotator forwarding and ephemeral WKWebView. Review opening requires a successful fresh snapshot; dismissal closes only forwarding.
- Explicit Parakeet preparation, local microphone conversion and inference, 194 sanitized command aliases. A unique completion id delivers manual/cap transcripts to their owning draft once; sending remains explicit.
- XcodeGen project, original icon and Mac build script requiring Swift 6.2 / Xcode 26+.
- Parallel SwiftPM/xtool device-build lane using Swift 6.4 / xtool 1.21 and an Apple-provided Xcode 27 SDK. Mac configuration is unchanged; the small SwiftTerm manifest patch is confined to an owned Linux cache.

## Checks performed

- Host protocol suite: **23 tests passed** on Node 24.20.0 against the real CLI/extension and isolated external Pi/Herdr peers. No live sessions or model calls. See [TESTING.md](TESTING.md) for coverage and limits.
- Strict TypeScript/checkJs against installed Pi 1.1.0 declarations, including test clients: passed (`host/check-host.mjs` and project `code_check`).
- All authored `.mjs` files: `node --check` passed.
- Python importer: Ruff lint and Python grammar passed. JSON/profile structure was checked; no credentials or desktop scripts were exported.
- Thirteen Core XCTest methods: **compiled and passed on native Linux with Swift 6.4**. Evidence: `ios/TestResults/core-key-paste-final.log`. These include six credential-preparation tests using synthetic armor/base64, not real keys or decryption. This does not prove any clipboard/Keychain/UIKit/SSH/audio path.
- App SwiftPM manifest accepted and real dependency graph resolved, with `ios/Package.resolved` retained. SwiftTerm manifest before/after checks prove the Apple/UIKit source exclusions are removed only for the explicit cross-target build. The derived app plist retains privacy strings and has no unexpanded Xcode variables.
- **Actual iOS semantic compile, link and packaging passed** through `tools/build-ios-linux.sh`, including SwiftUI, UIKit/Metal SwiftTerm, Citadel/NIO, WebKit and FluidAudio/Core ML. Initial and cached-planning failures are retained alongside four successful runs under `ios/TestResults/xtool-cache-fix-*.log`. An unwrapped xtool command still fails; the scoped wrapper passes `--disable-build-manifest-caching` while retaining SwiftBuild's reusable descriptions/objects.
- Output inspected: Mach-O arm64 executable, iOS 17 minimum, original bundle identity/iPhone-only family/privacy strings, byte-identical icon and VoxType profile, FluidAudio resource bundle, no provisioning profile. Load commands reference Apple system frameworks/libraries, not a missing third-party dynamic framework. None of this proves device loading/execution.
- SDK-fix regression repeats: seven Core tests passed (`core-post-sdk-fix.log`), 23 host tests passed (`host-post-sdk-fix.tap`), installed-declaration TypeScript/checkJs passed. The native warning cleanup compiled with no app-source warnings in the verified runs; a cold dependency build may still emit upstream warnings.
- Earlier Swift syntax-only/tree-sitter scans, plist/XcodeGen YAML and asset/profile JSON parsing are retained as supplementary checks, not substitutes for compilation.
- Build shell grammar and diff whitespace checks: passed. Setup/preparation rerun successfully without replacing the SDK or touching signing. Mac script's Linux rejection and Linux prerequisite gates were checked at the previous checkpoint; the Mac project/scripts remain unchanged.
- Harness Swift lint/typecheck/LSP mapping is unavailable; actual app/Core builds were run directly. ShellCheck is missing; JS lint and Python typechecking have no configured lane.

## Liquid Glass UI source checkpoint

The native material refresh is committed/pushed in `89497f3` (shared glass styles, status capsules, directory and settings craft) and `cbb1bb2` (floating composer, transcript styling, dictation controls, terminal keys and bounded dialog/accessory layout). iOS 26 uses Apple's glass APIs; iOS 17–25 retain native fallbacks. Navigation, host-owned permissions, terminal control and explicit draft sending remain intact in source.

The refreshed app's actual arm64 compile/link/package passes, including two source-change rebuilds: `ios/TestResults/xtool-build-20261011T075958Z.log` and `ios/TestResults/xtool-build-20261011T080147Z.log`. Thirteen current platform-neutral Core tests pass. The harness Swift checker remains unavailable; the real cross-build is the compile evidence, not a skipped check.

The independent source reviewer scored both named accessory-overflow and Follow-output findings resolved after corrections. **Native finish-review disposition: recapture.** No actual refresh screenshots, UI runtime tests or deployment occurred in this session; no visual ship verdict exists. [DESIGN.md](../DESIGN.md), its native sidecar and the [inspection checklist](TESTING.md#liquid-glass--required-native-inspection) describe the source system and remaining native checks without treating compilation as appearance proof.

## Compatibility and follow-up gates

- Host source targets Node 22.19+, Herdr 0.9.1 and Pi 1.1.0. Node/Herdr must be available in noninteractive SSH's PATH; no per-profile Node override is implemented.
- Native permissions target pi-permission-system 40.1.3 only. Existing uncaptured dialogs, editors, unsupported custom/overlay UIs and wrapped grant labels remain terminal-only. Actual approval/scoping/race behavior must be verified in dedicated sessions.
- Terminal history is capped at 8 MiB. Its copying runs on MainActor; Citadel's upstream output stream is unbounded. Device throughput/backpressure remains a known verification gap.
- Real SSH authentication, host-key rejection, terminal contention/resizing, WebKit ATS/assets/WebSockets, cancellation, model cache, microphone routes, five-minute delivery, memory/thermals and privacy instrumentation have not been exercised.
- Native visual inspection and independent finish review are blocked on actual iOS screenshots (Mac Simulator or physical phone). [DESIGN.md](../DESIGN.md) records a source baseline, not visual proof.
- Public test interfaces are approved. Thirteen Core methods compile/pass on Linux; eighteen app XCTest methods remain **uncompiled/unrun**. Connected native transport, cumulative history, real permissions and successful audio/inference paths remain outside automated proof.

No global Pi, Herdr, SSH, Tailscale or VoxType settings were changed; no host installation, live-session restart, Parakeet model download or paid inference was performed. The authorized Linux setup added private build tools and `usbmuxd` through desktop authorization; USB troubleshooting restarted only that service, without resetting pairing records. The user supplied Apple's SDK and configured signing credentials locally. The subsequent authorized install used those credentials through xtool for provisioning/signing; no secret material was displayed or committed and no revocation was approved. Follow [LINUX_SETUP.md](LINUX_SETUP.md) or [MAC_SETUP.md](MAC_SETUP.md) and record real app-runtime results before daily use.
