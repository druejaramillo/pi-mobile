# iOS direct SSH transport

Direct SSH, terminal and review modules are integrated with the native app and shared models. Their source-checked dependencies are declared in `ios/project.yml`. Public-boundary tests are approved; native guard tests are authored but unrun, and the host protocol suite passes. See [TESTING.md](TESTING.md). The private Linux Swift 6.4/xtool lane now compiles and links these modules in the real arm64 iOS app using the user-supplied Apple SDK. Seven Core tests pass. App-hosted XCTest, Mac/Xcode validation and actual iPhone transport behavior remain unverified.

## Public coordinator seam

All connection state and decoded events are published on MainActor:

```swift
@MainActor final class SSHBridgeConnection: ObservableObject {
    @Published private(set) var state: String
    @Published private(set) var lastError: String?
    @Published private(set) var agent: PiAgentSnapshot?
    @Published private(set) var topology: HerdrTopology?
    @Published private(set) var terminalFrame: TerminalFrame?
    func connect(profile: MachineProfile, secret: String) async throws
    func request(method: String, params: BridgeJSON) async throws -> BridgeJSON
    func disconnect()
    func openReview(_ review: PlannotatorReview) async throws -> PlannotatorTunnel
}
```

State strings are `disconnected`, `connecting`, `connected`, `failed`. Connect performs `hello` (protocol 1 and service name validation) and `snapshot`; it does not attach, acquire terminal control, install software or change host focus. Native UI must explicitly reconnect after foregrounding. `UIApplication.didEnterBackgroundNotification` closes the owned sockets, including sockets still connecting/authenticating. No background task, keepalive service, polling, automatic reconnect or mutation replay is implemented.

Every request uses a new UUID, has a 30-second deadline and is correlated by id. At most 64 requests may be pending. Cancellation/deadline does **not** establish that a delivered command was undone. Refresh authoritative state before another explicit action. Channel loss fails all pending requests and clears live agent/dialog/terminal attachment state. The last topology remains available only as explicitly stale cached navigation. Both stdout and stderr are drained, but stderr is discarded rather than published or logged. JSONL splits only on byte LF, validates UTF-8 after a complete record, rejects trailing partial records and caps each input/output command record at 1 MiB. A JSON `null` result remains a valid success. Unknown event names are ignored.

## Required parent dependencies and settings

The app target must link these products directly (imports are not assumed to be re-exported):

| Package | Product/module | Source-checked revision or constraint |
| --- | --- | --- |
| Local `ios/PiMobileCore` | `PiMobileCore` | Existing shared models |
| `https://github.com/orlandos-nl/Citadel.git` | `Citadel` | `ae8562f895de06ccb86fdb1cbb65fd99c8976e12` |
| `https://github.com/migueldeicaza/SwiftTerm.git` | `SwiftTerm` | `4dcf5278fde40af60c36f667d8a472a90b38b247` |
| `https://github.com/apple/swift-crypto.git` | `Crypto` | Citadel requires >= 3.12.3 |
| `https://github.com/apple/swift-nio.git` | `NIOCore`, `NIOPosix` | Citadel requires >= 2.81.0 |
| `https://github.com/Wellz26/swift-nio-ssh.git` | `NIOSSH` | Citadel manifest requires 0.3.4 ..< 0.4.0 |

Apple frameworks: Foundation, Combine, SwiftUI, UIKit, Security, WebKit. Deployment target **iOS 17+**, app **Swift 5 language mode**. The pinned SwiftTerm manifest itself uses **swift-tools-version 6.2** and **Swift 6 language mode**; an Xcode toolchain with Swift 6.2 support is therefore necessary regardless of the app's language mode. Citadel's checked-in `Package.resolved` still names the Joannis fork, whereas its current manifest names Wellz26: resolve from the manifest and do not add Apple's incompatible NIOSSH package alongside it. The integrated project declares these dependencies directly.

