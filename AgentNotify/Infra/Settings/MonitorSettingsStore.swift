import Foundation

protocol MonitorSettingsStoring: AnyObject {
    var isMuted: Bool { get set }
    var alertCooldown: TimeInterval { get set }
}

final class MonitorSettingsStore: MonitorSettingsStoring {
    private enum Key {
        static let isMuted = "monitor.isMuted"
        static let alertCooldown = "monitor.alertCooldown"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isMuted: Bool {
        get {
            defaults.object(forKey: Key.isMuted) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Key.isMuted)
        }
    }

    var alertCooldown: TimeInterval {
        get {
            defaults.object(forKey: Key.alertCooldown) as? Double ?? 60
        }
        set {
            defaults.set(newValue, forKey: Key.alertCooldown)
        }
    }
}
