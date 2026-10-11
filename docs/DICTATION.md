# On-device dictation

## Approved public interface

`ios/PiMobile/Dictation/ParakeetDictation.swift` provides:

```swift
@MainActor public final class ParakeetDictation: ObservableObject {
    @Published public private(set) var state: String
    @Published public private(set) var errorMessage: String?
    @Published public var transcript: String
    @Published public private(set) var completedTranscriptID: UUID?

    public init(profile: DictationProfile? = nil, bundle: Bundle = .main)
    public func prepare() async throws
    public func startRecording() async throws
    public func stopRecording() async throws -> String
    public func cancelRecording()
}
```

- Initialization performs no download or permission request. **Only call `prepare()` after the user chooses Download/Prepare**, not from an automatic view task. It may fetch missing/recover corrupt model files. Repeated prepare with an initialized manager is a no-op.
- State strings are exactly `notDownloaded`, `loading`, `ready`, `recording`, `transcribing`, `error`. Initial `notDownloaded` means this instance has not prepared; it is not an authoritative disk-cache inventory.
- Start requires preparation and foreground microphone permission. It never downloads models. Permission denial and capture/inference failures publish an actionable error.
- Stop returns the same cleaned text it publishes to `transcript`. `transcript` is writable for editing. No prompt submission, clipboard mutation, transport call, terminal key, or user-visible notification occurs.
- At 300 seconds or 4,800,000 converted samples, recording stops and transcribes automatically. **Each successful transcription publishes a new `completedTranscriptID` after `transcript`**, even if the text repeats. The owning composer consumes that publication once for both manual Stop and cap completion. It never also inserts Stop's return value, and hidden/abandoned composers do not own the result.
- Cancellation discards the active recording/result, leaves the previous editable transcript untouched, and preserves model weights. Interrupted recordings never resume automatically. Call cancel when abandoning the dictation surface.
- Backgrounding, an audio interruption beginning, media-services reset, or an input-route/engine-format change cancels recording. Backgrounding/interruption also cancels pending inference. Route changes caused by our own Stop/deactivation do not cancel inference.
- Caller cancellation propagates to download/inference work. Cancelling during a native permission sheet cannot dismiss Apple's sheet; the eventual response is ignored and cannot start capture.
- Only one operation owns the SDK and audio buffers. Cancel sets a usable-looking state immediately, but a new operation can throw `DictationFailure.busy` until the previous asynchronous operation settles. Core ML work is cooperatively cancelled, not forcibly interrupted; stale results cannot overwrite a later recording.

## Build integration and actual upstream API

Target: iPhone, **iOS 17+**, arm64 Apple hardware. FluidAudio itself requires Swift tools **6.0+**; the complete app requires **Swift 6.2 / Xcode 26+** because of pinned SwiftTerm. Simulator compilation is not evidence of Neural Engine inference or microphone behavior.

`ios/project.yml` declares both the FluidAudio product dependency and the required exact pin:

```yaml
FluidAudio:
  url: https://github.com/FluidInference/FluidAudio.git
  revision: fc8c3e4f5103bf63a242453566525272e143a054
```

Keep that revision, not a floating branch/version. Include all four Dictation Swift sources in the app target and `ios/PiMobile/Resources/voxtype-profile.json` in Copy Bundle Resources. `NSMicrophoneUsageDescription` is required and is already present in the inspected parent Info.plist. No background-audio mode or notification entitlement is needed. The native composer wires explicit preparation, recording, cancellation and completed-result delivery.

API source of truth is `/tmp/pi-mobile-research/FluidAudio` at the pin:

- `Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift`: `AsrModels.downloadAndLoad(version: .v3)` returns actual loaded Core ML weights; default encoder precision is `.int8`.
- `…/AsrManager.swift`: `AsrManager(config: ASRConfig(parallelChunkConcurrency: 1), models: models)` initializes the manager actor. `transcribe(samples, decoderState: &decoderState)` returns `ASRResult.text`.
- `…/Decoder/TdtDecoderState.swift`: `try TdtDecoderState()` creates fresh two-layer decoder state per utterance.
- `Sources/FluidAudio/Shared/MLModelConfigurationUtils.swift`: persistent cache under the app sandbox's `Library/Application Support/FluidAudio/Models/`. The adapter marks the v3 cache excluded from backup.
- `Sources/FluidAudio/Shared/AudioConverter.swift`: converter input-block state uses `OSAllocatedUnfairLock` for Swift concurrency safety. Our capture converter follows that pattern but uses `.noDataNow` between buffers and `.endOfStream` only at Stop.

Some upstream GettingStarted/README examples still show `configure(models:)` or `source: .system`; those are **not** the batch API at this revision. Implementation follows source declarations, not those stale snippets.

## Models, memory, and privacy

Upstream `Documentation/ASR/GettingStarted.md` estimates **about 480 MB** for v3's default download. Allow extra temporary/cache/compiled-runtime storage; measure actual device storage before making UI size promises. Do not package placeholder weights or switch to the smaller Redux/Phonon-2 models (those require iOS 18 and are not v3). The SDK defaults to CPU/Apple Neural Engine placement; phone latency, thermal behavior, and memory still need measurement. Its default Swift 6.0 manifest also links the NeMo text-processing binary (upstream estimates roughly 8 MB per slice); this adapter does not invoke any LLM or cloud cleanup.

