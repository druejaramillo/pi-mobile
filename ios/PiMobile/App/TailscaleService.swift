import Foundation
import Combine
import PiMobileCore

/// One in-app tailnet identity supplies both trusted host keys and direct SSH routing.
@MainActor
final class TailscaleService: ObservableObject {
    @Published private(set) var statusTitle = "Not connected"
    @Published private(set) var tailnetName: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var busy = false
    private let runtime = TailscaleRuntime()
    private var active = true

    func signIn() async -> TailscaleLoginRequest? {
        guard active, !busy else { return nil }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let url = try await runtime.loginURL()
            guard active else { return nil }
            if let url {
                statusTitle = "Finish sign-in"
                return TailscaleLoginRequest(url: url)
            }
            await refreshStatus()
        } catch { publish(error) }
        return nil
    }

    func refreshStatus() async {
        guard active else { return }
        do { apply(try await runtime.status()) }
        catch { publish(error) }
    }

    func validateProfile(_ profile: MachineProfile) async throws {
        let destination = try await resolve(profile)
        _ = try SSHBridgeConfiguration(profile: profile, trustedHostKeys: destination.peer.hostPublicKeys)
    }

    func prepareConnection(_ profile: MachineProfile) async throws -> (SSHBridgeConfiguration, TailscaleSSHSocket) {
        let destination = try await resolve(profile)
        let configuration = try SSHBridgeConfiguration(profile: profile, trustedHostKeys: destination.peer.hostPublicKeys)
        let socket = try await runtime.dial(destination)
        guard active else { socket.close(); throw TailscaleIdentityError.unavailable }
        return (configuration, socket)
    }

    func suspend() async {
        active = false
        statusTitle = "Not connected"
        await runtime.suspend()
    }

    func resume() async {
        active = true
        await runtime.resume()
    }

    private func resolve(_ profile: MachineProfile) async throws -> TailscaleResolvedPeer {
        guard active, profile.authentication == "tailscale", profile.port == 22 else {
            throw TailscaleIdentityError.unavailable
        }
        do {
            let destination = try await runtime.resolve(profile.hostname)
            guard active else { throw TailscaleIdentityError.unavailable }
            apply(destination.status)
            return destination
        } catch { publish(error); throw error }
    }

    private func apply(_ status: TailscaleNodeStatus) {
        guard active else { return }
        tailnetName = status.currentTailnet?.name
        switch status.backendState {
        case "Running":
            if status.selfPeer?.expired == true { statusTitle = "Sign-in required" }
            else if (try? status.requireRunning()) != nil { statusTitle = "Connected" }
            else { statusTitle = "Not connected" }
        case "NeedsLogin": statusTitle = "Sign-in required"
        case "NeedsMachineAuth": statusTitle = "Device approval required"
        default: statusTitle = "Not connected"
        }
        errorMessage = nil
    }

    private func publish(_ error: Error) {
        guard active else { return }
        // Only our bounded errors reach the UI; never display raw LocalAPI bodies or C diagnostics.
        let failure = error as? TailscaleIdentityError ?? .unavailable
        switch failure {
        case .signInRequired: statusTitle = "Sign-in required"
        case .approvalRequired: statusTitle = "Device approval required"
        case .unavailable: statusTitle = "Not connected"
        default: break // A missing remote peer does not mean the local node needs to log in again.
        }
        errorMessage = failure.localizedDescription
    }
}

/// Login URLs are temporary foreground UI state, never a profile or diagnostic field.
struct TailscaleLoginRequest: Identifiable {
    let id = UUID()
    let url: URL
}
