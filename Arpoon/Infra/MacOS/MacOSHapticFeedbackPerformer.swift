import AppKit
import Foundation

@MainActor
final class MacOSHapticFeedbackPerformer: HapticFeedbackPerforming {
    private let minimumInterval: TimeInterval
    private let followUpDelayNanoseconds: UInt64
    private var lastFeedbackDate = Date.distantPast
    private var pendingFollowUpTask: Task<Void, Never>?

    init(
        minimumInterval: TimeInterval = 0.12,
        followUpDelayNanoseconds: UInt64 = 35_000_000
    ) {
        self.minimumInterval = minimumInterval
        self.followUpDelayNanoseconds = followUpDelayNanoseconds
    }

    func performFocusConfirmation() {
        let now = Date()
        guard now.timeIntervalSince(lastFeedbackDate) >= minimumInterval else {
            return
        }

        lastFeedbackDate = now
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        pendingFollowUpTask?.cancel()
        pendingFollowUpTask = Task { @MainActor [followUpDelayNanoseconds] in
            try? await Task.sleep(nanoseconds: followUpDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
