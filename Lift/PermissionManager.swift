import ApplicationServices
import Foundation
import os

final class PermissionManager {
    private static let pollInterval: TimeInterval = 1.0

    // Erişilebilirlik ayarı değiştiğinde macOS bu bildirimi yayınlar. Ancak
    // bildirim anında AXIsProcessTrusted() hâlâ eski değeri döndürebiliyor, bu
    // yüzden durum hemen değil kısa bir gecikmeyle okunur.
    private static let accessibilityChangedNotification = Notification.Name("com.apple.accessibility.api")
    private static let settlingDelay: TimeInterval = 0.5

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lift", category: "PermissionManager")
    private var pollTimer: Timer?
    private var isObservingChanges = false
    private var lastKnownTrust: Bool?

    var onAccessGranted: (() -> Void)?
    var onAccessRevoked: (() -> Void)?

    deinit {
        pollTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func requestAccess() {
        observeChanges()

        guard !AXIsProcessTrusted() else {
            reconcile()
            return
        }

        logger.notice("AX izni yok; sistem diyaloğu açılıyor.")
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        startPolling()
    }

    // Tek doğruluk kaynağı: gerçek izin durumunu son bilinen durumla karşılaştırır
    // ve yalnızca değiştiğinde haber verir. Bildirim de yoklama da buraya düşer.
    private func reconcile() {
        let trusted = AXIsProcessTrusted()
        guard trusted != lastKnownTrust else { return }
        lastKnownTrust = trusted

        if trusted {
            stopPolling()
            logger.notice("AX izni verildi; motor başlatılıyor.")
            onAccessGranted?()
        } else {
            logger.notice("AX izni geri alındı; motor durduruluyor.")
            onAccessRevoked?()
            startPolling()
        }
    }

    private func observeChanges() {
        guard !isObservingChanges else { return }
        isObservingChanges = true

        DistributedNotificationCenter.default().addObserver(
            forName: Self.accessibilityChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settlingDelay) { [weak self] in
                self?.reconcile()
            }
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
