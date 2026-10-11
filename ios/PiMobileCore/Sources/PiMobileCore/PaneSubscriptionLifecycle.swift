import Foundation

/// Pane subscription lifecycle serializes view cleanup without retiring the shared machine connection.
@MainActor
public final class PaneSubscriptionLifecycle {
    private var owner: UUID?
    private var cleanup: Task<Void, Error>?
    private var generation = UUID()

    public init() {}

    /// A newly visible pane waits for the previous pane's detach acknowledgement before attaching.
    public func preparePaneSubscription(owner: UUID) async throws {
        let token = generation
        while let cleanup { try await cleanup.value }
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        guard self.owner == nil || self.owner == owner else { throw PaneSubscriptionError.alreadyOwned }
        self.owner = owner
    }

    /// A late dismissal from an older view cannot detach a newer pane's subscription.
    public func releasePaneSubscription(owner: UUID, detach: @escaping @MainActor () async throws -> Void) {
        guard self.owner == owner, cleanup == nil else { return }
        let token = generation
        cleanup = Task { @MainActor [weak self] in
            try Task.checkCancellation()
            try await detach()
            if self?.generation == token { self?.owner = nil; self?.cleanup = nil }
            // Retain a failed cleanup until machine disconnect invalidates it; never silently retry.
        }
    }

    /// Machine disconnect invalidates queued pane work; foregrounding never replays an attachment.
    public func invalidatePaneSubscriptions() {
        generation = UUID()
        owner = nil
        cleanup?.cancel()
        cleanup = nil
    }
}

/// Pane subscription error refuses concurrent view ownership rather than detaching another visible pane.
public enum PaneSubscriptionError: Error, LocalizedError {
    case alreadyOwned
    public var errorDescription: String? { "Pane subscription busy: close the previous pane before attaching another." }
}
