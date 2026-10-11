import Foundation
import CTailscale
import NIOCore
import PiMobileCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Embedded node lifetime is foreground-only; the protected on-device login survives restarts.
actor TailscaleRuntime {
    private var node: TailscaleNodeHandle?
    private var starting: Task<TailscaleNodeHandle, Error>?
    private var stopping: Task<Void, Never>?
    private var generation = UUID()
    private var active = true

    func resume() { active = true }

    func suspend() {
        active = false
        generation = UUID()
        if let node { stopping = node.shutdown() }
        if let starting {
            stopping = Task {
                if let pending = try? await starting.value { await pending.shutdown().value }
            }
        }
        node = nil
        starting = nil
    }

    func status() async throws -> TailscaleNodeStatus {
        let token = generation
        let handle = try await currentNode()
        let status = try await handle.readStatus()
        try validateGeneration(token)
        return status
    }

    func loginURL() async throws -> URL? {
        let token = generation
        let handle = try await currentNode()
        let status = try await handle.readStatus()
        if status.backendState == "Running" { return nil }
        if status.backendState == "NeedsMachineAuth" { throw TailscaleIdentityError.approvalRequired }
        try await handle.perform { node in
            guard PiTailscaleLogin(node) == 0 else { throw TailscaleIdentityError.unavailable }
        }
        // Bounded foreground sign-in preparation only, never background monitoring.
        for _ in 0..<20 {
            try Task.checkCancellation()
            let next = try await handle.readStatus()
            try validateGeneration(token)
            if next.backendState == "Running" { return nil }
            if next.backendState == "NeedsMachineAuth" { throw TailscaleIdentityError.approvalRequired }
            if let auth = next.authURL, !auth.isEmpty {
                guard let url = URL(string: auth), url.scheme == "https", url.host == "login.tailscale.com",
                      url.user == nil, url.password == nil, url.port == nil || url.port == 443 else {
                    throw TailscaleIdentityError.unavailable
                }
                return url
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw TailscaleIdentityError.unavailable
    }

    func resolve(_ destination: String) async throws -> TailscaleResolvedPeer {
        let token = generation
        let handle = try await currentNode()
        let status = try await handle.readStatus()
        try validateGeneration(token)
        return TailscaleResolvedPeer(peer: try status.verifiedPeer(for: destination), status: status,
                                     node: handle, generation: token)
    }

    func dial(_ destination: TailscaleResolvedPeer) async throws -> TailscaleSSHSocket {
        try validateGeneration(destination.generation)
        guard node === destination.node, let ip = destination.peer.addresses.first else {
            throw TailscaleIdentityError.unavailable
        }
        // Refuse malformed/non-numeric coordination addresses before crossing the C boundary.
        _ = try SocketAddress(ipAddress: ip, port: 22)
        let address = ip.contains(":") ? "[\(ip)]:22" : "\(ip):22"
        let socket = try await destination.node.perform { handle in
            let descriptor = PiTailscaleDial(handle, address)
            guard descriptor >= 0 else { throw TailscaleIdentityError.unavailable }
            return TailscaleSSHSocket(descriptor: descriptor)
        }
        do {
            try Task.checkCancellation()
            try validateGeneration(destination.generation)
            return socket
        } catch {
            socket.close()
            throw error
        }
    }

    private func validateGeneration(_ token: UUID) throws {
        guard active, token == generation else { throw TailscaleIdentityError.unavailable }
    }

    private func currentNode() async throws -> TailscaleNodeHandle {
        let token = generation
        try validateGeneration(token)
        if let node { return node }
        if let stopping { await stopping.value; try validateGeneration(token); self.stopping = nil }
        let operation: Task<TailscaleNodeHandle, Error>
        if let starting { operation = starting }
        else {
            let directory = try Self.stateDirectory()
            operation = Task.detached { try TailscaleNodeHandle.start(directory: directory.path) }
            starting = operation
        }
        do {
            let handle = try await operation.value
            try validateGeneration(token)
            node = handle
            starting = nil
            return handle
        } catch {
            if token == generation { starting = nil }
            throw error
        }
    }

    private static func stateDirectory() throws -> URL {
        let files = FileManager.default
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        var directory = support.appendingPathComponent("Tailscale", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }
}

/// A lookup cannot silently dial through a different node after suspension or sign-in changes.
struct TailscaleResolvedPeer: Sendable {
    let peer: TailscalePeerIdentity
    let status: TailscaleNodeStatus
    fileprivate let node: TailscaleNodeHandle
    fileprivate let generation: UUID
}

/// Blocking C operations use a serial worker; shutdown can interrupt them without holding the actor.
private final class TailscaleNodeHandle: @unchecked Sendable {
    private let descriptor: Int32
    private let worker = DispatchQueue(label: "pi-mobile.tailscale")
    private let lock = NSLock()
    private var closed = false

    private init(descriptor: Int32) { self.descriptor = descriptor }

    static func start(directory: String) throws -> TailscaleNodeHandle {
        let descriptor = PiTailscaleStart(directory)
        guard descriptor > 0 else { throw TailscaleIdentityError.unavailable }
        return TailscaleNodeHandle(descriptor: descriptor)
    }

    func readStatus() async throws -> TailscaleNodeStatus {
        try await perform { handle in
            guard let bytes = PiTailscaleStatus(handle) else { throw TailscaleIdentityError.unavailable }
            defer { free(bytes) }
            let size = strlen(bytes)
            guard size <= 16 * 1024 * 1024 else { throw TailscaleIdentityError.unavailable }
            do { return try JSONDecoder().decode(TailscaleNodeStatus.self, from: Data(bytes: bytes, count: size)) }
            catch { throw TailscaleIdentityError.unavailable }
        }
    }

    func perform<Value: Sendable>(_ operation: @escaping @Sendable (Int32) throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            worker.async { [self] in
                guard !lock.withLock({ closed }) else {
                    continuation.resume(throwing: TailscaleIdentityError.unavailable)
                    return
                }
                do { continuation.resume(returning: try operation(descriptor)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func shutdown() -> Task<Void, Never> {
        let shouldClose = lock.withLock {
            if closed { return false }
            closed = true
            return true
        }
        let descriptor = descriptor
        return Task.detached { if shouldClose { PiTailscaleClose(descriptor) } }
    }

    deinit {
        if !closed {
            let descriptor = descriptor
            DispatchQueue.global().async { PiTailscaleClose(descriptor) }
        }
    }
}

/// The native SSH bootstrap takes ownership once; abandoned or cancelled dials close their socket.
final class TailscaleSSHSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32?
    init(descriptor: Int32) { self.descriptor = descriptor }

    func takeDescriptor() throws -> Int32 {
        try lock.withLock {
            guard let descriptor else { throw TailscaleIdentityError.unavailable }
            self.descriptor = nil
            return descriptor
        }
    }

    func close() {
        lock.withLock {
            if let descriptor {
                _ = Darwin.close(descriptor)
                self.descriptor = nil
            }
        }
    }
    deinit { close() }
}
