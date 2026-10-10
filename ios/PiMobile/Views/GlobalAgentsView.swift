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

    var body: some View {
        Group {
            if machines.machines.isEmpty {
                ContentUnavailableView {
                    Label("Your agents, wherever they run", systemImage: "person.2")
                } description: {
                    Text("Add your first Tailscale machine. Its existing Herdr agents will appear here.")
                } actions: {
                    Button("Add machine", systemImage: "plus") { addingMachine = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if entries.isEmpty {
                        Section {
                            ContentUnavailableView(search.isEmpty ? "No agents found" : "No matching agents",
                                systemImage: "person.2", description: Text(search.isEmpty
                                    ? "Refresh reachable machines, or open Machines to start work in an existing terminal."
                                    : "Try a machine, workspace, tab or project name."))
                        }
                    } else {
                        Section {
                            ForEach(entries) { entry in
                                NavigationLink {
                                    PaneDetailView(profile: entry.profile, pane: entry.pane,
                                        connection: sessions.connection(for: entry.profile.id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(entry.title).font(.headline).lineLimit(2)
                                            Spacer(minLength: 8)
                                            AgentStatusLabel(state: entry.stale ? "offline" : entry.pane.state)
                                        }
                                        Text(entry.context).font(.subheadline).foregroundStyle(.secondary)
                                        if entry.stale {
                                            Text("Cached location · reconnect to check current state")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: { Text("Across all machines") }
                    }
                    Section("Machines") {
                        ForEach(machines.machines) { profile in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                    if let error = sessions.machineErrors[profile.id] {
                                        Text(error).font(.caption).foregroundStyle(.secondary)
                                    } else if let checked = sessions.checkedAt[profile.id] {
                                        Text("Checked \(checked.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("Not checked yet").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if sessions.refreshing.contains(profile.id) { ProgressView().accessibilityLabel("Checking \(profile.name)") }
                                else if sessions.machineErrors[profile.id] != nil {
                                    Button("Edit") { editingMachine = profile }.buttonStyle(.borderless)
                                } else {
                                    Image(systemName: sessions.connection(for: profile.id).state == "connected"
                                        ? "checkmark.circle" : "network.slash").foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                .searchable(text: $search, prompt: "Agents, projects and locations")
                .refreshable { await sessions.refreshAll(machines.machines) }
            }
        }
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await sessions.refreshAll(machines.machines) }
                }.disabled(!sessions.refreshing.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add machine", systemImage: "plus") { addingMachine = true }
            }
        }
        .task { await sessions.refreshAll(machines.machines) }
        .sheet(isPresented: $addingMachine) { MachineEditorView(profile: nil) }
        .sheet(item: $editingMachine) { MachineEditorView(profile: $0) }
    }
}

struct AgentStatusLabel: View {
    let state: String
    private var title: String {
        switch state {
        case "blocked": return "Needs input"
        case "working": return "Working"
        case "done": return "Finished"
        case "idle": return "Ready"
        case "offline": return "Offline"
        default: return "Unknown"
        }
    }
    private var color: Color {
        switch state {
        case "blocked": return .orange
        case "working": return .blue
        case "done", "idle": return .green
        default: return .secondary
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
