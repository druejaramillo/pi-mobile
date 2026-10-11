import Foundation
import Citadel
import Crypto
import NIOCore
import NIOPosix
import NIOSSH
import PiMobileCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs the real SSH connection boundary against an ephemeral loopback server, never a saved machine.
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
        let server = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                guard serverSockets.register(channel) else {
                    return channel.eventLoop.makeFailedFuture(SSHRegressionFailure.failed("server socket ownership"))
                }
                let handler = NIOSSHHandler(
                    role: .server(SSHServerConfiguration(hostKeys: [hostKey], userAuthDelegate: SSHRegressionPasswordDelegate())),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )
                return channel.pipeline.addHandler(handler)
            }
            .bind(host: "127.0.0.1", port: 0).get()
        guard let port = server.localAddress?.port else { throw SSHRegressionFailure.failed("loopback server port") }
        do {
            let profile = MachineProfile(name: "Loopback regression only", hostname: "127.0.0.1", port: port,
                username: "regression", hostPublicKey: String(openSSHPublicKey: hostKey.publicKey), authentication: "password")
            for _ in 0..<3 { try await verifySSHConnection(profile: profile) }
            print("PASS: three fresh existing-channel SSH connections authenticate and close without an event-loop assertion.")
            try await verifySSHFailure(profile: profile, password: "wrong-test-password") { error in
                if case SSHClientError.allAuthenticationOptionsFailed = error { return true }
                return false
            }
            print("PASS: wrong passwords fail promptly without crashing.")
            var wrongPin = profile
            let otherKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
            wrongPin.hostPublicKey = String(openSSHPublicKey: otherKey.publicKey)
            try await verifySSHFailure(profile: wrongPin, password: "test-only-password") { $0 is InvalidHostKey }
            print("PASS: mismatched host keys are rejected before authentication without crashing.")
            try await verifySSHLoginTeardown(profile: profile, group: group, serverSockets: serverSockets)
            print("PASS: closing owned sockets during stalled login terminates promptly.")
            serverSockets.close()
            try await server.close().get()
            try await group.shutdownGracefully()
        } catch {
            serverSockets.close()
            try? await server.close().get()
            try? await group.shutdownGracefully()
            throw error
        }
    }

    private static func verifySSHConnection(profile: MachineProfile) async throws {
        let configuration = try SSHBridgeConfiguration(profile: profile)
        let ownership = SSHChannelOwnership(limit: 1)
        defer { ownership.close() }
        let client = try await SSHOwnedClient.connect(configuration: configuration,
            authentication: .passwordBased(username: "regression", password: "test-only-password"), ownership: ownership)
        guard client.isConnected else { throw SSHRegressionFailure.failed("authenticated connection") }
        try await client.close()
        guard !client.isConnected else { throw SSHRegressionFailure.failed("closed connection is still active") }
    }

    private static func verifySSHFailure(profile: MachineProfile, password: String,
                                        expectedError: (Error) -> Bool) async throws {
        let configuration = try SSHBridgeConfiguration(profile: profile)
        let ownership = SSHChannelOwnership(limit: 1)
        defer { ownership.close() }
        let started = Date()
        var rejected = false
        do {
            let client = try await SSHOwnedClient.connect(configuration: configuration,
                authentication: .passwordBased(username: "regression", password: password), ownership: ownership)
            try await client.close()
        } catch { rejected = expectedError(error) }
        guard rejected, Date().timeIntervalSince(started) < 3 else {
            throw SSHRegressionFailure.failed("login rejection must propagate its actual error before the deadline")
        }
    }

    private static func verifySSHLoginTeardown(profile: MachineProfile, group: EventLoopGroup,
                                              serverSockets: SSHChannelOwnership) async throws {
        // This second listener deliberately never sends an SSH greeting; no unresolved auth delegate promises.
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
            let client = try await SSHOwnedClient.connect(configuration: SSHBridgeConfiguration(profile: stalledProfile),
                authentication: .passwordBased(username: "regression", password: "test-only-password"), ownership: ownership)
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

private enum SSHRegressionFailure: Error {
    case failed(String)
}
