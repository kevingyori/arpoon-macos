import AppKit
import Carbon
import XCTest
@testable import Arpoon

@MainActor
final class AppRuntimeAndCommandCenterTests: XCTestCase {
    func testRuntimeStartIsIdempotentAndDedupesEquivalentConfigurations() {
        let settings = makeSettings()
        let dynamicStore = makeDynamicHotkeyStore()
        let permissions = FakePermissionService()
        let hotkeys = FakeHotkeyController()
        let optionHold = FakeOptionHoldHUDController()

        let coordinator = AppRuntimeCoordinator(
            settings: settings,
            accessibilityPermissions: permissions,
            dynamicHotkeyStore: dynamicStore,
            hotkeyController: hotkeys,
            optionHoldHUDController: optionHold
        )

        coordinator.start()
        coordinator.start()

        XCTAssertEqual(permissions.startMonitoringCount, 1)
        XCTAssertEqual(optionHold.startCount, 1)
        XCTAssertEqual(hotkeys.configurations.count, 1)

        settings.hotkeyScheme = settings.hotkeyScheme
        XCTAssertEqual(hotkeys.configurations.count, 1)

        dynamicStore.bind(
            shortcut: HotkeyShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(optionKey)),
            target: .app(AppTarget(bundleId: "com.example.browser", appName: "Browser"))
        )
        XCTAssertEqual(hotkeys.configurations.count, 2)
    }

    func testRuntimeRecordingStateSuspendsAndResumesHotkeys() {
        let hotkeys = FakeHotkeyController()
        let optionHold = FakeOptionHoldHUDController()
        let coordinator = AppRuntimeCoordinator(
            settings: makeSettings(),
            accessibilityPermissions: FakePermissionService(),
            dynamicHotkeyStore: makeDynamicHotkeyStore(),
            hotkeyController: hotkeys,
            optionHoldHUDController: optionHold
        )

        coordinator.setHotkeyRecordingActive(true)
        coordinator.setHotkeyRecordingActive(false)

        XCTAssertEqual(hotkeys.suspendCount, 1)
        XCTAssertEqual(hotkeys.resumeCount, 1)
        XCTAssertEqual(optionHold.suppressedStates, [true, false])
    }

    func testSlotAndDynamicJumpShareTargetFallbackPath() {
        let slotStore = makeSlotStore()
        let dynamicStore = makeDynamicHotkeyStore()
        let target = Target.app(AppTarget(bundleId: "com.example.notes", appName: "Notes"))
        let shortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey))

        slotStore.bind(slot: 1, target: target)
        dynamicStore.bind(shortcut: shortcut, target: target)

        let focus = FakeFocusService()
        focus.targetOutcome = .focused(label: "Notes", strategy: nil)

        let commandCenter = makeCommandCenter(
            slotStore: slotStore,
            dynamicStore: dynamicStore,
            focusService: focus
        )

        commandCenter.jump(to: 1)
        commandCenter.jump(using: shortcut)

        XCTAssertEqual(focus.focusedTargets, [target, target])
    }

    func testClearOperationsRemoveCachedWindows() {
        let liveWindow = LiveWindow(
            bundleId: "com.example.term",
            appName: "Terminal",
            pid: 42,
            title: "Shell",
            windowID: 7,
            frame: WindowFrame(x: 10, y: 10, width: 400, height: 300),
            isMain: true,
            isFocused: true,
            axElement: nil
        )

        let windowTarget = Target.window(
            WindowTarget(
                bundleId: liveWindow.bundleId,
                appName: liveWindow.appName,
                pid: liveWindow.pid,
                windowTitle: liveWindow.title,
                windowID: liveWindow.windowID,
                frame: liveWindow.frame,
                capturedAt: .now
            )
        )
        let shortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey))
        let slotStore = makeSlotStore()
        let dynamicStore = makeDynamicHotkeyStore()
        let capture = FakeCaptureService()
        capture.outcome = CaptureOutcome(target: windowTarget, source: .window, liveWindow: liveWindow)

        let resolution = FakeResolutionService()
        resolution.result = .window(liveWindow, strategy: .exactTitle)

        let commandCenter = makeCommandCenter(
            slotStore: slotStore,
            dynamicStore: dynamicStore,
            captureService: capture,
            resolutionService: resolution
        )

        commandCenter.bindFocusedTarget(to: 1)
        XCTAssertTrue(commandCenter.hasCachedSlotWindow(for: 1))
        commandCenter.clear(slot: 1)
        XCTAssertFalse(commandCenter.hasCachedSlotWindow(for: 1))

        dynamicStore.bind(shortcut: shortcut, target: windowTarget)
        commandCenter.jump(using: shortcut)
        XCTAssertTrue(commandCenter.hasCachedDynamicWindow(for: shortcut))
        commandCenter.clearDynamicHotkey(shortcut: shortcut)
        XCTAssertFalse(commandCenter.hasCachedDynamicWindow(for: shortcut))
    }

    func testDynamicShortcutValidationRejectsConfiguredActionShortcut() {
        let commandCenter = makeCommandCenter()
        let duplicateShortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))

        XCTAssertEqual(
            commandCenter.validationErrorForDynamicShortcut(duplicateShortcut),
            "Already assigned to Add Hotkey for Focused Target."
        )
    }

    func testTheoStoreSeedsThreeLayersOnFirstLoad() async {
        let store = makeTheoStore()

        await store.load()

        XCTAssertEqual(store.layers.count, 3)
        XCTAssertEqual(store.layers.map(\.name), ["Project 1", "Project 2", "Project 3"])
    }

    func testTheoBindUsesCurrentLayerAndTool() async throws {
        let theoStore = makeTheoStore()
        let theoSession = TheoSession()
        await theoStore.load()
        theoSession.sync(layers: theoStore.layers)
        let firstLayer = try XCTUnwrap(theoStore.layers.first)
        let browserColumn = try XCTUnwrap(firstLayer.defaultColumn(kind: .browser))
        let terminalColumn = try XCTUnwrap(firstLayer.defaultColumn(kind: .terminal))
        _ = theoSession.selectTool(browserColumn, in: firstLayer)

        let target = Target.app(AppTarget(bundleId: "com.example.browser", appName: "Browser"))
        let capture = FakeCaptureService()
        capture.outcome = CaptureOutcome(target: target, source: .appFallback, liveWindow: nil)

        let commandCenter = makeCommandCenter(
            theoStore: theoStore,
            theoSession: theoSession,
            captureService: capture
        )

        commandCenter.bindFocusedTargetToTheoCurrentContext()

        let updatedLayer = try XCTUnwrap(theoStore.layers.first)
        XCTAssertEqual(updatedLayer.group(for: browserColumn).activeBinding?.target, target)
        XCTAssertTrue(updatedLayer.group(for: terminalColumn).bindings.isEmpty)
    }

    func testTheoJumpUsesCurrentToolAcrossLayers() async throws {
        let theoStore = makeTheoStore()
        let theoSession = TheoSession()
        await theoStore.load()

        let browserOne = Target.app(AppTarget(bundleId: "com.example.browser.one", appName: "Browser One"))
        let browserTwo = Target.app(AppTarget(bundleId: "com.example.browser.two", appName: "Browser Two"))
        let firstLayerID = try XCTUnwrap(theoStore.layers.first?.id)
        let secondLayerID = try XCTUnwrap(theoStore.layers.dropFirst().first?.id)
        let browserColumn = try XCTUnwrap(theoStore.layers.first?.defaultColumn(kind: .browser))
        _ = theoStore.replaceBinding(layerID: firstLayerID, tool: browserColumn, bindingID: nil, target: browserOne)
        _ = theoStore.replaceBinding(layerID: secondLayerID, tool: browserColumn, bindingID: nil, target: browserTwo)

        theoSession.sync(layers: theoStore.layers)
        _ = theoSession.selectTool(browserColumn, in: theoStore.layers.first)

        let focus = FakeFocusService()
        focus.targetOutcome = .focused(label: "Browser Two", strategy: nil)

        let commandCenter = makeCommandCenter(
            theoStore: theoStore,
            theoSession: theoSession,
            focusService: focus
        )

        commandCenter.jumpToTheoLayer(2)

        XCTAssertEqual(focus.focusedTargets.last, browserTwo)
        XCTAssertEqual(theoSession.currentLayerID, secondLayerID)
        XCTAssertEqual(theoSession.currentTool(in: theoStore.layer(id: secondLayerID)), browserColumn)
    }

    func testTheoStorePersistsCustomColumnsAlongsideDefaults() async throws {
        let store = makeTheoStore()

        await store.load()

        let layer = try XCTUnwrap(store.layers.first)
        let customColumn = try XCTUnwrap(store.addCustomColumn(layerID: layer.id))
        store.renameColumn(layerID: layer.id, columnID: TheoToolColumn.terminal.id, name: "Shells")
        store.setColumnIcon(layerID: layer.id, columnID: TheoToolColumn.browser.id, iconSymbol: "safari")
        store.renameColumn(layerID: layer.id, columnID: customColumn.id, name: "Docs")
        store.setColumnIcon(layerID: layer.id, columnID: customColumn.id, iconSymbol: "book")

        let updatedLayer = try XCTUnwrap(store.layers.first)
        XCTAssertEqual(updatedLayer.defaultColumn(kind: .terminal)?.title, "Shells")
        XCTAssertEqual(updatedLayer.defaultColumn(kind: .browser)?.iconSymbol, "safari")
        XCTAssertEqual(updatedLayer.columns.count, 4)
        XCTAssertEqual(updatedLayer.column(id: customColumn.id)?.title, "Docs")
        XCTAssertEqual(updatedLayer.column(id: customColumn.id)?.iconSymbol, "book")
    }

    private func makeCommandCenter(
        slotStore: SlotStore? = nil,
        dynamicStore: DynamicHotkeyStore? = nil,
        theoStore: TheoStore? = nil,
        theoSession: TheoSession? = nil,
        captureService: FakeCaptureService = FakeCaptureService(),
        resolutionService: FakeResolutionService = FakeResolutionService(),
        focusService: FakeFocusService = FakeFocusService()
    ) -> AppCommandCenter {
        AppCommandCenter(
            settings: makeSettings(),
            accessibilityPermissions: FakePermissionService(),
            slotStore: slotStore ?? makeSlotStore(),
            dynamicHotkeyStore: dynamicStore ?? makeDynamicHotkeyStore(),
            theoStore: theoStore ?? makeTheoStore(),
            theoSession: theoSession ?? TheoSession(),
            labelPolicy: TargetLabelPolicy(),
            captureService: captureService,
            resolutionService: resolutionService,
            focusService: focusService,
            windowProvider: FakeWindowProvider(),
            hudController: FakeHUDPresenter(),
            setHotkeyRecordingActive: { _ in }
        )
    }

    private func makeSettings() -> SettingsStore {
        let suiteName = "ArpoonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(defaults: defaults)
    }

    private func makeSlotStore() -> SlotStore {
        SlotStore(store: InMemoryAssignmentStore(), labelPolicy: TargetLabelPolicy())
    }

    private func makeDynamicHotkeyStore() -> DynamicHotkeyStore {
        DynamicHotkeyStore(
            store: InMemoryDynamicHotkeyAssignmentStore(),
            labelPolicy: TargetLabelPolicy()
        )
    }

    private func makeTheoStore() -> TheoStore {
        TheoStore(
            store: InMemoryTheoLayerStore(),
            labelPolicy: TargetLabelPolicy()
        )
    }
}

