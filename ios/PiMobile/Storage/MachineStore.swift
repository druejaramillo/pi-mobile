import Foundation
import Combine
import PiMobileCore

/// Saved machine addresses are independent of SSH secrets and live connections.
@MainActor
final class MachineStore: ObservableObject {
    @Published private(set) var machines: [MachineProfile]
    private let defaults: UserDefaults
    private let storageKey = "pi-mobile.machines.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        machines = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([MachineProfile].self, from: $0) } ?? []
    }

    func saveMachine(_ profile: MachineProfile) throws {
        var updated = machines
        if let index = updated.firstIndex(where: { $0.id == profile.id }) { updated[index] = profile }
        else { updated.append(profile) }
        let encoded = try JSONEncoder().encode(updated)
        defaults.set(encoded, forKey: storageKey)
        machines = updated
    }

    func removeMachine(_ profile: MachineProfile) throws {
        try MachineSecretStore.deleteSecret(machineId: profile.id)
        let updated = machines.filter { $0.id != profile.id }
        defaults.set(try JSONEncoder().encode(updated), forKey: storageKey)
        machines = updated
    }
}

/// Unsent drafts belong to a machine and stable terminal identity, never the focused pane.
@MainActor
final class PaneDraftStore {
    private let defaults = UserDefaults.standard
    func loadDraft(_ location: PaneLocation) -> String {
        defaults.string(forKey: "pi-mobile.draft.\(location.id)") ?? ""
    }
    func saveDraft(_ text: String, at location: PaneLocation) {
        let key = "pi-mobile.draft.\(location.id)"
        if text.isEmpty { defaults.removeObject(forKey: key) }
        else { defaults.set(text, forKey: key) }
    }
}
