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
                .environmentObject(dictation)
                .tint(.blue)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        dictation.cancelRecording()
                        sessions.suspendConnections()
                    } else if phase == .active {
                        // Foreground reads only. Pending prompts/approval actions are never retried.
                        Task { await sessions.refreshAll(machines.machines) }
                    }
                }
        }
    }
}

/// System navigation and tab bars adopt Liquid Glass automatically on iOS 26.
struct MobileRootView: View {
    @State private var selectedTab = MobileRootTab.agents

    var body: some View {
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
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

private enum MobileRootTab: Hashable {
    case agents, machines, settings
}
