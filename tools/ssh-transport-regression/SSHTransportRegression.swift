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
        do { try await runSSHRegression() }
        catch {
            FileHandle.standardError.write(Data("FAIL: SSH transport regression: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func runSSHRegression() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let serverSockets = SSHChannelOwnership(limit: 16)
        let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await bindSSHServer(group: group, sockets: serverSockets, hostKey: hostKey,
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
            try await verifySSHFailure(profile: wrongPin, secret: "test-only-password") { $0 is InvalidHostKey }
            print("PASS: mismatched host keys are rejected before authentication without crashing.")
            try await verifySSHLoginTeardown(profile: profile, group: group, serverSockets: serverSockets)
            print("PASS: closing owned sockets during stalled login terminates promptly.")

            let keyless = try await bindSSHServer(group: group, sockets: serverSockets, hostKey: hostKey,
                authentication: SSHRegressionTailscaleDelegate())
            keylessServer = keyless
            guard let keylessPort = keyless.localAddress?.port else { throw SSHRegressionFailure.failed("keyless server port") }
            let tailscale = MachineProfile(name: "Keyless loopback only", hostname: "127.0.0.1", port: keylessPort,
                username: "regression", hostPublicKey: String(openSSHPublicKey: hostKey.publicKey))
            for _ in 0..<3 { try await verifySSHConnection(profile: tailscale) }
            // Even an explicitly supplied old secret must not be offered in Tailscale mode.
            try await verifySSHConnection(profile: tailscale, secret: "unused-old-credential")
            print("PASS: keyless Tailscale SSH offers none, authenticates repeatedly, and never sends an old credential.")

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
            try await verifySSHFailure(profile: wrongPin) { $0 is InvalidHostKey }
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

    private static func bindSSHServer(group: EventLoopGroup, sockets: SSHChannelOwnership, hostKey: NIOSSHPrivateKey,
                                      authentication: NIOSSHServerUserAuthenticationDelegate) async throws -> Channel {
        try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                guard sockets.register(channel) else {
                    return channel.eventLoop.makeFailedFuture(SSHRegressionFailure.failed("server socket ownership"))
                }
                let handler = NIOSSHHandler(
                    role: .server(SSHServerConfiguration(hostKeys: [hostKey], userAuthDelegate: authentication)),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
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
