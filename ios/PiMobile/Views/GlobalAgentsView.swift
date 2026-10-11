import SwiftUI
import PiMobileCore

/// The launch screen jumps to live agents across machines without changing Herdr's desktop focus.
struct GlobalAgentsView: View {
    @EnvironmentObject private var machines: MachineStore
    @EnvironmentObject private var sessions: MobileSessionHub
    @State private var search = ""
    @State private var editingMachine: MachineProfile?
    @State private var addingMachine = false

    private var entries: [GlobalAgentEntry] {
        sessions.agentEntries(machines.machines).filter {
            search.isEmpty || "\($0.title) \($0.context) \($0.pane.cwd) \($0.pane.state)"
                .localizedCaseInsensitiveContains(search)
        }
    }

    private var emptyDirectoryTitle: String {
        if !search.isEmpty { return "No matching agents" }
        if !sessions.refreshing.isEmpty { return "Checking machines" }
        if machines.machines.contains(where: { sessions.machineErrors[$0.id] != nil }) {
            return "Some machines are unavailable"
        }
        return "No agents found"
    }

    private var emptyDirectoryDescription: String {
        if !search.isEmpty { return "Try a machine, workspace, tab or project name." }
        if !sessions.refreshing.isEmpty { return "Each machine is checked independently." }
        if machines.machines.contains(where: { sessions.machineErrors[$0.id] != nil }) {
            return "Reconnect unavailable machines to check their agents."
        }
        return "Refresh reachable machines, or open Machines to start work in an existing terminal."
    }

    var body: some View {
        Group {
            if machines.machines.isEmpty {
                ContentUnavailableView {
                    Label("Your agents, wherever they run", systemImage: "person.2")
                } description: {
                    Text("Add your first Tailscale machine. Its existing Herdr agents will appear here.")
                } actions: {
                    Button("Add machine", systemImage: "plus") { addingMachine = true }
                        .mobileGlassButtonStyle(prominent: true)
                        .controlSize(.large).buttonBorderShape(.capsule)
                }
            } else {
                List {
                    if entries.isEmpty {
                        Section {
                            ContentUnavailableView(emptyDirectoryTitle, systemImage: "person.2",
                                description: Text(emptyDirectoryDescription))
                        }
                    } else {
                        Section {
                            ForEach(entries) { entry in
                                NavigationLink {
                                    PaneDetailView(profile: entry.profile, pane: entry.pane,
                                        connection: sessions.connection(for: entry.profile.id))
                                } label: {
                                    AgentDirectoryRow(entry: entry)
                                }
                            }
                        } header: { Text("Across all machines") }
                    }
                    Section("Machines") {
                        ForEach(machines.machines) { profile in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(profile.name, systemImage: "server.rack")
                                        .font(.subheadline.weight(.medium))
                                    if let error = sessions.machineErrors[profile.id] {
                                        Text(error).font(.caption).foregroundStyle(.secondary)
                                    } else if let checked = sessions.checkedAt[profile.id] {
                                        Text("Checked \(checked.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("Not checked yet").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 12)
                                if sessions.refreshing.contains(profile.id) {
                                    ProgressView().accessibilityLabel("Checking \(profile.name)")
                                } else if sessions.machineErrors[profile.id] != nil {
                                    Button("Edit") { editingMachine = profile }
                                        .mobileGlassButtonStyle().buttonBorderShape(.capsule)
                                        .frame(minWidth: 44, minHeight: 44)
                                } else {
                                    let connected = sessions.connection(for: profile.id).state == "connected"
                                    Image(systemName: connected ? "checkmark.circle.fill" : "network.slash")
                                        .foregroundStyle(connected ? Color.green : Color.secondary)
                                        .accessibilityLabel(connected ? "Connected" : "Disconnected")
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(24)
                .searchable(text: $search, prompt: "Agents, projects and locations")
                .refreshable { await sessions.refreshAll(machines.machines) }
            }
        }
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await sessions.refreshAll(machines.machines) }
                }
                .mobileGlassHeaderControl(symbolOnly: true)
                .disabled(!sessions.refreshing.isEmpty)
            }.mobileGlassHeaderItem()
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add machine", systemImage: "plus") { addingMachine = true }
                    .mobileGlassHeaderControl(prominent: true, symbolOnly: true)
            }.mobileGlassHeaderItem()
        }
        .task { await sessions.refreshAll(machines.machines) }
        .sheet(isPresented: $addingMachine) { MachineEditorView(profile: nil) }
        .sheet(item: $editingMachine) { MachineEditorView(profile: $0) }
    }
}

/// Location stays readable at accessibility sizes instead of competing with a status badge.
private struct AgentDirectoryRow: View {
    let entry: GlobalAgentEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                title
                status
            } else {
                HStack(alignment: .top, spacing: 12) {
                    title
                    Spacer(minLength: 0)
                    status
                }
            }
            Text(entry.context).font(.subheadline).foregroundStyle(.secondary)
            if entry.stale {
                Label("Cached location · reconnect to check current state", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private var title: some View {
        Text(entry.title).font(.headline)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: some View {
        AgentStatusLabel(state: entry.stale ? "offline" : entry.pane.state)
    }
}
