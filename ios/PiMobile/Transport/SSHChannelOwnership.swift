import Foundation
import NIOCore

/// Channel ownership is lock-protected so background teardown also closes sockets still authenticating.
final class SSHChannelOwnership: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var channels: [UUID: Channel] = [:]
    private var closed = false

    init(limit: Int) { self.limit = limit }

    func register(_ channel: Channel) -> Bool {
        let id = UUID()
        lock.lock()
        guard !closed, channels.count < limit else {
            lock.unlock()
            channel.close(promise: nil)
            return false
        }
        channels[id] = channel
        lock.unlock()
        channel.closeFuture.whenComplete { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.channels.removeValue(forKey: id)
            self.lock.unlock()
        }
        return true
    }

    func close() {
        lock.lock()
        closed = true
        let owned = Array(channels.values)
        channels.removeAll()
        lock.unlock()
        for channel in owned { channel.close(promise: nil) }
    }

    deinit { close() }
}
