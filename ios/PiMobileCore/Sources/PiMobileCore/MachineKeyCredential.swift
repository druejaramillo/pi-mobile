import Foundation

/// Prepares imported or pasted SSH private keys; transport still validates Ed25519 and decryption.
public struct MachineKeyCredential: Sendable {
    /// The SSH transport limit applies to the entire Keychain secret, including its JSON bundle.
    public static let maximumBytes = 128 * 1024

    /// Normalized OpenSSH text stays in memory until the user explicitly saves to Keychain.
    public let privateKey: String

    /// Checks the private key's armor and base64, not its algorithm or encrypted contents.
    public init(privateKey: String) throws {
        guard privateKey.utf8.count <= Self.maximumBytes else { throw MachineKeyCredentialError.tooLarge }
        let normalized = privateKey.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = normalized.components(separatedBy: "\n")
        guard lines.count >= 3,
              lines.first == "-----BEGIN OPENSSH PRIVATE KEY-----",
              lines.last == "-----END OPENSSH PRIVATE KEY-----",
              let payload = Data(base64Encoded: lines.dropFirst().dropLast().joined()),
              !payload.isEmpty else {
            throw MachineKeyCredentialError.invalidPrivateKey
        }
        self.privateKey = normalized
    }

    /// Preserves the passphrase verbatim and uses the SSH transport's existing secret format.
    public func keychainSecret(passphrase: String = "") throws -> String {
        guard passphrase.utf8.count <= Self.maximumBytes else { throw MachineKeyCredentialError.tooLarge }
        let secret: String
        if passphrase.isEmpty {
            secret = privateKey
        } else {
            let bundle = BridgeJSON.object(["privateKey": .string(privateKey), "passphrase": .string(passphrase)])
            secret = String(decoding: try JSONEncoder().encode(bundle), as: UTF8.self)
        }
        guard secret.utf8.count <= Self.maximumBytes else { throw MachineKeyCredentialError.tooLarge }
        return secret
    }
}

/// Credential validation errors never include the supplied private key or passphrase.
public enum MachineKeyCredentialError: Error, LocalizedError {
    case invalidPrivateKey, tooLarge

    /// Safe recovery instructions can be displayed without revealing credential contents.
    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Add a complete OpenSSH Ed25519 private key, including its BEGIN and END lines, not a public key."
        case .tooLarge:
            return "SSH key and passphrase are too large. The saved credential must be 128 KiB or smaller."
        }
    }
}
