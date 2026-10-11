import Foundation
import XCTest
@testable import PiMobileCore

/// Synthetic authenticated-status fixtures cover exact destination matching, never network trust-on-first-use.
final class TailscalePeerIdentityTests: XCTestCase {
    func testExactDNSAndScopedShortNameAndIPResolveSamePeer() throws {
        let status = try decodeStatus()
        for address in ["work.tail-test.ts.net", "WORK.tail-test.ts.net.", "work", "100.80.0.2", "fd7a:115c:a1e0::2"] {
            let peer = try status.verifiedPeer(for: address)
            XCTAssertEqual(peer.id, "test-peer")
            XCTAssertEqual(peer.hostPublicKeys, ["ssh-ed25519 test-only-key"])
            XCTAssertEqual(peer.addresses.first, "100.80.0.2")
        }
    }

    func testPartialNamesHostNameAliasesAndUnrelatedSuffixesAreNotTrusted() throws {
        let status = try decodeStatus()
        for address in ["wor", "arbitrary-hostname", "work.other.ts.net", "100.80.0.3", "https://work.tail-test.ts.net"] {
            XCTAssertThrowsError(try status.verifiedPeer(for: address)) { XCTAssertEqual($0 as? TailscaleIdentityError, .missingPeer) }
        }
    }

    func testShortNameCannotMatchSharedPeerOutsideCurrentTailnet() throws {
        let status = try decodeStatus(dns: "work.shared.ts.net.")
        XCTAssertThrowsError(try status.verifiedPeer(for: "work")) { XCTAssertEqual($0 as? TailscaleIdentityError, .missingPeer) }
        XCTAssertEqual(try status.verifiedPeer(for: "work.shared.ts.net").id, "test-peer")
    }

    func testDuplicateExactMatchesFailClosed() throws {
        let status = try decodeStatus(duplicate: true)
        XCTAssertThrowsError(try status.verifiedPeer(for: "100.80.0.2")) { XCTAssertEqual($0 as? TailscaleIdentityError, .ambiguousPeer) }
    }

    func testMissingHostKeysFailClosed() throws {
        let status = try decodeStatus(keys: [])
        XCTAssertThrowsError(try status.verifiedPeer(for: "work")) { XCTAssertEqual($0 as? TailscaleIdentityError, .missingHostKeys) }
    }

    func testExpiredAndHistoricalPeersFailClosed() throws {
        XCTAssertThrowsError(try decodeStatus(expired: true).verifiedPeer(for: "work")) {
            XCTAssertEqual($0 as? TailscaleIdentityError, .expiredPeer)
        }
        XCTAssertThrowsError(try decodeStatus(inNetworkMap: false).verifiedPeer(for: "work")) {
            XCTAssertEqual($0 as? TailscaleIdentityError, .missingPeer)
        }
    }

    func testUnreadyNodeCannotSupplyTrustedKeys() throws {
        for (state, error) in [("NeedsLogin", TailscaleIdentityError.signInRequired),
                               ("NeedsMachineAuth", .approvalRequired), ("Starting", .unavailable), ("Stopped", .unavailable)] {
            XCTAssertThrowsError(try decodeStatus(state: state).verifiedPeer(for: "work")) {
                XCTAssertEqual($0 as? TailscaleIdentityError, error)
            }
        }
    }

    func testMissingOrExpiredLocalIdentityCannotSupplyTrustedKeys() throws {
        let status = """
            {"BackendState":"Running","AuthURL":"","Peer":{}}
            """
        let decoded = try JSONDecoder().decode(TailscaleNodeStatus.self, from: Data(status.utf8))
        XCTAssertThrowsError(try decoded.verifiedPeer(for: "work")) {
            XCTAssertEqual($0 as? TailscaleIdentityError, .unavailable)
        }
        XCTAssertThrowsError(try decodeStatus(selfExpired: true).verifiedPeer(for: "work")) {
            XCTAssertEqual($0 as? TailscaleIdentityError, .signInRequired)
        }
    }

    func testActualLowercaseKeyFieldAndLegacyStatusFieldDecode() throws {
        for field in ["sshHostKeys", "SSH_HostKeys"] {
            XCTAssertEqual(try decodeStatus(keyField: field).verifiedPeer(for: "work").hostPublicKeys,
                           ["ssh-ed25519 test-only-key"])
        }
    }

    func testLookupDoesNotRewriteSavedTailscaleOrLegacyProfiles() throws {
        for authentication in ["tailscale", "password", "key", "key+password"] {
            let saved = MachineProfile(name: "Saved", hostname: "work", username: "test",
                hostPublicKey: "previously-saved-pin", authentication: authentication)
            let before = try JSONEncoder().encode(saved)
            _ = try decodeStatus().verifiedPeer(for: saved.hostname)
            XCTAssertEqual(try JSONDecoder().decode(MachineProfile.self, from: before), saved)
            XCTAssertEqual(saved.hostPublicKey, "previously-saved-pin")
        }
    }

    private func decodeStatus(state: String = "Running", dns: String = "work.tail-test.ts.net.",
                              keys: [String] = ["ssh-ed25519 test-only-key"], keyField: String = "sshHostKeys",
                              expired: Bool = false, inNetworkMap: Bool = true, duplicate: Bool = false,
                              selfExpired: Bool = false) throws -> TailscaleNodeStatus {
        let peer: [String: Any] = ["ID": "test-peer", "DNSName": dns, "HostName": "arbitrary-hostname",
                                  "TailscaleIPs": ["100.80.0.2", "fd7a:115c:a1e0::2"], keyField: keys,
                                  "Expired": expired, "InNetworkMap": inNetworkMap]
        var peers = ["nodekey:test-only": peer]
        if duplicate { peers["nodekey:duplicate-only"] = peer }
        let document: [String: Any] = ["BackendState": state, "AuthURL": "",
            "CurrentTailnet": ["Name": "test-only", "MagicDNSSuffix": "tail-test.ts.net"], "Peer": peers,
            "Self": ["ID": "test-local", "DNSName": "pi-mobile.tail-test.ts.net.",
                     "TailscaleIPs": ["100.80.0.1"], "Expired": selfExpired]]
        return try JSONDecoder().decode(TailscaleNodeStatus.self, from: JSONSerialization.data(withJSONObject: document))
    }
}
