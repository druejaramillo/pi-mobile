# Build status

## Readiness

**Source integration checkpoint for a Mac build, not a device-verified release.** The authoring machine is Linux, without Swift/Xcode. Native compilation, Simulator rendering, physical-device behavior and permission compatibility remain unverified.

## Approved scope

Native iPhone app, direct SSH over Tailscale, existing Herdr/Pi sessions, global agent directory, native conversation and supported dialogs, terminal escape hatch, actual SSH-forwarded Plannotator, on-device Parakeet TDT v3 and deterministic VoxType cleanup. No notifications or background monitoring.

## Checkpoints

1. Protocol/product scaffold: committed and pushed (`c2e6c3c`).
2. Native UI/session navigation scaffold: committed and pushed (`55f681d`).
3. Host and native integration: authored with pinned dependencies, setup documentation and static checks below.

## Implemented in source

- Launch Agents tab: recognized agents across machines, search, machine/workspace/tab/pane context and direct stable-terminal navigation. Unreachable hosts are not treated as empty. In-memory cached locations are explicitly stale.
- Machine/workspace/tab browsing, device-only nonsynchronizable Keychain credentials, encrypted Ed25519-key passphrase entry, trusted host-key setup and per-terminal persisted drafts.
- Same-process Pi extension with a private Unix socket; no replacement agent or model client. Bounded JSONL adapter, generation checks, duplicate suppression, command expansion and unsupported-UI terminal fallback.
- Original generic UI promise wrappers and version/shape/render-gated permission actions. Text-taking actions are advertised individually; reason Append, Enter and Back remain separate. No new authorizer or fabricated verdict.
- Direct SSH exec, request deadlines, foreground-only socket ownership, no mutation replay, read-only terminal observation and explicit control/takeover.
- Real loopback Plannotator forwarding and ephemeral WKWebView. Review opening requires a successful fresh snapshot; dismissal closes only forwarding.
- Explicit Parakeet preparation, local microphone conversion and inference, 194 sanitized command aliases. A unique completion id delivers manual/cap transcripts to their owning draft once; sending remains explicit.
- XcodeGen project, original icon and Mac build script requiring Swift 6.2 / Xcode 26+.

## Checks performed

- Strict TypeScript/checkJs against installed Pi 1.1.0 declarations: passed (`host/check-host.mjs` and project `code_check`).
- All authored `.mjs` files: `node --check` passed.
- Python importer: Ruff lint and Python grammar passed. JSON/profile structure was checked; no credentials or desktop scripts were exported.
- Swift tree-sitter scan: 25 files, no findings other than two known empty-Void-tuple parser limitations at NIO `succeed(())` calls. **This is not a Swift compiler/typecheck.**
- Info.plist, XcodeGen YAML and asset/profile JSON: parsed.
- Build shell grammar and diff whitespace checks: passed. Build script refused Linux with exit 2 and a Mac prerequisite message.
- Swift lint/typecheck/LSP: unavailable in this harness, not a clean result. JS lint and Python typechecking have no configured lane.

## Compatibility and follow-up gates

- Host source targets Node 22.19+, Herdr 0.9.1 and Pi 1.1.0. Node/Herdr must be available in noninteractive SSH's PATH; no per-profile Node override is implemented.
- Native permissions target pi-permission-system 40.1.3 only. Existing uncaptured dialogs, editors, unsupported custom/overlay UIs and wrapped grant labels remain terminal-only. Actual approval/scoping/race behavior must be verified in dedicated sessions.
- Terminal history is capped at 8 MiB. Its copying runs on MainActor; Citadel's upstream output stream is unbounded. Device throughput/backpressure remains a known verification gap.
- Real SSH authentication, host-key rejection, terminal contention/resizing, WebKit ATS/assets/WebSockets, cancellation, model cache, microphone routes, five-minute delivery, memory/thermals and privacy instrumentation have not been exercised.
- Native visual inspection and independent finish review are blocked on Mac screenshots. [DESIGN.md](../DESIGN.md) records a source baseline, not visual proof.
- Public test seams (bridge protocol and native session/dictation interfaces, including cumulative terminal history) await user approval. **No tests have been authored or run.**

No global Pi, Herdr, SSH, Tailscale or VoxType settings were changed; no host installation, live-session restart, model download or paid inference was performed. Follow [MAC_SETUP.md](MAC_SETUP.md) and record real results here before daily use.
