import Foundation
import PiMobile
import XCTest

/// Dictation cleanup vectors exercise the public inert-text interface, not regex implementation details.
final class DictationTextProcessorTests: XCTestCase {
    func testLongestSpokenAliasWinsWithoutRecursiveExpansion() throws {
        let profile = DictationProfile(replacements: [
            .init(spoken: "run check", command: "/check"),
            .init(spoken: "run check now", command: "/check-now"),
            .init(spoken: "check", command: "/skill:check"),
        ])
        let cleaner = try DictationTextProcessor(profile: profile)
        XCTAssertEqual(cleaner.process("RUN check now."), "/check-now ")
        XCTAssertEqual(cleaner.process("run check"), "/check ")
    }

    func testCommandsKeepTheirSlashAndLoseASRSentencePunctuation() throws {
        let cleaner = try DictationTextProcessor()
        XCTAssertEqual(cleaner.process("/skill:slop-go. /review!"), "/skill:slop-go /review ")
    }

    func testAliasDoesNotMatchInsideAnIdentifierOrPath() throws {
        let cleaner = try DictationTextProcessor(profile: DictationProfile(replacements: [
            .init(spoken: "review", command: "/review"),
        ]))
        XCTAssertEqual(cleaner.process("preview /tmp/review review_queue review-now"),
            "preview /tmp/review review_queue review-now ")
    }

    func testSpokenPunctuationPreservesParagraphs() throws {
        let cleaner = try DictationTextProcessor()
        XCTAssertEqual(cleaner.process("Hello comma world new paragraph Next line period"),
            "Hello, world\n\nNext line. ")
    }

    func testFillerRemovalPreservesMeaningfulWordsAndFrench() throws {
        let cleaner = try DictationTextProcessor()
        XCTAssertEqual(cleaner.process("Um, I like this, well, you know, ben oui."),
            "I like this, well, you know, ben oui. ")
    }

    func testOptionalCleanupAndTrailingSpaceCanBeDisabled() throws {
        let profile = DictationProfile(spokenPunctuation: false, filterFillerWords: false, appendSpace: false)
        let cleaner = try DictationTextProcessor(profile: profile)
        XCTAssertEqual(cleaner.process("um comma well"), "um comma well")
    }

    func testEmptySpeechDoesNotAppendASeparator() throws {
        let cleaner = try DictationTextProcessor()
        XCTAssertEqual(cleaner.process("um uh"), "")
        XCTAssertEqual(cleaner.joining("", to: "Existing draft"), "Existing draft")
    }

    func testDraftJoiningDoesNotGlueWordsOrReprocessEditedText() throws {
        let cleaner = try DictationTextProcessor()
        XCTAssertEqual(cleaner.joining("review this. ", to: "Please"), "Please review this. ")
        XCTAssertEqual(cleaner.joining("review this. ", to: "Please\n"), "Please\nreview this. ")
        XCTAssertEqual(cleaner.joining("comma", to: "Edited"), "Edited comma")
    }

    func testDuplicateAliasesFailBeforeAnyTranscription() {
        let profile = DictationProfile(replacements: [
            .init(spoken: "run check", command: "/check"),
            .init(spoken: "run check", command: "/different"),
        ])
        XCTAssertThrowsError(try DictationTextProcessor(profile: profile)) { error in
            guard let failure = error as? DictationFailure, case .invalidProfile = failure else {
                return XCTFail("Expected invalid-profile error, got \(error)")
            }
        }
    }

    func testBundledVoxTypeProfileIsAvailableAndKeepsExistingCommands() throws {
        let profile = try DictationProfile.load(bundle: .main)
        XCTAssertFalse(profile.replacements.isEmpty)
        let cleaner = try DictationTextProcessor(profile: profile)
        XCTAssertEqual(cleaner.process("/skill:slop-go."), "/skill:slop-go ")
    }
}
