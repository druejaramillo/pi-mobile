import Citadel
import NIOCore
import NIOPosix
import NIOSSH

/// Raw TCP socket ownership precedes authentication; Citadel's existing-channel API does not await login.
struct SSHOwnedClient {
    static func connect(configuration: SSHBridgeConfiguration, authentication: SSHAuthenticationMethod,
                        ownership: SSHChannelOwnership, connectedSocket: CInt? = nil) async throws -> SSHClient {
        // A userspace Tailscale dial supplies a connected socketpair; NIO owns it from this boundary.
        let bootstrap = ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connectTimeout(.seconds(15))
            .channelOption(ChannelOptions.autoRead, value: false)
            .channelInitializer { channel in
                guard ownership.register(channel) else {
                    return channel.eventLoop.makeFailedFuture(SSHBridgeError.disconnected)
                }
                return channel.eventLoop.makeSucceededVoidFuture()
            }
        let channel: Channel
        if let connectedSocket {
            channel = try await bootstrap.withConnectedSocket(connectedSocket).get()
        } else {
            channel = try await bootstrap.connect(host: configuration.profile.hostname, port: configuration.profile.port).get()
        }
        do {
            // The existing-channel API leaves reconnect at SSHConnectionPoolSettings' default .never.
            let client = try await SSHClient.connect(on: channel, authenticationMethod: authentication,
                                                      hostKeyValidator: .trustedKeys(configuration.hostKeys))
            let authenticated = channel.eventLoop.makePromise(of: Void.self)
            let readiness = SSHAuthenticationReadiness(authenticated: authenticated)
            try await channel.eventLoop.submit {
                // Citadel's handshake handler consumes authentication events, so observe immediately after NIOSSH.
                let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                try channel.pipeline.syncOperations.addHandler(readiness, position: .after(sshHandler))
            }.get()
            // NIOSSH consumes channelInactive; its raw close future must also finish a pending login.
            channel.closeFuture.whenComplete { _ in readiness.channelClosed() }
            let loginFailure: SSHBridgeError = configuration.profile.authentication == "tailscale"
                ? .tailscaleSSHUnavailable : .requestDeadline
            let deadline = channel.eventLoop.scheduleTask(in: .seconds(15)) {
                readiness.expire(on: channel, error: loginFailure)
            }
            defer { deadline.cancel() }
            try await channel.setOption(ChannelOptions.autoRead, value: true).get()
            try await authenticated.futureResult.get()
            return client
        } catch {
            channel.close(promise: nil)
            if error is InvalidHostKey { throw SSHBridgeError.hostIdentityMismatch }
            // Citadel consumes its custom delegate after one offer, then emits this generic failure.
            if configuration.profile.authentication == "tailscale",
               case SSHClientError.allAuthenticationOptionsFailed = error {
                throw SSHBridgeError.tailscaleSSHUnavailable
            }
            throw error
        }
    }
}

/// Authentication readiness observes the real NIOSSH success event after host pin validation.
/// After pipeline installation, mutable state and the deadline are confined to that channel's event loop.
private final class SSHAuthenticationReadiness: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    private let authenticated: EventLoopPromise<Void>
    private var completed = false

    init(authenticated: EventLoopPromise<Void>) { self.authenticated = authenticated }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent, !completed {
            completed = true
            authenticated.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(error)
        context.fireErrorCaught(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        fail(SSHBridgeError.disconnected)
        context.fireChannelInactive()
    }

    func channelClosed() {
        fail(SSHBridgeError.disconnected)
    }

    func expire(on channel: Channel, error: SSHBridgeError) {
        guard !completed else { return }
        fail(error)
        channel.close(promise: nil)
    }

    private func fail(_ error: Error) {
        guard !completed else { return }
        completed = true
        authenticated.fail(error)
    }
}
