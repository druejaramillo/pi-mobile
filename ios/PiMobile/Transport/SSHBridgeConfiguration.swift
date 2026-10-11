import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH
import PiMobileCore

/// SSH transport failures never imply that an uncertain command is safe to retry.
public enum SSHBridgeError: Error, LocalizedError {
    case invalidProfile(String)
    case invalidSecret
    case disconnected
    case requestDeadline
    case protocolViolation(String)
    case capacityExceeded
    case invalidReview

    public var errorDescription: String? {
        switch self {
        case .invalidProfile(let reason): return "SSH profile invalid: \(reason)"
        case .invalidSecret: return "SSH secret invalid: provide a password or an OpenSSH Ed25519 private key with its passphrase."
        case .disconnected: return "SSH bridge disconnected: command delivery may be uncertain; refresh before acting again."
        case .requestDeadline: return "SSH bridge deadline exceeded: command delivery may be uncertain; do not replay it automatically."
        case .protocolViolation(let reason): return "SSH bridge protocol invalid: \(reason)"
        case .capacityExceeded: return "SSH bridge capacity exceeded: detach or reconnect explicitly to obtain fresh state."
        case .invalidReview: return "Plannotator review invalid: an advertised loopback HTTP URL and explicit port are required."
        }
    }
}

/// Validated SSH settings keep user-supplied strings out of unquoted shell syntax.
struct SSHBridgeConfiguration {
    let profile: MachineProfile
    let hostKey: NIOSSHPublicKey
    let command: String

    init(profile: MachineProfile) throws {
        guard (1...65535).contains(profile.port), !profile.hostname.isEmpty,
              profile.hostname.utf8.count <= 253,
              profile.hostname.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-").contains($0)
              }), !profile.hostname.hasPrefix("-"),
              Self.isSafeArgument(profile.username, maximumBytes: 256),
              !profile.username.contains(where: { $0.isWhitespace }),
              Self.isSafeArgument(profile.herdrSession, maximumBytes: 256),
              !profile.herdrSession.hasPrefix("-") else {
            throw SSHBridgeError.invalidProfile("hostname, port, username or Herdr session")
        }
        let pin = profile.hostPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeArgument(pin, maximumBytes: 16384),
              let algorithm = pin.split(separator: " ").first,
              ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521"].contains(String(algorithm)) else {
            throw SSHBridgeError.invalidProfile("pin a full supported OpenSSH host public key, not a fingerprint or known_hosts line")
        }
        do { hostKey = try NIOSSHPublicKey(openSSHPublicKey: pin) }
        catch { throw SSHBridgeError.invalidProfile("OpenSSH host public key cannot be parsed") }
        let path = try Self.bridgePathShellArgument(profile.bridgePath)
        command = "exec node \(path) --session \(Self.quoteShellArgument(profile.herdrSession))"
        self.profile = profile
    }

    private static func isSafeArgument(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes &&
            !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func bridgePathShellArgument(_ value: String) throws -> String {
        guard isSafeArgument(value, maximumBytes: 4096), !value.hasPrefix("~") else {
            throw SSHBridgeError.invalidProfile("bridge path must be absolute or relative to the remote home directory; tilde expansion is not supported")
        }
        var components: [String] = []
        for component in value.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else {
                    throw SSHBridgeError.invalidProfile("bridge path escapes its configured root")
                }
                components.removeLast()
            } else { components.append(String(component)) }
        }
        guard !components.isEmpty else { throw SSHBridgeError.invalidProfile("bridge path is not a file") }
        let path = components.joined(separator: "/")
        if value.hasPrefix("/") { return quoteShellArgument("/" + path) }
        // Expand only the SSH server's HOME; the profile path remains one safely quoted argument.
        return "\"${HOME:?SSH login has no home directory}\"/" + quoteShellArgument(path)
    }

    private static func quoteShellArgument(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// The one-string facade accepts this JSON bundle for encrypted keys or key/password authentication.
private struct SSHCredentialBundle: Decodable {
    let privateKey: String?
    let password: String?
    let passphrase: String?
}

extension SSHBridgeConfiguration {
    func authenticationMethod(secret: String) throws -> SSHAuthenticationMethod {
        guard !secret.isEmpty, secret.utf8.count <= 128 * 1024 else { throw SSHBridgeError.invalidSecret }
        if profile.authentication == "password" {
            return .passwordBased(username: profile.username, password: secret)
        }
        guard profile.authentication == "key" || profile.authentication == "key+password" else {
            throw SSHBridgeError.invalidProfile("authentication must be key, password or key+password")
        }
        do {
            let keyText: String
            let passphrase: String?
            let password: String?
            if secret.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") {
                keyText = secret; passphrase = nil; password = nil
            } else {
                let bundle = try JSONDecoder().decode(SSHCredentialBundle.self, from: Data(secret.utf8))
                guard let key = bundle.privateKey, !key.isEmpty else { throw SSHBridgeError.invalidSecret }
                keyText = key; passphrase = bundle.passphrase; password = bundle.password
            }
            let key = try Curve25519.Signing.PrivateKey(
                sshEd25519: keyText, decryptionKey: passphrase.map { Data($0.utf8) }
            )
            if profile.authentication == "key" { return .ed25519(username: profile.username, privateKey: key) }
            guard let password, !password.isEmpty else { throw SSHBridgeError.invalidSecret }
            return .custom(SSHKeyPasswordAuthentication(username: profile.username, privateKey: key, password: password))
        } catch { throw SSHBridgeError.invalidSecret }
    }
}

/// Authentication offers run only on the SSH event loop; each credential is offered at most once.
private final class SSHKeyPasswordAuthentication: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let privateKey: NIOSSHPrivateKey
    private let password: String
    private var offeredKey = false
    private var offeredPassword = false

    init(username: String, privateKey: Curve25519.Signing.PrivateKey, password: String) {
        self.username = username
        self.privateKey = NIOSSHPrivateKey(ed25519Key: privateKey)
        self.password = password
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        if !offeredKey, availableMethods.contains(.publicKey) {
            offeredKey = true
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username, serviceName: "", offer: .privateKey(.init(privateKey: privateKey))
            ))
        } else if !offeredPassword, availableMethods.contains(.password) {
            offeredPassword = true
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username, serviceName: "", offer: .password(.init(password: password))
            ))
        } else {
            nextChallengePromise.fail(SSHClientError.allAuthenticationOptionsFailed)
        }
    }
}
