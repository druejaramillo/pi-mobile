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
    @State private var successfulSends = 0
    @State private var composerDockHeight: CGFloat = 0
    @State private var accessoryContentHeight: CGFloat = 0
    @State private var conversationHeaderHeight: CGFloat = 52
    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sendTitle: String {
        if sending { return "Sending" }
        if snapshot.status == "working" { return delivery == "steer" ? "Send steer" : "Send follow-up" }
        return "Send"
    }

    var body: some View {
        GeometryReader { viewport in
            conversationSurface
                .mobileBottomBar {
                    ScrollView {
                        VStack(spacing: 10) {
                            if let dialog = snapshot.dialog {
                                PiDialogPanel(snapshot: snapshot, dialog: dialog, connection: connection,
                                    maximumHeight: max(44, min(viewport.size.height * 0.5,
                                        viewport.size.height - composerDockHeight - 28)))
                            }
                            composerDock
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerDockHeight = $0 }
                        }
                        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { accessoryContentHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .frame(height: min(accessoryContentHeight, max(0, viewport.size.height - conversationHeaderHeight)))
                }
        }
        .sensoryFeedback(.success, trigger: successfulSends)
        .onAppear { draft = drafts.loadDraft(location) }
        .onChange(of: draft) { _, text in drafts.saveDraft(text, at: location) }
        .sheet(isPresented: $choosingCommand) { commandPicker }
    }

    private var conversationSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AgentStatusLabel(state: connection.state == "connected" ? snapshot.status : "offline")
                Spacer(minLength: 0)
                Toggle(isOn: $followOutput) {
                    Label("Follow output", systemImage: "arrow.down.to.line")
                        .labelStyle(.iconOnly)
                }
                .toggleStyle(.button).buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("Keep the latest response in view")
            }
            .padding(.horizontal, 20).padding(.vertical, 4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { conversationHeaderHeight = $0 }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if snapshot.truncated {
                            Label("Showing recent conversation. Older content remains in Pi's session.", systemImage: "clock")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if snapshot.messages.isEmpty {
                            ContentUnavailableView("Continue with Pi", systemImage: "sparkles",
                                description: Text("Send an instruction below to continue this running session."))
                        }
                        ForEach(snapshot.messages) { message in
                            TranscriptMessageView(message: message).id(message.id)
                        }
                        Color.clear.frame(height: 1).id("conversation-bottom")
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scroll.scrollTo("conversation-bottom", anchor: .bottom) }
                .onChange(of: snapshot.messages.last?.text) { _, _ in
                    if followOutput { scroll.scrollTo("conversation-bottom", anchor: .bottom) }
                }
                .onChange(of: snapshot.messages.last?.id) { _, _ in
                    if followOutput { scroll.scrollTo("conversation-bottom", anchor: .bottom) }
                }
                .onChange(of: followOutput) { _, follow in
                    if follow { scroll.scrollTo("conversation-bottom", anchor: .bottom) }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var commandPicker: some View {
        NavigationStack {
            List(snapshot.commands.filter {
                commandSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(commandSearch)
                    || $0.description.localizedCaseInsensitiveContains(commandSearch)
            }) { command in
                Button {
                    draft = "/\(command.name) "
                    choosingCommand = false
                    composerFocused = true
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

    private var composerDock: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            composer
        }
    }

    private var composer: some View {
        MobileGlassContainer {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Message Pi…", text: $draft, axis: .vertical)
                        .font(.body).lineLimit(1...(dynamicTypeSize.isAccessibilitySize ? 3 : 6))
                        .textFieldStyle(.plain).focused($composerFocused)
                        .padding(.horizontal, 8).padding(.top, 8)
                        .frame(minHeight: 44, alignment: .topLeading)
                        .accessibilityLabel("Instruction draft")
                    if dictation.state == "recording" || dictation.state == "transcribing" {
                        Text(dictation.state == "recording" ? "Recording on this iPhone" : "Transcribing on device")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                    }
                    if let error = dictation.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 8)
                    }
                    HStack(spacing: 4) {
                        Button("Commands", systemImage: "slash.circle") { choosingCommand = true }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                            .disabled(snapshot.commands.isEmpty)
                        DictationButton { text in
                            if !draft.isEmpty && !draft.hasSuffix(" ") && !draft.hasSuffix("\n") { draft += " " }
                            draft += text
                        }
                        Spacer(minLength: 0)
                        if snapshot.status == "working" && !dynamicTypeSize.isAccessibilitySize { deliveryMenu }
                    }
                    .buttonStyle(.borderless)
                    if snapshot.status == "working" && dynamicTypeSize.isAccessibilitySize { deliveryMenu }
                }
                .padding(8)
                .mobileGlassSurface(in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                Button(action: sendPrompt) {
                    Group {
                        if sending { ProgressView().tint(.primary) }
                        else { Image(systemName: "arrow.up").font(.title3.weight(.semibold)) }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                .mobileGlassButtonStyle(prominent: true)
                .buttonBorderShape(.circle)
                .accessibilityLabel(sendTitle)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || snapshot.dialog != nil || connection.state != "connected")
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: dictation.state)
    }

    private var deliveryMenu: some View {
        Menu {
            Button { delivery = "followUp" } label: {
                Label("Follow-up after current work", systemImage: delivery == "followUp" ? "checkmark" : "text.bubble")
            }
            Button { delivery = "steer" } label: {
                Label("Steer the current work", systemImage: delivery == "steer" ? "checkmark" : "arrow.turn.up.right")
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                Text(delivery == "steer" ? "Steer" : "Follow-up").fixedSize()
                Image(systemName: delivery == "steer" ? "arrow.turn.up.right" : "text.bubble")
            }
            .font(.caption.weight(.medium)).padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(delivery == "steer" ? "Delivery: steer the current work" : "Delivery: follow-up after current work")
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
                successfulSends += 1
            } catch let error as BridgeFailure {
                errorMessage = error.message
            } catch {
                errorMessage = "Delivery may be uncertain. Check the conversation before sending again. \(error.localizedDescription)"
            }
        }
    }
}

/// Transcript content stays opaque and selectable beneath the floating control layer.
private struct TranscriptMessageView: View {
    let message: AgentTranscriptMessage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if message.role == "toolResult" || message.toolName != nil {
            DisclosureGroup {
                Text(message.text).font(.footnote.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            } label: {
                Label(message.toolName ?? "Tool result", systemImage: message.isError == true ? "exclamationmark.triangle" : "terminal")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(message.isError == true ? Color.red : Color.secondary)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        } else if message.role == "user" {
            HStack {
                Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 0 : 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text("You").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    messageText
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Pi", systemImage: "sparkle")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                messageText
            }
        }
    }

    private var messageText: some View {
        Text(.init(message.text)).font(.body).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Native controls carry live dialog id/revision; the host owns every permission outcome.
private struct PiDialogPanel: View {
    let snapshot: PiAgentSnapshot
    let dialog: PiDialogSnapshot
    @ObservedObject var connection: SSHBridgeConnection
    let maximumHeight: CGFloat
    @State private var contentHeight: CGFloat = 0
    @State private var text = ""
    @State private var sending = false
    @State private var expanded = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            dialogContent
                .padding(16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(maximumHeight, max(44, contentHeight)))
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .onChange(of: dialog.dialogId) { _, _ in text = ""; error = nil }
    }

    private var dialogContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $expanded) {
                ScrollView {
                    Text(dialog.text).font(.footnote).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 190)
            } label: {
                Label(dialog.title, systemImage: "hand.raised.fill")
                    .font(.headline).frame(minHeight: 44, alignment: .leading)
            }
            if dialog.kind == "terminal" {
                Text("This custom interface requires the Terminal view.").font(.footnote).foregroundStyle(.secondary)
            } else {
                if dialog.acceptsText {
                    TextField(dialog.kind == "permission" ? "Reason" : "Response", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...5)
                }
                MobileGlassContainer {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(dialog.options) { option in
                                Button(option.label) { respond(option) }
                                    .mobileGlassButtonStyle().buttonBorderShape(.capsule)
                                    .frame(minHeight: 44)
                            }
                        }.padding(.vertical, 4)
                    }
                }.disabled(sending || connection.state != "connected")
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func respond(_ option: PiDialogOption) {
        guard !sending else { return }
        sending = true
        let submitted = text
        var params: [String: BridgeJSON] = ["sessionId": .string(snapshot.sessionId), "generation": .string(snapshot.generation),
            "dialogId": .string(dialog.dialogId), "revision": .number(Double(dialog.revision)), "action": .string(option.id)]
        if option.acceptsValue == true { params["value"] = .string(submitted) }
        Task {
            defer { sending = false }
            do {
                _ = try await connection.request(method: "dialog.respond", params: .object(params))
                if dialog.kind == "permission", option.acceptsValue == true, text == submitted { text = "" }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
