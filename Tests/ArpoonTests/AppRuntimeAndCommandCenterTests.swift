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

        settings.hotkeyScheme = .dynamicWindows
        XCTAssertEqual(hotkeys.configurations.count, 2)

        dynamicStore.bind(
            shortcut: HotkeyShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(optionKey)),
            target: .app(AppTarget(bundleId: "com.example.browser", appName: "Browser"))
        )
        XCTAssertEqual(hotkeys.configurations.count, 3)
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

    func testGridRenameProjectUsesPromptResult() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()
        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession
        )
        commandCenter.requestGridProjectRename = { currentName in
            XCTAssertEqual(currentName, "Project 1")
            return "Alpha"
        }

        commandCenter.renameCurrentGridProject()

        XCTAssertEqual(gridStore.layers.first?.name, "Alpha")
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
        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)
        let browserColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .browser))
        let terminalColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .terminal))
        _ = gridSession.selectTool(browserColumn, in: gridStore.columns)

        let target = Target.app(AppTarget(bundleId: "com.example.browser", appName: "Browser"))
        let capture = FakeCaptureService()
        capture.outcome = CaptureOutcome(target: target, source: .appFallback, liveWindow: nil)
        let binder = FakeGridBindingSelectionController()

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            captureService: capture
        )
        commandCenter.gridBindingSelectionControllerFactory = { _ in binder }

        commandCenter.bindFocusedTargetToGridCurrentContext()
        binder.onConfirm?()

        let updatedLayer = try XCTUnwrap(gridStore.layers.first)
        XCTAssertEqual(updatedLayer.group(for: browserColumn).activeBinding?.target, target)
        XCTAssertTrue(updatedLayer.group(for: terminalColumn).bindings.isEmpty)
        XCTAssertEqual(binder.beginCount, 1)
        XCTAssertEqual(binder.finishCount, 1)
    }

    func testGridJumpUsesCurrentToolAcrossLayers() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()

        let browserOne = Target.app(AppTarget(bundleId: "com.example.browser.one", appName: "Browser One"))
        let browserTwo = Target.app(AppTarget(bundleId: "com.example.browser.two", appName: "Browser Two"))
        let firstLayerID = try XCTUnwrap(gridStore.layers.first?.id)
        let secondLayerID = try XCTUnwrap(gridStore.layers.dropFirst().first?.id)
        let browserColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .browser))
        _ = gridStore.replaceBinding(layerID: firstLayerID, tool: browserColumn, bindingID: nil, target: browserOne)
        _ = gridStore.replaceBinding(layerID: secondLayerID, tool: browserColumn, bindingID: nil, target: browserTwo)

        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)
        _ = gridSession.selectTool(browserColumn, in: gridStore.columns)

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
        XCTAssertEqual(gridSession.currentTool(in: gridStore.columns), browserColumn)
    }

    func testGridJumpRespectsShowJumpPopupsSetting() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()

        let browserOne = Target.app(AppTarget(bundleId: "com.example.browser.one", appName: "Browser One"))
        let firstLayerID = try XCTUnwrap(gridStore.layers.first?.id)
        let browserColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .browser))
        _ = gridStore.replaceBinding(layerID: firstLayerID, tool: browserColumn, bindingID: nil, target: browserOne)

        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)
        _ = gridSession.selectTool(browserColumn, in: gridStore.columns)

        let settings = makeSettings()
        settings.showJumpPopups = false
        let focus = FakeFocusService()
        focus.targetOutcome = .focused(label: "Browser One", strategy: nil)
        let hud = FakeHUDPresenter()

        let commandCenter = makeCommandCenter(
            settings: settings,
            gridStore: gridStore,
            gridSession: gridSession,
            focusService: focus,
            hudPresenter: hud
        )

        commandCenter.jumpToGridLayer(1)

        XCTAssertNil(hud.lastModel)
    }

    func testGridBindSelectionCanMoveBeforeConfirming() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()
        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)

        let browserColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .browser))
        let secondLayerID = try XCTUnwrap(gridStore.layers.dropFirst().first?.id)
        let target = Target.app(AppTarget(bundleId: "com.example.browser", appName: "Browser"))
        let capture = FakeCaptureService()
        capture.outcome = CaptureOutcome(target: target, source: .appFallback, liveWindow: nil)
        let binder = FakeGridBindingSelectionController()

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            captureService: capture
        )
        commandCenter.gridBindingSelectionControllerFactory = { _ in binder }

        commandCenter.bindFocusedTargetToGridCurrentContext()
        binder.onMove?(.down)
        binder.onMove?(.right)
        binder.onMove?(.right)
        binder.onConfirm?()

        let secondLayer = try XCTUnwrap(gridStore.layer(id: secondLayerID))
        XCTAssertEqual(gridSession.currentLayerID, secondLayerID)
        XCTAssertEqual(gridSession.currentColumnID, browserColumn.id)
        XCTAssertEqual(secondLayer.group(for: browserColumn).activeBinding?.target, target)
    }

    func testGridLeftRightMovesAcrossColumnsAndAllowsEmptySelection() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()

        let layer = try XCTUnwrap(gridStore.layers.first)
        let layerID = layer.id
        let ideColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .ide))
        let browserColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .browser))
        let customColumn = try XCTUnwrap(gridStore.addCustomColumn())

        let browserTarget = Target.app(AppTarget(bundleId: "com.example.browser", appName: "Browser"))
        let docsTarget = Target.app(AppTarget(bundleId: "com.example.docs", appName: "Docs"))
        _ = gridStore.replaceBinding(layerID: layerID, tool: browserColumn, bindingID: nil, target: browserTarget)
        _ = gridStore.replaceBinding(layerID: layerID, tool: customColumn, bindingID: nil, target: docsTarget)

        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)

        let focus = FakeFocusService()
        focus.targetOutcome = .focused(label: "Focused", strategy: nil)

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            focusService: focus
        )

        commandCenter.moveToNextBoundGridApp()
        XCTAssertEqual(gridSession.currentTool(in: gridStore.columns), ideColumn)
        XCTAssertNil(focus.focusedTargets.last)

        commandCenter.moveToNextBoundGridApp()
        XCTAssertEqual(focus.focusedTargets.last, browserTarget)
        XCTAssertEqual(gridSession.currentTool(in: gridStore.columns), browserColumn)

        commandCenter.moveToNextBoundGridApp()
        XCTAssertEqual(focus.focusedTargets.last, docsTarget)
        XCTAssertEqual(gridSession.currentTool(in: gridStore.columns), customColumn)

        commandCenter.moveToPreviousBoundGridApp()
        XCTAssertEqual(focus.focusedTargets.last, browserTarget)
        XCTAssertEqual(gridSession.currentTool(in: gridStore.columns), browserColumn)
    }

    func testGridStorePersistsCustomColumnsAlongsideDefaults() async throws {
        let store = makeGridStore()

        await store.load()

        let customColumn = try XCTUnwrap(store.addCustomColumn())
        store.renameColumn(columnID: GridToolColumn.terminal.id, name: "Shells")
        store.setColumnIcon(columnID: GridToolColumn.browser.id, iconSymbol: "safari")
        store.renameColumn(columnID: customColumn.id, name: "Docs")
        store.setColumnIcon(columnID: customColumn.id, iconSymbol: "book")

        XCTAssertEqual(store.defaultColumn(kind: .terminal)?.title, "Shells")
        XCTAssertEqual(store.defaultColumn(kind: .browser)?.iconSymbol, "safari")
        XCTAssertEqual(store.columns.count, 4)
        XCTAssertEqual(store.column(id: customColumn.id)?.title, "Docs")
        XCTAssertEqual(store.column(id: customColumn.id)?.iconSymbol, "book")
    }

    func testGridStorePreservesColumnOrderAcrossReload() async throws {
        let backingStore = InMemoryGridLayerStore()
        let store = GridStore(store: backingStore, labelPolicy: TargetLabelPolicy())

        await store.load()

        let customColumn = try XCTUnwrap(store.addCustomColumn())
        store.moveColumns(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        store.moveColumns(fromOffsets: IndexSet(integer: 3), toOffset: 1)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let reloaded = GridStore(store: backingStore, labelPolicy: TargetLabelPolicy())
        await reloaded.load()

        XCTAssertEqual(reloaded.columns.map(\.id), [GridToolColumn.browser.id, customColumn.id, GridToolColumn.terminal.id, GridToolColumn.ide.id])
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

    func testApplyingGridVimPresetOverridesGridNavigationKeys() {
        let settings = makeSettings()

        settings.applyGridShortcutPreset(.vim)

        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridPreviousLayer, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(optionKey))
        )
        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridNextLayer, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(optionKey))
        )
        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridFocusBrowser, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(optionKey))
        )
    }

    func testDefaultSettingsUseGridScheme() {
        let settings = makeSettings()

        XCTAssertEqual(settings.hotkeyScheme, .grid)
    }

    func testDefaultSettingsEnableExperimentalGridExternalSync() {
        let settings = makeSettings()

        XCTAssertTrue(settings.enableExperimentalGridExternalSync)
    }

    func testDefaultSettingsSeedGridWithGamerPreset() {
        let settings = makeSettings()

        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridFocusLeft, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))
        )
        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridBindCurrent, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(optionKey | shiftKey))
        )
        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridFocusTerminal, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(optionKey))
        )
    }

    func testApplyingGridGamerPresetMovesBindOffOptionA() {
        let settings = makeSettings()

        settings.applyGridShortcutPreset(.gamer)

        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridFocusLeft, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))
        )
        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridBindCurrent, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(optionKey | shiftKey))
        )
        XCTAssertEqual(
            settings.shortcut(for: HotkeyAction(kind: .gridFocusTerminal, slot: nil)),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(optionKey))
        )
    }

    func testGridRenameProjectHasDefaultShortcut() {
        XCTAssertEqual(
            HotkeyAction(kind: .gridRenameProject, slot: nil).defaultShortcut,
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey))
        )
    }

    func testGridMinimapPreferredSizeExpandsWithRowsAndColumns() {
        let compact = HUDModel.gridMinimap(
            GridMinimapModel(
                layers: [
                    GridMinimapLayer(
                        id: "one",
                        name: "Project 1",
                        color: .cobalt,
                        columns: [
                            GridMinimapColumn(id: "terminal", name: "Terminal", iconSymbol: "terminal", bundleId: "com.example.term", isFilled: true, activeLabel: "Shell")
                        ],
                        isCurrent: true
                    )
                ],
                movement: .neutral,
                hint: nil,
                animateSelectionMotion: true,
                detailMode: .compact,
                selectedLayerIndex: 0,
                selectedColumnIndex: 0
            )
        )

        let expanded = HUDModel.gridMinimap(
            GridMinimapModel(
                layers: [
                    GridMinimapLayer(
                        id: "one",
                        name: "Project 1",
                        color: .cobalt,
                        columns: [
                            GridMinimapColumn(id: "terminal", name: "Terminal", iconSymbol: "terminal", bundleId: "com.example.term", isFilled: true, activeLabel: "Shell"),
                            GridMinimapColumn(id: "ide", name: "IDE", iconSymbol: "curlybraces", bundleId: nil, isFilled: false, activeLabel: nil),
                            GridMinimapColumn(id: "browser", name: "Browser", iconSymbol: "globe", bundleId: "com.example.browser", isFilled: true, activeLabel: "Site")
                        ],
                        isCurrent: true
                    ),
                    GridMinimapLayer(
                        id: "two",
                        name: "Project 2",
                        color: .rose,
                        columns: [
                            GridMinimapColumn(id: "terminal", name: "Terminal", iconSymbol: "terminal", bundleId: "com.example.term", isFilled: true, activeLabel: "Shell"),
                            GridMinimapColumn(id: "ide", name: "IDE", iconSymbol: "curlybraces", bundleId: "com.example.ide", isFilled: true, activeLabel: "Editor"),
                            GridMinimapColumn(id: "browser", name: "Browser", iconSymbol: "globe", bundleId: nil, isFilled: false, activeLabel: nil)
                        ],
                        isCurrent: false
                    )
                ],
                movement: .neutral,
                hint: GridHUDHint(title: "Hint", detail: "Detail", tone: .neutral),
                animateSelectionMotion: true,
                detailMode: .expanded,
                selectedLayerIndex: 0,
                selectedColumnIndex: 1
            )
        )

        XCTAssertGreaterThan(expanded.preferredWidth, compact.preferredWidth)
        XCTAssertGreaterThan(expanded.preferredHeight, compact.preferredHeight)
    }

    func testShowGridHUDUsesExpandedMinimapDetail() async {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()
        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)
        let hud = FakeHUDPresenter()

        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            hudPresenter: hud
        )

        commandCenter.showGridHUD()

        guard case .gridMinimap(let minimap)? = hud.lastModel else {
            return XCTFail("Expected grid minimap HUD")
        }

        XCTAssertEqual(minimap.detailMode, .expanded)
    }

    func testSyncGridSelectionToFocusedWindowSelectsMatchingCell() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()
        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)

        let ideColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .ide))
        let secondLayerID = try XCTUnwrap(gridStore.layers.dropFirst().first?.id)
        let liveWindow = LiveWindow(
            bundleId: "com.example.editor",
            appName: "Editor",
            pid: 44,
            title: "Repo",
            windowID: 99,
            frame: WindowFrame(x: 10, y: 10, width: 1200, height: 800),
            isMain: true,
            isFocused: true,
            axElement: nil
        )

        _ = gridStore.replaceBinding(
            layerID: secondLayerID,
            tool: ideColumn,
            bindingID: nil,
            target: .window(
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
        )

        let windowProvider = FakeWindowProvider()
        windowProvider.focusedWindowValue = liveWindow
        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            windowProvider: windowProvider
        )

        commandCenter.syncGridSelectionToFocusedTarget()

        XCTAssertEqual(gridSession.currentLayerID, secondLayerID)
        XCTAssertEqual(gridSession.currentColumnID, ideColumn.id)
    }

    func testSyncGridSelectionToFocusedWindowPrefersCurrentLayerWhenDuplicated() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()
        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)

        let browserColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .browser))
        let firstLayerID = try XCTUnwrap(gridStore.layers.first?.id)
        let secondLayerID = try XCTUnwrap(gridStore.layers.dropFirst().first?.id)
        let liveWindow = LiveWindow(
            bundleId: "com.example.browser",
            appName: "Browser",
            pid: 88,
            title: "Docs",
            windowID: 501,
            frame: WindowFrame(x: 40, y: 40, width: 900, height: 700),
            isMain: true,
            isFocused: true,
            axElement: nil
        )
        let target = Target.window(
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

        _ = gridStore.replaceBinding(layerID: firstLayerID, tool: browserColumn, bindingID: nil, target: target)
        _ = gridStore.replaceBinding(layerID: secondLayerID, tool: browserColumn, bindingID: nil, target: target)
        _ = gridSession.selectLayer(id: secondLayerID)

        let windowProvider = FakeWindowProvider()
        windowProvider.focusedWindowValue = liveWindow
        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            windowProvider: windowProvider
        )

        commandCenter.syncGridSelectionToFocusedTarget()

        XCTAssertEqual(gridSession.currentLayerID, secondLayerID)
        XCTAssertEqual(gridSession.currentColumnID, browserColumn.id)
    }

    func testExternalGridSyncDoesNotOverrideManualEmptySlotSelectionWithoutFocusChange() async throws {
        let gridStore = makeGridStore()
        let gridSession = GridSession()
        await gridStore.load()
        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)

        let browserColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .browser))
        let ideColumn = try XCTUnwrap(gridStore.defaultColumn(kind: .ide))
        let firstLayerID = try XCTUnwrap(gridStore.layers.first?.id)
        let liveWindow = LiveWindow(
            bundleId: "com.example.browser",
            appName: "Browser",
            pid: 31,
            title: "Docs",
            windowID: 901,
            frame: WindowFrame(x: 60, y: 60, width: 1024, height: 768),
            isMain: true,
            isFocused: true,
            axElement: nil
        )

        _ = gridStore.replaceBinding(
            layerID: firstLayerID,
            tool: browserColumn,
            bindingID: nil,
            target: .window(
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
        )

        let windowProvider = FakeWindowProvider()
        windowProvider.focusedWindowValue = liveWindow
        let commandCenter = makeCommandCenter(
            gridStore: gridStore,
            gridSession: gridSession,
            windowProvider: windowProvider
        )

        commandCenter.syncGridSelectionToFocusedTargetIfNeeded()
        XCTAssertEqual(gridSession.currentColumnID, browserColumn.id)

        _ = gridSession.selectTool(ideColumn, in: gridStore.columns)
        commandCenter.syncGridSelectionToFocusedTargetIfNeeded()

        XCTAssertEqual(gridSession.currentColumnID, ideColumn.id)
    }

    private func makeCommandCenter(
        settings: SettingsStore? = nil,
        slotStore: SlotStore? = nil,
        dynamicStore: DynamicHotkeyStore? = nil,
        gridStore: GridStore? = nil,
        gridSession: GridSession? = nil,
        captureService: FakeCaptureService = FakeCaptureService(),
        resolutionService: FakeResolutionService = FakeResolutionService(),
        focusService: FakeFocusService = FakeFocusService(),
        appProvider: FakeAppProvider = FakeAppProvider(),
        windowProvider: FakeWindowProvider = FakeWindowProvider(),
        hudPresenter: FakeHUDPresenter = FakeHUDPresenter()
    ) -> AppCommandCenter {
        AppCommandCenter(
            settings: settings ?? makeSettings(),
            accessibilityPermissions: FakePermissionService(),
            slotStore: slotStore ?? makeSlotStore(),
            dynamicHotkeyStore: dynamicStore ?? makeDynamicHotkeyStore(),
            gridStore: gridStore ?? makeGridStore(),
            gridSession: gridSession ?? GridSession(),
            labelPolicy: TargetLabelPolicy(),
            captureService: captureService,
            resolutionService: resolutionService,
            focusService: focusService,
            appProvider: appProvider,
            windowProvider: windowProvider,
            hudController: hudPresenter,
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
    var onGridRenameProject: (() -> Void)?
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

private final class FakeAppProvider: AppProviding {
    var focusedAppValue: LiveApp?

    func focusedApp() -> LiveApp? {
        focusedAppValue
    }
}

private final class FakeWindowProvider: WindowProviding {
    var focusedWindowValue: LiveWindow?

    func focusedWindow() -> LiveWindow? {
        focusedWindowValue
    }

    func visibleWindow(from reference: LiveWindow, toward direction: SpatialNavigationDirection) -> LiveWindow? {
        nil
    }
}

private final class FakeHUDPresenter: HUDPresenting {
    private(set) var lastModel: HUDModel?

    func show(model: HUDModel, timeout: Double) {
        lastModel = model
    }

    func showPersistent(model: HUDModel) {
        lastModel = model
    }

    func hide() {}
}

private final class FakeGridBindingSelectionController: GridBindingSelectionPresenting {
    var onMove: ((GridBindingSelectionMove) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var beginCount = 0
    private(set) var finishCount = 0
    private(set) var models: [HUDModel] = []

    func begin() {
        beginCount += 1
    }

    func update(model: HUDModel) {
        models.append(model)
    }

    func finish() {
        finishCount += 1
    }
}
