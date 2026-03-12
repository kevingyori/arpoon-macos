import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityPermissionService: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    private var refreshTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    func startMonitoring() {
        refresh()

        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    func requestAccess() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary

        isTrusted = AXIsProcessTrustedWithOptions(options)
    }
}
