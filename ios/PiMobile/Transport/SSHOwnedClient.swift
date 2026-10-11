import Citadel
import NIOCore
import NIOPosix
import NIOSSH

/// Raw TCP socket ownership precedes authentication; Citadel's existing-channel API does not await login.
struct SSHOwnedClient {
    static func connect(configuration: SSHBridgeConfiguration, authentication: SSHAuthenticationMethod,
                        ownership: SSHChannelOwnership) async throws -> SSHClient {
        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connectTimeout(.seconds(15))
            .channelOption(ChannelOptions.autoRead, value: false)
            .channelInitializer { channel in
                guard ownership.register(channel) else {
                    return channel.eventLoop.makeFailedFuture(SSHBridgeError.disconnected)
                }
                return channel.eventLoop.makeSucceededVoidFuture()
            }
            .connect(host: configuration.profile.hostname, port: configuration.profile.port).get()
        do {
            // The existing-channel API leaves reconnect at SSHConnectionPoolSettings' default .never.
            let client = try await SSHClient.connect(on: channel, authenticationMethod: authentication,
                                                      hostKeyValidator: .trustedKeys([configuration.hostKey]))
            let authenticated = channel.eventLoop.makePromise(of: Void.self)
            let readiness = SSHAuthenticationReadiness(authenticated: authenticated)
            try await channel.pipeline.addHandler(readiness).get()
            let deadline = channel.eventLoop.scheduleTask(in: .seconds(15)) {
                readiness.expire(on: channel)
            }
            defer { deadline.cancel() }
            try await channel.setOption(ChannelOptions.autoRead, value: true).get()
            try await authenticated.futureResult.get()
            return client
        } catch {
            channel.close(promise: nil)
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
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        fail(SSHBridgeError.disconnected)
        context.fireChannelInactive()
    }

    func expire(on channel: Channel) {
        guard !completed else { return }
        fail(SSHBridgeError.requestDeadline)
        channel.close(promise: nil)
    }

    private func fail(_ error: Error) {
        guard !completed else { return }
        completed = true
        authenticated.fail(error)
    }
}
