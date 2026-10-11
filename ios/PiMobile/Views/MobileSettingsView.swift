import SwiftUI

struct MobileSettingsView: View {
    @EnvironmentObject private var dictation: ParakeetDictation

    private var dictationStateTitle: String {
        switch dictation.state {
        case "notDownloaded": return "Not set up"
        case "loading": return "Preparing model"
        case "ready": return "Ready"
        case "recording": return "Recording"
        case "transcribing": return "Transcribing"
        default: return "Needs attention"
        }
    }

    var body: some View {
        Form {
            TailscaleAccountSection()
            Section {
                LabeledContent("Engine", value: "Parakeet TDT v3")
                LabeledContent("State", value: dictationStateTitle)
                Text("Audio stays on this iPhone. The first setup downloads the Core ML model; later transcription works offline.")
                    .foregroundStyle(.secondary)
                if !["ready", "recording", "transcribing"].contains(dictation.state) {
                    Button(dictation.state == "loading" ? "Preparing Parakeet…" : "Download and prepare Parakeet") {
                        Task { do { try await dictation.prepare() } catch { /* The service publishes the actionable error. */ } }
                    }
                    .mobileGlassButtonStyle(prominent: true)
                    .buttonBorderShape(.capsule)
                    .frame(minHeight: 44)
                    .disabled(dictation.state == "loading")
                }
                if dictation.state == "loading" { ProgressView().accessibilityLabel("Preparing Parakeet model") }
                if let error = dictation.errorMessage { Text(error).foregroundStyle(.red) }
            } header: {
                Label("On-device dictation", systemImage: "waveform")
            }
            Section("VoxType behavior") {
                Text("16 kHz audio · up to five minutes per recording")
                Text("Spoken punctuation and Pi command aliases are applied locally. Transcripts are editable and never sent automatically.")
                Text("The desktop OpenAI cleanup step is not included.").foregroundStyle(.secondary)
            }
            Section("Check in on your terms") {
                Label("No notifications", systemImage: "bell.slash")
                Text("Pi Mobile connects while you use it. Your host agents keep running when the app closes.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                Text("Native SSH companion for Herdr and Pi. Requires Tailscale and the host bridge on each machine.")
                    .foregroundStyle(.secondary)
            }
        }
        .listSectionSpacing(24)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct DictationButton: View {
    @EnvironmentObject private var dictation: ParakeetDictation
    let onTranscript: (String) -> Void
    @State private var setup = false
    @State private var operationInFlight = false
    @State private var ownsRecording = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard !operationInFlight else { return }
                if dictation.state == "recording" {
                    operationInFlight = true
                    Task {
                        defer { operationInFlight = false }
                        do { _ = try await dictation.stopRecording() } catch { ownsRecording = false }
                    }
                } else if dictation.state == "ready" {
                    operationInFlight = true
                    ownsRecording = true
                    Task {
                        defer { operationInFlight = false }
                        do { try await dictation.startRecording() } catch { ownsRecording = false }
                    }
                } else { setup = true }
            } label: {
                if dictation.state == "transcribing" || dictation.state == "loading" {
                    ProgressView().accessibilityLabel(dictation.state == "loading" ? "Preparing dictation" : "Transcribing on this iPhone")
                } else {
                    Label(dictation.state == "recording" ? "Stop recording" : "Dictate instructions",
                        systemImage: dictation.state == "recording" ? "stop.circle.fill" : "mic")
                        .labelStyle(.iconOnly)
                        .symbolEffect(.bounce, value: reduceMotion ? "" : dictation.state)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.borderless)
            .tint(dictation.state == "recording" ? .red : .blue)
            .disabled(operationInFlight || dictation.state == "loading" || dictation.state == "transcribing")
            .accessibilityHint(dictation.state == "recording" ? "Transcribe this recording into the draft" : "Record instructions locally")
            if dictation.state == "recording" {
                Button("Cancel recording", systemImage: "xmark") {
                    ownsRecording = false
                    dictation.cancelRecording()
                }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.borderless)
            }
        }
        .onChange(of: dictation.completedTranscriptID) { _, id in
            guard id != nil, ownsRecording else { return }
            ownsRecording = false
            // One delivery path handles manual Stop and the five-minute cap, without duplicate insertion.
            onTranscript(dictation.transcript)
        }
        .onDisappear {
            if ownsRecording { dictation.cancelRecording() }
            ownsRecording = false
        }
        .sheet(isPresented: $setup) {
            NavigationStack {
                MobileSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { setup = false }.mobileGlassHeaderControl()
                        }.mobileGlassHeaderItem()
                    }
            }
        }
    }
}
