import Foundation
import Security

/// SSH private keys/passwords are device-only Keychain items, never UserDefaults or Git.
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

    static func saveSecret(_ secret: String, machineId: UUID) throws {
        let query = itemQuery(machineId)
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            attributes.forEach { newItem[$0.key] = $0.value }
            let created = SecItemAdd(newItem as CFDictionary, nil)
            guard created == errSecSuccess else { throw CredentialError.keychain(created) }
        } else if status != errSecSuccess { throw CredentialError.keychain(status) }
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
        case .missing: return "No SSH credential saved. Edit this machine to add its key or password."
        case .keychain(let status): return "Keychain could not access the SSH credential (\(status)). Unlock the iPhone and try again."
        }
    }
}
