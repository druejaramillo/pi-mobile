import Foundation
import PiMobile
import PiMobileCore
import XCTest

/// Native session tests use public facade guards, never real credentials or an SSH daemon.
final class SSHBridgeSessionTests: XCTestCase {
    @MainActor
    func testDisconnectedRequestsFailWithoutCreatingAnAttachment() async {
        let connection = SSHBridgeConnection()
        do {
            _ = try await connection.request(method: "agent.abort", params: .object([:]))
            XCTFail("A disconnected session must not submit a mutation.")
        } catch SSHBridgeError.disconnected {
            XCTAssertEqual(connection.state, "disconnected")
            XCTAssertNil(connection.agent)
            XCTAssertNil(connection.terminalFrame)
        } catch { XCTFail("Unexpected session error: \(error)") }
    }

    @MainActor
    func testMissingHostPinFailsClosedBeforeAuthentication() async {
        let connection = SSHBridgeConnection()
        let profile = MachineProfile(name: "Test only", hostname: "127.0.0.1", username: "test", authentication: "password")
        do {
            try await connection.connect(profile: profile, secret: "unused-test-value")
            XCTFail("An empty host pin must never connect.")
        } catch SSHBridgeError.invalidProfile(_) {
            XCTAssertEqual(connection.state, "failed")
            XCTAssertNil(connection.agent)
            XCTAssertFalse(connection.lastError?.contains("unused-test-value") ?? false)
        } catch { XCTFail("Unexpected profile error: \(error)") }
        connection.disconnect()
    }

    @MainActor
    func testUnadvertisedReviewCannotOpenForwarding() async throws {
        let connection = SSHBridgeConnection()
        let review = try JSONDecoder().decode(PlannotatorReview.self,
            from: Data("{\"id\":\"plannotator_a1\",\"url\":\"http://127.0.0.1:43111/review\"}".utf8))
        do {
            _ = try await connection.openReview(review)
            XCTFail("An unadvertised review must not create forwarding.")
        } catch SSHBridgeError.invalidReview {
            XCTAssertEqual(connection.state, "disconnected")
        } catch { XCTFail("Unexpected review error: \(error)") }
    }

    @MainActor
    func testDisconnectIsIdempotentAndClearsLiveState() async {
        let connection = SSHBridgeConnection()
        connection.disconnect()
        connection.disconnect()
        XCTAssertEqual(connection.state, "disconnected")
        XCTAssertNil(connection.agent)
        XCTAssertNil(connection.terminalFrame)
    }
}