Do not enable `NSAllowsArbitraryLoads` or `NSAllowsArbitraryLoadsInWebContent`. If local HTTP needs ATS configuration on the chosen SDK/device, use the narrow `NSAppTransportSecurity.NSAllowsLocalNetworking` setting and verify the numeric loopback WKWebView case on-device. The app declares `NSAllowsLocalNetworking`, not either arbitrary-loads exception; numeric-loopback WebKit behavior is still unproven on-device. No local-network discovery or Bonjour is used.

## Actual SSH APIs and ownership

Sources inspected in the supplied Citadel checkout:

- `SSHCert.swift`: `Curve25519.Signing.PrivateKey(sshEd25519: String, decryptionKey: Data? = nil)` (also a Data overload).
- `SSHAuthenticationMethod.swift`: `.ed25519(username:privateKey:)`, `.passwordBased(username:password:)`, `.custom(_:)`. Custom key/password authentication implements `NIOSSHClientUserAuthenticationDelegate.nextAuthenticationType(availableMethods:nextChallengePromise:)`, offering each credential at most once.
- NIOSSH Wellz26 0.3.4 `NIOSSHPublicKey.swift`: `NIOSSHPublicKey(openSSHPublicKey: String) throws`, not a fabricated raw-key initializer. It parses the OpenSSH algorithm/base64 format and checks the embedded algorithm. Citadel's `SSHHostKeyValidator.trustedKeys(Set<NIOSSHPublicKey>)` verifies the full pinned key. No permissive validator is used.
- `Client.swift`: `SSHClient.connect(on: Channel, authenticationMethod: @autoclosure ..., hostKeyValidator: ..., algorithms: ..., protocolOptions: ...)`. **This existing-channel overload does not wait for authentication.** `SSHOwnedClient` owns a NIO `ClientBootstrap` socket before authentication, initially disables reads, installs Citadel's handlers and a readiness observer, then enables reads and waits for the real `UserAuthSuccessEvent`. TCP and authentication deadlines are each 15 seconds. Failures/cancellation close the owned socket. `SSHConnectionPoolSettings` defaults to `.never`, so this overload does not reconnect.
- `TTY/Client/TTY.swift`: `withExec(_:environment:perform:)` supplies `TTYOutput` and `TTYStdinWriter`; `TTYStdinWriter.write(ByteBuffer)` sends stdin bytes. The closure remains alive while consuming stdout/stderr; the writer is retained until channel teardown. Its `.command` mode requests exec, not a PTY or shell session. Exec readiness has a 20-second deadline. Citadel's `@available(macOS 15.0, *)` annotation does not impose an extra iOS availability requirement.
- `DirectTCPIP/Client/DirectTCPIP+Client.swift`: `createDirectTCPIPChannel(using: SSHChannelType.DirectTCPIP, initialize: (Channel) -> EventLoopFuture<Void>) async throws -> Channel`. Citadel already installs an SSHChannelData/ByteBuffer codec; the app adds ByteBuffer relays, not a second codec.

Citadel's output AsyncThrowingStream is upstream **unbounded**; our record and history limits do not turn that queue into a bounded queue. Device profiling/upstream stream backpressure remains follow-up work. Parsing and published history copying currently run on MainActor; no throughput/performance claim is made.

## Configuration and Keychain

Require a full OpenSSH host public key obtained and verified out-of-band. A fingerprint, an empty pin and a `known_hosts` hostname-prefixed line are rejected. This implementation accepts native NIOSSH Ed25519 and NIST ECDSA host-key types; it does not globally register legacy RSA algorithms.

Hostname, SSH port, username, Herdr session and bridge path are validated. Remote command invokes `exec node` with POSIX-quoted path/session arguments. Relative paths resolve beneath the **remote SSH account's `$HOME`**, expanded inside double quotes, with the normalized profile path separately single-quoted. They never depend on the authoring machine or a hardcoded username. Traversal above that root, controls, empty paths and tilde expansion are rejected. Absolute paths normalize beneath `/`. This validates command arguments, not the remote file's existence, ownership or symlinks. Remote installation/PATH remains the user's responsibility. Nothing is auto-installed.

