import Foundation
import Combine
import UIKit
import Citadel
import NIOCore
import PiMobileCore

/// Direct SSH bridge connection owns only mobile subscriptions and never reconnects or replays commands.
@MainActor
public final class SSHBridgeConnection: ObservableObject {
    /// Connection state is disconnected, connecting, connected or failed; no background connection is retained.
    @Published public private(set) var state: String = "disconnected"
    /// Last transport error excludes SSH secrets and stderr diagnostics.
    @Published public private(set) var lastError: String?
    /// Agent snapshot is authoritative only for this live connection's attached generation.
    @Published public private(set) var agent: PiAgentSnapshot?
    /// Herdr topology includes only the explicitly configured host session.
    @Published public private(set) var topology: HerdrTopology?
    /// Terminal frame contains cumulative ANSI output since attach, not just the latest incremental wire frame.
    @Published public private(set) var terminalFrame: TerminalFrame?

    private var epoch = UUID()
    private var client: SSHClient?
    private var ownership: SSHChannelOwnership?
    private var writer: TTYStdinWriter?
    private var execTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var readyDeadline: Task<Void, Never>?
    private var pending: [String: PendingBridgeRequest] = [:]
    private var renderHistory = TerminalRenderHistory()
    private let paneSubscriptions = PaneSubscriptionLifecycle()
    private var reviews: [UUID: OwnedReviewTunnel] = [:]
    private var backgroundSubscription: AnyCancellable?
    private var tailscale: TailscaleService?

