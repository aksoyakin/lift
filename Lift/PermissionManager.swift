import ApplicationServices
import Foundation
import os

final class PermissionManager {
    private static let pollInterval: TimeInterval = 1.0

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lift", category: "PermissionManager")
    private var pollTimer: Timer?

    var onAccessGranted: (() -> Void)?

    deinit { pollTimer?.invalidate() }

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccess() {
        guard !AXIsProcessTrusted() else {
            logger.notice("AX izni mevcut; motor başlatılıyor.")
            onAccessGranted?()
            return
        }

        logger.notice("AX izni yok; sistem diyaloğu açılıyor.")
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        startPolling()
    }

    private func startPolling() {
        guard pollTimer == nil else { return }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            guard let self, AXIsProcessTrusted() else { return }
            self.stopPolling()
            self.logger.notice("AX izni verildi; motor otomatik başlatılıyor.")
            self.onAccessGranted?()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
