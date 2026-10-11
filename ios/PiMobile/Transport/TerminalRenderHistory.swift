import Foundation
import PiMobileCore

/// Bounded cumulative ANSI history survives coalesced SwiftUI updates without replaying terminal input.
struct TerminalRenderHistory {
    private static let maximumHistoryBytes = 8 * 1024 * 1024
    private var terminalID: String?
    private var bytes = Data()

    mutating func append(_ frame: TerminalFrame) throws -> TerminalFrame {
        guard (1...4096).contains(frame.cols), (1...4096).contains(frame.rows), let incoming = frame.bytes else {
            throw SSHBridgeError.protocolViolation("terminal frame dimensions or base64 bytes")
        }
        if terminalID != frame.terminalId {
            bytes.removeAll(keepingCapacity: false)
            terminalID = frame.terminalId
        }
        guard bytes.count + incoming.count <= Self.maximumHistoryBytes else { throw SSHBridgeError.capacityExceeded }
        bytes.append(incoming)
        // Shared models have no public memberwise initializer. Decode through their actual Codable seam.
        return try BridgeJSON.object([
            "terminalId": .string(frame.terminalId), "data": .string(bytes.base64EncodedString()),
            "cols": .number(Double(frame.cols)), "rows": .number(Double(frame.rows))
        ]).decode(TerminalFrame.self)
    }
}
