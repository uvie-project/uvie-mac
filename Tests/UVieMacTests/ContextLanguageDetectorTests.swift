import XCTest
@testable import UVieMac

/// Sentence-language verdicts the engine receives at every word commit.
/// Expectations are the NLLanguageRecognizer probabilities measured on macOS
/// with `languageConstraints` `[.vietnamese, .english]` (see the thresholds in
/// `ContextLanguageDetector`).
final class ContextLanguageDetectorTests: XCTestCase {
    func test_vietnameseSentenceWithEnglishNouns_isVietnamese() {
        let detector = ContextLanguageDetector()
        XCTAssertEqual(detector.hint(for: "deploy server nó", pendingRaw: ""), .vietnamese)
        XCTAssertGreaterThanOrEqual(detector.lastVietnameseProbability, 0.80)
        XCTAssertEqual(detector.hint(for: "review code có", pendingRaw: ""), .vietnamese)
        XCTAssertEqual(detector.hint(for: "em", pendingRaw: ""), .vietnamese)
    }

    func test_englishSentence_needsThreeWordsAndHighProbability() {
        let detector = ContextLanguageDetector()
        XCTAssertEqual(detector.hint(for: "the car is", pendingRaw: ""), .english)
        XCTAssertGreaterThanOrEqual(detector.lastEnglishProbability, 0.95)
        // Two English nouns alone stay auto: a Vietnamese sentence can open
        // with them ("deploy server nó").
        XCTAssertEqual(detector.hint(for: "deploy server", pendingRaw: ""), .auto)
        // A single English word never flips the sentence to English.
        XCTAssertEqual(detector.hint(for: "car", pendingRaw: ""), .auto)
        // Below the English threshold.
        XCTAssertEqual(detector.hint(for: "ok", pendingRaw: ""), .auto)
    }

    func test_emptyText_isAuto() {
        let detector = ContextLanguageDetector()
        XCTAssertEqual(detector.hint(for: "", pendingRaw: ""), .auto)
        XCTAssertEqual(detector.hint(for: "   ", pendingRaw: ""), .auto)
        XCTAssertEqual(detector.lastText, "")
    }

    /// The parameter exists for experiments: raw keystrokes are appended to
    /// the sentence before recognition.
    func test_pendingRaw_isAppendedToTheSentence() {
        let detector = ContextLanguageDetector()
        XCTAssertEqual(detector.hint(for: "deploy server", pendingRaw: " nó"), .vietnamese)
        XCTAssertEqual(detector.lastText, "deploy server nó")
    }

    func test_repeatedText_reusesTheCachedVerdict() {
        let detector = ContextLanguageDetector()
        XCTAssertEqual(detector.hint(for: "the car is", pendingRaw: ""), .english)
        let vi = detector.lastVietnameseProbability
        let en = detector.lastEnglishProbability
        XCTAssertEqual(detector.hint(for: "the car is", pendingRaw: ""), .english)
        XCTAssertEqual(detector.lastVietnameseProbability, vi)
        XCTAssertEqual(detector.lastEnglishProbability, en)

        // A different sentence recomputes.
        XCTAssertEqual(detector.hint(for: "chào bạn", pendingRaw: ""), .vietnamese)
        XCTAssertNotEqual(detector.lastText, "the car is")
    }
}
