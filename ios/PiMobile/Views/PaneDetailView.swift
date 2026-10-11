import SwiftUI
import PiMobileCore

/// Agent and terminal are two views of one existing terminal; opening either never starts Pi.
struct PaneDetailView: View {
    let profile: MachineProfile
    let pane: HerdrPane
    @ObservedObject var connection: SSHBridgeConnection
    @EnvironmentObject private var sessions: MobileSessionHub
    @EnvironmentObject private var dictation: ParakeetDictation
    @State private var surface = "Agent"
    @State private var attaching = false
    @State private var terminalWritable = false
    @State private var attachedTerminal = false
    @State private var controlAttemptFailed = false
    @State private var errorMessage: String?
    @State private var confirmTakeover = false
    @State private var confirmAbort = false
    @State private var reviewPresentation: ReviewPresentation?
    @State private var openingReview = false
    @State private var paneVisible = false
    @State private var paneSubscriptionOwner = UUID()

    private var location: PaneLocation { PaneLocation(machineId: profile.id, terminalId: pane.terminalId) }
    private var currentPane: HerdrPane { connection.topology?.panes.first { $0.terminalId == pane.terminalId } ?? pane }
    private var agent: PiAgentSnapshot? {
        guard connection.agent?.terminalId == pane.terminalId else { return nil }
        return connection.agent
    }

