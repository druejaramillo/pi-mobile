import Foundation
import NIOCore
import PiMobileCore

/// JSONL framing counts bytes and decodes only complete LF-delimited UTF-8 records.
struct BridgeLineFramer {
    static let maximumRecordBytes = 1024 * 1024
    private var partial = Data()

    mutating func consume(_ buffer: ByteBuffer, onRecord: (BridgeJSON) throws -> Void) throws {
        var bytes = buffer.readableBytesView[...]
        while !bytes.isEmpty {
            let end = bytes.firstIndex(of: 0x0A) ?? bytes.endIndex
            let fragment = bytes[..<end]
            guard partial.count + fragment.count <= Self.maximumRecordBytes else {
                throw SSHBridgeError.protocolViolation("JSONL record exceeds 1 MiB")
            }
            partial.append(contentsOf: fragment)
            if end == bytes.endIndex { return }
            guard !partial.isEmpty, String(data: partial, encoding: .utf8) != nil else {
                throw SSHBridgeError.protocolViolation("empty or invalid UTF-8 JSONL record")
            }
            let record: BridgeJSON
            do { record = try JSONDecoder().decode(BridgeJSON.self, from: partial) }
            catch { throw SSHBridgeError.protocolViolation("JSONL record is not a bridge envelope") }
            partial.removeAll(keepingCapacity: true)
            try onRecord(record)
            bytes = bytes[bytes.index(after: end)...]
        }
    }

    func validateEndOfStream() throws {
        guard partial.isEmpty else { throw SSHBridgeError.protocolViolation("EOF before JSONL record LF") }
    }
}
