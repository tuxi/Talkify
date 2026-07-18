import Foundation
import Observation

@Observable
public final class AppPreferences {
    public var defaultRemoveWatermark: Bool {
        didSet {
            UserDefaults.standard.set(defaultRemoveWatermark, forKey: Key.defaultRemoveWatermark)
        }
    }

    public var autoPlayPreview: Bool {
        didSet {
            UserDefaults.standard.set(autoPlayPreview, forKey: Key.autoPlayPreview)
        }
    }

    public var wifiOnlyDownload: Bool {
        didSet {
            UserDefaults.standard.set(wifiOnlyDownload, forKey: Key.wifiOnlyDownload)
        }
    }

    public init() {
        let defaults = UserDefaults.standard
        self.defaultRemoveWatermark = Self.readBool(defaults, key: Key.defaultRemoveWatermark, defaultValue: false)
        self.autoPlayPreview = Self.readBool(defaults, key: Key.autoPlayPreview, defaultValue: true)
        self.wifiOnlyDownload = Self.readBool(defaults, key: Key.wifiOnlyDownload, defaultValue: true)
    }

    private static func readBool(_ defaults: UserDefaults, key: String, defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : defaultValue
    }
}

private enum Key {
    static let defaultRemoveWatermark = "settings.default_remove_watermark"
    static let autoPlayPreview = "settings.auto_play_preview"
    static let wifiOnlyDownload = "settings.wifi_only_download"
}