private final class InMemoryAssignmentStore: AssignmentStore {
    private var assignments: [SlotAssignment] = []

    func loadAssignments() async throws -> [SlotAssignment] {
        assignments
    }

    func saveAssignments(_ assignments: [SlotAssignment]) async throws {
        self.assignments = assignments
    }
}

private final class InMemoryDynamicHotkeyAssignmentStore: DynamicHotkeyAssignmentStore {
    private var assignments: [DynamicHotkeyAssignment] = []

    func loadAssignments() async throws -> [DynamicHotkeyAssignment] {
        assignments
    }

    func saveAssignments(_ assignments: [DynamicHotkeyAssignment]) async throws {
        self.assignments = assignments
    }
}

private final class InMemoryTheoLayerStore: TheoLayerStore {
    private var layers: [TheoLayer] = []

    func loadLayers() async throws -> [TheoLayer] {
        layers
    }

    func saveLayers(_ layers: [TheoLayer]) async throws {
        self.layers = layers
    }
}

private final class FakePermissionService: AccessibilityPermissionMonitoring {
    var isTrusted = true
    private(set) var startMonitoringCount = 0
    private(set) var requestAccessCount = 0

    func startMonitoring() {
        startMonitoringCount += 1
    }

    func requestAccess() {
        requestAccessCount += 1
    }
}

