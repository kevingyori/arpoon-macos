import Combine
import AppKit

@MainActor
protocol OptionHoldHUDControlling: AnyObject {
    var onShow: (() -> Void)? { get set }
    var onHide: (() -> Void)? { get set }

    func start()
    func setSuppressed(_ isSuppressed: Bool)
    /// Called when an Arpoon shortcut fires, so a held Option that's part of a chord
    /// (e.g. ⌥S, ⌥S, ⌥S) doesn't also bring up the hold HUD.
    func noteShortcutTriggered()
}

@MainActor
final class OptionHoldHUDController: OptionHoldHUDControlling {
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    private let settings: SettingsStore
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var holdTask: DispatchWorkItem?
    private var optionPressed = false
    /// Set once Option is used as part of a chord; cleared only when Option is fully released,
    /// so adding/removing Shift mid-chord can't re-arm the hold HUD.
    private var optionUsedInChord = false
    private var hudVisible = false
    private var suppressed = false
    private var settingsCancellable: AnyCancellable?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard settingsCancellable == nil else {
            return
        }

        settingsCancellable = settings.$showHUDOnOptionHold
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.setMonitoringEnabled(isEnabled)
            }
    }

    func noteShortcutTriggered() {
        // Only Option-based chords should consume the current Option press; otherwise the flag
        // would linger and block the next genuine hold.
        guard NSEvent.modifierFlags.contains(.option) else {
            return
        }

        markOptionUsedInChord()
    }

    func setSuppressed(_ isSuppressed: Bool) {
        suppressed = isSuppressed

        if isSuppressed {
            cancelHold()
            hideHUDIfNeeded()
        }
    }

    private func setMonitoringEnabled(_ isEnabled: Bool) {
        if isEnabled {
            startMonitoring()
        } else {
            optionPressed = false
            cancelHold()
            hideHUDIfNeeded()
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard localMonitor == nil, globalMonitor == nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let type = event.type
            let flags = event.modifierFlags
            Task { @MainActor in
                self?.handle(type: type, flags: flags)
            }
        }
    }

    private func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        handle(type: event.type, flags: event.modifierFlags)
    }

    private func handle(type: NSEvent.EventType, flags: NSEvent.ModifierFlags) {
        // Any key pressed while Option is down (⌥← in an editor, an Arpoon chord, …) means
        // Option is being used as a modifier, not held on its own.
        if type == .keyDown {
            if flags.contains(.option) {
                markOptionUsedInChord()
            }
            return
        }

        if !flags.contains(.option) {
            optionUsedInChord = false
        }

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
                if !optionUsedInChord {
                    scheduleHold()
                }
            }
        } else {
            optionPressed = false
            cancelHold()
            hideHUDIfNeeded()
        }
    }

    private func markOptionUsedInChord() {
        optionUsedInChord = true
        cancelHold()

        // The shortcut's own feedback replaces the hold HUD. Hiding it here also means releasing
        // Option afterwards won't dismiss that feedback early.
        hideHUDIfNeeded()
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
