import Foundation
import XCTest
import PiMobileCore

final class MachineSessionRegistryTests: XCTestCase {
    @MainActor
    func testEditingKeepsTheConnectionObservedByAnOpenScreen() async {
        let registry = MachineSessionRegistry<FixtureMachineConnection>()
        let id = UUID()
        let observed = registry.connection(for: id) { FixtureMachineConnection() }
        observed.connected = true
        registry.resetMachine(id) { $0.connected = false }
        let refreshed = registry.connection(for: id) { FixtureMachineConnection() }
        refreshed.connected = true
        XCTAssertTrue(observed === refreshed, "Editing must not leave an open screen observing a retired connection.")
        XCTAssertTrue(observed.connected, "A successful refresh must not keep the observed screen offline/cached.")
    }

    @MainActor
    func testEditingAllowsANewRefreshBeforeTheOldReadFinishes() async throws {
        let registry = MachineSessionRegistry<FixtureMachineConnection>()
        let id = UUID()
        let old = try XCTUnwrap(registry.beginRefresh(for: id))
        registry.resetMachine(id) { _ in }
        let current = try XCTUnwrap(registry.beginRefresh(for: id))
        XCTAssertFalse(registry.isCurrentRefresh(old, for: id))
        XCTAssertFalse(registry.finishRefresh(old, for: id), "An old completion must not clear the new refresh.")
        XCTAssertTrue(registry.isCurrentRefresh(current, for: id))
        XCTAssertEqual(registry.refreshingMachineIds, [id])
        XCTAssertTrue(registry.finishRefresh(current, for: id))
        XCTAssertTrue(registry.refreshingMachineIds.isEmpty)
    }

    @MainActor
    func testRefreshFailureOnAnotherMachineDoesNotInvalidateThisMachine() async throws {
        let registry = MachineSessionRegistry<FixtureMachineConnection>()
        let first = UUID(), second = UUID()
        let firstToken = try XCTUnwrap(registry.beginRefresh(for: first))
        let secondToken = try XCTUnwrap(registry.beginRefresh(for: second))
        registry.resetMachine(first) { _ in }
        XCTAssertFalse(registry.isCurrentRefresh(firstToken, for: first))
        XCTAssertTrue(registry.isCurrentRefresh(secondToken, for: second))
        XCTAssertNil(registry.beginRefresh(for: second))
    }

    @MainActor
    func testRemovingMachineRetiresItsConnectionAndPendingRead() async throws {
        let registry = MachineSessionRegistry<FixtureMachineConnection>()
        let id = UUID()
        let oldConnection = registry.connection(for: id) { FixtureMachineConnection() }
        let token = try XCTUnwrap(registry.beginRefresh(for: id))
        registry.removeMachine(id) { $0.connected = false }
        XCTAssertNil(registry.existingConnection(for: id))
        XCTAssertFalse(registry.isCurrentRefresh(token, for: id))
        XCTAssertFalse(oldConnection === registry.connection(for: id) { FixtureMachineConnection() })
    }

    @MainActor
    func testBackgroundSuspensionKeepsIdentityButRejectsPendingReads() async throws {
        let registry = MachineSessionRegistry<FixtureMachineConnection>()
        let id = UUID()
        let observed = registry.connection(for: id) { FixtureMachineConnection() }
        observed.connected = true
        let token = try XCTUnwrap(registry.beginRefresh(for: id))
        registry.suspendMachines { $0.connected = false }
        XCTAssertFalse(observed.connected)
        XCTAssertFalse(registry.isCurrentRefresh(token, for: id))
        XCTAssertTrue(registry.refreshingMachineIds.isEmpty)
        XCTAssertTrue(observed === registry.connection(for: id) { FixtureMachineConnection() })
    }
}

/// The registry treats transport handles as opaque identities; no fixture SSH behavior is simulated.
private final class FixtureMachineConnection {
    var connected = false
}