private final class FakeHotkeyController: HotkeyControlling {
    var onJump: ((Int) -> Void)?
    var onBind: ((Int) -> Void)?
    var onShowHUD: (() -> Void)?
    var onFocusVisibleAppLeft: (() -> Void)?
    var onFocusVisibleAppRight: (() -> Void)?
    var onFocusVisibleAppUp: (() -> Void)?
    var onFocusVisibleAppDown: (() -> Void)?
    var onAddDynamicHotkey: (() -> Void)?
    var onDynamicHotkey: ((HotkeyShortcut) -> Void)?
    var onTheoNextLayer: (() -> Void)?
    var onTheoPreviousLayer: (() -> Void)?
    var onTheoJumpLayer: ((Int) -> Void)?
    var onTheoFocusTerminal: (() -> Void)?
    var onTheoFocusIDE: (() -> Void)?
    var onTheoFocusBrowser: (() -> Void)?
    var onTheoCycleTerminal: (() -> Void)?
    var onTheoCycleBrowser: (() -> Void)?
    var onTheoBindCurrent: (() -> Void)?
    var onTheoShowHUD: (() -> Void)?

    private(set) var configurations: [HotkeyConfiguration] = []
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0

    func apply(configuration: HotkeyConfiguration) {
        configurations.append(configuration)
    }

