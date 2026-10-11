import Foundation
import PiMobileCore
import XCTest

/// Tests legacy credential preparation without Keychain access or real SSH keys.
final class MachineKeyCredentialTests: XCTestCase {
    // Synthetic armor/base64 only; cryptographic key parsing remains the SSH transport's responsibility.
    private let privateKey = "-----BEGIN OPENSSH PRIVATE KEY-----\nZml4dHVyZQ==\n-----END OPENSSH PRIVATE KEY-----"

    func testImportedAndPastedKeysNormalizeLineEndingsAndSurroundingWhitespace() throws {
        let imported = try MachineKeyCredential(privateKey: privateKey + "\n")
        for separator in ["\n", "\r\n", "\r"] {
            let pasted = " \t\n" + privateKey.replacingOccurrences(of: "\n", with: separator) + "\n\t "
            let credential = try MachineKeyCredential(privateKey: pasted)
            XCTAssertEqual(credential.privateKey, imported.privateKey)
            XCTAssertEqual(try credential.keychainSecret(), privateKey)
        }
    }

    func testPublicTruncatedAndMalformedKeysAreRejectedWithoutEchoingInput() {
        let invalidKeys = [
            "", "ssh-ed25519 Zml4dHVyZQ== test-only",
            "-----BEGIN OPENSSH PRIVATE KEY-----\nZml4dHVyZQ==",
            "-----BEGIN OPENSSH PRIVATE KEY-----\n-----END OPENSSH PRIVATE KEY-----",
            "-----BEGIN OPENSSH PRIVATE KEY-----\n!invalid!\n-----END OPENSSH PRIVATE KEY-----",
            "untrusted prefix\n" + privateKey, privateKey + "\nuntrusted suffix",
            privateKey.replacingOccurrences(of: "OPENSSH", with: "RSA"),
        ]
        for input in invalidKeys {
            XCTAssertThrowsError(try MachineKeyCredential(privateKey: input)) { error in
                guard case MachineKeyCredentialError.invalidPrivateKey = error else {
                    return XCTFail("Expected a private-key validation error.")
                }
                XCTAssertFalse(error.localizedDescription.contains("untrusted"))
                XCTAssertFalse(error.localizedDescription.contains("Zml4dHVyZQ=="))
            }
        }
    }

    func testPastedPassphraseKeepsWhitespaceUnicodeAndJSONEscapesExactly() throws {
        let passphrase = " \tclé 🔑 \"quoted\" \\ slash\n "
        let credential = try MachineKeyCredential(privateKey: privateKey)
        let secret = try credential.keychainSecret(passphrase: passphrase)
        let bundle = try JSONDecoder().decode(BridgeJSON.self, from: Data(secret.utf8))
        XCTAssertEqual(bundle["privateKey"]?.string, privateKey)
        XCTAssertEqual(bundle["passphrase"]?.string, passphrase)
        XCTAssertEqual(try credential.keychainSecret(passphrase: ""), privateKey)
    }

    func testPrivateKeyInputLimitCountsUTF8BytesBeforeNormalization() throws {
        let padding = MachineKeyCredential.maximumBytes - privateKey.utf8.count
        let atLimit = privateKey + String(repeating: " ", count: padding)
        XCTAssertEqual(try MachineKeyCredential(privateKey: atLimit).privateKey, privateKey)
        XCTAssertThrowsError(try MachineKeyCredential(privateKey: atLimit + "é")) { error in
            guard case MachineKeyCredentialError.tooLarge = error else {
                return XCTFail("Expected a byte-counted credential limit error.")
            }
        }
    }

    func testSavedSecretLimitIncludesKeyAndPassphraseBundleOverhead() throws {
        let credential = try MachineKeyCredential(privateKey: privateKey)
        let overhead = try credential.keychainSecret(passphrase: "x").utf8.count - 1
        let passphrase = String(repeating: "x", count: MachineKeyCredential.maximumBytes - overhead)
        XCTAssertEqual(try credential.keychainSecret(passphrase: passphrase).utf8.count, MachineKeyCredential.maximumBytes)
        XCTAssertThrowsError(try credential.keychainSecret(passphrase: passphrase + "x")) { error in
            guard case MachineKeyCredentialError.tooLarge = error else {
                return XCTFail("Expected a saved-secret limit error.")
            }
        }
    }

    func testSavedSecretLimitIncludesJSONEscapingExpansion() throws {
        let credential = try MachineKeyCredential(privateKey: privateKey)
        let passphrase = String(repeating: "\"\\\n", count: MachineKeyCredential.maximumBytes / 4)
        XCTAssertLessThan(passphrase.utf8.count, MachineKeyCredential.maximumBytes)
        XCTAssertThrowsError(try credential.keychainSecret(passphrase: passphrase)) { error in
            guard case MachineKeyCredentialError.tooLarge = error else {
                return XCTFail("Expected escaped JSON to count toward the saved-secret limit.")
            }
        }
    }
}