    var body: some View {
        VStack(spacing: 0) {
            if currentPane.agent == "pi" {
                MobilePaneSurfacePicker(selection: $surface)
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            if connection.state != "connected" {
                HStack {
                    Label("Disconnected", systemImage: "network.slash")
                    Spacer()
                    Button("Reconnect") { Task { await reconnectPane() } }
                        .mobileGlassButtonStyle().buttonBorderShape(.capsule)
                        .frame(minHeight: 44).disabled(attaching)
                }
                .font(.subheadline).padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            if let errorMessage {
                HStack(alignment: .top) {
                    Text(errorMessage).font(.footnote).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss error", systemImage: "xmark") { self.errorMessage = nil }
                        .mobileGlassHeaderControl(symbolOnly: true)
                }.padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
            if surface == "Agent" && currentPane.agent == "pi" {
                if let agent {
                    AgentConversationView(snapshot: agent, connection: connection,
                        location: location, drafts: sessions.drafts)
                } else if attaching {
                    ProgressView("Attaching to the running agent…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Use the real terminal", systemImage: "terminal")
                    } description: {
                        Text("This Pi process has no compatible mobile bridge attached. Its existing TUI is still available.")
                    } actions: {
                        Button("Open terminal") { surface = "Terminal" }
                            .mobileGlassButtonStyle(prominent: true)
                            .controlSize(.large).buttonBorderShape(.capsule)
                    }
                }
            } else {
                terminalSurface
            }
        }
        .navigationTitle(currentPane.title.isEmpty ? "Terminal" : currentPane.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.selection, trigger: surface)
        .toolbar {
            if !currentPane.reviews.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(currentPane.reviews) { review in
                            Button("Open review") { Task { await openReview(review) } }
                        }
                    } label: { Label("Reviews", systemImage: "doc.text.magnifyingglass") }
                    .menuStyle(.button)
                    .mobileGlassHeaderControl(symbolOnly: true)
                    .disabled(openingReview || connection.state != "connected")
                }.mobileGlassHeaderItem()
            }
            if agent?.status == "working" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stop agent", systemImage: "stop.circle") { confirmAbort = true }
                        .mobileGlassHeaderControl(symbolOnly: true).tint(.red)
                }.mobileGlassHeaderItem()
            }
        }
        .task {
            paneVisible = true
            if pane.agent != "pi" { surface = "Terminal" }
            await reconnectPane()
        }
        .onChange(of: surface) { _, value in
            if value == "Terminal" && !attachedTerminal { Task { await attachTerminal(control: false, takeover: false) } }
            else if value == "Agent" && terminalWritable {
                Task {
                    _ = try? await connection.request(method: "terminal.detach", params: .object([:]))
                    terminalWritable = false; attachedTerminal = false
                }
            }
        }
        .onChange(of: connection.state) { _, state in
            if state != "connected" { terminalWritable = false; attachedTerminal = false; controlAttemptFailed = false }
            else if paneVisible && !attaching { Task { await attachPane() } }
        }
        .onChange(of: connection.terminalFrame?.terminalId) { _, terminalId in
            if terminalId == nil && !attaching {
                terminalWritable = false
                attachedTerminal = false
            }
        }
        .onDisappear {
            paneVisible = false
            dictation.cancelRecording()
            reviewPresentation?.tunnel.close()
            // Release only this pane's subscriptions; the machine directory remains live in the foreground.
            connection.releasePaneSubscription(owner: paneSubscriptionOwner)
        }
        .sheet(item: $reviewPresentation, onDismiss: {
            Task { await sessions.refreshMachine(profile) }
        }) { presentation in
            ReviewSheet(presentation: presentation)
        }
        .confirmationDialog("Take terminal control from another client?", isPresented: $confirmTakeover, titleVisibility: .visible) {
            Button("Take control", role: .destructive) { Task { await attachTerminal(control: true, takeover: true) } }
        } message: { Text("This changes the input owner, not the running process.") }
        .confirmationDialog("Stop the agent's current work?", isPresented: $confirmAbort, titleVisibility: .visible) {
            Button("Stop work", role: .destructive) {
                guard let agent else { return }
                Task {
                    do {
                        _ = try await connection.request(method: "agent.abort", params: .object([
                            "sessionId": .string(agent.sessionId), "generation": .string(agent.generation)]))
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private var terminalSurface: some View {
        VStack(spacing: 0) {
            HStack {
                Label(terminalWritable ? "You control this terminal" : "Read-only terminal",
                    systemImage: terminalWritable ? "keyboard" : "lock")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if terminalWritable {
                    Button {
                        Task {
                            _ = try? await connection.request(method: "terminal.detach", params: .object([:]))
                            terminalWritable = false; attachedTerminal = false
                            await attachTerminal(control: false, takeover: false)
                        }
                    } label: { Text("Release").frame(minHeight: 44) }
                } else {
                    if controlAttemptFailed {
                        Button { confirmTakeover = true } label: { Text("Take over…").frame(minHeight: 44) }
                            .disabled(connection.state != "connected" || attaching)
                    } else if attachedTerminal {
                        Button { Task { await attachTerminal(control: true, takeover: false) } } label: {
                            Text("Take control").frame(minHeight: 44)
                        }.disabled(connection.state != "connected" || attaching)
                    }
                    if !attachedTerminal {
                        Button { Task { await attachTerminal(control: false, takeover: false) } } label: {
                            Text("Observe").frame(minHeight: 44)
                        }.disabled(connection.state != "connected" || attaching)
                    }
                }
            }
            .mobileGlassButtonStyle().buttonBorderShape(.capsule)
            .font(.subheadline).controlSize(.regular)
            .padding(.horizontal, 16).padding(.vertical, 8)
            MobileTerminalView(frame: connection.terminalFrame?.terminalId == pane.terminalId ? connection.terminalFrame : nil,
                onInput: { sendTerminalBytes($0) }, onResize: { cols, rows in resizeTerminal(cols, rows) },
                interactive: terminalWritable)
        }
        .mobileBottomBar {
            TerminalKeyStrip(interactive: terminalWritable, send: sendTerminalBytes)
        }
    }

    private func reconnectPane() async {
        guard !attaching else { return }
        attaching = true
        await sessions.refreshMachine(profile)
        attaching = false
        guard connection.state == "connected" else {
            errorMessage = sessions.machineErrors[profile.id] ?? connection.lastError
            return
        }
        guard connection.topology?.panes.contains(where: { $0.terminalId == pane.terminalId }) == true else {
            errorMessage = "This terminal has closed. Go back to Agents or Machines and refresh."
            return
        }
        await attachPane()
    }

    private func attachPane() async {
        guard paneVisible, !Task.isCancelled else { return }
        if surface == "Terminal" { await attachTerminal(control: false, takeover: false); return }
        guard !attaching else { return }
        attaching = true
        defer { attaching = false }
        do {
            try await connection.preparePaneSubscription(owner: paneSubscriptionOwner)
            guard paneVisible, !Task.isCancelled else {
                connection.releasePaneSubscription(owner: paneSubscriptionOwner)
                return
            }
            _ = try await connection.request(method: "agent.attach", params: .object(["terminalId": .string(pane.terminalId)]))
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func attachTerminal(control: Bool, takeover: Bool) async {
        guard paneVisible, !Task.isCancelled, !attaching, connection.state == "connected" else { return }
        attaching = true
        defer { attaching = false }
        do {
            try await connection.preparePaneSubscription(owner: paneSubscriptionOwner)
            guard paneVisible, !Task.isCancelled else {
                connection.releasePaneSubscription(owner: paneSubscriptionOwner)
                return
            }
            _ = try await connection.request(method: "terminal.attach", params: .object([
                "terminalId": .string(pane.terminalId), "control": .bool(control), "takeover": .bool(takeover),
                "cols": .number(80), "rows": .number(24)]))
            terminalWritable = control; attachedTerminal = true; errorMessage = nil
            if control { controlAttemptFailed = false }
        } catch {
            terminalWritable = false; attachedTerminal = false
            errorMessage = error.localizedDescription
            // The real Herdr CLI reports a closed startup stream, not the guessed busy codes.
            // A takeover stays a separate, explicitly confirmed action after a failed control attempt.
            if control && !takeover { controlAttemptFailed = true }
        }
    }

    private func sendTerminalBytes(_ bytes: Data) {
        guard terminalWritable else { return }
        Task {
            do {
                _ = try await connection.request(method: "terminal.input", params: .object(["data": .string(bytes.base64EncodedString())]))
            } catch {
                terminalWritable = false
                errorMessage = "Input delivery failed. Check the terminal before typing again. \(error.localizedDescription)"
            }
        }
    }

    private func resizeTerminal(_ cols: Int, _ rows: Int) {
        guard terminalWritable else { return }
        Task {
            do { _ = try await connection.request(method: "terminal.resize", params: .object(["cols": .number(Double(cols)), "rows": .number(Double(rows))])) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func openReview(_ review: PlannotatorReview) async {
        openingReview = true
        defer { openingReview = false }
        do {
            // Validate that the request is still advertised before opening its loopback forwarding.
            _ = try await connection.request(method: "snapshot", params: .object([:]))
            guard connection.topology?.panes.first(where: { $0.terminalId == pane.terminalId })?
                .reviews.contains(where: { $0.id == review.id && $0.url == review.url }) == true else {
                errorMessage = "This review has ended. Refresh the agent to see its latest response."
                return
            }
            let tunnel = try await connection.openReview(review)
            reviewPresentation = ReviewPresentation(id: review.id, tunnel: tunnel)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ReviewPresentation: Identifiable {
    let id: String
    let tunnel: PlannotatorTunnel
}

private struct ReviewSheet: View {
    let presentation: ReviewPresentation
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PlannotatorReviewView(url: presentation.tunnel.url)
                .navigationTitle("Plannotator").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Back to agent") { dismiss() }.mobileGlassHeaderControl()
                    }.mobileGlassHeaderItem()
                }
        }.onDisappear { presentation.tunnel.close() }
    }
}

private struct TerminalKeyStrip: View {
    let interactive: Bool
    let send: (Data) -> Void
    var body: some View {
        MobileGlassContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    key("Esc", bytes: "\u{1b}")
                    key("Ctrl-C", bytes: "\u{03}")
                    key("Tab", bytes: "\t")
                    key("Enter", bytes: "\r")
                    arrow("Up", symbol: "arrow.up", bytes: "\u{1b}[A")
                    arrow("Down", symbol: "arrow.down", bytes: "\u{1b}[B")
                    arrow("Left", symbol: "arrow.left", bytes: "\u{1b}[D")
                    arrow("Right", symbol: "arrow.right", bytes: "\u{1b}[C")
                }
                .mobileGlassButtonStyle().buttonBorderShape(.capsule)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .disabled(!interactive)
    }
    private func key(_ name: String, bytes: String) -> some View {
        Button(name) { send(Data(bytes.utf8)) }
            .font(.subheadline.monospaced()).frame(minWidth: 44, minHeight: 44)
    }
    private func arrow(_ name: String, symbol: String, bytes: String) -> some View {
        Button(name, systemImage: symbol) { send(Data(bytes.utf8)) }
            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
    }
}
