import Foundation
import XCTest
import PiMobileCore

final class PaneSubscriptionLifecycleTests: XCTestCase {
    @MainActor
    func testNavigationDetachesBeforeTheNextPaneAttaches() async throws {
        let lifecycle = PaneSubscriptionLifecycle()
        let first = UUID(), second = UUID()
        let gate = FixturePaneCleanupGate()
        var order: [String] = []
        try await lifecycle.preparePaneSubscription(owner: first)
        lifecycle.releasePaneSubscription(owner: first) {
            order.append("detach starts")
            await gate.wait()
            order.append("detach acknowledged")
        }
        let next = Task { @MainActor in
            try await lifecycle.preparePaneSubscription(owner: second)
            order.append("next pane attaches")
        }
        await gate.waitUntilStarted()
        gate.finish()
        try await next.value
        XCTAssertEqual(order, ["detach starts", "detach acknowledged", "next pane attaches"])
    }

    @MainActor
    func testLateOldViewDismissalCannotDetachTheNewPane() async throws {
        let lifecycle = PaneSubscriptionLifecycle()
        let first = UUID(), second = UUID()
        var detachedOwners: [UUID] = []
        try await lifecycle.preparePaneSubscription(owner: first)
        lifecycle.releasePaneSubscription(owner: first) { detachedOwners.append(first) }
        try await lifecycle.preparePaneSubscription(owner: second)
        lifecycle.releasePaneSubscription(owner: first) { detachedOwners.append(first) }
        lifecycle.releasePaneSubscription(owner: second) { detachedOwners.append(second) }
        try await lifecycle.preparePaneSubscription(owner: UUID())
        XCTAssertEqual(detachedOwners, [first, second])
    }

    @MainActor
    func testDuplicateDismissalCleansUpOnlyOnce() async throws {
        let lifecycle = PaneSubscriptionLifecycle()
        let owner = UUID()
        var cleanups = 0
        try await lifecycle.preparePaneSubscription(owner: owner)
        lifecycle.releasePaneSubscription(owner: owner) { cleanups += 1 }
        lifecycle.releasePaneSubscription(owner: owner) { cleanups += 1 }
        try await lifecycle.preparePaneSubscription(owner: UUID())
        XCTAssertEqual(cleanups, 1)
    }

    @MainActor
    func testDisconnectAllowsFreshOwnershipWithoutReplayingOldCleanup() async throws {
        let lifecycle = PaneSubscriptionLifecycle()
        let gate = FixturePaneCleanupGate()
        let oldOwner = UUID(), newOwner = UUID()
        var cleanups = 0
        try await lifecycle.preparePaneSubscription(owner: oldOwner)
        lifecycle.releasePaneSubscription(owner: oldOwner) { cleanups += 1; await gate.wait() }
        await gate.waitUntilStarted()
        lifecycle.invalidatePaneSubscriptions()
        try await lifecycle.preparePaneSubscription(owner: newOwner)
        gate.finish()
        lifecycle.releasePaneSubscription(owner: oldOwner) { cleanups += 1 }
        do { try await lifecycle.preparePaneSubscription(owner: UUID()); XCTFail("Old cleanup must not release fresh ownership.") }
        catch PaneSubscriptionError.alreadyOwned {}
        XCTAssertEqual(cleanups, 1)
    }

    @MainActor
    func testCancelledViewCannotClaimPaneOwnership() async throws {
        let lifecycle = PaneSubscriptionLifecycle()
        let cancelled = Task { @MainActor in try await lifecycle.preparePaneSubscription(owner: UUID()) }
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("A dismissed view cannot claim mobile subscriptions.") }
        catch is CancellationError {}
        try await lifecycle.preparePaneSubscription(owner: UUID())
    }

    @MainActor
    func testAnotherActivePaneCannotSilentlyTakeOwnership() async throws {
        let lifecycle = PaneSubscriptionLifecycle()
        try await lifecycle.preparePaneSubscription(owner: UUID())
        do { try await lifecycle.preparePaneSubscription(owner: UUID()); XCTFail("One pane owns mobile subscriptions.") }
        catch PaneSubscriptionError.alreadyOwned {}
    }

    @MainActor
    func testDetachFailurePropagatesWithoutRetry() async throws {
        let lifecycle = PaneSubscriptionLifecycle()
        let owner = UUID()
        let gate = FixturePaneCleanupGate()
        var attempts = 0
        try await lifecycle.preparePaneSubscription(owner: owner)
        lifecycle.releasePaneSubscription(owner: owner) { attempts += 1; await gate.wait(); throw FixturePaneCleanupFailure() }
        let next = Task { @MainActor in try await lifecycle.preparePaneSubscription(owner: UUID()) }
        await gate.waitUntilStarted()
        gate.finish()
        do { try await next.value; XCTFail("Failed release must not permit an unchecked new attachment.") }
        catch is FixturePaneCleanupFailure {}
        XCTAssertEqual(attempts, 1)
    }
}

private struct FixturePaneCleanupFailure: Error {}

@MainActor
private final class FixturePaneCleanupGate {
    private var completion: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { completion = $0; started?.resume(); started = nil }
    }
    func waitUntilStarted() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() { completion?.resume(); completion = nil }
}
