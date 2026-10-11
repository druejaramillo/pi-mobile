import PiMobile
import XCTest

/// Unprepared/cancelled lifecycle tests never download weights, request a microphone or run inference.
final class ParakeetDictationLifecycleTests: XCTestCase {
    @MainActor
    func testRecordingRequiresExplicitPreparation() async {
        let dictation = ParakeetDictation()
        do {
            try await dictation.startRecording()
            XCTFail("Recording must require explicit model preparation.")
        } catch DictationFailure.notPrepared {
            XCTAssertEqual(dictation.state, "notDownloaded")
            XCTAssertNil(dictation.completedTranscriptID)
            XCTAssertEqual(dictation.transcript, "")
        } catch { XCTFail("Unexpected recording error: \(error)") }
    }

    @MainActor
    func testStopCannotInventATranscriptWithoutARecording() async {
        let dictation = ParakeetDictation()
        do {
            _ = try await dictation.stopRecording()
            XCTFail("Stop must not fabricate a transcript.")
        } catch DictationFailure.notRecording {
            XCTAssertEqual(dictation.transcript, "")
            XCTAssertNil(dictation.completedTranscriptID)
        } catch { XCTFail("Unexpected stop error: \(error)") }
    }

    @MainActor
    func testCancellationPreservesPreviouslyEditedText() async {
        let dictation = ParakeetDictation()
        dictation.transcript = "Keep my edited instruction."
        dictation.cancelRecording()
        dictation.cancelRecording()
        XCTAssertEqual(dictation.transcript, "Keep my edited instruction.")
        XCTAssertNil(dictation.completedTranscriptID)
        XCTAssertEqual(dictation.state, "notDownloaded")
    }

    @MainActor
    func testInvalidProfilePreparationFailsBeforeModelAcquisition() async {
        let profile = DictationProfile(replacements: [.init(spoken: "UPPERCASE", command: "/check")])
        let dictation = ParakeetDictation(profile: profile)
        do {
            try await dictation.prepare()
            XCTFail("Invalid profiles must fail before model acquisition.")
        } catch DictationFailure.invalidProfile(_) {
            XCTAssertEqual(dictation.state, "error")
            XCTAssertNotNil(dictation.errorMessage)
            XCTAssertNil(dictation.completedTranscriptID)
        } catch { XCTFail("Unexpected prepare error: \(error)") }
        dictation.cancelRecording()
    }
}
