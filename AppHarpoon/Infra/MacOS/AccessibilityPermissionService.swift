import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityPermissionService: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    func requestAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        isTrusted = AXIsProcessTrustedWithOptions(options)
    }
}
