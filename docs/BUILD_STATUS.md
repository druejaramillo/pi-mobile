# Build status

## Readiness

**Source integration checkpoint, not a device-verified release.** The Linux authoring machine now has private Swift 6.4/xtool 1.21; the Core package compiles and passes XCTest. The first actual iOS app build is blocked on Apple's SDK, and signing/physical-device access are not configured. Simulator rendering and permission compatibility remain unverified.

## Approved scope

Native iPhone app, direct SSH over Tailscale, existing Herdr/Pi sessions, global agent directory, native conversation and supported dialogs, terminal escape hatch, actual SSH-forwarded Plannotator, on-device Parakeet TDT v3 and deterministic VoxType cleanup. No notifications or background monitoring.

## Checkpoints

1. Protocol/product scaffold: committed and pushed (`c2e6c3c`).
2. Native UI/session navigation scaffold: committed and pushed (`55f681d`).
3. Host and native integration: committed and pushed (`93ae84e`) with pinned dependencies and setup documentation.
4. Approved-boundary test suite: committed/pushed (`1c0ee29`), with 23 host tests and 25 XCTest methods.
5. Linux xtool build/deploy lane: private verified toolchain, resolved app graph, exact SwiftTerm cross-target manifest patch, packaging and explicit USB deployment scripts. Seven Core tests compile/pass; eighteen app-hosted tests remain unrun. No iOS binary yet.

## Implemented in source

- Launch Agents tab: recognized agents across machines, search, machine/workspace/tab/pane context and direct stable-terminal navigation. Unreachable hosts are not treated as empty. In-memory cached locations are explicitly stale.
- Machine/workspace/tab browsing, device-only nonsynchronizable Keychain credentials, encrypted Ed25519-key passphrase entry, trusted host-key setup and per-terminal persisted drafts.
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
- Seven Core XCTest methods: **compiled and passed on native Linux with Swift 6.4**. Evidence: `ios/TestResults/core-linux-runpath.log`. This does not prove any UIKit/SSH/audio path.
- App SwiftPM manifest accepted and real dependency graph resolved, with `ios/Package.resolved` retained. SwiftTerm manifest before/after checks prove the Apple/UIKit source exclusions are removed only for the explicit cross-target build. The derived app plist retains privacy strings and has no unexpanded Xcode variables.
- Swift 6.4 compiler **syntax-only parse** accepted all 23 app source files in Swift 5 mode. The original tree-sitter scan had only two empty-Void-tuple parser limitations. Neither check establishes app semantic compilation/API compatibility; that remains unperformed.
- Info.plist, XcodeGen YAML and asset/profile JSON: parsed.
- Build shell grammar and diff whitespace checks: passed. Mac script still refuses Linux with exit 2; Linux script now reaches its real SDK gate and refuses a missing Apple SDK with exit 2. Private toolchain setup and dependency preparation were rerun successfully.
- Harness Swift lint/typecheck/LSP mapping is unavailable; actual Core compile/XCTest was run directly. Native app typechecking remains blocked on Apple's SDK. ShellCheck was initially missing; JS lint and Python typechecking have no configured lane.

## Compatibility and follow-up gates

- Host source targets Node 22.19+, Herdr 0.9.1 and Pi 1.1.0. Node/Herdr must be available in noninteractive SSH's PATH; no per-profile Node override is implemented.
- Native permissions target pi-permission-system 40.1.3 only. Existing uncaptured dialogs, editors, unsupported custom/overlay UIs and wrapped grant labels remain terminal-only. Actual approval/scoping/race behavior must be verified in dedicated sessions.
- Terminal history is capped at 8 MiB. Its copying runs on MainActor; Citadel's upstream output stream is unbounded. Device throughput/backpressure remains a known verification gap.
- Real SSH authentication, host-key rejection, terminal contention/resizing, WebKit ATS/assets/WebSockets, cancellation, model cache, microphone routes, five-minute delivery, memory/thermals and privacy instrumentation have not been exercised.
- Native visual inspection and independent finish review are blocked on actual iOS screenshots (Mac Simulator or physical phone). [DESIGN.md](../DESIGN.md) records a source baseline, not visual proof.
- Public test interfaces are approved. Seven Core methods compile/pass on Linux; eighteen app XCTest methods remain **uncompiled/unrun**. Connected native transport, cumulative history, real permissions and successful audio/inference paths remain outside automated proof.

No global Pi, Herdr, SSH, Tailscale or VoxType settings were changed; no host installation, live-session restart, model download or paid inference was performed. The authorized Linux setup added private build tools and `usbmuxd` through desktop authorization; no Apple credential, SDK, certificate or device-install action has happened. Follow [LINUX_SETUP.md](LINUX_SETUP.md) or [MAC_SETUP.md](MAC_SETUP.md) and record real results here before daily use.
