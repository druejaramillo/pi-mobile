# Build status

## Readiness

**Physical-install checkpoint, not a device-verified release.** The private Linux Swift 6.4/xtool 1.21 lane builds the real arm64 iPhone app with the user-supplied Xcode 27 slim SDK; full and repeated builds pass. The latest authorized USB deployment successfully provisioned, signed, installed and verified the automatic trusted-host-key Tailscale build (`02eaf97`) on an iPhone running iOS 26.6.2. Pairing and Developer Mode were verified first; no certificate-revocation prompt appeared. App launch/runtime behavior, app-hosted tests, Mac/Xcode validation, rendering and actual permission compatibility remain unverified.

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

## Automatic trusted Tailscale identity — installed

Infrastructure checkpoint `1b77174` pins official libtailscale `019b925b989a2d1bbf3d750f14c740a20078c98b` / `tailscale.com v1.104.1`. Integration `02eaf97` adds one in-app browser sign-in and a separate **pi-mobile** tailnet device. The same foreground-only userspace node retrieves the exact peer's advertised host keys and supplies the SSH socket; no manual public-key copy, administrative token, network-scan trust or VPN/credential fallback exists. All supported advertised keys are parsed and validated against the real SSH server. Legacy pins/profiles/Keychain remain unchanged; saved Tailscale pin fields are retained but coordination keys now provide verification authority. No host/policy changes or mutation replay.

**Twenty-six Core tests, two Go/C race-detector regressions, the actual SSH socket-adoption/multi-key/rejection regression and six metadata tests pass.** Go vet passes. Initial and source-change/final arm64 app builds pass; current binary evidence is `ios/TestResults/xtool-build-20261011T173354Z.log`. Swift harness checks are unavailable, not a lint pass. Mac/Xcode and nineteen app-hosted XCTest methods remain unrun.

The user requested installation. Pairing and Developer Mode were validated on the selected iPhone18,1 running iOS 26.6.2. `tools/deploy-ios-linux.sh` ran **once** for the existing `02eaf97` artifact: provisioning, signing, installation and verification completed with `Successfully installed!`. No revocation prompt, uninstall, profile/Keychain reset, host/session change or app launch occurred. Private deployment-result summary: `ios/TestResults/tailscale-device-install-20261011.md`.