Only model acquisition uses network access, via FluidAudio's Hugging Face downloader. No downloader runs in Start/Stop. Microphone audio never leaves the device and is never written to disk. Conversion and inference are off the main actor:

1. AVAudioEngine taps the real input format (16 kHz is only a preferred hardware rate).
2. Tap-owned memory is copied before the callback returns. A bounded admission gate permits at most 32 copied buffers; overload fails rather than growing an unbounded queue or silently dropping speech.
3. A serial queue alone owns AVAudioConverter and the mutable sample array. Conversion yields 16 kHz, mono, noninterleaved Float32.
4. Stop removes the tap/stops the engine, closes admission, drains admitted buffers and converter output, then transfers an immutable sample snapshot. No concurrent array append/read occurs.
5. Detached inference uses a fresh decoder state; one chunk worker limits phone memory pressure. Cancellation clears capture data and rejects late results.

Five minutes of raw converted PCM is **19.2 MB** (4.8 million Float32 samples), not total process memory. Array capacity, model/runtime workspaces, copied input buffers, and long-form chunking add overhead. No microphone/transcript logging is added. Native light haptics replace desktop feedback sounds; no local/push notifications are used. NotificationCenter registrations here are internal audio/lifecycle observers only.

## Offline VoxType profile and cleaner

Regenerate with Python 3.11+:

```sh
python3 tools/import-voxtype.py /explicit/path/to/config.toml
```

The importer uses stdlib `tomllib`, opens **only the explicit TOML file**, and writes only the fixed owned resource path. It does not discover other configuration, expand shell/environment expressions, open cleanup scripts, or load credentials. Imported whitelist:

- Parakeet TDT 0.6b v3; 16,000 Hz; 300 seconds (other values fail).
- Feedback enabled, spoken punctuation, filler filtering.
- Slash-command replacement aliases, sorted by descending phrase length and lexical tie-break.
- `append_text` only when empty or one space, represented by `appendSpace`.

The current sanitized profile has **194 aliases**. Non-command replacements and desktop second-pass prefix repairs are omitted. Hotkeys, typing/clipboard modes, ydotool, shift-enter behavior, MPRIS, sound themes/paths, notifications, VAD configuration, post-process commands, and LLM-dependent `format:*` directives are not ported. The importer does not read or execute the configured desktop `gpt-cleanup.sh`. Initial research inspected that script read-only; it was never executed or ported, and no `.env` or credentials were read.

`DictationProfile.load(bundle:)` validates the bundle resource. A missing/invalid resource fails visibly rather than quietly dropping the user's aliases. `DictationTextProcessor(profile:)` is public and configurable; `process(_:) -> String` is synchronous, deterministic, offline, and safe to call off-main. It never executes its output.

- Case-insensitive, whole-token matching, longest phrase first; flexible horizontal spacing within phrases.
- One simultaneous pass over the original text: inserted `/skill:…` or `/…` cannot be matched again. Existing slash commands are protected, with attached sentence punctuation removed.
- English spoken punctuation: period/full stop, comma, colon, semicolon, question/exclamation mark, parentheses, new line, new paragraph. Existing punctuation/capitalization is otherwise retained; there is no grammar rewrite.
- Filler filtering removes **only `um` and `uh`**, plus an attached filler comma. It does not strip meaningful `like`, `well`, `you know`, or French `ben`.
- Whitespace cleanup preserves line/paragraph breaks. Nonempty output has exactly one trailing space when `appendSpace` is enabled; empty output remains empty.
- `joining(_:to:)` joins an already processed/edited transcript to an existing draft with one separator only when both adjoining characters are non-whitespace. It does not rerun cleanup or send anything. Example: draft `"Please"` plus transcript `"review this. "` becomes `"Please review this. "`.

## Verification boundary

After public-interface approval, XCTest vectors for the cleaner and unprepared/cancelled/invalid-profile service paths were authored. They are **uncompiled and unrun**; [TESTING.md](TESTING.md) explains the boundaries. This Linux pass performed Python lint/format/syntax and JSON structural checks plus manual upstream API/concurrency review. Swift checks/LSP are unavailable in the harness; no Swift compiler, Apple SDK build, simulator, model download, or device inference was run. Treat the Swift sources as unverified until compiled on a Mac.

Still verify on real iPhone hardware: first-download consent/cancellation/storage; cached relaunch in airplane mode; 44.1/48 kHz and Bluetooth routes; microphone denied/empty audio; native haptics; interruption/background/route cancellation; cancelling Stop/Prepare followed by immediate retry; five-minute cap and parent draft delivery without duplicate insertion; repeated short/long French and English recordings; temperature/memory/latency; exact aliases/overlap/token boundaries/slash punctuation/fillers/output joining; editable text and explicit Send only. Audio-network privacy should be checked with network instrumentation after models are cached.
