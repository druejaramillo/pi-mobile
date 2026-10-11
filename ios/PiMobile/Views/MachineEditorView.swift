import SwiftUI
import UniformTypeIdentifiers
import PiMobileCore

/// Adding a connection requires a trusted host key; the app never accepts any host automatically.
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
    @State private var authentication = "key"
    @State private var secret = ""
    @State private var keyPassphrase = ""
    @State private var error: String?
    @State private var importingKey = false
    @State private var confirmRemove = false
    @State private var machineId = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section("Machine") {
                    TextField("Name", text: $name)
                    TextField("Tailscale name or address", text: $hostname)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("SSH username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("SSH port", text: $port).keyboardType(.numberPad)
                }
                Section {
                    TextField("Herdr session", text: $herdrSession)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Bridge path relative to home", text: $bridgePath)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Host bridge") } footer: {
                    Text("Install the host files from this repository first. Connections never install or restart software.")
                }
                Section {
                    TextEditor(text: $hostPublicKey)
                        .font(.body.monospaced()).frame(minHeight: 110)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Verified SSH host public key")
                } header: { Text("Verified host public key") } footer: {
                    Text("Paste the ssh-ed25519 host public key obtained directly from a machine you trust, including its key type. A network key scan alone is not proof of identity.")
                }
                Section {
                    Picker("Authentication", selection: $authentication) {
                        Text("SSH key").tag("key")
                        Text("Password").tag("password")
                    }
                    if authentication == "key" {
                        LabeledContent("Private key") {
                            PasteButton(payloadType: String.self) { values in
                                guard let text = values.first else { return }
                                acceptPrivateKey(text)
                            }
                            .mobileGlassButtonStyle().buttonBorderShape(.capsule)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Paste OpenSSH private key")
                        }
                        Button("Import OpenSSH private key", systemImage: "square.and.arrow.down") { importingKey = true }
                            .mobileGlassButtonStyle().buttonBorderShape(.capsule).frame(minHeight: 44)
                        if !secret.isEmpty {
                            Label("Key ready to save", systemImage: "key.fill")
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField("Key passphrase (if encrypted)", text: $keyPassphrase)
                                    .textContentType(.password)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .frame(minHeight: 44)
                                PasteButton(payloadType: String.self) { values in
                                    guard authentication == "key", let passphrase = values.first else { return }
                                    keyPassphrase = passphrase
                                }
                                .mobileGlassButtonStyle().buttonBorderShape(.capsule)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Paste key passphrase")
                            }
                        }
                    } else {
                        SecureField(profile == nil ? "SSH password" : "New password (optional)", text: $secret)
                            .textContentType(.password)
                    }
                } header: { Text("Device-only credential") } footer: {
                    Text(profile == nil
                        ? "Stored in this iPhone's Keychain, not in machine settings or iCloud. OpenSSH Ed25519 keys can be pasted or imported."
                        : "Leave the credential unchanged to keep its existing Keychain item. Changing authentication requires a new key or password.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if profile != nil {
                    Section {
                        Button("Remove saved machine", role: .destructive) { confirmRemove = true }
                            .mobileGlassButtonStyle().buttonBorderShape(.capsule).frame(minHeight: 44)
                    } footer: { Text("Removes this connection and its credential only. Host sessions keep running.") }
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
                bridgePath = profile.bridgePath; hostPublicKey = profile.hostPublicKey; authentication = profile.authentication
            }
            .onChange(of: authentication) { _, _ in secret = ""; keyPassphrase = "" }
            .fileImporter(isPresented: $importingKey, allowedContentTypes: [.plainText, .data]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? 0) <= MachineKeyCredential.maximumBytes else { throw MachineKeyCredentialError.tooLarge }
                    let imported = try String(contentsOf: url, encoding: .utf8)
                    acceptPrivateKey(imported)
                } catch { self.error = error.localizedDescription }
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

    /// File import and system paste use the same validation without displaying the private key.
    private func acceptPrivateKey(_ text: String) {
        guard authentication == "key" else { return }
        do {
            let key = try MachineKeyCredential(privateKey: text)
            if secret != key.privateKey { keyPassphrase = "" }
            secret = key.privateKey
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func saveMachine() {
        do {
            let address = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty, !address.isEmpty, !username.isEmpty,
                  !address.contains(where: { $0.isWhitespace }),
                  let sshPort = Int(port), (1...65535).contains(sshPort) else {
                throw MachineFormError.invalid("Add a name, Tailscale address, SSH username and valid port.")
            }
            let pin = hostPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = pin.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 2, fields[0] == "ssh-ed25519", Data(base64Encoded: String(fields[1])) != nil else {
                throw MachineFormError.invalid("Paste a verified ssh-ed25519 host public key, including the key type.")
            }
            if profile == nil || profile?.authentication != authentication {
                guard !secret.isEmpty else { throw MachineFormError.invalid("Add an SSH credential for this authentication type.") }
            }
            if !secret.isEmpty {
                let credential: String
                if authentication == "key" {
                    credential = try MachineKeyCredential(privateKey: secret).keychainSecret(passphrase: keyPassphrase)
                } else { credential = secret }
                try MachineSecretStore.saveSecret(credential, machineId: machineId)
            }
            let updated = MachineProfile(id: machineId, name: displayName, hostname: address, port: sshPort,
                username: username, herdrSession: herdrSession, bridgePath: bridgePath,
                hostPublicKey: pin, authentication: authentication)
            try machines.saveMachine(updated)
            sessions.forgetMachine(machineId)
            secret = ""; keyPassphrase = ""
            dismiss()
            Task { await sessions.refreshMachine(updated) }
        } catch { self.error = error.localizedDescription }
    }
}

enum MachineFormError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
