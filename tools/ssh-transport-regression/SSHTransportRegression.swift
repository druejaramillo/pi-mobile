import Foundation
import Citadel
import Crypto
import NIOCore
import NIOPosix
// Pinned NIOSSH predates Sendable; server keys are immutable and delegates below are stateless.
@preconcurrency import NIOSSH
import PiMobileCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs the real SSH connection boundary against ephemeral loopback servers, never a saved machine.
@main
struct SSHTransportRegression {
    static func main() async {
        do {
            if CommandLine.arguments.contains("--exec-only") { try await runSSHExecRegression() }
            else { try await runSSHRegression() }
        }
        catch {
            FileHandle.standardError.write(Data("FAIL: SSH transport regression: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func runSSHExecRegression() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sockets = SSHChannelOwnership(limit: 8)
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await bindSSHServer(group: group, sockets: sockets, hostKeys: [key],
                                             authentication: SSHRegressionTailscaleDelegate())
        do {
            guard let port = server.localAddress?.port else { throw SSHRegressionFailure.failed("exec fixture server port") }
            let commands: [String]? = CommandLine.arguments.contains("--early-exit-only") ? ["fixture-missing-bridge"] : nil
            try await verifySSHExecLifecycle(port: port, hostKeys: [key], sockets: sockets, commands: commands,
                                             useSocketpair: !CommandLine.arguments.contains("--raw-tcp"))
            sockets.close()
            try await server.close().get()
            try await group.shutdownGracefully()
        } catch {
            sockets.close()
            try? await server.close().get()
            try? await group.shutdownGracefully()
            throw error
        }
    }

    private static func runSSHRegression() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let serverSockets = SSHChannelOwnership(limit: 16)
        let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await bindSSHServer(group: group, sockets: serverSockets, hostKeys: [hostKey],
            authentication: SSHRegressionPasswordDelegate())
        var keylessServer: Channel?
        do {
            guard let port = server.localAddress?.port else { throw SSHRegressionFailure.failed("loopback server port") }
            let profile = MachineProfile(name: "Loopback regression only", hostname: "127.0.0.1", port: port,
                username: "regression", hostPublicKey: String(openSSHPublicKey: hostKey.publicKey), authentication: "password")
            for _ in 0..<3 { try await verifySSHConnection(profile: profile, secret: "test-only-password") }
            print("PASS: three fresh existing-channel SSH connections authenticate and close without an event-loop assertion.")
            try await verifySSHFailure(profile: profile, secret: "wrong-test-password") { error in
                if case SSHClientError.allAuthenticationOptionsFailed = error { return true }
                return false
            }
            print("PASS: wrong passwords fail promptly without crashing.")
            var wrongPin = profile
            let otherKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
            wrongPin.hostPublicKey = String(openSSHPublicKey: otherKey.publicKey)
            try await verifySSHFailure(profile: wrongPin, secret: "test-only-password") { isHostIdentityMismatch($0) }
            print("PASS: mismatched host keys are rejected before authentication without crashing.")
            try await verifySSHLoginTeardown(profile: profile, group: group, serverSockets: serverSockets)
            print("PASS: closing owned sockets during stalled login terminates promptly.")

            // Real SSH/Tailscale servers advertise several host key types; an Ed25519 pin must still work.
            let ecdsaHostKey = NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey())
            let keyless = try await bindSSHServer(group: group, sockets: serverSockets, hostKeys: [ecdsaHostKey, hostKey],
                authentication: SSHRegressionTailscaleDelegate())
            keylessServer = keyless
            guard let keylessPort = keyless.localAddress?.port else { throw SSHRegressionFailure.failed("keyless server port") }
            let tailscale = MachineProfile(name: "Keyless loopback only", hostname: "127.0.0.1", port: keylessPort,
                username: "regression", hostPublicKey: String(openSSHPublicKey: hostKey.publicKey))
            for _ in 0..<3 { try await verifySSHConnection(profile: tailscale) }
            // Even an explicitly supplied old secret must not be offered in Tailscale mode.
            try await verifySSHConnection(profile: tailscale, secret: "unused-old-credential")
            print("PASS: keyless Tailscale SSH offers none, authenticates repeatedly, and never sends an old credential.")
            print("PASS: a verified Ed25519 host pin works when the server also advertises an ECDSA host key.")
            try await verifySSHCoordinationKeys(port: keylessPort, hostKeys: [hostKey, ecdsaHostKey], sockets: serverSockets)
            print("PASS: advertised host-key sets authenticate over an adopted userspace socketpair without a manual pin.")
            print("PASS: automatic identity rejects wrong, malformed, missing and unsupported-only keys; legacy pins cannot be overridden.")
            try await verifySSHExecLifecycle(port: keylessPort, hostKeys: [hostKey, ecdsaHostKey], sockets: serverSockets)
            try await verifySSHExecLifecycle(port: keylessPort, hostKeys: [hostKey, ecdsaHostKey], sockets: serverSockets, useSocketpair: false)

            var deniedUser = tailscale
            deniedUser.username = "not-allowed"
            try await verifySSHFailure(profile: deniedUser) { error in
                if case SSHBridgeError.tailscaleSSHUnavailable = error { return true }
                return false
            }
            print("PASS: denied keyless usernames fail promptly without repeated authentication offers.")
            var passwordOnly = profile
            passwordOnly.authentication = "tailscale"
            try await verifySSHFailure(profile: passwordOnly, secret: "test-only-password") { error in
                if case SSHBridgeError.tailscaleSSHUnavailable = error { return true }
                return false
            }
            print("PASS: keyless mode rejects password-only SSH without falling back to a supplied password.")

            wrongPin.port = keylessPort
            wrongPin.authentication = "tailscale"
            try await verifySSHFailure(profile: wrongPin) { isHostIdentityMismatch($0) }
            var missingPin = tailscale
            missingPin.hostPublicKey = ""
            do {
                _ = try SSHBridgeConfiguration(profile: missingPin)
                throw SSHRegressionFailure.failed("keyless mode accepted an empty host pin")
            } catch SSHBridgeError.invalidProfile(_) {}
            print("PASS: keyless SSH still rejects mismatched and missing host identity keys.")
            do {
                _ = try SSHBridgeConfiguration(profile: profile).authenticationMethod()
                throw SSHRegressionFailure.failed("legacy password mode accepted a missing credential")
            } catch SSHBridgeError.invalidSecret {}
            print("PASS: legacy SSH still requires its credential; it is not silently migrated.")

            serverSockets.close()
            try await keyless.close().get()
            try await server.close().get()
            try await group.shutdownGracefully()
        } catch {
            serverSockets.close()
            try? await keylessServer?.close().get()
            try? await server.close().get()
            try? await group.shutdownGracefully()
            throw error
        }
    }

    private static func isHostIdentityMismatch(_ error: Error) -> Bool {
        if case SSHBridgeError.hostIdentityMismatch = error { return true }
        return false
    }

    private static func verifySSHCoordinationKeys(port: Int, hostKeys: [NIOSSHPrivateKey],
                                                  sockets: SSHChannelOwnership) async throws {
        // The DNS name intentionally cannot resolve through the OS; only the adopted socket reaches the fixture.
        let profile = MachineProfile(name: "Automatic identity test", hostname: "fixture.tail-test.ts.net", username: "regression")
        let advertised = hostKeys.map { String(openSSHPublicKey: $0.publicKey) }
        let configuration = try SSHBridgeConfiguration(profile: profile, trustedHostKeys: advertised + ["ssh-rsa test-unsupported-only"])
        guard configuration.hostKeys.count == 2 else { throw SSHRegressionFailure.failed("all supported advertised keys must be trusted") }
        let ownership = SSHChannelOwnership(limit: 1)
        defer { ownership.close() }
        let descriptor = try await relayedSSHSocket(port: port, sockets: sockets)
        let client = try await SSHOwnedClient.connect(configuration: configuration,
            authentication: configuration.authenticationMethod(), ownership: ownership, connectedSocket: descriptor)
        guard client.isConnected else { throw SSHRegressionFailure.failed("adopted Tailscale socket authentication") }
        try await client.close()

        let wrongKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let incorrect = try SSHBridgeConfiguration(profile: profile, trustedHostKeys: [String(openSSHPublicKey: wrongKey.publicKey)])
        let wrongOwnership = SSHChannelOwnership(limit: 1)
        defer { wrongOwnership.close() }
        let wrongDescriptor = try await relayedSSHSocket(port: port, sockets: sockets)
        do {
            _ = try await SSHOwnedClient.connect(configuration: incorrect,
                authentication: incorrect.authenticationMethod(), ownership: wrongOwnership, connectedSocket: wrongDescriptor)
            throw SSHRegressionFailure.failed("unadvertised server key was accepted")
        } catch SSHBridgeError.hostIdentityMismatch {}
        for keys in [[], ["ssh-rsa test-unsupported-only"]] {
            do {
                _ = try SSHBridgeConfiguration(profile: profile, trustedHostKeys: keys)
                throw SSHRegressionFailure.failed("empty/unsupported coordination key set accepted")
            } catch TailscaleIdentityError.missingHostKeys {}
        }
        do {
            _ = try SSHBridgeConfiguration(profile: profile, trustedHostKeys: ["ssh-ed25519 malformed-key"])
            throw SSHRegressionFailure.failed("malformed coordination key accepted")
        } catch SSHBridgeError.invalidProfile(_) {}
        var legacy = profile
        legacy.authentication = "password"
        do {
            _ = try SSHBridgeConfiguration(profile: legacy, trustedHostKeys: advertised)
            throw SSHRegressionFailure.failed("coordination keys overrode a legacy saved pin")
        } catch SSHBridgeError.invalidProfile(_) {}
    }

    private static func verifySSHExecLifecycle(port: Int, hostKeys: [NIOSSHPrivateKey], sockets: SSHChannelOwnership,
                                               commands: [String]? = nil,
                                               useSocketpair: Bool = true) async throws {
        let profile = MachineProfile(name: "Exec lifecycle only", hostname: useSocketpair ? "fixture.tail-test.ts.net" : "127.0.0.1",
            port: useSocketpair ? 22 : port, username: "regression", hostPublicKey: String(openSSHPublicKey: hostKeys[0].publicKey))
        let configuration = try SSHBridgeConfiguration(profile: profile,
            trustedHostKeys: useSocketpair ? hostKeys.map { String(openSSHPublicKey: $0.publicKey) } : nil)
        for command in commands ?? ["fixture-echo", "fixture-missing-bridge", "fixture-exit-one", "fixture-exit-zero", "fixture-callback-error"] {
            let ownership = SSHChannelOwnership(limit: 1)
            defer { ownership.close() }
            let descriptor = useSocketpair ? try await relayedSSHSocket(port: port, sockets: sockets) : nil
            let client = try await SSHOwnedClient.connect(configuration: configuration,
                authentication: configuration.authenticationMethod(), ownership: ownership, connectedSocket: descriptor)
            defer { Task { try? await client.close() } }
            var receivedEcho = false
            let transport = useSocketpair ? "socketpair" : "raw TCP"
            do {
                try await SSHBridgeExec.run(client: client, command: command) { inbound, outbound in
                    if command == "fixture-echo" { try await outbound.write(ByteBuffer(string: "fixture JSONL input\n")) }
                    for try await output in inbound {
                        if command == "fixture-echo", case .stdout(let bytes) = output {
                            guard String(buffer: bytes) == "fixture JSONL input\n" else {
                                throw SSHRegressionFailure.failed("SSH exec changed fixture stdin/stdout")
                            }
                            receivedEcho = true
                            break
                        }
                    }
                    if command == "fixture-callback-error" { throw SSHBridgeError.protocolViolation("fixture callback failure") }
                }
                if command == "fixture-echo", receivedEcho {
                    print("PASS: authenticated \(transport) SSH exec carries bidirectional bridge bytes.")
                } else if command == "fixture-exit-zero" {
                    print("PASS: remote EOF after exit 0 does not become alreadyClosed on \(transport).")
                } else { throw SSHRegressionFailure.failed("early exit or callback failure must retain its original error") }
            } catch {
                if let expectedExit = ["fixture-missing-bridge": 127, "fixture-exit-one": 1][command],
                   case SSHBridgeError.hostBridgeExited(let status) = error, status == expectedExit {
                    guard error.localizedDescription.contains("exit \(status)"),
                          error.localizedDescription.contains("saved path"), error.localizedDescription.contains("PATH") else {
                        throw SSHRegressionFailure.failed("remote bridge exit must explain the host setup checks")
                    }
                    print("PASS: early bridge exit \(status) remains an actionable host error on \(transport), not NIO error 6.")
                } else if command == "fixture-callback-error",
                          case SSHBridgeError.protocolViolation("fixture callback failure") = error {
                    print("PASS: exec cleanup preserves the original callback error after remote close on \(transport).")
                } else { throw error }
            }
        }
    }

    private static func relayedSSHSocket(port: Int, sockets: SSHChannelOwnership) async throws -> Int32 {
        var pair: [Int32] = [-1, -1]
        #if canImport(Darwin)
        let stream = SOCK_STREAM
        #else
        let stream = Int32(SOCK_STREAM.rawValue)
        #endif
        guard socketpair(AF_UNIX, stream, 0, &pair) == 0 else { throw SSHRegressionFailure.failed("socketpair creation") }
        // The return descriptor is raw until the production bootstrap consumes it.
        do {
            let bootstrap = ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .channelOption(ChannelOptions.autoRead, value: false)
                .channelInitializer { channel in
                    guard sockets.register(channel) else { return channel.eventLoop.makeFailedFuture(SSHBridgeError.disconnected) }
                    return channel.eventLoop.makeSucceededVoidFuture()
                }
            let relay = try await bootstrap.withConnectedSocket(pair[1]).get()
            let remote = try await bootstrap.connect(host: "127.0.0.1", port: port).get()
            try await relay.pipeline.addHandler(SSHRegressionSocketRelay(peer: remote)).get()
            try await remote.pipeline.addHandler(SSHRegressionSocketRelay(peer: relay)).get()
            try await relay.setOption(ChannelOptions.autoRead, value: true).get()
            try await remote.setOption(ChannelOptions.autoRead, value: true).get()
            return pair[0]
        } catch {
            _ = close(pair[0])
            throw error
        }
    }

    private static func bindSSHServer(group: EventLoopGroup, sockets: SSHChannelOwnership, hostKeys: [NIOSSHPrivateKey],
                                      authentication: NIOSSHServerUserAuthenticationDelegate) async throws -> Channel {
        try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                guard sockets.register(channel) else {
                    return channel.eventLoop.makeFailedFuture(SSHRegressionFailure.failed("server socket ownership"))
                }
                let handler = NIOSSHHandler(
                    role: .server(SSHServerConfiguration(hostKeys: hostKeys, userAuthDelegate: authentication)),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: { child, type in
                        guard type == .session else { return child.eventLoop.makeFailedFuture(SSHBridgeError.invalidReview) }
                        return child.pipeline.addHandler(SSHRegressionExecResponder())
                    }
                )
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(handler)
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
    }

    private static func verifySSHConnection(profile: MachineProfile, secret: String? = nil) async throws {
        let configuration = try SSHBridgeConfiguration(profile: profile)
        let ownership = SSHChannelOwnership(limit: 1)
        defer { ownership.close() }
        let client = try await SSHOwnedClient.connect(configuration: configuration,
            authentication: configuration.authenticationMethod(secret: secret), ownership: ownership)
        guard client.isConnected else { throw SSHRegressionFailure.failed("authenticated connection") }
        try await client.close()
        guard !client.isConnected else { throw SSHRegressionFailure.failed("closed connection is still active") }
    }

    private static func verifySSHFailure(profile: MachineProfile, secret: String? = nil,
                                        expectedError: (Error) -> Bool) async throws {
        let configuration = try SSHBridgeConfiguration(profile: profile)
        let ownership = SSHChannelOwnership(limit: 1)
        defer { ownership.close() }
        let started = Date()
        var failure: Error?
        do {
            let client = try await SSHOwnedClient.connect(configuration: configuration,
                authentication: configuration.authenticationMethod(secret: secret), ownership: ownership)
            try await client.close()
        } catch { failure = error }
        guard let failure, expectedError(failure), Date().timeIntervalSince(started) < 3 else {
            throw SSHRegressionFailure.failed("login rejection must propagate its actual error before the deadline; got \(String(describing: failure))")
        }
    }

    private static func verifySSHLoginTeardown(profile: MachineProfile, group: EventLoopGroup,
                                              serverSockets: SSHChannelOwnership) async throws {
        // This listener deliberately never sends an SSH greeting; no unresolved auth delegate promises.
        let stalledServer = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                guard serverSockets.register(channel) else {
                    return channel.eventLoop.makeFailedFuture(SSHRegressionFailure.failed("stalled server ownership"))
                }
                return channel.eventLoop.makeSucceededVoidFuture()
            }.bind(host: "127.0.0.1", port: 0).get()
        defer { stalledServer.close(promise: nil) }
        guard let port = stalledServer.localAddress?.port else { throw SSHRegressionFailure.failed("stalled server port") }
        var stalledProfile = profile
        stalledProfile.port = port
        let ownership = SSHChannelOwnership(limit: 1)
        defer { ownership.close() }
        let teardown = Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            ownership.close()
        }
        defer { teardown.cancel() }
        let started = Date()
        var disconnected = false
        do {
            let configuration = try SSHBridgeConfiguration(profile: stalledProfile)
            let client = try await SSHOwnedClient.connect(configuration: configuration,
                authentication: configuration.authenticationMethod(secret: "test-only-password"), ownership: ownership)
            try await client.close()
        } catch SSHBridgeError.disconnected { disconnected = true }
        guard disconnected, Date().timeIntervalSince(started) < 3 else {
            throw SSHRegressionFailure.failed("socket teardown during login must fail promptly, not wait for authentication")
        }
    }
}

