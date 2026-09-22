import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lift", category: "AppDelegate")
    private let settings = SettingsStore.shared
    private let permissions = PermissionManager()
    private let pointer = SystemPointerLocator()
    private let eventMonitor = EventMonitor()
    private let updateChecker = UpdateChecker()

    private var menuBarController: MenuBarController?
    private var engine: FocusEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }
        let engine = FocusEngine(settings: settings, resolver: WindowResolver(), actions: FocusActions(), pointer: pointer)
        self.engine = engine
        eventMonitor.delegate = engine
        let menuBarController = MenuBarController(settings: settings)
        menuBarController.onMenuTrackingChange = { [weak engine] isTracking in engine?.setSuspended(isTracking) }
        menuBarController.onCheckForUpdates = { [weak self] in self?.updateChecker.check() }
        self.menuBarController = menuBarController

        updateChecker.onResult = { [weak menuBarController] version in
            menuBarController?.availableUpdate = version
        }
        updateChecker.check()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name: SettingsStore.didChangeNotification, object: nil)
        permissions.onAccessGranted = { [weak self] in self?.startEngine() }
        permissions.requestAccess()
    }

    func applicationWillTerminate(_ notification: Notification) { eventMonitor.stop() }

    private func startEngine() {
        guard !eventMonitor.isRunning else { return }
        eventMonitor.start()
        logger.notice("Motor aktif (gecikme: \(self.settings.delayMs, privacy: .public) ms)")
    }
   
    @objc private func settingsDidChange() { engine?.settingsDidChange() }

    private static var isRunningUnitTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
}
