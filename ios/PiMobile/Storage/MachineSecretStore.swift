import Foundation
import Security

/// Legacy SSH credentials remain device-only Keychain items; new Tailscale SSH profiles never access them.
enum MachineSecretStore {
    private static let service = "com.druejaramillo.pi-mobile.ssh"

    static func readSecret(machineId: UUID) throws -> String {
        var query = itemQuery(machineId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw CredentialError.missing }
        guard status == errSecSuccess, let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else { throw CredentialError.keychain(status) }
        return secret
    }

    static func deleteSecret(machineId: UUID) throws {
        let status = SecItemDelete(itemQuery(machineId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.keychain(status) }
    }

    private static func itemQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString, kSecAttrSynchronizable as String: false]
    }
}

enum CredentialError: LocalizedError {
    case missing, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .missing: return "No saved SSH credential. Edit this machine to switch to Tailscale SSH after enabling it on the host."
        case .keychain(let status): return "Keychain could not access the SSH credential (\(status)). Unlock the iPhone and try again."
        }
    }
}
