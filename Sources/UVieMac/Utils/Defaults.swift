import Foundation

enum DefaultsKey {
    static let inputMethod = "InputMethod"
    static let modernOrthography = "ModernOrthography"
    static let relaxedCoda = "RelaxedCoda"
    static let checkSpelling = "CheckSpelling"
    static let smartSwitchKey = "SmartSwitchKey"
    static let uppercaseFirstChar = "UppercaseFirstChar"
    static let macroEnabled = "MacroEnabled"
    static let inputMethodHotkey = "InputMethodHotkey"
    static let inputMethodHotkeyEnabled = "InputMethodHotkeyEnabled"
    static let onboardingCompleted = "OnboardingCompleted"
    static let engineEnabled = "EngineEnabled"
    static let autoDisableOnNonLatinLayout = "AutoDisableOnNonLatinLayout"
    static let quickTelex = "QuickTelex"
    static let quickStart = "QuickStart"
    static let editCommittedWords = "EditCommittedWords"
    /// NaturalLanguage sentence-language hint (see `ContextLanguageDetector`).
    static let contextLanguageDetection = "ContextLanguageDetection"
    static let customCompoundApps = "CustomCompoundApps"
    static let customChromiumApps = "CustomChromiumApps"
    static let customExcludedApps = "CustomExcludedApps"
    static let customBypassApps = "CustomBypassApps"
    /// Bundle IDs the user removed from the built-in default lists. Stored
    /// separately because the custom lists only hold user additions; writing
    /// them alone silently restored every default app on the next launch.
    static let removedCompoundApps = "RemovedCompoundApps"
    static let removedChromiumApps = "RemovedChromiumApps"
    static let removedBypassApps = "RemovedBypassApps"
    /// Dev-build fallback for the "auto install updates" toggle; packaged
    /// builds read/write Sparkle's own `automaticallyDownloadsUpdates`.
    static let autoInstallUpdates = "AutoInstallUpdates"
    static let customToggleEnabled = "CustomToggleEnabled"
    static let customToggleKeyCode = "CustomToggleKeyCode"
    static let customToggleModifiers = "CustomToggleModifiers"
    /// Feature flag for the optional UVieIM input-source mode (off by
    /// default - when off, every code path behaves exactly as before).
    static let inputSourceModeEnabled = "InputSourceModeEnabled"
    /// "marked" (default) renders the composing word as marked text; "direct"
    /// replaces the word's UTF-16 range in place.
    static let inputSourceStyle = "InputSourceStyle"
    /// The keyboard layout ID to return to when the UVie input method is
    /// deselected.
    static let inputSourcePreviousLayout = "InputSourcePreviousLayout"
}

/// Registers the app's factory defaults - only applied when a key has never
/// been set. Shared by the app (`applicationDidFinishLaunching`) and the
/// UVieIM input-method process so a missing key resolves identically in both.
func registerFactoryDefaults() {
    UserDefaults.standard.register(defaults: [
        DefaultsKey.engineEnabled:      true,
        DefaultsKey.checkSpelling:      true,
        DefaultsKey.smartSwitchKey:     true,
        DefaultsKey.uppercaseFirstChar: false,
        DefaultsKey.macroEnabled:       false,
        DefaultsKey.modernOrthography:  true,
        DefaultsKey.relaxedCoda:        false,
        DefaultsKey.inputMethod:        "telex",
        DefaultsKey.inputMethodHotkeyEnabled: true,
        DefaultsKey.autoDisableOnNonLatinLayout: true,
        DefaultsKey.quickTelex:         false,
        DefaultsKey.quickStart:         false,
        DefaultsKey.contextLanguageDetection: true,
        DefaultsKey.autoInstallUpdates: true,
    ])
}
