import AppKit
import Combine
import Foundation
@preconcurrency
import Quartz

struct TrackpadGestureUpdate: Equatable {
    let horizontalStepCount: Int
    let verticalStepCount: Int
    let horizontalFractionalOffset: Double
    let verticalFractionalOffset: Double
    let totalHorizontalOffset: Double
    let totalVerticalOffset: Double
}

private struct UncheckedSendableValue<T>: @unchecked Sendable {
    let value: T
}

private final class EventTapResultBox: @unchecked Sendable {
    var result: Unmanaged<CGEvent>?
}

final class TrackpadGestureController {
    var onGestureBegan: (() -> Void)?
    var onGestureEnded: (() -> Void)?
    var onGestureUpdate: ((TrackpadGestureUpdate) -> Void)?

    private let settings: SettingsStore
    private var settingsCancellables = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var suppressed = false
    private var gestureActive = false
    private var accumulatedHorizontalDelta = 0.0
    private var accumulatedVerticalDelta = 0.0
    private var totalHorizontalOffset = 0.0
    private var totalVerticalOffset = 0.0
    private var currentHotkeyScheme: HotkeyScheme
    private var currentNiriTrackpadGesturesEnabled: Bool
    private var currentTrackpadGestureModifier: TrackpadGestureModifier

    // The minimap cells are much wider than they are tall, and vertical trackpad
    // scroll tends to come through a bit hotter than horizontal in practice.
    // Bias the thresholds so the on-screen pill feels more even across axes.
    private let horizontalActionThreshold = 74.0
    private let verticalActionThreshold = 52.0
    private let edgeInset = 24.0
    private let dominantAxisCrossBlendFloor = 0.12
    private let secondaryAxisCrossBlendFloor = 0.22
    private let crossAxisBlendExponent = 1.7

    @MainActor
    init(settings: SettingsStore) {
        self.settings = settings
        currentHotkeyScheme = settings.hotkeyScheme
        currentNiriTrackpadGesturesEnabled = settings.enableNiriTrackpadGestures
        currentTrackpadGestureModifier = settings.trackpadGestureModifier

        settings.$hotkeyScheme
            .sink { [weak self] in
                self?.currentHotkeyScheme = $0
            }
            .store(in: &settingsCancellables)

        settings.$enableNiriTrackpadGestures
            .sink { [weak self] in
                self?.currentNiriTrackpadGesturesEnabled = $0
            }
            .store(in: &settingsCancellables)

        settings.$trackpadGestureModifier
            .sink { [weak self] in
                self?.currentTrackpadGestureModifier = $0
            }
            .store(in: &settingsCancellables)
    }

    deinit {
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
    }

    func start() {
        guard localMonitor == nil, globalMonitor == nil, eventTap == nil else {
            return
        }

        if installEventTap() {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self else {
                return event
            }

            return self.processLocalMonitorEvent(event) ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.processScrollEvent(event)
        }
    }

    func setSuppressed(_ isSuppressed: Bool) {
        suppressed = isSuppressed

        if isSuppressed {
            resetGestureTracking()
        }
    }

    @discardableResult
    func handleScroll(
        deltaX: Double,
        deltaY: Double,
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        hasPreciseScrollingDeltas: Bool,
        modifierFlags: NSEvent.ModifierFlags,
        mouseLocation: CGPoint,
        timestamp: TimeInterval
    ) -> TrackpadGestureUpdate? {
        guard !suppressed,
              supportsTrackpadGestures(for: currentHotkeyScheme),
              currentNiriTrackpadGesturesEnabled else {
            resetGestureTracking()
            return nil
        }

        if phase.contains(.ended) || phase.contains(.cancelled) ||
            momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
            resetGestureTracking()
            return nil
        }

        guard hasPreciseScrollingDeltas else {
            resetGestureTracking()
            return nil
        }

        let gateSatisfied = gateAllows(modifierFlags: modifierFlags, mouseLocation: mouseLocation)
        guard gateSatisfied || gestureActive else {
            resetGestureTracking()
            return nil
        }

        if !momentumPhase.isEmpty {
            return nil
        }

        guard !phase.isEmpty else {
            return nil
        }

        if !gestureActive {
            gestureActive = true
            notifyGestureBegan()
        }

        let adjustedDelta = adjustedGestureDelta(deltaX: deltaX, deltaY: deltaY)
        accumulatedHorizontalDelta += adjustedDelta.x
        accumulatedVerticalDelta += adjustedDelta.y
        totalHorizontalOffset += adjustedDelta.x / horizontalActionThreshold
        totalVerticalOffset += adjustedDelta.y / verticalActionThreshold

