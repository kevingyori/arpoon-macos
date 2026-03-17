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
            gridStore: makeGridStore(),
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
            gridStore: makeGridStore(),
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

    func testGridStandaloneShortcutValidationRejectsConfiguredActionShortcut() {
        let commandCenter = makeCommandCenter()
        let duplicateShortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | shiftKey))

        XCTAssertEqual(
            commandCenter.validationErrorForGridStandaloneShortcut(duplicateShortcut),
            "Already assigned to The Grid Add Standalone App Hotkey."
        )
    }

    func testGridStoreSeedsThreeLayersOnFirstLoad() async {
        let store = makeGridStore()

        await store.load()

        XCTAssertEqual(store.layers.count, 3)
        XCTAssertEqual(store.layers.map(\.name), ["Project 1", "Project 2", "Project 3"])
    }

    func testGridBindUsesCurrentLayerAndTool() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()
        gridSession.sync(layers: gridStore.layers)
        let firstLayer = try XCTUnwrap(gridStore.layers.first)
        let browserColumn = try XCTUnwrap(firstLayer.defaultColumn(kind: .browser))
        let terminalColumn = try XCTUnwrap(firstLayer.defaultColumn(kind: .terminal))
        _ = gridSession.selectTool(browserColumn, in: firstLayer)

        let target = Target.app(AppTarget(bundleId: "com.example.browser", appName: "Browser"))
        let capture = FakeCaptureService()
        capture.outcome = CaptureOutcome(target: target, source: .appFallback, liveWindow: nil)

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            captureService: capture
        )

        commandCenter.bindFocusedTargetToGridCurrentContext()

        let updatedLayer = try XCTUnwrap(gridStore.layers.first)
        XCTAssertEqual(updatedLayer.group(for: browserColumn).activeBinding?.target, target)
        XCTAssertTrue(updatedLayer.group(for: terminalColumn).bindings.isEmpty)
    }

    func testGridJumpUsesCurrentToolAcrossLayers() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()

        let browserOne = Target.app(AppTarget(bundleId: "com.example.browser.one", appName: "Browser One"))
        let browserTwo = Target.app(AppTarget(bundleId: "com.example.browser.two", appName: "Browser Two"))
        let firstLayerID = try XCTUnwrap(gridStore.layers.first?.id)
        let secondLayerID = try XCTUnwrap(gridStore.layers.dropFirst().first?.id)
        let browserColumn = try XCTUnwrap(gridStore.layers.first?.defaultColumn(kind: .browser))
        _ = gridStore.replaceBinding(layerID: firstLayerID, tool: browserColumn, bindingID: nil, target: browserOne)
        _ = gridStore.replaceBinding(layerID: secondLayerID, tool: browserColumn, bindingID: nil, target: browserTwo)

        gridSession.sync(layers: gridStore.layers)
        _ = gridSession.selectTool(browserColumn, in: gridStore.layers.first)

        let focus = FakeFocusService()
        focus.targetOutcome = .focused(label: "Browser Two", strategy: nil)

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            focusService: focus
        )

        commandCenter.jumpToGridLayer(2)

        XCTAssertEqual(focus.focusedTargets.last, browserTwo)
        XCTAssertEqual(gridSession.currentLayerID, secondLayerID)
        XCTAssertEqual(gridSession.currentTool(in: gridStore.layer(id: secondLayerID)), browserColumn)
    }

    func testGridLeftRightMovesAcrossBoundAppsAndSkipsEmptyColumns() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()

        let layer = try XCTUnwrap(gridStore.layers.first)
        let layerID = layer.id
        let browserColumn = try XCTUnwrap(layer.defaultColumn(kind: .browser))
        let customColumn = try XCTUnwrap(gridStore.addCustomColumn(layerID: layerID))

        let browserTarget = Target.app(AppTarget(bundleId: "com.example.browser", appName: "Browser"))
        let docsTarget = Target.app(AppTarget(bundleId: "com.example.docs", appName: "Docs"))
        _ = gridStore.replaceBinding(layerID: layerID, tool: browserColumn, bindingID: nil, target: browserTarget)
        _ = gridStore.replaceBinding(layerID: layerID, tool: customColumn, bindingID: nil, target: docsTarget)

        gridSession.sync(layers: gridStore.layers)

        let focus = FakeFocusService()
        focus.targetOutcome = .focused(label: "Focused", strategy: nil)

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            focusService: focus
        )

        commandCenter.moveToNextBoundGridApp()
        XCTAssertEqual(focus.focusedTargets.last, browserTarget)
        XCTAssertEqual(gridSession.currentTool(in: gridStore.layers.first), browserColumn)

        commandCenter.moveToNextBoundGridApp()
        XCTAssertEqual(focus.focusedTargets.last, docsTarget)
        XCTAssertEqual(gridSession.currentTool(in: gridStore.layers.first), customColumn)

        commandCenter.moveToPreviousBoundGridApp()
        XCTAssertEqual(focus.focusedTargets.last, browserTarget)
        XCTAssertEqual(gridSession.currentTool(in: gridStore.layers.first), browserColumn)
    }

    func testGridStorePersistsCustomColumnsAlongsideDefaults() async throws {
        let store = makeGridStore()

        await store.load()

        let layer = try XCTUnwrap(store.layers.first)
        let customColumn = try XCTUnwrap(store.addCustomColumn(layerID: layer.id))
        store.renameColumn(layerID: layer.id, columnID: GridToolColumn.terminal.id, name: "Shells")
        store.setColumnIcon(layerID: layer.id, columnID: GridToolColumn.browser.id, iconSymbol: "safari")
        store.renameColumn(layerID: layer.id, columnID: customColumn.id, name: "Docs")
        store.setColumnIcon(layerID: layer.id, columnID: customColumn.id, iconSymbol: "book")

        let updatedLayer = try XCTUnwrap(store.layers.first)
        XCTAssertEqual(updatedLayer.defaultColumn(kind: .terminal)?.title, "Shells")
        XCTAssertEqual(updatedLayer.defaultColumn(kind: .browser)?.iconSymbol, "safari")
        XCTAssertEqual(updatedLayer.columns.count, 4)
        XCTAssertEqual(updatedLayer.column(id: customColumn.id)?.title, "Docs")
        XCTAssertEqual(updatedLayer.column(id: customColumn.id)?.iconSymbol, "book")
    }

    func testGridStandaloneAppShortcutJumpsToSharedAppTarget() async throws {
        let gridStore = makeGridStore()
        await gridStore.load()

        let app = gridStore.addStandaloneApp()
        gridStore.renameStandaloneApp(id: app.id, name: "Music")
        gridStore.setStandaloneAppShortcut(
            id: app.id,
            shortcut: HotkeyShortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(optionKey))
        )
        _ = gridStore.replaceStandaloneAppBinding(
            id: app.id,
            target: .app(AppTarget(bundleId: "com.example.music", appName: "Music"))
        )

        let focus = FakeFocusService()
        focus.targetOutcome = .focused(label: "Music", strategy: nil)

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            focusService: focus
        )

        commandCenter.jumpToGridStandaloneApp(app.id)

        XCTAssertEqual(
            focus.focusedTargets.last,
            .app(AppTarget(bundleId: "com.example.music", appName: "Music"))
        )
    }

    private func makeCommandCenter(
        slotStore: SlotStore? = nil,
        dynamicStore: DynamicHotkeyStore? = nil,
        gridStore: GridStore? = nil,
        gridSession: GridSession? = nil,
        captureService: FakeCaptureService = FakeCaptureService(),
        resolutionService: FakeResolutionService = FakeResolutionService(),
        focusService: FakeFocusService = FakeFocusService()
    ) -> AppCommandCenter {
        AppCommandCenter(
            settings: makeSettings(),
            accessibilityPermissions: FakePermissionService(),
            slotStore: slotStore ?? makeSlotStore(),
            dynamicHotkeyStore: dynamicStore ?? makeDynamicHotkeyStore(),
            gridStore: gridStore ?? makeGridStore(),
            gridSession: gridSession ?? GridSession(),
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

    private func makeGridStore() -> GridStore {
        GridStore(
            store: InMemoryGridLayerStore(),
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

private final class InMemoryGridLayerStore: GridLayerStore {
    private var state = GridWorkspaceState()

    func loadState() async throws -> GridWorkspaceState {
        state
    }

    func saveState(_ state: GridWorkspaceState) async throws {
        self.state = state
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
    var onGridNextLayer: (() -> Void)?
    var onGridPreviousLayer: (() -> Void)?
    var onGridJumpLayer: ((Int) -> Void)?
    var onGridFocusLeft: (() -> Void)?
    var onGridFocusRight: (() -> Void)?
    var onGridFocusTerminal: (() -> Void)?
    var onGridFocusIDE: (() -> Void)?
    var onGridFocusBrowser: (() -> Void)?
    var onGridAddStandaloneHotkey: (() -> Void)?
    var onGridBindCurrent: (() -> Void)?
    var onGridShowHUD: (() -> Void)?
    var onGridStandaloneApp: ((String) -> Void)?

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
