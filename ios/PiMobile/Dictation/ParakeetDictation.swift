@preconcurrency import AVFoundation
import Combine
import FluidAudio
import Foundation
import UIKit

/// User-initiated on-device Parakeet v3 dictation; editable output never sends a prompt or keys.
@MainActor
public final class ParakeetDictation: ObservableObject {
    @Published public private(set) var state: String = "notDownloaded"
    @Published public private(set) var errorMessage: String?
    @Published public var transcript: String = ""
    /// A successful utterance publishes a unique id, including repeated identical transcripts and automatic stops.
    @Published public private(set) var completedTranscriptID: UUID?

    private let suppliedProfile: DictationProfile?
    private let bundle: Bundle
    private var processor: DictationTextProcessor?
    private var manager: AsrManager?
    private var microphone: DictationMicrophone?
    private var prepareTask: Task<AsrManager, Error>?
    private var transcriptionTask: Task<String, Error>?
    private var limitTask: Task<Void, Never>?
    private var operationID: UUID?
    private var starting = false
    private var finishing = false
    private let observations = DictationObservationBag()

    /// Construction does not download, request permission, or activate the microphone.
    public init(profile: DictationProfile? = nil, bundle: Bundle = .main) {
        suppliedProfile = profile
        self.bundle = bundle
    }

