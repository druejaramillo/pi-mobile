import SwiftUI
import SafariServices

/// In-app browser login registers pi-mobile as a separate tailnet device; it never requests an admin token.
struct TailscaleAccountSection: View {
    @EnvironmentObject private var tailscale: TailscaleService
    @Environment(\.scenePhase) private var scenePhase
    @State private var loginRequest: TailscaleLoginRequest?

    var body: some View {
        Section {
            LabeledContent("Connection", value: tailscale.statusTitle)
            if let name = tailscale.tailnetName { LabeledContent("Tailnet", value: name) }
            if tailscale.statusTitle != "Connected" {
                Button(tailscale.busy ? "Preparing sign-in…" : "Sign in to Tailscale", systemImage: "network") {
                    Task { loginRequest = await tailscale.signIn() }
                }
                .mobileGlassButtonStyle(prominent: true).buttonBorderShape(.capsule).frame(minHeight: 44)
                .disabled(tailscale.busy)
            }
            Button("Check Tailscale connection", systemImage: "arrow.clockwise") {
                Task { await tailscale.refreshStatus() }
            }
            .mobileGlassButtonStyle().buttonBorderShape(.capsule).frame(minHeight: 44)
            .disabled(tailscale.busy)
            if tailscale.busy { ProgressView().accessibilityLabel("Preparing Tailscale sign-in") }
            if let error = tailscale.errorMessage { Text(error).foregroundStyle(.red) }
        } header: { Text("Tailscale") } footer: {
            Text("Sign in once for Pi Mobile. It appears as a separate pi-mobile device in your tailnet and verifies host keys automatically. This doesn't change the Tailscale VPN app or your host settings.")
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { loginRequest = nil } }
        .sheet(item: $loginRequest, onDismiss: { Task { await tailscale.refreshStatus() } }) { request in
            TailscaleSignInBrowser(url: request.url)
                .ignoresSafeArea()
        }
    }
}

/// Safari owns identity-provider navigation and cookies; the app only receives local node status.
private struct TailscaleSignInBrowser: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: { dismiss() }) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onFinish() }
    }
}
