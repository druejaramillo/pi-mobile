import Foundation
import PiMobileCore
import XCTest

/// New machines use keyless Tailscale SSH without changing persisted legacy logins or host pins.
final class MachineProfileTests: XCTestCase {
    func testNewMachineDefaultsToKeylessTailscaleSSH() {
        let profile = MachineProfile(name: "Test machine", hostname: "test-host", username: "test")
        XCTAssertEqual(profile.authentication, "tailscale")
        XCTAssertEqual(profile.port, 22)
        XCTAssertFalse(profile.requiresSSHCredential)
    }

    func testTailscaleProfileRoundTripPreservesIdentityAndHostPin() throws {
        let profile = MachineProfile(name: "Test machine", hostname: "test-host", username: "test",
            hostPublicKey: "test-only-public-pin")
        let decoded = try JSONDecoder().decode(MachineProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertFalse(decoded.requiresSSHCredential)
        XCTAssertEqual(decoded.hostPublicKey, "test-only-public-pin")
    }

    func testLegacyProfilesKeepTheirAuthenticationAndCredentialRequirement() throws {
        for authentication in ["key", "password", "key+password"] {
            let wire = """
                {"id":"00000000-0000-0000-0000-000000000001","name":"Saved machine",
                "hostname":"saved-host","port":2222,"username":"saved-user","herdrSession":"work",
                "bridgePath":"host/bridge-cli.mjs","hostPublicKey":"test-only-saved-pin",
                "authentication":"\(authentication)"}
                """
            let profile = try JSONDecoder().decode(MachineProfile.self, from: Data(wire.utf8))
            XCTAssertEqual(profile.id.uuidString, "00000000-0000-0000-0000-000000000001")
            XCTAssertEqual(profile.authentication, authentication)
            XCTAssertTrue(profile.requiresSSHCredential)
            XCTAssertEqual(profile.port, 2222)
            XCTAssertEqual(profile.herdrSession, "work")
            XCTAssertEqual(profile.hostPublicKey, "test-only-saved-pin")
        }
    }
}
