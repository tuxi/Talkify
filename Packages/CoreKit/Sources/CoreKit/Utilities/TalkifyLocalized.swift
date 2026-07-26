import Foundation

/// Talkify localization helper that wraps String Catalog lookups with an injectable bundle.
///
/// FeatureAuth and ClientToolsKit use ``TalkifyLocalized/bundle-swift.type.property``
/// to route lookups to the host app's `Localizable.xcstrings` rather than their own
/// (possibly empty) package resource bundles.
///
/// In tests, inject a test bundle that contains a test `.xcstrings` / `.strings` file:
///
/// ```swift
/// TalkifyLocalized.bundle = Bundle(for: type(of: self))
/// ```
public enum TalkifyLocalized {
    /// The bundle used for all localized string lookups. Defaults to `.main`.
    ///
    /// - Important: This is a mutable global. It should only be set during app / test
    ///   launch and must never be changed after the UI is displayed.
    public static nonisolated(unsafe) var bundle: Bundle = .main

    /// Returns a localized string for the given key.
    ///
    /// The key must match an entry in the `Localizable.xcstrings` String Catalog.
    /// If no translation is found, the key itself is returned as a development signal.
    ///
    /// - Parameters:
    ///   - key: The semantic key in the String Catalog (e.g. `"common.action.cancel"`).
    ///   - comment: Optional context for translators (unused at runtime; reserved for tooling).
    /// - Returns: The localized string, or `key` if no match is found.
    public static func string(_ key: String, comment: String = "") -> String {
        // NSLocalizedString searches the compiled .strings resources (derived from
        // .xcstrings at build time) in the given bundle. It returns `key` itself
        // when no match is found, which serves as a development signal.
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: comment)
    }
}
