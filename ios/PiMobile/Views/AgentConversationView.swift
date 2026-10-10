import SwiftUI
import PiMobileCore

struct AgentConversationView: View {
    let snapshot: PiAgentSnapshot
    @ObservedObject var connection: SSHBridgeConnection
    let location: PaneLocation
    let drafts: PaneDraftStore
    @EnvironmentObject private var dictation: ParakeetDictation
    @State private var draft = ""
    @State private var sending = false
    @State private var delivery = "followUp"
    @State private var errorMessage: String?
    @State private var followOutput = true
    @State private var choosingCommand = false
    @State private var commandSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                AgentStatusLabel(state: snapshot.status)
                Spacer()
                Toggle("Follow output", isOn: $followOutput).toggleStyle(.button).font(.caption)
            }.padding(.horizontal).padding(.vertical, 8)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if snapshot.truncated {
                            Text("Showing recent conversation. Older content remains in Pi's session.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(snapshot.messages) { message in
                            TranscriptMessageView(message: message).id(message.id)
                        }
                        Color.clear.frame(height: 1).id("conversation-bottom")
                    }.padding()
                }
                .onAppear { scroll.scrollTo("conversation-bottom", anchor: .bottom) }
                .onChange(of: snapshot.messages.last?.text) { _, _ in
                    if followOutput { scroll.scrollTo("conversation-bottom", anchor: .bottom) }
                }
            }
            if let dialog = snapshot.dialog {
                PiDialogPanel(snapshot: snapshot, dialog: dialog, connection: connection)
            }
            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal).padding(.vertical, 8) }
            composer
        }
        .onAppear { draft = drafts.loadDraft(location) }
        .onChange(of: draft) { _, text in drafts.saveDraft(text, at: location) }
        .sheet(isPresented: $choosingCommand) {
            NavigationStack {
                List(snapshot.commands.filter {
                    commandSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(commandSearch)
                        || $0.description.localizedCaseInsensitiveContains(commandSearch)
                }) { command in
                    Button {
                        draft = "/\(command.name) "
                        choosingCommand = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("/\(command.name)").font(.body.monospaced())
                            Text(command.description).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                .searchable(text: $commandSearch, prompt: "Commands and skills")
                .navigationTitle("Pi commands")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { choosingCommand = false } } }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .frame(minHeight: 66, maxHeight: 140)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Instruction draft")
            if let error = dictation.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            HStack(spacing: 10) {
                Button("Commands", systemImage: "slash.circle") { choosingCommand = true }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    .disabled(snapshot.commands.isEmpty)
                DictationButton { text in
                    if !draft.isEmpty && !draft.hasSuffix(" ") && !draft.hasSuffix("\n") { draft += " " }
                    draft += text
                }
                Spacer(minLength: 0)
                if snapshot.status == "working" {
                    Menu {
                        Button("Follow-up after current work") { delivery = "followUp" }
                        Button("Steer the current work") { delivery = "steer" }
                    } label: {
                        Text(delivery == "steer" ? "Steer" : "Follow-up").font(.caption)
                    }
                }
                Button(snapshot.status == "working" ? (delivery == "steer" ? "Send steer" : "Send follow-up") : "Send",
                    systemImage: "arrow.up") { sendPrompt() }
                    .buttonStyle(.borderedProminent)
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || snapshot.dialog != nil || connection.state != "connected")
            }
        }
        .padding(.horizontal).padding(.vertical, 10).background(.bar)
    }

    private func sendPrompt() {
        guard !sending, snapshot.dialog == nil else { return }
        sending = true
        let submitted = draft
        var params: [String: BridgeJSON] = ["sessionId": .string(snapshot.sessionId),
            "generation": .string(snapshot.generation), "message": .string(submitted)]
        if snapshot.status == "working" { params["delivery"] = .string(delivery) }
        Task {
            defer { sending = false }
            do {
                _ = try await connection.request(method: "agent.prompt", params: .object(params))
                // Do not erase text the user added while an earlier draft was in flight.
                if draft == submitted { draft = ""; drafts.saveDraft("", at: location) }
                errorMessage = nil
            } catch let error as BridgeFailure {
                errorMessage = error.message
            } catch {
                errorMessage = "Delivery may be uncertain. Check the conversation before sending again. \(error.localizedDescription)"
            }
        }
    }
}

private struct TranscriptMessageView: View {
    let message: AgentTranscriptMessage
    var body: some View {
        if message.role == "toolResult" || message.toolName != nil {
            DisclosureGroup {
                Text(message.text).font(.footnote.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label(message.toolName ?? "Tool result", systemImage: message.isError == true ? "exclamationmark.triangle" : "wrench")
                    .font(.subheadline).foregroundStyle(message.isError == true ? Color.red : Color.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text(message.role == "user" ? "You" : "Pi").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(.init(message.text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Native controls carry live dialog id/revision; the host owns every permission outcome.
private struct PiDialogPanel: View {
    let snapshot: PiAgentSnapshot
    let dialog: PiDialogSnapshot
    @ObservedObject var connection: SSHBridgeConnection
    @State private var text = ""
    @State private var sending = false
    @State private var expanded = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $expanded) {
                ScrollView {
                    Text(dialog.text).font(.footnote).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 190)
            } label: { Label(dialog.title, systemImage: "hand.raised").font(.headline) }
            if dialog.kind == "terminal" {
                Text("This custom interface requires the Terminal view.").font(.footnote).foregroundStyle(.secondary)
            } else {
                if dialog.acceptsText {
                    TextField(dialog.kind == "permission" ? "Reason" : "Response", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...5)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dialog.options) { option in
                            Button(option.label) { respond(option.id) }.buttonStyle(.bordered).frame(minHeight: 44)
                        }
                    }
                }.disabled(sending || connection.state != "connected")
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }.padding().background(.bar)
        .onChange(of: dialog.dialogId) { _, _ in text = ""; error = nil }
    }

    private func respond(_ action: String) {
        guard !sending else { return }
        sending = true
        var params: [String: BridgeJSON] = ["sessionId": .string(snapshot.sessionId), "generation": .string(snapshot.generation),
            "dialogId": .string(dialog.dialogId), "revision": .number(Double(dialog.revision)), "action": .string(action)]
        if dialog.acceptsText { params["value"] = .string(text) }
        Task {
            defer { sending = false }
            do {
                _ = try await connection.request(method: "dialog.respond", params: .object(params))
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
