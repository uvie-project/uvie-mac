import Foundation
import Carbon

/// Monitors keyboard layout changes and notifies when non-Latin layout is active.
/// Used for "Auto-disable on non-Latin layout" feature.
final class KeyboardLayoutMonitor: ObservableObject {
    static let shared = KeyboardLayoutMonitor()

    @Published var isNonLatinLayout: Bool = false

    private var currentSource: TISInputSource?

    private init() {
        checkCurrentLayout()
        startMonitoring()
    }

    /// Check if current keyboard layout is Latin-based
    private func checkCurrentLayout() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            isNonLatinLayout = false
            return
        }
        currentSource = source
        isNonLatinLayout = !isLatinLayout(source)
    }

    /// Check if input source uses Latin script
    private func isLatinLayout(_ source: TISInputSource) -> Bool {
        // Preferred signal: the input source's primary language. The keyboard
        // layout ID is a poor classifier — "Ukrainian" contains the Latin
        // keyword "UK", "Serbian" vs "Serbian-Latin" differ by a suffix, and
        // many non-Latin layouts ship IDs with no script keyword at all
        // (Kazakh, Mongolian, Nepali, Tamil, Sinhala, Persian, Pashto,
        // Belarusian, …). Those were classified Latin, so the engine stayed
        // enabled on a layout whose keys are all non-ASCII — and swallowed
        // every keystroke. The language code is authoritative.
        if let languagesPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let languages = Unmanaged<CFArray>.fromOpaque(languagesPtr)
                .takeUnretainedValue() as? [String] ?? []
            if let primary = languages.first {
                return Self.isLatinLanguage(primary)
            }
        }
        // Fallback: keyword classification on the input source ID.
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return true // Default to Latin if can't determine
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        return Self.isLatinSourceID(sourceID)
    }

    /// ISO language codes whose default script is not Latin. Kept deliberately
    /// conservative: a wrong "non-Latin" verdict disables the IME for a user
    /// who needs it, while a wrong "Latin" verdict leaves the engine enabled
    /// on a layout it cannot process (the worse failure — it swallows keys).
    /// Script subtags ("-Latn"/"-Cyrl"/…) override the primary code.
    static let nonLatinLanguages: Set<String> = [
        // Cyrillic
        "ru", "uk", "be", "bg", "sr", "mk", "kk", "ky", "tg", "mn", "tt",
        "ba", "cv", "ce", "os", "ab", "udm", "sah", "kv", "ady", "av", "dar",
        "kbd", "lez", "mhr", "myv", "koi", "kum", "nog", "tyv", "xal", "bua",
        // Other non-Latin scripts
        "ka", "hy", "el", "ar", "fa", "ur", "ps", "sd", "ku", "ckb", "he",
        "yi", "dv", "syr", "ug", "th", "lo", "km", "my", "bo", "dz", "ne",
        "hi", "bn", "pa", "gu", "or", "ta", "te", "kn", "ml", "si", "as",
        "mai", "mr", "sa", "zh", "ja", "ko", "am", "ti", "chr", "iu", "ii",
        "yue", "wuu", "hak", "nan",
    ]

    /// Classifies an ISO language code (e.g. "en", "ru", "sr-Latn") as Latin
    /// script. Static + internal so tests can drive it without touching TIS.
    static func isLatinLanguage(_ code: String) -> Bool {
        let lowered = code.lowercased()
        // Explicit script subtag wins (e.g. "sr-Latn" is Latin, "az-Cyrl" is not).
        if lowered.contains("-latn") || lowered.contains("_latn") { return true }
        if lowered.contains("-cyrl") || lowered.contains("_cyrl") { return false }
        let primary = lowered.split(separator: "-").first.map(String.init) ?? lowered
        return !nonLatinLanguages.contains(primary)
    }

    /// Classifies an input-source ID as Latin (true) or non-Latin (false).
    /// Static + internal so tests can drive it without touching TIS.
    ///
    /// The non-Latin check runs FIRST: source IDs like "Ukrainian" contain
    /// the Latin keyword "UK" as a substring, and a Cyrillic layout must not
    /// be classified Latin just because of that substring.
    static func isLatinSourceID(_ sourceID: String) -> Bool {
        // A Latin-script variant of a script that has both forms
        // ("Serbian-Latin", "Azeri-Latin") is Latin even though its ID
        // contains the non-Latin keyword.
        if sourceID.localizedCaseInsensitiveContains("-Latin") {
            return true
        }

        // Non-Latin layouts typically contain these keywords
        let nonLatinKeywords = [
            "Chinese", "Japanese", "Korean", "Kotoeri", "Hiragana", "Katakana",
            "Pinyin", "Wubi", "Bopomofo", "Cangjie", "Simplified", "Traditional",
            "Hangul", "Hanja", "Russian", "Greek", "Arabic", "Hebrew", "Thai",
            "Hindi", "Devanagari", "Cyrillic", "Georgian", "Armenian",
            "Ukrainian", "Macedonian", "Bulgarian", "Farsi", "Urdu",
            // Scripts whose IDs carry no "-Latin" suffix and were previously
            // misclassified as Latin (their keys are non-ASCII). Dual-script
            // layouts that are Latin by default (Azeri, Uzbek, Turkmen) are
            // deliberately NOT listed — their "-Cyrillic" variants still match
            // the "Cyrillic" keyword, and a wrong non-Latin verdict would
            // disable the IME for a user who needs it.
            "Persian", "Pashto", "Kurdish", "Kazakh", "Kyrgyz", "Mongolian",
            "Tatar", "Bashkir", "Chuvash", "Belarusian", "Serbian",
            "Nepali", "Sinhala", "Tamil", "Telugu",
            "Kannada", "Malayalam", "Gujarati", "Gurmukhi", "Punjabi",
            "Bengali", "Oriya", "Myanmar", "Burmese", "Khmer", "Lao", "Tibetan",
            "Amharic", "Ethiopic", "Cherokee", "Inuktitut", "Syriac", "Yiddish",
            "Divehi", "Dhivehi", "Uyghur", "Tigrinya", "Assamese",
            "Marathi", "Sanskrit", "Tigre",
        ]

        for keyword in nonLatinKeywords {
            if sourceID.localizedCaseInsensitiveContains(keyword) {
                return false
            }
        }

        // Common Latin-based input sources
        let latinKeywords = [
            "ABC", "US", "UK", "French", "German", "Spanish", "Italian",
            "Portuguese", "Dutch", "Swedish", "Norwegian", "Danish", "Finnish",
            "Polish", "Czech", "Hungarian", "Romanian", "Slovak", "Slovenian",
            "Croatian", "Serbian-Latin", "Estonian", "Latvian", "Lithuanian",
            "Turkish", "Vietnamese", "Telex", "VNI", "British", "Irish",
            "Icelandic", "Welsh", "Maltese", "Albanian", "Bosnian", "Filipino",
            "Indonesian", "Malay", "Swahili", "Afrikaans", "Catalan", "Basque",
            "Galician", "Dvorak", "Colemak", "QWERTY", "AZERTY",
        ]

        // Check if source ID contains any Latin keyword
        for keyword in latinKeywords {
            if sourceID.localizedCaseInsensitiveContains(keyword) {
                return true
            }
        }

        // Default: assume Latin for unknown layouts
        return true
    }

    /// Start monitoring keyboard layout changes
    private func startMonitoring() {
        // Distributed notification for input source changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    @objc private func inputSourceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.checkCurrentLayout()
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