Open **Settings → Tailscale → Sign in**, finish the browser flow and any deliberate pi-mobile device approval, then connect the saved machine. Actual tailnet sign-in, retained saved-machine state, iPhone SSH, node suspend/resume and native appearance remain unverified. The substituted inline native finish review is **recapture**, not a visual verdict; there are no native screenshots. Existing visual-system tokens are preserved, and pre-existing sidecar drift is not repaired. See [embedded client](TAILSCALE_CLIENT.md) and [device checklist](TESTING.md#tailscale-ssh-setup--required-native-verification).

## SSH save/launch crash fix

Five crash reports copied from the connected iPhone (kept on the device) show a fatal `EventLoop.preconditionInEventLoop` assertion in Citadel's existing-channel pipeline setup. The first followed Save; later launches retried the persisted machine through `refreshAll`. The same app transport sources reproduced the assertion against a disposable loopback server on Linux, exit 132.

Both build lanes now prepare the unchanged Citadel revision with a checked-in patch that confines pipeline/session construction to the socket's event loop. Authentication readiness observes events before Citadel's consuming handler and observes the raw close future too. No profile, Keychain, host-key policy, Tailscale configuration or host agent is reset or changed.

`tools/test-ssh-transport.sh` passes repeated successful logins/clean closes, wrong-password rejection, wrong-host-key rejection and raw socket teardown during stalled login. Thirteen Core tests and the real iPhone compile/link/package pass. Evidence is retained privately under `ios/TestResults/`; the fixture-only Linux `CDispatch` import is a compiler compatibility fix, not a runtime change. The corrected transport is included in the subsequently authorized in-place updates, including keyless build `440e66d`. A device launch/connection check with the existing saved machine is still required before claiming the user's on-device crash loop is resolved.

## Machine credential paste checkpoint (superseded)

Private keys can now be pasted with a native system Paste control or imported from a file; encrypted-key passphrases have a separate Paste control and remain masked. Preparation checks OpenSSH armor/base64, normalizes key line endings, preserves passphrases verbatim and enforces the serialized credential limit. Keys remain device-only Keychain items; host-key verification is unchanged. At this historical checkpoint, keyless Tailscale SSH was not yet available. The later keyless setup below supersedes these credential-entry controls.

Thirteen Core tests pass (`ios/TestResults/core-key-paste-final.log`), and initial/repeated iPhone compile/link/package builds pass (`xtool-build-20261011T075224Z.log`, `xtool-build-20261011T075250Z.log`). Native clipboard/Keychain/SSH interaction remains unrun. The inline native visual review's disposition is **recapture** because iPhone screenshots are unavailable; no visual approval is claimed. The current [keyless setup checklist](TESTING.md#tailscale-ssh-setup--required-native-verification) supersedes the paste UI checklist.

## Keyless Tailscale SSH setup (historical, manual identity entry superseded)

Transport checkpoint `8608f70` adds SSH `none` authentication for new profiles and skips Keychain access, including when an old item remains. Existing profiles retain their auth mode, port, UUID and host pin; no automatic migration or deletion occurs. The editor now removes the auth picker, private-key import/paste, password/passphrase controls and new-machine port field. Port 22 is automatic, and host bridge defaults sit under a disclosure. The verified **public host identity** remains required. Existing machines can explicitly switch to Tailscale SSH; that clears the draft pin and requires the advertised public key before Save. Cancel leaves saved state unchanged.

Tailscale SSH must be enabled on the host and permitted for the phone's identity/username. This implementation requires an SSH `accept` rule; interactive `check`-mode browser sign-in is **not supported**. Host configuration/policy is documented, never changed automatically. Legacy Keychain read/delete and SSH auth are retained for old machines; credential writes are removed.

**Sixteen Core tests pass** (`ios/TestResults/core-tailscale-ssh.log`). The actual loopback transport passes repeated keyless logins, rejecting denied users/password-only SSH, no supplied-secret fallback, missing/mismatched host pins and the earlier crash regressions (`ssh-transport-regression.log`). The real arm64 iPhone app compiles/links/packages in initial and source-change confirmation builds (`xtool-build-20261011T090131Z.log`, `xtool-build-20261011T090542Z.log`). Real tailnet SSH, Keychain/migration interaction and native screenshots remain unverified. Native finish disposition remains **recapture**; compilation is not visual/runtime approval.

Authorized in-place USB update (2026-10-11): the user explicitly requested installation. Existing pairing validated and Developer Mode was already enabled on the selected connected iPhone running iOS 26.6.2. `tools/deploy-ios-linux.sh` ran once with the existing `440e66d` app artifact; provisioning, signing, installation and installer verification completed with `Successfully installed!`. No certificate-revocation prompt appeared. No uninstall, saved-profile/Keychain reset, app launch or host setting change was performed. Evidence: `ios/TestResults/deploy-keyless-tailscale-20261011T090750Z.log`. Launch with the existing saved machine and confirm connection/error presentation; installation alone is not runtime proof.

## Implemented in source

- Launch Agents tab: recognized agents across machines, search, machine/workspace/tab/pane context and direct stable-terminal navigation. Unreachable hosts are not treated as empty. In-memory cached locations are explicitly stale.
- Machine/workspace/tab browsing, keyless Tailscale SSH setup, in-app sign-in as a separate device, automatic verified host identity and per-terminal persisted drafts. Existing SSH/Keychain logins remain compatible; switching is explicit. Private-key/password/passphrase setup is removed.
- Same-process Pi extension with a private Unix socket; no replacement agent or model client. Bounded JSONL adapter, generation checks, duplicate suppression, command expansion and unsupported-UI terminal fallback.
- Original generic UI promise wrappers and version/shape/render-gated permission actions. Text-taking actions are advertised individually; reason Append, Enter and Back remain separate. No new authorizer or fabricated verdict.
- Direct SSH exec, request deadlines, foreground-only socket ownership, no mutation replay, read-only terminal observation and explicit control/takeover.
- Real loopback Plannotator forwarding and ephemeral WKWebView. Review opening requires a successful fresh snapshot; dismissal closes only forwarding.
- Explicit Parakeet preparation, local microphone conversion and inference, 194 sanitized command aliases. A unique completion id delivers manual/cap transcripts to their owning draft once; sending remains explicit.
- XcodeGen project, original icon and Mac build script requiring Swift 6.2 / Xcode 26+.
- Parallel SwiftPM/xtool device-build lane using Swift 6.4 / xtool 1.21 and an Apple-provided Xcode 27 SDK. Both lanes prepare the pinned destination-specific Tailscale C archive; Mac device/Simulator destinations must be prepared separately. The small SwiftTerm manifest patch remains confined to an owned Linux cache.

## Checks performed

- Host protocol suite: **23 tests passed** on Node 24.20.0 against the real CLI/extension and isolated external Pi/Herdr peers. No live sessions or model calls. See [TESTING.md](TESTING.md) for coverage and limits.
- Strict TypeScript/checkJs against installed Pi 1.1.0 declarations, including test clients: passed (`host/check-host.mjs` and project `code_check`).
- All authored `.mjs` files: `node --check` passed.
- Python importer: Ruff lint and Python grammar passed. JSON/profile structure was checked; no credentials or desktop scripts were exported.
- Twenty-six Core XCTest methods: **compiled and passed on native Linux with Swift 6.4**. Evidence: `ios/TestResults/core-tailscale-identity.log`. These include three keyless/default/legacy-profile tests and six retained credential-preparation tests using synthetic armor/base64, not real keys or decryption. This does not prove any Keychain/UIKit/SSH/audio path.
- App SwiftPM manifest accepted and real dependency graph resolved, with `ios/Package.resolved` retained. SwiftTerm manifest before/after checks prove the Apple/UIKit source exclusions are removed only for the explicit cross-target build. The derived app plist retains privacy strings and has no unexpanded Xcode variables.
- **Actual iOS semantic compile, link and packaging passed** through `tools/build-ios-linux.sh`, including SwiftUI, UIKit/Metal SwiftTerm, Citadel/NIO, WebKit and FluidAudio/Core ML. Initial and cached-planning failures are retained alongside four successful runs under `ios/TestResults/xtool-cache-fix-*.log`. An unwrapped xtool command still fails; the scoped wrapper passes `--disable-build-manifest-caching` while retaining SwiftBuild's reusable descriptions/objects.
- Output inspected: Mach-O arm64 executable, iOS 17 minimum, original bundle identity/iPhone-only family/privacy strings, byte-identical icon and VoxType profile, FluidAudio resource bundle, no provisioning profile. Load commands reference Apple system frameworks/libraries, not a missing third-party dynamic framework. None of this proves device loading/execution.
- SDK-fix regression repeats: seven Core tests passed (`core-post-sdk-fix.log`), 23 host tests passed (`host-post-sdk-fix.tap`), installed-declaration TypeScript/checkJs passed. The native warning cleanup compiled with no app-source warnings in the verified runs; a cold dependency build may still emit upstream warnings.
- Earlier Swift syntax-only/tree-sitter scans, plist/XcodeGen YAML and asset/profile JSON parsing are retained as supplementary checks, not substitutes for compilation.
- Build shell grammar and diff whitespace checks: passed. Setup/preparation rerun successfully without replacing the SDK or touching signing. Mac script's Linux rejection and Linux prerequisite gates were checked at the previous checkpoint; the Mac project/scripts remain unchanged.
- Harness Swift lint/typecheck/LSP mapping is unavailable; actual app/Core builds were run directly. ShellCheck is missing; JS lint and Python typechecking have no configured lane.

## Liquid Glass UI source checkpoint

The native material refresh is committed/pushed in `89497f3` (shared glass styles, status capsules, directory and settings craft) and `cbb1bb2` (floating composer, transcript styling, dictation controls, terminal keys and bounded dialog/accessory layout). iOS 26 uses Apple's glass APIs; iOS 17–25 retain native fallbacks. Navigation, host-owned permissions, terminal control and explicit draft sending remain intact in source.

The refreshed app's actual arm64 compile/link/package passes, including two source-change rebuilds: `ios/TestResults/xtool-build-20261011T075958Z.log` and `ios/TestResults/xtool-build-20261011T080147Z.log`. Thirteen platform-neutral Core tests passed at this earlier checkpoint. The harness Swift checker remains unavailable; the real cross-build is the compile evidence, not a skipped check.

The independent source reviewer scored both named accessory-overflow and Follow-output findings resolved after corrections. **Native finish-review disposition: recapture.** No actual refresh screenshots or UI runtime tests have been captured; no visual ship verdict exists. [DESIGN.md](../DESIGN.md), its native sidecar and the [inspection checklist](TESTING.md#liquid-glass--required-native-inspection) describe the source system and remaining native checks without treating compilation as appearance proof.

Follow-up authorized USB installation (2026-10-11): rebuilt revision `ce51440` (`ios/TestResults/xtool-build-20261011T081003Z.log`), validated the existing pairing and confirmed Developer Mode was already enabled on the connected iPhone running iOS 26.6.2, then ran the explicit deployment script once. Provisioning, signing, installation and installer verification completed with `Successfully installed!`; no certificate-revocation prompt appeared. The refreshed app is installed. Launch, appearance and interaction checks remain human verification gates; installation is not runtime proof.

## Compatibility and follow-up gates

- Host source targets Node 22.19+, Herdr 0.9.1 and Pi 1.1.0. Node/Herdr must be available in noninteractive SSH's PATH; no per-profile Node override is implemented.
- Native permissions target pi-permission-system 40.1.3 only. Existing uncaptured dialogs, editors, unsupported custom/overlay UIs and wrapped grant labels remain terminal-only. Actual approval/scoping/race behavior must be verified in dedicated sessions.
- Terminal history is capped at 8 MiB. Its copying runs on MainActor; Citadel's upstream output stream is unbounded. Device throughput/backpressure remains a known verification gap.
- Real SSH authentication, host-key rejection, terminal contention/resizing, WebKit ATS/assets/WebSockets, cancellation, model cache, microphone routes, five-minute delivery, memory/thermals and privacy instrumentation have not been exercised.
- Native visual inspection and independent finish review are blocked on actual iOS screenshots (Mac Simulator or physical phone). [DESIGN.md](../DESIGN.md) records a source baseline, not visual proof.
- Public test interfaces are approved. Twenty-six Core methods compile/pass on Linux; nineteen app XCTest methods remain **uncompiled/unrun**. Connected native transport, cumulative history, real permissions and successful audio/inference paths remain outside automated proof.

No global Pi, Herdr, SSH, Tailscale or VoxType settings were changed; no host installation, live-session restart, Parakeet model download or paid inference was performed. The authorized Linux setup added private build tools and `usbmuxd` through desktop authorization; USB troubleshooting restarted only that service, without resetting pairing records. The user supplied Apple's SDK and configured signing credentials locally. The subsequent authorized install used those credentials through xtool for provisioning/signing; no secret material was displayed or committed and no revocation was approved. Follow [LINUX_SETUP.md](LINUX_SETUP.md) or [MAC_SETUP.md](MAC_SETUP.md) and record real app-runtime results before daily use.
