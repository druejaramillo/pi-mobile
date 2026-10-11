import SwiftUI

@main
struct PiMobileApp: App {
    @StateObject private var machines = MachineStore()
    @StateObject private var sessions = MobileSessionHub()
    @StateObject private var dictation = ParakeetDictation()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(machines)
                .environmentObject(sessions)
                .environmentObject(sessions.tailscale)
                .environmentObject(dictation)
                .tint(.blue)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        dictation.cancelRecording()
                        sessions.suspendConnections()
                        Task { await sessions.tailscale.suspend() }
                    } else if phase == .active {
                        // Foreground reads only. Pending prompts/approval actions are never retried.
                        Task {
                            await sessions.tailscale.resume()
                            await sessions.refreshAll(machines.machines)
                        }
                    }
                }
        }
    }
}

/// Native Liquid Glass navigation requires the executable to record SDK 26+, not just new headers.
struct MobileRootView: View {
    @State private var selectedTab = MobileRootTab.agents

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $selectedTab) {
                    Tab("Agents", systemImage: "sparkles", value: MobileRootTab.agents) {
                        NavigationStack { GlobalAgentsView() }
                    }
                    Tab("Machines", systemImage: "server.rack", value: MobileRootTab.machines) {
                        NavigationStack { MachinesView() }
                    }
                    Tab("Settings", systemImage: "gearshape", value: MobileRootTab.settings) {
                        NavigationStack { MobileSettingsView() }
                    }
                }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack { GlobalAgentsView() }
                        .tabItem { Label("Agents", systemImage: "sparkles") }
                        .tag(MobileRootTab.agents)
                    NavigationStack { MachinesView() }
                        .tabItem { Label("Machines", systemImage: "server.rack") }
                        .tag(MobileRootTab.machines)
                    NavigationStack { MobileSettingsView() }
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(MobileRootTab.settings)
                }
            }
        }
        .mobileGlassTabBar()
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

private enum MobileRootTab: Hashable {
    case agents, machines, settings
}
