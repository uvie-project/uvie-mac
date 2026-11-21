import Foundation

/// Constants shared by the app and the UVieIM input-method bundle (the same
/// executable, distinguished by bundle identifier).
enum InputSourceIdentity {
    /// The input method's bundle identifier - also its TIS input source ID.
    static let bundleID = "com.uvie-project.inputmethod.UVie"
    /// The named connection IMK clients use to reach the input method server.
    static let connectionName = "UVie_IM_Connection"
    /// The app's UserDefaults domain. The IM process adds it as a suite so
    /// every `UserDefaults.standard` read in shared code sees the app's
    /// settings without code changes.
    static let appDefaultsSuite = "com.uvie-project.UVieMac"
    /// Distributed notification posted by the app (and observed by the IM
    /// process) when any input-method-relevant setting changes.
    static let settingsChangedNotification = "com.uvie-project.UVieMac.settingsChanged"
}