        let update = TrackpadGestureUpdate(
            horizontalStepCount: extractStepCount(from: &accumulatedHorizontalDelta, threshold: horizontalActionThreshold),
            verticalStepCount: extractStepCount(from: &accumulatedVerticalDelta, threshold: verticalActionThreshold),
            horizontalFractionalOffset: accumulatedHorizontalDelta / horizontalActionThreshold,
            verticalFractionalOffset: accumulatedVerticalDelta / verticalActionThreshold,
            totalHorizontalOffset: totalHorizontalOffset,
            totalVerticalOffset: totalVerticalOffset
        )
        notifyGestureUpdate(update)
        return update
    }

    private func adjustedGestureDelta(deltaX: Double, deltaY: Double) -> (x: Double, y: Double) {
        let absoluteX = abs(deltaX)
        let absoluteY = abs(deltaY)

        guard absoluteX > 0, absoluteY > 0 else {
            return (deltaX, deltaY)
        }

        if absoluteY >= absoluteX {
            return (
                deltaX * crossAxisBlend(crossAxisMagnitude: absoluteX, dominantAxisMagnitude: absoluteY, floor: dominantAxisCrossBlendFloor),
                deltaY
            )
        }

        return (
            deltaX,
            deltaY * crossAxisBlend(crossAxisMagnitude: absoluteY, dominantAxisMagnitude: absoluteX, floor: secondaryAxisCrossBlendFloor)
        )
    }

    private func crossAxisBlend(crossAxisMagnitude: Double, dominantAxisMagnitude: Double, floor: Double) -> Double {
        guard dominantAxisMagnitude > 0 else {
            return 1
        }

        let ratio = min(max(crossAxisMagnitude / dominantAxisMagnitude, 0), 1)
        return floor + (1 - floor) * pow(ratio, crossAxisBlendExponent)
    }

    private func processLocalMonitorEvent(_ event: NSEvent) -> Bool {
        let shouldConsume = shouldConsumeScrollEvent(event)
        processScrollEvent(event)
        return shouldConsume
    }

    private func processScrollEvent(_ event: NSEvent) {
        _ = handleScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            modifierFlags: event.modifierFlags,
            mouseLocation: NSEvent.mouseLocation,
            timestamp: event.timestamp
        )
    }

    private func installEventTap() -> Bool {
        let eventMask = (1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let controller = Unmanaged<TrackpadGestureController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handleTapEvent(type: type, event: event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let tapLocations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]

        for location in tapLocations {
            guard let eventTap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: refcon
            ) else {
                continue
            }

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
                continue
            }

            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)

            self.eventTap = eventTap
            self.eventTapSource = source
            return true
        }

        return false
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if Thread.isMainThread {
            return processTapEvent(type: type, event: event)
        }

        let controller = UncheckedSendableValue(value: self)
        let wrappedEvent = UncheckedSendableValue(value: event)
        let resultBox = EventTapResultBox()
        DispatchQueue.main.sync {
            resultBox.result = controller.value.processTapEvent(type: type, event: wrappedEvent.value)
        }
        return resultBox.result ?? Unmanaged.passUnretained(event)
    }

    private func processTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel,
              let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        let shouldConsume = shouldConsumeScrollEvent(nsEvent)
        processScrollEvent(nsEvent)
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func shouldConsumeScrollEvent(_ event: NSEvent) -> Bool {
        shouldConsumeTrackpadScroll(
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            modifierFlags: event.modifierFlags,
            mouseLocation: NSEvent.mouseLocation
        )
    }

    func shouldConsumeTrackpadScroll(
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        hasPreciseScrollingDeltas: Bool,
        modifierFlags: NSEvent.ModifierFlags,
        mouseLocation: CGPoint
    ) -> Bool {
        guard !suppressed,
              supportsTrackpadGestures(for: currentHotkeyScheme),
              currentNiriTrackpadGesturesEnabled,
              hasPreciseScrollingDeltas else {
            return false
        }

        if phase.contains(.ended) || phase.contains(.cancelled) ||
            momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
            return gestureActive
        }

        if gateAllows(modifierFlags: modifierFlags, mouseLocation: mouseLocation) {
            return true
        }

        return gestureActive
    }

    private func supportsTrackpadGestures(for scheme: HotkeyScheme) -> Bool {
        scheme == .niri || scheme == .grid
    }

    private func gateAllows(modifierFlags: NSEvent.ModifierFlags, mouseLocation: CGPoint) -> Bool {
        let expectedModifier: NSEvent.ModifierFlags
        switch currentTrackpadGestureModifier {
        case .option:
            expectedModifier = .option
        case .command:
            expectedModifier = .command
        case .control:
            expectedModifier = .control
        case .shift:
            expectedModifier = .shift
        }
        return modifierFlags.contains(expectedModifier)
    }

    private func extractStepCount(from accumulator: inout Double, threshold: Double) -> Int {
        var stepCount = 0

        while abs(accumulator) >= threshold {
            if accumulator > 0 {
                accumulator -= threshold
                stepCount += 1
            } else {
                accumulator += threshold
                stepCount -= 1
            }
        }

        return stepCount
    }

    private func resetGestureTracking() {
        if gestureActive {
            gestureActive = false
            notifyGestureEnded()
        }

        accumulatedHorizontalDelta = 0
        accumulatedVerticalDelta = 0
        totalHorizontalOffset = 0
        totalVerticalOffset = 0
    }

    private func notifyGestureBegan() {
        onGestureBegan?()
    }

    private func notifyGestureUpdate(_ update: TrackpadGestureUpdate) {
        onGestureUpdate?(update)
    }

    private func notifyGestureEnded() {
        onGestureEnded?()
    }
}
