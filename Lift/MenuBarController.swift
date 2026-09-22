import AppKit
import ServiceManagement
import os

final class MenuBarController: NSObject, NSMenuDelegate {
    private static let statusIconName = "cursorarrow.rays"

    private let settings: SettingsStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lift", category: "MenuBarController")

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let enabledItem = NSMenuItem(title: "Etkin", action: nil, keyEquivalent: "e")
    private let delayItem = NSMenuItem(title: "Gecikme", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Girişte başlat", action: nil, keyEquivalent: "")
    private var delayOptionItems: [NSMenuItem] = []

    var onMenuTrackingChange: ((Bool) -> Void)?

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        super.init()
        configureStatusItem()
        buildMenu()
        refreshState()
    }

    private func configureStatusItem() {
        if let image = NSImage(systemSymbolName: Self.statusIconName, accessibilityDescription: "Lift") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "Lift"
        }
        statusItem.menu = menu
    }

    private func buildMenu() {
        menu.delegate = self

        enabledItem.target = self
        enabledItem.action = #selector(toggleEnabled)
        menu.addItem(enabledItem)

        let delaySubmenu = NSMenu()
        delayOptionItems = SettingsStore.delayOptions.map { option in
            let item = NSMenuItem(title: Self.delayTitle(forMilliseconds: option),
                                  action: #selector(selectDelay(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = option
            delaySubmenu.addItem(item)
            return item
        }
        delayItem.submenu = delaySubmenu
        menu.addItem(delayItem)

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Çıkış", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private static func delayTitle(forMilliseconds milliseconds: Int) -> String {
        milliseconds == 0 ? "Anında" : "\(milliseconds) ms"
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) { refreshState() }

    func menuWillOpen(_ menu: NSMenu) { onMenuTrackingChange?(true) }

    func menuDidClose(_ menu: NSMenu) { onMenuTrackingChange?(false) }

    // MARK: - Eylemler

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        logger.notice("Etkin: \(self.settings.isEnabled, privacy: .public)")
        refreshState()
    }

    @objc private func selectDelay(_ sender: NSMenuItem) {
        settings.delayMs = sender.tag
        refreshState()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            logger.error("Girişte başlat değiştirilemedi: \(error.localizedDescription, privacy: .public)")
        }
        refreshState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Durum

    private func refreshState() {
        enabledItem.state = settings.isEnabled ? .on : .off
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let currentDelay = settings.delayMs
        for item in delayOptionItems {
            item.state = item.tag == currentDelay ? .on : .off
        }
        delayItem.title = "Gecikme (\(Self.delayTitle(forMilliseconds: currentDelay)))"
    }
}
