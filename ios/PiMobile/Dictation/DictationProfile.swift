import Foundation

/// Whitelisted VoxType settings; no desktop actions, scripts, or credentials.
public struct DictationProfile: Codable, Equatable, Sendable {
    /// One spoken alias produces one inert slash command, never an action.
    public struct Replacement: Codable, Equatable, Sendable {
        public let spoken: String
        public let command: String

        public init(spoken: String, command: String) {
            self.spoken = spoken
            self.command = command
        }
    }

    public let schemaVersion: Int
    public let engine: String
    public let model: String
    public let sampleRate: Int
    public let maxDurationSeconds: Int
    public let feedbackEnabled: Bool
    public let spokenPunctuation: Bool
    public let filterFillerWords: Bool
    public let appendSpace: Bool
    public let replacements: [Replacement]

    /// Explicit profiles can disable cleanup without changing the 16 kHz/300 s contract.
    public init(feedbackEnabled: Bool = true, spokenPunctuation: Bool = true,
                filterFillerWords: Bool = true, appendSpace: Bool = true,
                replacements: [Replacement] = []) {
        schemaVersion = 1
        engine = "parakeet"
        model = "parakeet-tdt-0.6b-v3"
        sampleRate = 16_000
        maxDurationSeconds = 300
        self.feedbackEnabled = feedbackEnabled
        self.spokenPunctuation = spokenPunctuation
        self.filterFillerWords = filterFillerWords
        self.appendSpace = appendSpace
        self.replacements = replacements
    }

    /// Load the sanitized app bundle resource; missing or invalid profiles fail visibly.
    public static func load(bundle: Bundle = .main) throws -> DictationProfile {
        guard let url = bundle.url(forResource: "voxtype-profile", withExtension: "json") else {
            throw DictationFailure.invalidProfile("Bundle voxtype-profile.json as an app resource.")
        }
        let profile = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try profile.validate()
        return profile
    }

    /// Enforce the supported model and reject executable-looking replacement data.
    public func validate() throws {
        guard schemaVersion == 1, engine == "parakeet", model == "parakeet-tdt-0.6b-v3",
              sampleRate == 16_000, maxDurationSeconds == 300 else {
            throw DictationFailure.invalidProfile("Only Parakeet v3, 16 kHz, and 300 seconds are supported.")
        }
        var aliases = Set<String>()
        for replacement in replacements {
            let spoken = replacement.spoken
            guard spoken == spoken.lowercased(),
                  spoken.range(of: "\\A[a-z0-9]+(?:[ -][a-z0-9]+)*\\z", options: .regularExpression) != nil,
                  replacement.command.range(of: "\\A/(?:skill:)?[a-z0-9]+(?:-[a-z0-9]+)*\\z", options: .regularExpression) != nil,
                  aliases.insert(spoken).inserted else {
                throw DictationFailure.invalidProfile("Command aliases must be unique lowercase phrases and slash commands.")
            }
        }
    }
}

/// Recoverable dictation errors contain no audio or transcript payloads.
public enum DictationFailure: Error, LocalizedError, Sendable {
    case invalidProfile(String)
    case busy
    case notPrepared
    case notRecording
    case microphonePermission
    case inactiveApplication
    case invalidAudioFormat
    case audioBufferAllocation
    case audioConversion
    case audioBackpressure
    case emptyRecording

    public var errorDescription: String? {
        switch self {
        case .invalidProfile(let detail): "Dictation profile: \(detail)"
        case .busy: "Dictation busy: wait for the current operation to finish cancelling."
        case .notPrepared: "Dictation models: tap Download/Prepare before recording."
        case .notRecording: "Dictation recording: there is no active recording to stop."
        case .microphonePermission: "Dictation microphone: allow microphone access in Settings."
        case .inactiveApplication: "Dictation microphone: keep Pi Mobile in the foreground."
        case .invalidAudioFormat: "Dictation microphone: this input route has no usable audio format."
        case .audioBufferAllocation: "Dictation audio: could not allocate a microphone buffer."
        case .audioConversion: "Dictation audio: 16 kHz mono conversion failed."
        case .audioBackpressure: "Dictation audio: conversion could not keep up; recording was cancelled."
        case .emptyRecording: "Dictation audio: no microphone samples were captured."
        }
    }
}
