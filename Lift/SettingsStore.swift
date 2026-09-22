import Foundation

protocol FocusSettings: AnyObject {
    var isEnabled: Bool { get }
    var delayMs: Int { get }
    var typingGuardMs: Int { get }
}

extension FocusSettings {
    var delay: TimeInterval { TimeInterval(delayMs) / 1000 }
    var typingGuard: TimeInterval { TimeInterval(typingGuardMs) / 1000 }
}

final class SettingsStore: FocusSettings {
    static let shared = SettingsStore()
    static let didChangeNotification = Notification.Name("SettingsStoreDidChangeNotification")
    static let delayOptions = [0, 100, 150, 300, 500]

    private enum Key {
        static let isEnabled = "isEnabled"
        static let delayMs = "delayMs"
        static let typingGuardMs = "typingGuardMs"
    }

    private enum Fallback {
        static let isEnabled = true
        static let delayMs = 150
        static let typingGuardMs = 1000
    }

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        defaults.register(defaults: [
            Key.isEnabled: Fallback.isEnabled,
            Key.delayMs: Fallback.delayMs,
            Key.typingGuardMs: Fallback.typingGuardMs,
        ])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set { write(newValue, forKey: Key.isEnabled) }
    }

    var delayMs: Int {
        get { defaults.integer(forKey: Key.delayMs) }
        set { write(newValue, forKey: Key.delayMs) }
    }

    var typingGuardMs: Int {
        get { defaults.integer(forKey: Key.typingGuardMs) }
        set { write(newValue, forKey: Key.typingGuardMs) }
    }

    private func write(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}
