import ApplicationServices
import AppKit
import Combine
import Foundation

@MainActor
final class AccessibilityPermissionService: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    private var cancellables = Set<AnyCancellable>()

    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    func startMonitoring() {
        refresh()

        guard cancellables.isEmpty else {
            return
        }

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func requestAccess() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary

        isTrusted = AXIsProcessTrustedWithOptions(options)
    }
}
