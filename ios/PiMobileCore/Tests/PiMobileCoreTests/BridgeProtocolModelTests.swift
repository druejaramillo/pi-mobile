import Foundation
import PiMobileCore
import XCTest

/// Public wire models preserve identity and values independently of app transport implementation.
final class BridgeProtocolModelTests: XCTestCase {
    func testCommandKeepsLiveMutationIdentity() throws {
        let command = BridgeCommand(id: "11111111-1111-1111-1111-111111111111", method: "dialog.respond", params: .object([
            "sessionId": .string("session-one"), "generation": .string("generation-one"),
            "dialogId": .string("dialog-one"), "revision": .number(7), "action": .string("submit"),
            "value": .string("réponse 🙂\u{2028}second line"),
        ]))
        let wire = try JSONDecoder().decode(BridgeJSON.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(wire["id"]?.string, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(wire["params"]?["sessionId"]?.string, "session-one")
        XCTAssertEqual(wire["params"]?["generation"]?.string, "generation-one")
        XCTAssertEqual(wire["params"]?["revision"]?.integer, 7)
        XCTAssertEqual(wire["params"]?["value"]?.string, "réponse 🙂\u{2028}second line")
    }

    func testNewCommandsHaveDistinctUUIDs() {
        let first = BridgeCommand(method: "snapshot")
        let second = BridgeCommand(method: "snapshot")
        XCTAssertNotNil(UUID(uuidString: first.id))
        XCTAssertNotEqual(first.id, second.id)
    }

    func testNullSuccessIsPresentRatherThanMissing() throws {
        let response = try JSONDecoder().decode(BridgeJSON.self, from: Data("{\"id\":\"reply\",\"result\":null}".utf8))
        XCTAssertEqual(response["result"], .null)
        XCTAssertNil(response["error"])
        XCTAssertNil(response["missing"])
    }

    func testTextTakingDialogActionsAreExplicitAndBackwardCompatible() throws {
        let normal = try JSONDecoder().decode(PiDialogOption.self, from: Data("{\"id\":\"cancel\",\"label\":\"Cancel\"}".utf8))
        let text = try JSONDecoder().decode(PiDialogOption.self, from: Data("{\"id\":\"submit\",\"label\":\"Submit\",\"acceptsValue\":true}".utf8))
        XCTAssertFalse(normal.acceptsValue ?? false)
        XCTAssertEqual(text.acceptsValue, true)
    }

    func testPaneIdentityIncludesItsMachine() throws {
        let first = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let second = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let a = PaneLocation(machineId: first, terminalId: "term_shared")
        let b = PaneLocation(machineId: second, terminalId: "term_shared")
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.id, "00000000-0000-0000-0000-000000000001/term_shared")
    }

    func testTerminalBytesDecodeWithoutChangingControlCharacters() throws {
        let frame = try JSONDecoder().decode(TerminalFrame.self,
            from: Data("{\"terminalId\":\"term_one\",\"data\":\"G1tB\",\"cols\":80,\"rows\":24}".utf8))
        XCTAssertEqual(frame.bytes, Data([0x1b, 0x5b, 0x41]))
        let invalid = try JSONDecoder().decode(TerminalFrame.self,
            from: Data("{\"terminalId\":\"term_one\",\"data\":\"!invalid!\",\"cols\":80,\"rows\":24}".utf8))
        XCTAssertNil(invalid.bytes)
    }

    func testFractionalOrNonfiniteValuesCannotBecomeIntegerIdentity() {
        XCTAssertNil(BridgeJSON.number(1.5).integer)
        XCTAssertNil(BridgeJSON.number(.infinity).integer)
        XCTAssertNil(BridgeJSON.bool(true).integer)
    }
}
