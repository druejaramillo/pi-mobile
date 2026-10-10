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
                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.name).font(.headline)
                        Text("\(profile.username)@\(profile.hostname)")
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        if let error = sessions.machineErrors[profile.id] {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Edit", systemImage: "pencil") { editing = profile }.tint(.blue)
                }
            }
        }
        .overlay {
            if machines.machines.isEmpty {
                ContentUnavailableView("No machines yet", systemImage: "server.rack",
                    description: Text("Add a Tailscale host, its SSH credential and verified host public key."))
            }
        }
        .navigationTitle("Machines")
        .toolbar { Button("Add machine", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { MachineEditorView(profile: nil) }
        .sheet(item: $editing) { MachineEditorView(profile: $0) }
    }
}

struct MachineBrowserView: View {
    let profile: MachineProfile
    @ObservedObject var connection: SSHBridgeConnection
    @EnvironmentObject private var sessions: MobileSessionHub
    @State private var editing = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text(connection.state.capitalized)
                    Spacer()
                    if sessions.refreshing.contains(profile.id) { ProgressView() }
                    Button("Refresh") { Task { await sessions.refreshMachine(profile) } }
                        .disabled(sessions.refreshing.contains(profile.id))
                }
                if let error = sessions.machineErrors[profile.id] {
                    Text(error).foregroundStyle(.secondary)
                    Button("Edit connection") { editing = true }
                }
            }
            if let topology = connection.topology {
                ForEach(topology.workspaces) { workspace in
                    Section(workspace.name) {
                        ForEach(topology.tabs.filter { $0.workspaceId == workspace.id }) { tab in
                            NavigationLink {
                                TabPanesView(profile: profile, tab: tab, connection: connection)
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
        .navigationTitle(profile.name)
        .toolbar { Button("Edit", systemImage: "pencil") { editing = true } }
        .task { await sessions.refreshMachine(profile) }
        .sheet(isPresented: $editing) { MachineEditorView(profile: profile) }
    }
}

struct TabPanesView: View {
    let profile: MachineProfile
    let tab: HerdrTab
    @ObservedObject var connection: SSHBridgeConnection

    var body: some View {
        List {
            ForEach(connection.topology?.panes.filter { $0.tabId == tab.id } ?? []) { pane in
                NavigationLink {
                    PaneDetailView(profile: profile, pane: pane, connection: connection)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(pane.title.isEmpty ? "Terminal" : pane.title).font(.headline)
                            Spacer()
                            if pane.agent != nil { AgentStatusLabel(state: pane.state) }
                        }
                        Text(pane.cwd).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle(tab.name)
    }
}