/// A synthetic SSH exec peer, not an actual shell, host bridge, or local subprocess.
private final class SSHRegressionExecResponder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    private var echo = false

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let request = event as? SSHChannelRequestEvent.ExecRequest else {
            context.fireUserInboundEventTriggered(event)
            return
        }
        if request.command == "fixture-echo" {
            echo = true
            context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
        } else {
            let status: Int
            switch request.command {
            case "fixture-missing-bridge": status = 127
            case "fixture-exit-one": status = 1
            case "fixture-exit-zero", "fixture-callback-error": status = 0
            default:
                context.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil)
                context.close(promise: nil)
                return
            }
            context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            if status != 0 {
                context.writeAndFlush(NIOAny(SSHChannelData(type: .stdErr, data: .byteBuffer(ByteBuffer(string: "fixture bridge could not start\n")))), promise: nil)
            }
            context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: status), promise: nil)
            context.close(promise: nil)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if echo { context.writeAndFlush(data, promise: nil) }
    }
}

/// Models libtailscale's byte relay without joining a real tailnet or resolving the fixture DNS name.
private final class SSHRegressionSocketRelay: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private let peer: Channel
    init(peer: Channel) { self.peer = peer }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        peer.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        peer.close(promise: nil)
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        peer.close(promise: nil)
        context.close(promise: nil)
    }
}

/// Only a synthetic test password is accepted; the server binds to loopback on an ephemeral port.
private final class SSHRegressionPasswordDelegate: NIOSSHServerUserAuthenticationDelegate {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = .password

    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        if case .password(let password) = request.request,
           request.username == "regression", password.password == "test-only-password" {
            responsePromise.succeed(.success)
        } else {
            responsePromise.succeed(.failure)
        }
    }
}

/// Models Tailscale SSH's none-auth protocol only, not real tailnet identity or policy evaluation.
private final class SSHRegressionTailscaleDelegate: NIOSSHServerUserAuthenticationDelegate {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = []

    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        if case .none = request.request, request.username == "regression" {
            responsePromise.succeed(.success)
        } else {
            responsePromise.succeed(.failure)
        }
    }
}

private enum SSHRegressionFailure: Error {
    case failed(String)
}
