import Foundation
import NaturalLanguage

/// Sentence-language verdict the host hands the engine at commit time
/// (`uvie_engine_set_context_hint`). The engine reads it as the language of
/// the sentence being typed, so a Vietnamese sentence keeps the marks on
/// ambiguous words ("nó", "cả", "có") and an English sentence restores its
/// English words instead of rendering fake Vietnamese.
enum ContextHint: UInt8 {
    case auto = 0
    case vietnamese = 1
    case english = 2

    /// Short name used in keystroke-trace lines.
    var traceName: String {
        switch self {
        case .auto: return "auto"
        case .vietnamese: return "vi"
        case .english: return "en"
        }
    }
}

/// Recognizes the language of the sentence being typed with Apple's
/// NaturalLanguage framework.
///
/// One recognizer is reused for the engine's lifetime — `NLLanguageRecognizer`
/// is expensive to allocate and the language constraints are re-applied on
/// every call. A constrained call over a short sentence measures ~1 ms, which
/// is why the verdict is only asked for at a word commit (once per space) and
/// the last `(text → hint)` answer is cached: the same sentence can be
/// committed again (punctuation after a space, a retried commit) without
/// paying twice.
///
/// Thresholds (measured with `languageConstraints` `[.vietnamese, .english]`):
/// "deploy server nó" vi=1.00, "em" vi=0.97, "the car is" en=1.00,
/// "deploy server" en=1.00, "car" en=0.98, "ok" en=0.74. Two English nouns
/// alone are not enough to call a sentence English — a Vietnamese sentence
/// can open with them ("deploy server nó") — so English also needs three
/// words.
final class ContextLanguageDetector {
    private let recognizer = NLLanguageRecognizer()

    /// Last recognized text and its verdict (see `hint(for:pendingRaw:)`).
    private var cachedText: String?
    private var cachedHint: ContextHint = .auto

    /// Probabilities of the last recognized text (0…1), for the keystroke
    /// trace. They belong to the cache: the same text yields the same numbers,
    /// so a cache hit does not recompute them.
    private(set) var lastVietnameseProbability: Double = 0
    private(set) var lastEnglishProbability: Double = 0
    /// The trimmed text the last verdict was computed from.
    private(set) var lastText = ""

    /// Vietnamese wins from 0.80 — a Vietnamese sentence with English nouns
    /// still scores high, while an English one scores near zero. English needs
    /// a much higher 0.95 plus a three-word sentence.
    static let vietnameseThreshold = 0.80
    static let englishThreshold = 0.95
    static let englishMinimumWords = 3

    /// Language hint for `sentence` (the engine's committed sentence text,
    /// see `EngineBridge.sentenceText()`) plus `pendingRaw`, the raw
    /// keystrokes of the word about to commit. `sentence_text` already
    /// excludes the composing word and the commit renders that word under the
    /// language of the sentence BEFORE it, so callers pass `""`; the parameter
    /// stays for experiments.
    func hint(for sentence: String, pendingRaw: String) -> ContextHint {
        let text = (sentence + pendingRaw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // Nothing to judge — the engine's own rules decide.
            lastText = ""
            lastVietnameseProbability = 0
            lastEnglishProbability = 0
            return .auto
        }
        if text == cachedText {
            return cachedHint
        }

        recognizer.reset()
        recognizer.languageConstraints = [.vietnamese, .english]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        let vi = hypotheses[.vietnamese] ?? 0
        let en = hypotheses[.english] ?? 0

        let hint: ContextHint
        if vi >= Self.vietnameseThreshold {
            hint = .vietnamese
        } else if en >= Self.englishThreshold,
                  text.split(whereSeparator: { $0.isWhitespace }).count >= Self.englishMinimumWords {
            hint = .english
        } else {
            hint = .auto
        }

        cachedText = text
        cachedHint = hint
        lastText = text
        lastVietnameseProbability = vi
        lastEnglishProbability = en
        return hint
    }
}
