import SwiftUI
import PiMobileCore

struct MachinesView: View {
    @EnvironmentObject private var machines: MachineStore
    @EnvironmentObject private var sessions: MobileSessionHub
    @State private var adding = false
    @State private var editing: MachineProfile?

    var body: some View {
        List {
            ForEach(machines.machines) { profile in
                NavigationLink {
                    MachineBrowserView(profile: profile, connection: sessions.connection(for: profile.id))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(profile.name, systemImage: "server.rack").font(.headline)
                        Text("\(profile.username)@\(profile.hostname)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let error = sessions.machineErrors[profile.id] {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Edit", systemImage: "pencil") { editing = profile }.tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if machines.machines.isEmpty {
                ContentUnavailableView {
                    Label("No machines yet", systemImage: "server.rack")
                } description: {
                    Text("Add a Tailscale SSH host and verify its identity. No private key or password needed.")
                } actions: {
                    Button("Add machine", systemImage: "plus") { adding = true }
                        .mobileGlassButtonStyle(prominent: true)
                        .controlSize(.large).buttonBorderShape(.capsule)
                }
            }
        }
        .navigationTitle("Machines")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add machine", systemImage: "plus") { adding = true }
                    .mobileGlassHeaderControl(prominent: true, symbolOnly: true)
            }.mobileGlassHeaderItem()
        }
        .sheet(isPresented: $adding) { MachineEditorView(profile: nil) }
        .sheet(item: $editing) { MachineEditorView(profile: $0) }
    }
}

struct MachineBrowserView: View {
    let profile: MachineProfile
    @ObservedObject var connection: SSHBridgeConnection
    @EnvironmentObject private var sessions: MobileSessionHub
    @EnvironmentObject private var machines: MachineStore
    @State private var editing = false

    private var currentProfile: MachineProfile { machines.machines.first { $0.id == profile.id } ?? profile }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(connection.state.capitalized)
                    Spacer()
                    if sessions.refreshing.contains(profile.id) { ProgressView() }
                    Button("Refresh") { Task { await sessions.refreshMachine(profile) } }
                        .mobileGlassButtonStyle().buttonBorderShape(.capsule)
                        .frame(minHeight: 44).disabled(sessions.refreshing.contains(profile.id))
                }
                if let error = sessions.machineErrors[profile.id] {
                    Text(error).foregroundStyle(.secondary)
                    Button("Edit connection") { editing = true }
                        .mobileGlassButtonStyle().buttonBorderShape(.capsule).frame(minHeight: 44)
                }
            }
            if let topology = sessions.cachedTopology(for: profile.id) {
                if connection.state != "connected" {
                    Text("Cached workspaces · reconnect to check current state").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(topology.workspaces) { workspace in
                    Section(workspace.name) {
                        ForEach(topology.tabs.filter { $0.workspaceId == workspace.id }) { tab in
                            NavigationLink {
                                TabPanesView(profile: currentProfile, tab: tab, connection: connection)
                            } label: {
                                Label(tab.name, systemImage: "rectangle.on.rectangle")
                            }
                        }
                    }
                }
                if topology.workspaces.isEmpty {
                    ContentUnavailableView("No workspaces", systemImage: "rectangle.stack",
                        description: Text("Create a Herdr workspace on this machine, then refresh."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(24)
        .navigationTitle(currentProfile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", systemImage: "pencil") { editing = true }
                    .mobileGlassHeaderControl(symbolOnly: true)
            }.mobileGlassHeaderItem()
        }
        .task { await sessions.refreshMachine(profile) }
        .sheet(isPresented: $editing) { MachineEditorView(profile: currentProfile) }
    }
}

struct TabPanesView: View {
    let profile: MachineProfile
    let tab: HerdrTab
    @ObservedObject var connection: SSHBridgeConnection
    @EnvironmentObject private var sessions: MobileSessionHub
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            if connection.state != "connected" {
                Text("Cached panes · reconnect to check current state").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(sessions.cachedTopology(for: profile.id)?.panes.filter { $0.tabId == tab.id } ?? []) { pane in
                NavigationLink {
                    PaneDetailView(profile: profile, pane: pane, connection: connection)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(pane.title.isEmpty ? "Terminal" : pane.title).font(.headline)
                        if pane.agent != nil {
                            AgentStatusLabel(state: connection.state == "connected" ? pane.state : "offline")
                        }
                        Text(pane.cwd).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }.padding(.vertical, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(tab.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
