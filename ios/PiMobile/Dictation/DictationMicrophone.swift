@preconcurrency import AVFoundation
import Foundation
import os

/// Engine/session lifecycle is main-actor-only; deinit owns the final emergency stop.
/// Sendability is limited to teardown: no engine or mutable samples cross executors.
final class DictationMicrophone: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var sessionActive = false
    private var accumulator: DictationAudioAccumulator?

    @MainActor
    func start(maximumSamples: Int, onEvent: @escaping @Sendable (DictationCaptureEvent) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setPreferredSampleRate(16_000) // A preference, never assumed to be the hardware rate.
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
            sessionActive = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw DictationFailure.invalidAudioFormat
            }
            let accumulator = try DictationAudioAccumulator(inputFormat: format, maximumSamples: maximumSamples, onEvent: onEvent)
            self.accumulator = accumulator
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                accumulator.enqueue(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }
    }

    @MainActor
    func finish() async throws -> [Float] {
        stopEngine()
        guard let accumulator else { throw DictationFailure.emptyRecording }
        // The serial queue barrier drains copied buffers and the converter before
        // transferring its array. Recording cannot mutate the returned array.
        let samples = try await accumulator.finish()
        self.accumulator = nil
        return samples
    }

    @MainActor
    func cancel() {
        accumulator?.cancel()
        accumulator = nil
        stopEngine()
    }

    private func stopEngine() {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }

    deinit {
        accumulator?.cancel()
        stopEngine()
    }
}

enum DictationCaptureEvent: Sendable {
    case limitReached
    case failure(DictationFailure)
}

/// AVAudioEngine owns tap memory; this independent copy is immutable after construction.
private struct DictationOwnedAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(copying source: AVAudioPCMBuffer) throws {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else {
            throw DictationFailure.audioBufferAllocation
        }
        copy.frameLength = source.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { throw DictationFailure.audioConversion }
        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData,
                  sourceBuffers[index].mDataByteSize <= destinationBuffers[index].mDataByteSize else {
                throw DictationFailure.audioConversion
            }
            memcpy(destinationData, sourceData, Int(sourceBuffers[index].mDataByteSize))
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }
        buffer = copy
    }
}

/// Converter and sample array have one serial owner; only the admission gate uses a lock.
private final class DictationAudioAccumulator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "PiMobile.Dictation.AudioConversion", qos: .userInitiated)
    private let gate = NSLock()
    private var accepting = true // gate-owned
    private var cancelled = false // gate-owned
    private var pending = 0 // gate-owned; bounds copied input buffers to 32
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let maximumSamples: Int
    private let onEvent: @Sendable (DictationCaptureEvent) -> Void
    private var samples: [Float] = [] // queue-owned
    private var failure: DictationFailure? // queue-owned
    private var reachedLimit = false // queue-owned

    init(inputFormat: AVAudioFormat, maximumSamples: Int,
         onEvent: @escaping @Sendable (DictationCaptureEvent) -> Void) throws {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output) else {
            throw DictationFailure.invalidAudioFormat
        }
        self.converter = converter
        outputFormat = output
        self.maximumSamples = maximumSamples
        self.onEvent = onEvent
        converter.primeMethod = .none
    }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        gate.lock()
        defer { gate.unlock() }
        guard accepting, !cancelled else { return }
        guard pending < 32 else {
            accepting = false
            queue.async { self.fail(.audioBackpressure) }
            return
        }
        pending += 1
        // Hold admission through copy + enqueue, so finish's queue barrier
        // cannot overtake a tap callback that already owns a buffer slot.
        do {
            let copy = try DictationOwnedAudioBuffer(copying: buffer)
            queue.async {
                defer { self.gate.lock(); self.pending -= 1; self.gate.unlock() }
                guard !self.isCancelled, self.failure == nil, !self.reachedLimit else { return }
                do { try self.convert(copy) }
                catch { self.fail(.audioConversion) }
            }
        } catch {
            pending -= 1
            accepting = false
            queue.async { self.fail(.audioBufferAllocation) }
        }
    }

    private func closeAdmission() {
        gate.lock()
        accepting = false
        gate.unlock()
    }

    func finish() async throws -> [Float] {
        closeAdmission()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard !self.isCancelled else { throw CancellationError() }
                    if let failure = self.failure { throw failure }
                    if !self.reachedLimit { try self.flushConverter() }
                    guard !self.samples.isEmpty else { throw DictationFailure.emptyRecording }
                    let snapshot = self.samples
                    self.samples = []
                    continuation.resume(returning: snapshot)
                } catch {
                    self.samples = []
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancel() {
        gate.lock()
        cancelled = true
        accepting = false
        gate.unlock()
        queue.async { self.samples = [] }
    }

    private var isCancelled: Bool {
        gate.lock()
        defer { gate.unlock() }
        return cancelled
    }

    private func convert(_ input: DictationOwnedAudioBuffer) throws {
        let capacity = AVAudioFrameCount(ceil(Double(input.buffer.frameLength) * 16_000 / input.buffer.format.sampleRate) + 256)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw DictationFailure.audioBufferAllocation
        }
        // Like upstream AudioConverter, use a lock for the input-block flag:
        // AVAudioConverter invokes synchronously, but its callback is @Sendable.
        let suppliedInput = OSAllocatedUnfairLock(initialState: false)
        // .noDataNow retains converter state between tap buffers (not EOF).
        while true {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                let alreadySupplied = suppliedInput.withLock { supplied -> Bool in
                    if supplied { return true }
                    supplied = true
                    return false
                }
                if alreadySupplied { inputStatus.pointee = .noDataNow; return nil }
                inputStatus.pointee = .haveData
                return input.buffer
            }
            guard status != .error, error == nil else { throw DictationFailure.audioConversion }
            append(output)
            if reachedLimit || status == .inputRanDry || status == .endOfStream || output.frameLength == 0 { break }
        }
    }

    private func flushConverter() throws {
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1_024) else {
            throw DictationFailure.audioBufferAllocation
        }
        while true {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard status != .error, error == nil else { throw DictationFailure.audioConversion }
            append(output)
            if reachedLimit || status == .endOfStream || status == .inputRanDry || output.frameLength == 0 { break }
        }
    }

    private func append(_ output: AVAudioPCMBuffer) {
        guard let channel = output.floatChannelData?[0] else { return }
        let count = min(Int(output.frameLength), maximumSamples - samples.count)
        if count > 0 { samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count)) }
        if samples.count == maximumSamples, !reachedLimit {
            reachedLimit = true
            gate.lock()
            accepting = false
            gate.unlock()
            onEvent(.limitReached)
        }
    }

    private func fail(_ error: DictationFailure) {
        guard failure == nil, !isCancelled else { return }
        failure = error
        gate.lock()
        accepting = false
        gate.unlock()
        samples = []
        onEvent(.failure(error))
    }
}