    func suspend() {
        suspendCount += 1
    }

    func resume() {
        resumeCount += 1
    }
}

private final class FakeOptionHoldHUDController: OptionHoldHUDControlling {
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    private(set) var startCount = 0
    private(set) var suppressedStates: [Bool] = []

    func start() {
        startCount += 1
    }

    func setSuppressed(_ isSuppressed: Bool) {
        suppressedStates.append(isSuppressed)
    }
}

private final class FakeCaptureService: TargetCapturing {
    var outcome: CaptureOutcome?

    func captureFocusedTarget() -> CaptureOutcome? {
        outcome
    }
}

private final class FakeResolutionService: TargetResolving {
    var result: ResolutionResult = .unavailable(reason: "Unavailable")

    func resolve(target: Target) -> ResolutionResult {
        result
    }
}

private final class FakeFocusService: TargetFocusing {
    var liveWindowOutcome: FocusOutcome = .unavailable(reason: "Unavailable")
    var targetOutcome: FocusOutcome = .unavailable(reason: "Unavailable")
    private(set) var focusedTargets: [Target] = []

    func focus(liveWindow: LiveWindow, strategy: ResolutionStrategy) -> FocusOutcome {
        liveWindowOutcome
    }

    func focus(target: Target) -> FocusOutcome {
        focusedTargets.append(target)
        return targetOutcome
    }
}

private final class FakeWindowProvider: WindowProviding {
    func focusedWindow() -> LiveWindow? {
        nil
    }

    func visibleWindow(from reference: LiveWindow, toward direction: SpatialNavigationDirection) -> LiveWindow? {
        nil
    }
}

private final class FakeHUDPresenter: HUDPresenting {
    func show(model: HUDModel, timeout: Double) {}
    func showPersistent(model: HUDModel) {}
    func hide() {}
}