    /// Call only after explicit model-download consent; cached Core ML weights are reused.
    public func prepare() async throws {
        try requireIdle()
        if manager != nil { state = "ready"; errorMessage = nil; return }
        let id = UUID()
        operationID = id
        state = "loading"
        errorMessage = nil
        defer {
            prepareTask = nil
            if operationID == id { operationID = nil }
        }
        do {
            try Task.checkCancellation()
            let profile = try suppliedProfile ?? DictationProfile.load(bundle: bundle)
            processor = try DictationTextProcessor(profile: profile)
            let task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                try Task.checkCancellation()
                // Model weights belong in the SDK's persistent sandbox cache,
                // not in iCloud backups. No audio is ever persisted there.
                var cache = AsrModels.defaultCacheDirectory(for: .v3)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try cache.setResourceValues(values)
                return AsrManager(config: ASRConfig(parallelChunkConcurrency: 1), models: models)
            }
            prepareTask = task
            let loaded = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try checkOperation(id)
            manager = loaded
            state = "ready"
        } catch {
            if operationID != id || Task.isCancelled || error is CancellationError {
                if operationID == id { cancelRecording() }
                throw CancellationError()
            }
            recordFailure(error)
            throw error
        }
    }

    /// Request native microphone permission and begin foreground-only capture, without downloading.
    public func startRecording() async throws {
        try requireIdle()
        guard manager != nil, let processor else { throw DictationFailure.notPrepared }
        let id = UUID()
        operationID = id
        starting = true
        errorMessage = nil
        defer { starting = false }
        do {
            try Task.checkCancellation()
            let allowed = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            try checkOperation(id)
            guard allowed else { throw DictationFailure.microphonePermission }
            guard UIApplication.shared.applicationState == .active else { throw DictationFailure.inactiveApplication }
            let microphone = DictationMicrophone()
            self.microphone = microphone
            try microphone.start(maximumSamples: processor.profile.sampleRate * processor.profile.maxDurationSeconds) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.operationID == id else { return }
                    switch event {
                    case .limitReached:
                        guard self.state == "recording" else { return }
                        do { _ = try await self.stopRecording() } catch { /* State carries the failure. */ }
                    case .failure(let error):
                        self.cancelRecording()
                        self.recordFailure(error)
                    }
                }
            }
            state = "recording"
            installCancellationObservers(id: id)
            feedback()
            let duration = UInt64(processor.profile.maxDurationSeconds) * 1_000_000_000
            limitTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: duration) } catch { return }
                guard let self, self.operationID == id, self.state == "recording" else { return }
                // Stop must not cancel this same task and thereby cancel inference.
                self.limitTask = nil
                do { _ = try await self.stopRecording() } catch { /* State carries the failure. */ }
            }
        } catch {
            if operationID != id || Task.isCancelled || error is CancellationError {
                if operationID == id { cancelRecording() }
                throw CancellationError()
            }
            cancelRecording()
            recordFailure(error)
            throw error
        }
    }

    /// Stop capture, transfer its immutable samples, and return offline-cleaned editable text.
    public func stopRecording() async throws -> String {
        guard state == "recording", let microphone, let manager, let processor, let id = operationID else {
            throw DictationFailure.notRecording
        }
        finishing = true
        state = "transcribing"
        limitTask?.cancel()
        limitTask = nil
        feedback()
        defer {
            transcriptionTask = nil
            finishing = false
            if operationID == id {
                operationID = nil
                self.microphone = nil
                observations.removeAll()
            }
        }
        do {
            return try await withTaskCancellationHandler {
                let samples = try await microphone.finish()
                self.microphone = nil
                try checkOperation(id)
                let task = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    // A new decoder state per utterance prevents cross-recording context leakage.
                    var decoderState = try TdtDecoderState()
                    let result = try await manager.transcribe(samples, decoderState: &decoderState)
                    try Task.checkCancellation()
                    return processor.process(result.text)
                }
                transcriptionTask = task
                let text = try await task.value
                try checkOperation(id)
                transcript = text
                completedTranscriptID = id
                errorMessage = nil
                state = "ready"
                return text
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, self.operationID == id else { return }
                    self.cancelRecording()
                }
            }
        } catch {
            if operationID != id || Task.isCancelled || error is CancellationError {
                if operationID == id { cancelRecording() }
                throw CancellationError()
            }
            microphone.cancel()
            recordFailure(error)
            throw error
        }
    }

    /// Discard this recording/inference; preserve previous user-edited text and cached weights.
    public func cancelRecording() {
        let wasRecording = state == "recording"
        operationID = nil
        limitTask?.cancel()
        limitTask = nil
        prepareTask?.cancel()
        transcriptionTask?.cancel()
        microphone?.cancel()
        microphone = nil
        observations.removeAll()
        errorMessage = nil
        state = manager == nil ? "notDownloaded" : "ready"
        if wasRecording { feedback() }
        // Keep task handles until their awaiting public call settles; requireIdle
        // prevents reentrant SDK use even if Core ML cancellation takes time.
    }

    private func requireIdle() throws {
        guard prepareTask == nil, transcriptionTask == nil, !starting, !finishing,
              operationID == nil, microphone == nil else { throw DictationFailure.busy }
    }

    private func checkOperation(_ id: UUID) throws {
        try Task.checkCancellation()
        guard operationID == id else { throw CancellationError() }
    }

    private func recordFailure(_ error: Error) {
        state = "error"
        errorMessage = error.localizedDescription
    }

    private func feedback() {
        guard processor?.profile.feedbackEnabled == true else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func installCancellationObservers(id: UUID) {
        observations.removeAll()
        let names: [Notification.Name] = [
            AVAudioSession.interruptionNotification,
            AVAudioSession.routeChangeNotification,
            AVAudioSession.mediaServicesWereResetNotification,
            .AVAudioEngineConfigurationChange,
            UIApplication.didEnterBackgroundNotification,
        ]
        for name in names {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if name == AVAudioSession.interruptionNotification {
                    let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                }
                Task { @MainActor [weak self] in
                    guard let self, self.operationID == id else { return }
                    // Deactivating our own session after Stop can change routes;
                    // only backgrounding/interruptions cancel pending inference.
                    if self.state == "transcribing",
                       (name == AVAudioSession.routeChangeNotification || name == .AVAudioEngineConfigurationChange) { return }
                    self.cancelRecording()
                }
            }
            observations.add(observer)
        }
    }
}

/// Weak observers do not retain dictation; the bag removes registrations on owner teardown.
private final class DictationObservationBag {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) { tokens.append(token) }
    func removeAll() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens.removeAll()
    }
    deinit { removeAll() }
}