    /// Creates an idle connection; the native coordinator must explicitly connect after foregrounding.
    public init() {
        backgroundSubscription = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.disconnect() }
            }
    }

    /// The app injects its single tailnet identity; standalone legacy callers remain compatible.
    convenience init(tailscale: TailscaleService) {
        self.init()
        self.tailscale = tailscale
    }

    /// Connects with authenticated coordination keys for Tailscale, or the saved pin for legacy SSH.
    public func connect(profile: MachineProfile, secret: String? = nil) async throws {
        disconnect()
        lastError = nil
        guard UIApplication.shared.applicationState != .background else { throw SSHBridgeError.disconnected }
        state = "connecting"
        let token = epoch
        let sockets = SSHChannelOwnership(limit: 1)
        ownership = sockets
        do {
            try await withTaskCancellationHandler {
                let configuration: SSHBridgeConfiguration
                var socket: TailscaleSSHSocket?
                if profile.authentication == "tailscale" {
                    guard let tailscale else { throw TailscaleIdentityError.signInRequired }
                    (configuration, socket) = try await tailscale.prepareConnection(profile)
                } else { configuration = try SSHBridgeConfiguration(profile: profile) }
                guard epoch == token, !Task.isCancelled,
                      UIApplication.shared.applicationState != .background else {
                    socket?.close()
                    throw SSHBridgeError.disconnected
                }
                let authentication = try configuration.authenticationMethod(secret: secret)
                let connected = try await SSHOwnedClient.connect(configuration: configuration,
                    authentication: authentication, ownership: sockets, connectedSocket: try socket?.takeDescriptor())
                guard epoch == token, !Task.isCancelled,
                      UIApplication.shared.applicationState != .background else {
                    try? await connected.close()
                    throw SSHBridgeError.disconnected
                }
                client = connected
                connected.onDisconnect { [weak self] in
                    Task { @MainActor [weak self] in self?.channelLost(token: token, error: SSHBridgeError.disconnected) }
                }
                try await startBridgeExec(client: connected, command: configuration.command, token: token)
                let hello = try await request(method: "hello", params: .object([:]))
                guard hello["protocol"]?.integer == 1, hello["name"]?.string == "pi-mobile" else {
                    throw SSHBridgeError.protocolViolation("unsupported hello protocol or service")
                }
                _ = try await request(method: "snapshot", params: .object([:]))
                try Task.checkCancellation()
                guard epoch == token else { throw SSHBridgeError.disconnected }
                state = "connected"
            } onCancel: {
                sockets.close()
                Task { @MainActor [weak self] in self?.channelLost(token: token, error: CancellationError()) }
            }
        } catch {
            sockets.close()
            if epoch == token { channelLost(token: token, error: error) }
            throw error
        }
    }

    /// Sends one UUID-addressed JSONL command with a 30-second deadline; uncertain mutations are never retried.
    public func request(method: String, params: BridgeJSON) async throws -> BridgeJSON {
        guard let writer, let client, client.isConnected else { throw SSHBridgeError.disconnected }
        guard case .object = params, !method.isEmpty, method.utf8.count <= 64,
              method.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._").contains($0) }) else {
            throw SSHBridgeError.protocolViolation("request method or params")
        }
        guard pending.count < 64 else { throw SSHBridgeError.capacityExceeded }
        let command = BridgeCommand(method: method, params: params)
        var bytes = try JSONEncoder().encode(command)
        guard bytes.count <= BridgeLineFramer.maximumRecordBytes else { throw SSHBridgeError.capacityExceeded }
        bytes.append(0x0A)
        let buffer = ByteBuffer(bytes: bytes)
        let token = epoch
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                    catch { return }
                    self?.finishRequest(id: command.id, result: .failure(SSHBridgeError.requestDeadline))
                }
                pending[command.id] = PendingBridgeRequest(method: method, continuation: continuation, deadline: deadline)
                if method == "terminal.attach" { clearTerminalHistory() }
                Task { @MainActor [weak self] in
                    guard let self, self.epoch == token, self.pending[command.id] != nil else { return }
                    do { try await writer.write(buffer) }
                    catch { self.channelLost(token: token, error: error) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishRequest(id: command.id, result: .failure(CancellationError()))
            }
        }
    }

    /// Disconnect closes the phone's sockets, streams and review tunnels, never the host's agent processes.
    public func disconnect() {
        tearDown(error: SSHBridgeError.disconnected)
        state = "disconnected"
    }

    /// The next pane waits for the previous view's owned subscriptions to finish detaching.
    public func preparePaneSubscription(owner: UUID) async throws {
        guard state == "connected" else { throw SSHBridgeError.disconnected }
        let token = epoch
        try await paneSubscriptions.preparePaneSubscription(owner: owner)
        guard epoch == token, state == "connected" else { throw SSHBridgeError.disconnected }
    }

    /// Leaving a pane releases mobile agent/control subscriptions, not the shared foreground SSH connection.
    public func releasePaneSubscription(owner: UUID) {
        let token = epoch
        paneSubscriptions.releasePaneSubscription(owner: owner) { [weak self] in
            guard let self, self.epoch == token, self.state == "connected" else { throw SSHBridgeError.disconnected }
            do {
                _ = try await self.request(method: "terminal.detach", params: .object([:]))
                _ = try await self.request(method: "agent.detach", params: .object([:]))
            } catch {
                // If control release cannot be confirmed, closing the owned socket fails closed.
                self.channelLost(token: token, error: error)
                throw error
            }
        }
    }

    /// Changing a saved endpoint keeps this observed object but discards the old endpoint's cached topology.
    func resetForProfileChange() {
        disconnect()
        topology = nil
    }

    /// Opens forwarding only for a currently advertised Plannotator review, never an arbitrary remote host.
    public func openReview(_ review: PlannotatorReview) async throws -> PlannotatorTunnel {
        guard state == "connected", let client, isAdvertised(review) else { throw SSHBridgeError.invalidReview }
        let token = epoch
        // One visible review at a time; do not retain closed tunnels for still-advertised tokens.
        for owned in reviews.values { owned.tunnel.close() }
        reviews.removeAll()
        let tunnel = try await PlannotatorTunnel.open(review: review, client: client)
        guard token == epoch, state == "connected", isAdvertised(review) else {
            tunnel.close()
            throw SSHBridgeError.disconnected
        }
        reviews[UUID()] = OwnedReviewTunnel(review: review, tunnel: tunnel)
        return tunnel
    }

    private func startBridgeExec(client: SSHClient, command: String, token: UUID) async throws {
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            readyDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 20_000_000_000) }
                catch { return }
                self?.channelLost(token: token, error: SSHBridgeError.requestDeadline)
            }
            execTask = Task { @MainActor [weak self] in
                do {
                    try await SSHBridgeExec.run(client: client, command: command) { [weak self] inbound, outbound in
                        guard self?.epoch == token else { throw SSHBridgeError.disconnected }
                        self?.writer = outbound
                        self?.readyDeadline?.cancel()
                        self?.readyDeadline = nil
                        let ready = self?.readyContinuation
                        self?.readyContinuation = nil
                        ready?.resume()
                        var framer = BridgeLineFramer()
                        for try await output in inbound {
                            try Task.checkCancellation()
                            guard self?.epoch == token else { throw SSHBridgeError.disconnected }
                            switch output {
                            case .stdout(let buffer):
                                try framer.consume(buffer) { record in
                                    guard self?.epoch == token else { throw SSHBridgeError.disconnected }
                                    try self?.receiveRecord(record)
                                }
                            case .stderr:
                                // Drain diagnostics without treating them as JSON or retaining credential-bearing output.
                                break
                            }
                        }
                        try framer.validateEndOfStream()
                    }
                    self?.channelLost(token: token, error: SSHBridgeError.hostBridgeExited(0))
                } catch { self?.channelLost(token: token, error: error) }
            }
        }
    }

    private func receiveRecord(_ record: BridgeJSON) throws {
        guard case .object = record else { throw SSHBridgeError.protocolViolation("envelope must be an object") }
        if let id = record["id"]?.string {
            guard !id.isEmpty, record["event"] == nil,
                  (record["result"] != nil) != (record["error"] != nil) else {
                throw SSHBridgeError.protocolViolation("response must have exactly one result or error")
            }
            guard let request = pending[id] else { return } // Expired/cancelled response: never replay or apply stale results.
            if let failure = record["error"] {
                let error = try failure.decode(BridgeFailure.self)
                lastError = error.localizedDescription
                finishRequest(id: id, result: .failure(error))
            } else if let result = record["result"] {
                try applyResponse(result, method: request.method)
                finishRequest(id: id, result: .success(result))
            }
            return
        }
        guard record["id"] == nil, let event = record["event"]?.string, let data = record["data"] else {
            throw SSHBridgeError.protocolViolation("event must have a name and data")
        }
        switch event {
        case "agent.snapshot": agent = try data.decode(PiAgentSnapshot.self)
        case "terminal.frame": terminalFrame = try renderHistory.append(data.decode(TerminalFrame.self))
        case "terminal.closed": clearTerminalHistory()
        default: break // Future event types are ignored, not interpreted as commands.
        }
    }

    private func applyResponse(_ result: BridgeJSON, method: String) throws {
        switch method {
        case "snapshot":
            topology = try result.decode(HerdrTopology.self)
            let ended = reviews.filter { !isAdvertised($0.value.review) }
            for (id, owned) in ended { owned.tunnel.close(); reviews.removeValue(forKey: id) }
        case "agent.attach": agent = try result.decode(PiAgentSnapshot.self)
        case "agent.detach": agent = nil
        case "terminal.detach": clearTerminalHistory()
        default: break
        }
    }

    private func isAdvertised(_ review: PlannotatorReview) -> Bool {
        topology?.panes.contains(where: { pane in
            pane.reviews.contains(where: { $0.id == review.id && $0.url == review.url })
        }) == true
    }

    private func clearTerminalHistory() {
        renderHistory = TerminalRenderHistory()
        terminalFrame = nil
    }

    private func finishRequest(id: String, result: Result<BridgeJSON, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.deadline.cancel()
        request.continuation.resume(with: result)
    }

    private func channelLost(token: UUID, error: Error) {
        guard epoch == token else { return }
        lastError = error.localizedDescription
        tearDown(error: error)
        state = "failed"
    }

    private func tearDown(error: Error) {
        epoch = UUID()
        paneSubscriptions.invalidatePaneSubscriptions()
        ownership?.close()
        ownership = nil
        let oldClient = client
        client = nil
        writer = nil
        execTask?.cancel()
        execTask = nil
        readyDeadline?.cancel()
        readyDeadline = nil
        let ready = readyContinuation
        readyContinuation = nil
        ready?.resume(throwing: error)
        let requests = pending
        pending.removeAll()
        for request in requests.values {
            request.deadline.cancel()
            request.continuation.resume(throwing: error)
        }
        for owned in reviews.values { owned.tunnel.close() }
        reviews.removeAll()
        agent = nil
        // Preserve the last topology for explicitly stale navigation, never live dialog/control state.
        clearTerminalHistory()
        if let oldClient { Task { try? await oldClient.close() } }
    }

    deinit {
        ownership?.close()
        execTask?.cancel()
        readyDeadline?.cancel()
        readyContinuation?.resume(throwing: SSHBridgeError.disconnected)
        for request in pending.values {
            request.deadline.cancel()
            request.continuation.resume(throwing: SSHBridgeError.disconnected)
        }
        for owned in reviews.values { owned.tunnel.close() }
    }
}

private struct PendingBridgeRequest {
    let method: String
    let continuation: CheckedContinuation<BridgeJSON, Error>
    let deadline: Task<Void, Never>
}

private struct OwnedReviewTunnel {
    let review: PlannotatorReview
    let tunnel: PlannotatorTunnel
}
