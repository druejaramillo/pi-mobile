import Foundation

/// Machine session registry owns stable connection identities and rejects refresh results from retired generations.
@MainActor
public final class MachineSessionRegistry<Connection: AnyObject> {
    private var connections: [UUID: Connection] = [:]
    private var refreshTokens: [UUID: MachineRefreshToken] = [:]

    public init() {}

    /// Refreshing machine IDs include only reads from current machine generations.
    public var refreshingMachineIds: Set<UUID> { Set(refreshTokens.keys) }

    /// Connection lookup preserves the object identity already observed by navigation.
    public func connection(for machineId: UUID, create: () -> Connection) -> Connection {
        if let connection = connections[machineId] { return connection }
        let connection = create()
        connections[machineId] = connection
        return connection
    }

    /// Existing connection lookup never creates a transport just to display cached state.
    public func existingConnection(for machineId: UUID) -> Connection? { connections[machineId] }

    /// Beginning a refresh excludes concurrent reads in the same current generation.
    public func beginRefresh(for machineId: UUID) -> MachineRefreshToken? {
        guard refreshTokens[machineId] == nil else { return nil }
        let token = MachineRefreshToken()
        refreshTokens[machineId] = token
        return token
    }

    /// A refresh result is current only if its machine has not been edited, removed or suspended.
    public func isCurrentRefresh(_ token: MachineRefreshToken, for machineId: UUID) -> Bool {
        refreshTokens[machineId] == token
    }

    /// Finishing an old refresh cannot clear a newer machine's refresh indicator.
    @discardableResult
    public func finishRefresh(_ token: MachineRefreshToken, for machineId: UUID) -> Bool {
        guard isCurrentRefresh(token, for: machineId) else { return false }
        refreshTokens.removeValue(forKey: machineId)
        return true
    }

    /// Editing resets the transport without retiring the connection identity observed by navigation.
    public func resetMachine(_ machineId: UUID, disconnect: (Connection) -> Void) {
        refreshTokens.removeValue(forKey: machineId)
        if let connection = connections[machineId] { disconnect(connection) }
    }

    /// Removal, unlike editing, retires the saved machine's connection identity.
    public func removeMachine(_ machineId: UUID, disconnect: (Connection) -> Void) {
        refreshTokens.removeValue(forKey: machineId)
        if let connection = connections.removeValue(forKey: machineId) { disconnect(connection) }
    }

    /// Background suspension invalidates pending reads but preserves foreground navigation identities.
    public func suspendMachines(disconnect: (Connection) -> Void) {
        refreshTokens.removeAll()
        connections.values.forEach(disconnect)
    }
}

/// Machine refresh token is opaque and cannot be mistaken for a saved machine ID.
public struct MachineRefreshToken: Equatable, Sendable {
    fileprivate let id = UUID()
    fileprivate init() {}
}
