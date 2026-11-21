import Foundation

/// The engine-relevant part of settings, shared by the event tap
/// (`EventTap.applyEngineSettings`) and the input-method composer
/// (`InputSourceComposer.reloadSettings`). Callers keep their own
/// reset-on-method-change logic and flag caches; this only pushes values to
/// the engine.
enum EngineSettings {
    static func apply(to engine: EngineBridge, defaults: UserDefaults) {
        let method = defaults.string(forKey: DefaultsKey.inputMethod) ?? "telex"
        engine.setInputMethod(InputMethod(rawValue: method) ?? .telex)
        engine.setModernOrthography(defaults.bool(forKey: DefaultsKey.modernOrthography))
        engine.setRelaxedCoda(defaults.bool(forKey: DefaultsKey.relaxedCoda))
        engine.setQuickTelex(defaults.bool(forKey: DefaultsKey.quickTelex))
        engine.setQuickStart(defaults.bool(forKey: DefaultsKey.quickStart))
        // Restore-English-words override (dictionary passthrough). The
        // checkSpelling key defaults to true; treat a missing key as enabled.
        engine.setEnglishOverride(
            defaults.object(forKey: DefaultsKey.checkSpelling) == nil
                || defaults.bool(forKey: DefaultsKey.checkSpelling)
        )
    }
}
