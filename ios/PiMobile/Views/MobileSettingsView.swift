import SwiftUI

struct MobileSettingsView: View {
    @EnvironmentObject private var dictation: ParakeetDictation

    var body: some View {
        Form {
            Section("On-device dictation") {
                LabeledContent("Engine", value: "Parakeet TDT v3")
                LabeledContent("State", value: dictation.state)
                Text("Audio stays on this iPhone. The first setup downloads the Core ML model; later transcription works offline.")
                    .foregroundStyle(.secondary)
                if !["ready", "recording", "transcribing"].contains(dictation.state) {
                    Button(dictation.state == "loading" ? "Preparing Parakeet…" : "Download and prepare Parakeet") {
                        Task { do { try await dictation.prepare() } catch { /* The service publishes the actionable error. */ } }
                    }.disabled(dictation.state == "loading")
                }
                if dictation.state == "loading" { ProgressView().accessibilityLabel("Preparing Parakeet model") }
                if let error = dictation.errorMessage { Text(error).foregroundStyle(.red) }
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
        }.navigationTitle("Settings")
    }
}

struct DictationButton: View {
    @EnvironmentObject private var dictation: ParakeetDictation
    let onTranscript: (String) -> Void
    @State private var setup = false
    @State private var operationInFlight = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard !operationInFlight else { return }
                if dictation.state == "recording" {
                    operationInFlight = true
                    Task {
                        defer { operationInFlight = false }
                        do { onTranscript(try await dictation.stopRecording()) } catch { }
                    }
                } else if dictation.state == "ready" {
                    operationInFlight = true
                    Task {
                        defer { operationInFlight = false }
                        do { try await dictation.startRecording() } catch { }
                    }
                } else { setup = true }
            } label: {
                Label(dictation.state == "recording" ? "Stop" : "Dictate",
                    systemImage: dictation.state == "recording" ? "stop.circle.fill" : "mic")
            }
            .buttonStyle(.bordered)
            .disabled(operationInFlight || dictation.state == "loading" || dictation.state == "transcribing")
            .accessibilityHint(dictation.state == "recording" ? "Transcribe this recording into the draft" : "Record instructions locally")
            if dictation.state == "recording" {
                Button("Cancel recording", systemImage: "xmark") { dictation.cancelRecording() }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            } else if dictation.state == "transcribing" {
                ProgressView().accessibilityLabel("Transcribing on this iPhone")
            }
        }
        .sheet(isPresented: $setup) {
            NavigationStack {
                MobileSettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { setup = false } } }
            }
        }
    }
}
