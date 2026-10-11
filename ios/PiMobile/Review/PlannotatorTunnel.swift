import Foundation
// The pinned Citadel API predates Sendable; direct-channel work is submitted to its NIO event loop.
@preconcurrency import Citadel
import NIOCore
import NIOPosix
import NIOSSH
import PiMobileCore

/// Plannotator tunnel owns an ephemeral IPv4 loopback listener and only its SSH forwarding channels.
public final class PlannotatorTunnel {
    /// Local review URL preserves the advertised path, query and fragment, including any review token.
    public let url: URL
    private let ownership: SSHChannelOwnership

    private init(url: URL, ownership: SSHChannelOwnership) {
        self.url = url
        self.ownership = ownership
    }

    /// Review dismissal closes local forwarding, not the remote review server or its originating agent.
    public func close() { ownership.close() }

    @MainActor
    static func open(review: PlannotatorReview, client: SSHClient) async throws -> PlannotatorTunnel {
        var components = try validatedReviewComponents(review)
        guard let remotePort = components.port else { throw SSHBridgeError.invalidReview }
        let ownership = SSHChannelOwnership(limit: 33) // Listener plus at most 32 connected/connecting child channels.
        do {
            let listener = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .serverChannelInitializer { channel in
                    guard ownership.register(channel) else {
                        return channel.eventLoop.makeFailedFuture(SSHBridgeError.disconnected)
                    }
                    return channel.eventLoop.makeSucceededVoidFuture()
                }
                .childChannelOption(ChannelOptions.autoRead, value: false)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
                .childChannelInitializer { local in
                    guard ownership.register(local) else {
                        return local.eventLoop.makeFailedFuture(SSHBridgeError.capacityExceeded)
                    }
                    let initialized = local.eventLoop.makePromise(of: Void.self)
                    let pair = ReviewForwardingPair(local: local)
                    let deadline = local.eventLoop.scheduleTask(in: .seconds(15)) { pair.close() }
                    Task {
                        defer { deadline.cancel() }
                        do {
                            let originator = try local.remoteAddress ?? SocketAddress(ipAddress: "127.0.0.1", port: 0)
                            let remote = try await client.createDirectTCPIPChannel(using: SSHChannelType.DirectTCPIP(
                                targetHost: "127.0.0.1", targetPort: remotePort, originatorAddress: originator
                            )) { remote in
                                guard ownership.register(remote), pair.install(remote: remote) else {
                                    remote.close(promise: nil)
                                    return remote.eventLoop.makeFailedFuture(SSHBridgeError.disconnected)
                                }
                                return remote.setOption(ChannelOptions.autoRead, value: false).flatMap {
                                    remote.pipeline.addHandler(ReviewRelayHandler(peer: local))
                                }
                            }
                            try await local.pipeline.addHandler(ReviewRelayHandler(peer: remote)).get()
                            initialized.succeed(())
                            // Both relays are now installed; no auto-read stream can outrun the other end.
                            local.read()
                            remote.read()
                        } catch {
                            pair.close()
                            initialized.fail(error)
                        }
                    }
                    return initialized.futureResult
                }
                .bind(host: "127.0.0.1", port: 0).get()
            guard let localPort = listener.localAddress?.port, (1...65535).contains(localPort) else {
                throw SSHBridgeError.invalidReview
            }
            components.host = "127.0.0.1"
            components.port = localPort
            guard let url = components.url else { throw SSHBridgeError.invalidReview }
            return PlannotatorTunnel(url: url, ownership: ownership)
        } catch {
            ownership.close()
            throw error
        }
    }

    private static func validatedReviewComponents(_ review: PlannotatorReview) throws -> URLComponents {
        guard review.id.range(of: "^plannotator_[0-9a-fA-F]+$", options: .regularExpression) != nil,
              review.url.utf8.count <= 16384,
              !review.url.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: review.url), components.scheme == "http",
              components.user == nil, components.password == nil,
              let host = components.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host),
              let port = components.port, (1...65535).contains(port), components.url != nil else {
            throw SSHBridgeError.invalidReview
        }
        return components
    }

    deinit { close() }
}

/// Per-browser socket pairing lets an opening-channel deadline close both ends, including unconfirmed SSH channels.
private final class ReviewForwardingPair: @unchecked Sendable {
    private let lock = NSLock()
    private let local: Channel
    private var remote: Channel?
    private var closed = false

    init(local: Channel) {
        self.local = local
        local.closeFuture.whenComplete { [weak self] _ in self?.close() }
    }

    func install(remote: Channel) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }
        self.remote = remote
        return true
    }

    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        let remote = self.remote
        lock.unlock()
        local.close(promise: nil)
        remote?.close(promise: nil)
    }
}

/// Manual reads apply TCP/SSH backpressure; relays carry HTTP and WebSocket bytes without interpreting either protocol.
/// Each instance belongs to one pipeline; peer-write completions return to its source event loop before touching state.
private final class ReviewRelayHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private let peer: Channel
    private var writes = 0
    private var readComplete = false

    init(peer: Channel) { self.peer = peer }

    func channelActive(context: ChannelHandlerContext) {
        context.fireChannelActive()
        context.read()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        writes += 1
        readComplete = false
        let source = context.channel
        peer.writeAndFlush(unwrapInboundIn(data)).whenComplete { result in
            source.eventLoop.execute {
                self.writes -= 1
                switch result {
                case .failure:
                    source.close(promise: nil)
                    self.peer.close(promise: nil)
                case .success:
                    if self.writes == 0, self.readComplete { source.read() }
                }
            }
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        readComplete = true
        if writes == 0 { context.read() }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, event == .inputClosed {
            peer.close(mode: .output, promise: nil)
        } else { context.fireUserInboundEventTriggered(event) }
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
