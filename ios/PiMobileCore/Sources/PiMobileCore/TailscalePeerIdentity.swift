import Foundation

/// Trusted lookup failures never permit a scanned host key or an OS-network fallback.
public enum TailscaleIdentityError: Error, LocalizedError, Equatable {
    case signInRequired, approvalRequired, unavailable, missingPeer, ambiguousPeer, expiredPeer, missingHostKeys

    public var errorDescription: String? {
        switch self {
        case .signInRequired: return "Tailscale sign-in required: connect Pi Mobile to your tailnet in Settings."
        case .approvalRequired: return "Tailscale device approval required: approve pi-mobile in your tailnet, then check the connection again."
        case .unavailable: return "Tailscale connection unavailable: check Pi Mobile's Tailscale connection and try again."
        case .missingPeer: return "Tailscale machine not found: use its exact MagicDNS name or tailnet IP and check the device's access policy."
        case .ambiguousPeer: return "Tailscale machine identity is ambiguous: use its full MagicDNS name or tailnet IP."
        case .expiredPeer: return "Tailscale machine identity expired: renew that device's Tailscale sign-in before connecting."
        case .missingHostKeys: return "Tailscale host keys unavailable: enable Tailscale SSH on that machine, then refresh. No unverified key will be accepted."
        }
    }
}

/// Authenticated local node status, decoded only from libtailscale's in-memory LocalAPI.
public struct TailscaleNodeStatus: Decodable, Sendable {
    public let backendState: String
    public let authURL: String?
    public let currentTailnet: Tailnet?
    public let selfPeer: TailscalePeerIdentity?
    public let peers: [String: TailscalePeerIdentity]?

    public struct Tailnet: Decodable, Sendable {
        public let name: String
        public let magicDNSSuffix: String
        enum CodingKeys: String, CodingKey { case name = "Name", magicDNSSuffix = "MagicDNSSuffix" }
    }

    enum CodingKeys: String, CodingKey {
        case backendState = "BackendState", authURL = "AuthURL", currentTailnet = "CurrentTailnet"
        case selfPeer = "Self", peers = "Peer"
    }

    /// Match exactly one current peer; short names are scoped to this authenticated tailnet's DNS suffix.
    public func verifiedPeer(for destination: String) throws -> TailscalePeerIdentity {
        try requireRunning()
        let address = Self.normalizedName(destination)
        guard !address.isEmpty else { throw TailscaleIdentityError.missingPeer }
        let suffix = currentTailnet.map { Self.normalizedName($0.magicDNSSuffix) } ?? ""
        let matches = (peers ?? [:]).values.filter { peer in
            let dns = Self.normalizedName(peer.dnsName)
            return peer.addresses.contains(where: { $0.lowercased() == address }) || dns == address ||
                (!address.contains(".") && !address.contains(":") && !suffix.isEmpty && dns == "\(address).\(suffix)")
        }
        guard !matches.isEmpty else { throw TailscaleIdentityError.missingPeer }
        guard matches.count == 1, let peer = matches.first else { throw TailscaleIdentityError.ambiguousPeer }
        guard peer.inNetworkMap == true else { throw TailscaleIdentityError.missingPeer }
        guard peer.expired != true else { throw TailscaleIdentityError.expiredPeer }
        guard !peer.id.isEmpty, !peer.addresses.isEmpty else { throw TailscaleIdentityError.missingPeer }
        guard !peer.hostPublicKeys.isEmpty else { throw TailscaleIdentityError.missingHostKeys }
        return peer
    }

    /// Sign-in and device approval are separate from SSH check-mode authentication.
    public func requireRunning() throws {
        switch backendState {
        case "NeedsLogin": throw TailscaleIdentityError.signInRequired
        case "NeedsMachineAuth": throw TailscaleIdentityError.approvalRequired
        case "Running":
            guard let selfPeer, !selfPeer.id.isEmpty, !selfPeer.addresses.isEmpty else {
                throw TailscaleIdentityError.unavailable
            }
            guard selfPeer.expired != true else { throw TailscaleIdentityError.signInRequired }
        default: throw TailscaleIdentityError.unavailable
        }
    }

    private static func normalizedName(_ value: String) -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name.hasSuffix(".") ? String(name.dropLast()) : name
    }
}

/// Host identity and numeric dial address come from the same authenticated coordination record.
public struct TailscalePeerIdentity: Decodable, Sendable, Equatable {
    public let id: String
    public let dnsName: String
    public let addresses: [String]
    public let hostPublicKeys: [String]
    public let inNetworkMap: Bool?
    public let expired: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "ID", dnsName = "DNSName", addresses = "TailscaleIPs"
        case hostPublicKeys = "sshHostKeys", legacyHostPublicKeys = "SSH_HostKeys"
        case inNetworkMap = "InNetworkMap", expired = "Expired"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        dnsName = try values.decode(String.self, forKey: .dnsName)
        addresses = try values.decodeIfPresent([String].self, forKey: .addresses) ?? []
        hostPublicKeys = try values.decodeIfPresent([String].self, forKey: .hostPublicKeys)
            ?? values.decodeIfPresent([String].self, forKey: .legacyHostPublicKeys) ?? []
        inNetworkMap = try values.decodeIfPresent(Bool.self, forKey: .inNetworkMap)
        expired = try values.decodeIfPresent(Bool.self, forKey: .expired)
    }
}
