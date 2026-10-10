import Foundation

/// Lossless JSON at the SSH protocol boundary; never decode external payloads as Any.
public enum BridgeJSON: Codable, Sendable, Equatable {
    case object([String: BridgeJSON]), array([BridgeJSON]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([BridgeJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: BridgeJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(_ key: String) -> BridgeJSON? {
        guard case .object(let values) = self else { return nil }
        return values[key]
    }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var integer: Int? {
        guard case .number(let value) = self, value.isFinite, value.rounded() == value,
              value >= Double(Int.min), value < Double(Int.max) else { return nil }
        return Int(value)
    }
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

/// SSH connection settings persist separately from secrets kept in Keychain.
public struct MachineProfile: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var herdrSession: String
    public var bridgePath: String
    public var hostPublicKey: String
    public var authentication: String

    public init(id: UUID = UUID(), name: String, hostname: String, port: Int = 22,
                username: String, herdrSession: String = "default",
                bridgePath: String = ".local/share/pi-mobile/host/bridge-cli.mjs",
                hostPublicKey: String = "", authentication: String = "key") {
        self.id = id; self.name = name; self.hostname = hostname; self.port = port
        self.username = username; self.herdrSession = herdrSession; self.bridgePath = bridgePath
        self.hostPublicKey = hostPublicKey; self.authentication = authentication
    }
}

/// One terminal's stable identity remains valid when Herdr moves its pane.
public struct PaneLocation: Hashable, Sendable, Identifiable {
    public let machineId: UUID
    public let terminalId: String
    public var id: String { "\(machineId.uuidString)/\(terminalId)" }
    public init(machineId: UUID, terminalId: String) { self.machineId = machineId; self.terminalId = terminalId }
}

public struct HerdrWorkspace: Codable, Identifiable, Sendable { public let id: String; public let name: String }
public struct HerdrTab: Codable, Identifiable, Sendable { public let id: String; public let workspaceId: String; public let name: String }
public struct PlannotatorReview: Codable, Identifiable, Sendable { public let id: String; public let url: String }
public struct HerdrPane: Codable, Identifiable, Sendable {
    public let id: String
    public let terminalId: String
    public let workspaceId: String
    public let tabId: String
    public let title: String
    public let cwd: String
    public let agent: String?
    public let state: String
    public let mobileAvailable: Bool
    public let reviews: [PlannotatorReview]
}
public struct HerdrTopology: Codable, Sendable {
    public let workspaces: [HerdrWorkspace]
    public let tabs: [HerdrTab]
    public let panes: [HerdrPane]
}
public struct AgentTranscriptMessage: Codable, Identifiable, Sendable {
    public let id: String
    public let role: String
    public let text: String
    public let toolName: String?
    public let isError: Bool?
}
public struct PiSlashCommand: Codable, Identifiable, Sendable {
    public let name: String
    public let description: String
    public var id: String { name }
}
public struct PiDialogOption: Codable, Identifiable, Sendable { public let id: String; public let label: String }
public struct PiDialogSnapshot: Codable, Identifiable, Sendable {
    public let dialogId: String
    public let revision: Int
    public let kind: String
    public let title: String
    public let text: String
    public let options: [PiDialogOption]
    public let acceptsText: Bool
    public var id: String { dialogId }
}
public struct PiAgentSnapshot: Codable, Sendable {
    public let sessionId: String
    public let generation: String
    public let terminalId: String
    public let name: String
    public let cwd: String
    public let status: String
    public let messages: [AgentTranscriptMessage]
    public let commands: [PiSlashCommand]
    public let dialog: PiDialogSnapshot?
    public let truncated: Bool
}
public struct TerminalFrame: Codable, Sendable {
    public let terminalId: String
    public let data: String
    public let cols: Int
    public let rows: Int
    public var bytes: Data? { Data(base64Encoded: data) }
}

/// Each command id is unique; transport reconnect never replays a mutation.
public struct BridgeCommand: Codable, Sendable {
    public let id: String
    public let method: String
    public let params: BridgeJSON
    public init(id: String = UUID().uuidString, method: String, params: BridgeJSON = .object([:])) {
        self.id = id; self.method = method; self.params = params
    }
}
public struct BridgeFailure: Codable, Error, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public var errorDescription: String? { message }
}
public struct BridgeRecord: Codable, Sendable {
    public let id: String?
    public let result: BridgeJSON?
    public let error: BridgeFailure?
    public let event: String?
    public let data: BridgeJSON?
}
