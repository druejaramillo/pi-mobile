import Foundation
import Combine
import PiMobileCore

/// Global agent index composes independent machines; no background monitoring or mutation replay.
@MainActor
final class MobileSessionHub: ObservableObject {
    @Published private(set) var refreshing = Set<UUID>()
    @Published private(set) var checkedAt: [UUID: Date] = [:]
    @Published private(set) var machineErrors: [UUID: String] = [:]
    private let registry = MachineSessionRegistry<SSHBridgeConnection>()
    private let machines: MachineStore
    private var subscriptions: [UUID: AnyCancellable] = [:]
    private var cachedTopologies: [UUID: HerdrTopology] = [:]
    let drafts = PaneDraftStore()
    let tailscale = TailscaleService()

    init(machines: MachineStore) { self.machines = machines }

    func connection(for machineId: UUID) -> SSHBridgeConnection {
        registry.connection(for: machineId) {
            let connection = SSHBridgeConnection(tailscale: tailscale)
            subscriptions[machineId] = connection.objectWillChange.sink { [weak self] _ in
                // Child @Published changes become visible after objectWillChange's pre-change callback.
                Task { @MainActor in self?.objectWillChange.send() }
            }
            return connection
        }
    }

    func refreshMachine(_ profile: MachineProfile) async {
        // Navigation may hold an older profile value after editing; the saved store is authoritative.
        guard let profile = machines.machines.first(where: { $0.id == profile.id }),
              let token = registry.beginRefresh(for: profile.id) else { return }
        refreshing = registry.refreshingMachineIds
        defer {
            if registry.finishRefresh(token, for: profile.id) { refreshing = registry.refreshingMachineIds }
        }
        do {
            let client = connection(for: profile.id)
            if client.state != "connected" {
                // Keyless Tailscale profiles never read Keychain, even if an old credential remains saved.
                let secret = try profile.requiresSSHCredential
                    ? MachineSecretStore.readSecret(machineId: profile.id) : nil
                try await client.connect(profile: profile, secret: secret)
            }
            guard registry.isCurrentRefresh(token, for: profile.id) else { return }
            let response = try await client.request(method: "snapshot", params: .object([:]))
            let topology = try response.decode(HerdrTopology.self)
            guard registry.isCurrentRefresh(token, for: profile.id) else { return }
            cachedTopologies[profile.id] = topology
            checkedAt[profile.id] = Date()
            machineErrors.removeValue(forKey: profile.id)
        } catch {
            guard registry.isCurrentRefresh(token, for: profile.id) else { return }
            machineErrors[profile.id] = error.localizedDescription
        }
    }

    func refreshAll(_ profiles: [MachineProfile]) async {
        // Three hosts normally; each failed connection must not block another host's result.
        await withTaskGroup(of: Void.self) { group in
            for profile in profiles {
                group.addTask { [weak self] in await self?.refreshMachine(profile) }
            }
        }
    }

    func cachedTopology(for machineId: UUID) -> HerdrTopology? {
        registry.existingConnection(for: machineId)?.topology ?? cachedTopologies[machineId]
    }

    func agentEntries(_ profiles: [MachineProfile]) -> [GlobalAgentEntry] {
        profiles.flatMap { profile in
            guard let topology = cachedTopology(for: profile.id) else { return [GlobalAgentEntry]() }
            return topology.panes.compactMap { pane in
                guard let kind = pane.agent, !kind.isEmpty else { return nil }
                let workspace = topology.workspaces.first { $0.id == pane.workspaceId }?.name ?? pane.workspaceId
                let tab = topology.tabs.first { $0.id == pane.tabId }?.name ?? pane.tabId
                return GlobalAgentEntry(profile: profile, pane: pane, workspaceName: workspace, tabName: tab,
                    stale: registry.existingConnection(for: profile.id)?.state != "connected" || machineErrors[profile.id] != nil)
            }
        }.sorted { first, second in
            if first.stale != second.stale { return !first.stale }
            let rank: [String: Int] = ["blocked": 0, "working": 1, "done": 2, "idle": 3, "unknown": 4]
            let a = rank[first.pane.state] ?? 4, b = rank[second.pane.state] ?? 4
            if a != b { return a < b }
            return first.title.localizedStandardCompare(second.title) == .orderedAscending
        }
    }

    /// Editing clears old endpoint data, not the connection identity held by an open screen.
    func resetMachine(_ id: UUID) {
        registry.resetMachine(id) { $0.resetForProfileChange() }
        refreshing = registry.refreshingMachineIds
        checkedAt.removeValue(forKey: id)
        machineErrors.removeValue(forKey: id)
        cachedTopologies.removeValue(forKey: id)
    }

    func forgetMachine(_ id: UUID) {
        registry.removeMachine(id) { $0.resetForProfileChange() }
        subscriptions.removeValue(forKey: id)
        refreshing = registry.refreshingMachineIds
        checkedAt.removeValue(forKey: id)
        machineErrors.removeValue(forKey: id)
        cachedTopologies.removeValue(forKey: id)
    }

    func suspendConnections() {
        registry.suspendMachines { $0.disconnect() }
        refreshing = registry.refreshingMachineIds
        objectWillChange.send()
    }
}

struct GlobalAgentEntry: Identifiable {
    let profile: MachineProfile
    let pane: HerdrPane
    let workspaceName: String
    let tabName: String
    let stale: Bool
    var id: String { "\(profile.id.uuidString)/\(pane.terminalId)" }
    var title: String { pane.title.isEmpty ? (pane.agent ?? "Agent") : pane.title }
    var context: String { "\(profile.name) · \(workspaceName) · \(tabName) · \(pane.id)" }
}
