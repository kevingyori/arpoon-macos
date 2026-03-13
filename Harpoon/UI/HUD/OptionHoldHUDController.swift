import AppKit

@MainActor
final class OptionHoldHUDController {
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    private let settings: SettingsStore
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var holdTask: DispatchWorkItem?
    private var optionPressed = false
    private var hudVisible = false
    private var suppressed = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard localMonitor == nil, globalMonitor == nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(flags: event.modifierFlags)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.handle(flags: event.modifierFlags)
            }
        }
    }

    func setSuppressed(_ isSuppressed: Bool) {
        suppressed = isSuppressed

        if isSuppressed {
            cancelHold()
            hideHUDIfNeeded()
        }
    }

    private func handle(flags: NSEvent.ModifierFlags) {
        guard settings.showHUDOnOptionHold, !suppressed else {
            cancelHold()
            hideHUDIfNeeded()
            return
        }

        let normalizedFlags = flags.intersection(.deviceIndependentFlagsMask)
        let optionOnly = normalizedFlags == [.option]

        if optionOnly {
            if !optionPressed {
                optionPressed = true
                scheduleHold()
            }
        } else {
            optionPressed = false
            cancelHold()
            hideHUDIfNeeded()
        }
    }

    private func scheduleHold() {
        cancelHold()

        let task = DispatchWorkItem { [weak self] in
            guard let self, self.optionPressed, self.settings.showHUDOnOptionHold, !self.suppressed else {
                return
            }

            self.hudVisible = true
            self.onShow?()
        }

        holdTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.optionHoldDuration, execute: task)
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
    }

    private func hideHUDIfNeeded() {
        guard hudVisible else {
            return
        }

        hudVisible = false
        onHide?()
    }
}
