import SwiftUI
import PiMobileCore

/// Tailscale SSH setup obtains host identity automatically; legacy pins and credentials are preserved.
struct MachineEditorView: View {
    let profile: MachineProfile?
    @EnvironmentObject private var machines: MachineStore
    @EnvironmentObject private var sessions: MobileSessionHub
    @EnvironmentObject private var tailscale: TailscaleService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var herdrSession = "default"
    @State private var bridgePath = ".local/share/pi-mobile/host/bridge-cli.mjs"
    @State private var hostPublicKey = ""
    @State private var useTailscaleSSH = true
    @State private var error: String?
    @State private var confirmRemove = false
    @State private var machineId = UUID()
    @State private var loaded = false
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Tailscale name or address", text: $hostname)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Host username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !useTailscaleSSH {
                        TextField("Saved SSH port", text: $port).keyboardType(.numberPad)
                    }
                } header: { Text("Machine") } footer: {
                    if useTailscaleSSH {
                        Text("Tailscale verifies this machine's host keys automatically. SSH uses port 22 with no private key or password. The host must allow this username without an interactive SSH check.")
                    }
                }
                if useTailscaleSSH {
                    TailscaleAccountSection()
                } else {
                    Section {
                        Button("Switch to Tailscale SSH", systemImage: "network") {
                            useTailscaleSSH = true
                            port = "22"
                            hostPublicKey = ""
                            error = nil
                        }
                        .mobileGlassButtonStyle().buttonBorderShape(.capsule).frame(minHeight: 44)
                    } footer: {
                        Text("Keeps the saved SSH login until you save. Switching verifies host keys through Pi Mobile's Tailscale connection; Cancel changes nothing.")
                    }
                    Section {
                        TextEditor(text: $hostPublicKey)
                            .font(.body.monospaced()).frame(minHeight: 110)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Verified public host key")
                    } header: { Text("Saved host identity") } footer: {
                        Text("Keep the verified public host key for this legacy SSH connection. A network scan alone is not proof of identity.")
                    }
                }
                Section {
                    DisclosureGroup("Host bridge") {
                        TextField("Herdr session", text: $herdrSession)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Bridge path relative to home", text: $bridgePath)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } footer: {
                    Text("Install the host bridge first. Change these settings only if its session or location differs from the defaults.")
                }
                if saving { Section { ProgressView("Verifying host identity…") } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if profile != nil {
                    Section {
                        Button("Remove saved machine", role: .destructive) { confirmRemove = true }
                            .mobileGlassButtonStyle().buttonBorderShape(.capsule).frame(minHeight: 44)
                    } footer: { Text("Removes this connection and any saved login credential. Host sessions keep running.") }
                }
            }
            .disabled(saving)
            .navigationTitle(profile == nil ? "Add machine" : "Edit machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { saveTask?.cancel(); dismiss() }.mobileGlassHeaderControl()
                }.mobileGlassHeaderItem()
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTask = Task { await saveMachine() } }
                        .mobileGlassHeaderControl(prominent: true).disabled(saving)
                }.mobileGlassHeaderItem()
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                guard let profile else { return }
                machineId = profile.id; name = profile.name; hostname = profile.hostname
                port = String(profile.port); username = profile.username; herdrSession = profile.herdrSession
                bridgePath = profile.bridgePath; hostPublicKey = profile.hostPublicKey
                useTailscaleSSH = !profile.requiresSSHCredential
            }
            .onDisappear { saveTask?.cancel() }
            .confirmationDialog("Remove this machine from Pi Mobile?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove machine", role: .destructive) {
                    guard let profile else { return }
                    do {
                        try machines.removeMachine(profile)
                        sessions.forgetMachine(profile.id)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    private func saveMachine() async {
        guard !saving else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let address = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty, !address.isEmpty, !account.isEmpty else {
                throw MachineFormError.invalid("Add a name, Tailscale address and host username.")
            }
            guard let sshPort = useTailscaleSSH ? 22 : Int(port), (1...65535).contains(sshPort) else {
                throw MachineFormError.invalid("Saved SSH port must be 1–65535.")
            }
            let updated = MachineProfile(id: machineId, name: displayName, hostname: address, port: sshPort,
                username: account, herdrSession: herdrSession, bridgePath: bridgePath,
                hostPublicKey: hostPublicKey.trimmingCharacters(in: .whitespacesAndNewlines),
                authentication: useTailscaleSSH ? "tailscale" : (profile?.authentication ?? "tailscale"))
            if useTailscaleSSH { try await tailscale.validateProfile(updated) }
            else { _ = try SSHBridgeConfiguration(profile: updated) }
            // Cancel, backgrounding or a failed trusted lookup cannot persist a partial migration.
            try Task.checkCancellation()
            try machines.saveMachine(updated)
            sessions.resetMachine(machineId)
            dismiss()
            Task { await sessions.refreshMachine(updated) }
        } catch is CancellationError { /* Cancel never alters the saved machine. */ }
        catch { self.error = error.localizedDescription }
    }
}

enum MachineFormError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