`MachineProfile.authentication` values:

- `password`: `secret` is the password (not a JSON bundle).
- `key`: `secret` is an unencrypted OpenSSH Ed25519 private key, or JSON `{"privateKey":"...","passphrase":"..."}` for a supported encrypted OpenSSH key.
- `key+password`: JSON `{"privateKey":"...","passphrase":"optional","password":"..."}`; offer key then password according to the server's advertised methods. No keyboard-interactive/MFA UI is supplied.

Encrypted formats are limited to Citadel's actual parser support; no promise of every OpenSSH cipher/KDF. Secrets have a 128-KiB limit. The coordinator supplies the explicit secret to `connect`; transport never loads or persists credentials. `ios/PiMobile/Storage/MachineSecretStore.swift` is the single Keychain owner, using the machine UUID, nonsynchronizable `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` items. The machine editor saves a password, imported key, or encrypted-key/passphrase bundle. Key+password is a transport capability, not currently exposed by the editor. Keychain errors expose OSStatus only. Credentials necessarily exist in RAM while authentication is active; secure-memory zeroization is not claimed. Never store them in profile/UserDefaults or diagnostics.

## Terminal integration and important frame contract

```swift
MobileTerminalView(frame: connection.terminalFrame,
                   onInput: { bytes in /* explicit terminal.input with base64 */ },
                   onResize: { cols, rows in /* explicit terminal.resize */ },
                   interactive: hasConfirmedWritableAttachment)
```

**The facade's `terminalFrame.data` is cumulative connection-local ANSI history, not an individual wire-event payload.** Herdr's source-checked `render_stream.rs` emits incremental ANSI diffs. The shared frame has no event sequence identifier and SwiftUI may coalesce repeated published updates. `TerminalRenderHistory` therefore accumulates up to **8 MiB of decoded bytes** per attachment, without editing the shared model or host protocol. The representable feeds only the newly appended suffix, so coalesced updates and identical successive real output chunks remain correct. Nil/different terminal identity/non-prefix history resets the renderer. Attach/detach/closure/disconnect reset history. At capacity the connection fails rather than silently discarding diffs; the user must explicitly detach/reattach or reconnect for a fresh baseline. This is bounded correctness, not a long-running unlimited terminal solution. Approval should confirm this local facade contract before tests/integration are authored.

Pinned SwiftTerm APIs: `TerminalView(frame:font:)`, `.terminalDelegate`, `.feed(byteArray: ArraySlice<UInt8>)`, `.terminalDimensions` (copied `cols`/`rows`), `.resize(cols:rows:)`, `.resetToInitialState()`, `.updateUiClosed()`. **`getTerminal()` is removed at this revision**. All non-default TerminalViewDelegate methods are implemented. Kitty clipboard defaults deny unsupported access; OSC 52 reads/writes and remote link opening are explicitly denied. Permanent teardown waits for Metal-idle close as SwiftTerm's own representable does.

Observe mode denies input/keyboard and host resizing while retaining local selection/scrolling; it renders the advertised grid. Input and resize callbacks are gated and resize notifications deduplicated/deferred outside synchronous SwiftUI updates. The parent must first request `terminal.attach` with `control:false,takeover:false`, then explicitly acquire control/takeover. Never infer writable attachment from keyboard focus. Parent callbacks encode bytes as base64 for `terminal.input`. `MobileTerminalKey` exposes Esc, Tab, Enter, Backspace, arrows, Ctrl-C and Ctrl-D as Data for a native toolbar; arrows use normal ANSI cursor mode (application-cursor-mode-aware toolbar input is not implemented). Test observation-to-control grid transitions and orientation/keyboard resizing on-device.

