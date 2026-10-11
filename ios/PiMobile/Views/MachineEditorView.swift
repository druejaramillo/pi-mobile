import SwiftUI
import PiMobileCore

/// New machines use keyless Tailscale SSH; every connection still requires a verified public host identity.
struct MachineEditorView: View {
    let profile: MachineProfile?
    @EnvironmentObject private var machines: MachineStore
    @EnvironmentObject private var sessions: MobileSessionHub
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
                        Text("Tailscale SSH handles login on port 22. No private key or password. The host must allow this username without an interactive sign-in check.")
                    }
                }
                if !useTailscaleSSH {
                    Section {
                        Button("Switch to Tailscale SSH", systemImage: "network") {
                            useTailscaleSSH = true
                            port = "22"
                            hostPublicKey = ""
                            error = nil
                        }
                        .mobileGlassButtonStyle().buttonBorderShape(.capsule).frame(minHeight: 44)
                    } footer: {
                        Text("This machine keeps its saved SSH login. Switching requires Tailscale SSH on the host and its verified public host key. Nothing changes until you save.")
                    }
                }
                Section {
                    TextEditor(text: $hostPublicKey)
                        .font(.body.monospaced()).frame(minHeight: 110)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Verified public host key")
                } header: { Text(useTailscaleSSH ? "Tailscale host identity" : "Host identity") } footer: {
                    Text(useTailscaleSSH
                        ? "Paste the full public host key advertised by Tailscale, verified from a trusted device. This identifies the machine; it is not a private login key."
                        : "Keep the verified public host key for this saved SSH connection. A network scan alone is not proof of identity.")
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
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if profile != nil {
                    Section {
                        Button("Remove saved machine", role: .destructive) { confirmRemove = true }
                            .mobileGlassButtonStyle().buttonBorderShape(.capsule).frame(minHeight: 44)
                    } footer: { Text("Removes this connection and any saved login credential. Host sessions keep running.") }
                }
            }
            .navigationTitle(profile == nil ? "Add machine" : "Edit machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.mobileGlassHeaderControl()
                }.mobileGlassHeaderItem()
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveMachine() }.mobileGlassHeaderControl(prominent: true)
                }.mobileGlassHeaderItem()
            }
            .onAppear {
                guard let profile else { return }
                machineId = profile.id; name = profile.name; hostname = profile.hostname
                port = String(profile.port); username = profile.username; herdrSession = profile.herdrSession
                bridgePath = profile.bridgePath; hostPublicKey = profile.hostPublicKey
                useTailscaleSSH = !profile.requiresSSHCredential
            }
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

    private func saveMachine() {
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
            // Validate the actual transport settings, including the parsed public key, before persisting.
            _ = try SSHBridgeConfiguration(profile: updated)
            try machines.saveMachine(updated)
            sessions.forgetMachine(machineId)
            dismiss()
            Task { await sessions.refreshMachine(updated) }
        } catch { self.error = error.localizedDescription }
    }
}

enum MachineFormError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
