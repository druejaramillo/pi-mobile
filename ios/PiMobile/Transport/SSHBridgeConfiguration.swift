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
    case tailscaleSSHUnavailable
    case hostIdentityMismatch
    case hostBridgeExited(Int)
    case disconnected
    case requestDeadline
    case protocolViolation(String)
    case capacityExceeded
    case invalidReview

    public var errorDescription: String? {
        switch self {
        case .invalidProfile(let reason): return "SSH profile invalid: \(reason)"
        case .invalidSecret: return "Saved SSH credential invalid: switch this machine to Tailscale SSH after enabling it on the host."
        case .tailscaleSSHUnavailable: return "Tailscale SSH login failed: enable SSH on the host and allow this username with an accept rule in the tailnet policy. Interactive check-mode sign-in is not supported."
        case .hostIdentityMismatch: return "SSH host identity mismatch: the server key does not match this machine's trusted identity. Check the destination and its Tailscale SSH setup; no connection was accepted."
        case .hostBridgeExited(let status): return "Host bridge stopped (exit \(status)): check that the bridge is installed at the saved path, the Herdr session exists, and Node 22.19+ and Herdr are available in this SSH user's noninteractive PATH. Delivery may be uncertain; reconnect for fresh state before acting again. Pi Mobile does not install the bridge or start host sessions."
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
    let hostKeys: Set<NIOSSHPublicKey>
    let command: String

    /// Coordination keys are accepted only for Tailscale SSH; legacy profiles keep their exact saved pin.
    init(profile: MachineProfile, trustedHostKeys: [String]? = nil) throws {
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
        if let trustedHostKeys {
            guard profile.authentication == "tailscale", profile.port == 22, trustedHostKeys.count <= 32 else {
                throw SSHBridgeError.invalidProfile("coordination host keys require Tailscale SSH on port 22")
            }
            let supported = trustedHostKeys.filter { Self.supportedHostKey($0) }
            guard !supported.isEmpty else { throw TailscaleIdentityError.missingHostKeys }
            hostKeys = try Set(supported.map { try Self.parseHostKey($0) })
        } else {
            hostKeys = [try Self.parseHostKey(profile.hostPublicKey)]
        }
        let path = try Self.bridgePathShellArgument(profile.bridgePath)
        command = "exec node \(path) --session \(Self.quoteShellArgument(profile.herdrSession))"
        self.profile = profile
    }

    private static func supportedHostKey(_ value: String) -> Bool {
        guard let algorithm = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first else { return false }
        return ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521"].contains(String(algorithm))
    }

    private static func parseHostKey(_ value: String) throws -> NIOSSHPublicKey {
        let pin = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeArgument(pin, maximumBytes: 16384), supportedHostKey(pin) else {
            throw SSHBridgeError.invalidProfile("a full supported OpenSSH host public key is required, not a fingerprint or known_hosts line")
        }
        do { return try NIOSSHPublicKey(openSSHPublicKey: pin) }
        catch { throw SSHBridgeError.invalidProfile("OpenSSH host public key cannot be parsed") }
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

/// Existing Keychain secrets may contain this JSON bundle for legacy encrypted-key or key/password login.
private struct SSHCredentialBundle: Decodable {
    let privateKey: String?
    let password: String?
    let passphrase: String?
}

extension SSHBridgeConfiguration {
    func authenticationMethod(secret: String? = nil) throws -> SSHAuthenticationMethod {
        if profile.authentication == "tailscale" {
            // The tailnet already authenticates this device; never offer a saved key or password.
            return .custom(SSHTailscaleAuthentication(username: profile.username))
        }
        guard ["key", "password", "key+password"].contains(profile.authentication) else {
            throw SSHBridgeError.invalidProfile("authentication must be tailscale, key, password or key+password")
        }
        guard let secret, !secret.isEmpty,
              secret.utf8.count <= MachineKeyCredential.maximumBytes else { throw SSHBridgeError.invalidSecret }
        if profile.authentication == "password" {
            return .passwordBased(username: profile.username, password: secret)
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
                sshEd25519: try MachineKeyCredential(privateKey: keyText).privateKey,
                decryptionKey: passphrase.map { Data($0.utf8) }
            )
            if profile.authentication == "key" { return .ed25519(username: profile.username, privateKey: key) }
            guard let password, !password.isEmpty else { throw SSHBridgeError.invalidSecret }
            return .custom(SSHKeyPasswordAuthentication(username: profile.username, privateKey: key, password: password))
        } catch { throw SSHBridgeError.invalidSecret }
    }
}

/// Keyless Tailscale SSH offers `none` once; rejection never falls back to a key or password.
private final class SSHTailscaleAuthentication: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private var offeredIdentity = false

    init(username: String) { self.username = username }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard !offeredIdentity else {
            nextChallengePromise.fail(SSHBridgeError.tailscaleSSHUnavailable)
            return
        }
        offeredIdentity = true
        // `none` is valid before the server advertises authentication methods, including an empty set.
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
            username: username, serviceName: "", offer: .none
        ))
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