## Plannotator forwarding and web view

`openReview` requires the exact id/URL pair in current topology and an id matching `plannotator_<hex>`. Accept only HTTP, no credentials, a loopback host (`localhost`, `127.0.0.1`, `::1`) and explicit port 1...65535. Regardless of the advertised loopback spelling, SSH destination is **always `127.0.0.1:<validated advertised port>`**. IPv6-only remote review servers are therefore not supported.

Only one review tunnel is retained per connection; opening a new review closes the previous owned forwarding without touching its remote server. Each tunnel binds only `127.0.0.1:0`. Its public `url: URL` rewrites the origin to the ephemeral local port and preserves path/query/fragment. `close()` is idempotent and closes only owned listener and child forwarding channels. Up to 33 channels per tunnel are retained, including the listener and both local/remote sides of connecting children; each forwarding setup has a 15-second deadline. Relays disable auto-read and advance reads after peer writes complete, carrying HTTP and WebSocket bytes without a general-purpose remote URL proxy. TCP half-close is forwarded. Closing one side closes its peer. The NIO singleton event-loop group is shared, not shut down globally.

Retain the tunnel while presenting `PlannotatorReviewView(url: tunnel.url)`; call `tunnel.close()` on dismissal, including error/interactive dismissal paths. Fresh `snapshot` responses close tunnels whose advertisements disappeared. There is no background topology polling, so disappearance is recognized on the next explicit snapshot or disconnection, not instantly while idle. Absolute remote-origin links/requests are not rewritten; pages must use same-origin relative requests. Cookies use an ephemeral WKWebsiteDataStore. Navigation actions/responses/popups are constrained to the exact local origin; external links are blocked, with no automatic Safari launch. If external browsing is needed, add an explicit parent-owned user/Safari action, not a permissive navigation delegate.

A WKContentRuleList blocks other resource origins and loading fails closed if compilation fails. This is defense-in-depth, not a claim that WK content rules sandbox every JavaScript network API. Verify real Plannotator assets, token URLs, WebSockets, redirects, popup behavior and WebKit rules/ATS on-device. The view is not an HTTP proxy and does not expose arbitrary remote hosts. Loopback ports are not a security boundary against other processes on the same device; rely on review tokens and the short owned lifetime.

## Checks performed and required next checks

- Read `PRODUCT.md`, `docs/BRIDGE_PROTOCOL.md`, and all shared `BridgeModels.swift`.
- Source-checked the Citadel and SwiftTerm APIs above, plus NIOSSH 0.3.4 public-key/auth/channel declarations and Herdr incremental rendering.
- Static scans found no permissive host validator, PTY API, arbitrary-loads setting, removed `getTerminal()` call, or arbitrary direct-tcpip target.
- `code_check` reported **SKIPPED: no .swift mapping**; `code_lsp` reported **no .swift mapping**. Structural search for removed `getTerminal()` found zero matches; it is not a typecheck.
- The complete native app now compiles/links/packages through the Linux iOS lane; repeated builds pass. NIO handler Sendable declarations document event-loop confinement; pinned Citadel interop uses `@preconcurrency`, not a claim that every library operation is Sendable-safe. The separate Core package passes seven XCTest methods. No app-hosted XCTest, Simulator, actual SSH/WebKit runtime, device, UI/performance or paid experiment was run. Host tests use isolated external peers, not an SSH round-trip.

Next: compile/run the authored public-facade tests with Swift 6.2-capable Xcode in app Swift 5 mode. Connected-path verification remains: actual pinned-key rejection, password/encrypted-key/dual auth, cancellation during connect/login, out-of-order responses/deadlines/EOF, background/manual foreground reconnect, cumulative terminal coalescing/capacity, and real review HTTP/WebSocket/navigation/dismissal. Strict Swift 6 concurrency mode is not claimed.
