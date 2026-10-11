import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

private enum GridInspectorSelection: Hashable {
    case project(layerID: String)
    case column(columnID: String)
    case layerSlot(layerID: String, columnID: String)
    case standaloneApp(id: String)
    case newStandaloneApp
}

private extension GridInspectorSelection {
    var showsWindowPicker: Bool {
        switch self {
        case .layerSlot, .standaloneApp, .newStandaloneApp:
            return true
        case .project, .column:
            return false
        }
    }
}

struct GridSettingsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var gridStore: GridStore
    let availableWindowsProvider: @MainActor () async -> [LiveWindow]
    @Binding var activeRecorderID: String?

    @State private var inspectorSelection: GridInspectorSelection?
    @State private var draggedLayerID: String?
    @State private var draggedColumnID: String?
    @State private var availableWindows: [LiveWindow] = []
    @State private var availableWindowsLoadedAt: Date?
    @State private var availableWindowsTask: Task<Void, Never>?
    @State private var isLoadingWindows = false
    @State private var drawerKeyMonitor: Any?
    private let windowMatchPolicy = WindowTargetMatchPolicy()
    private let labelPolicy = TargetLabelPolicy()

    private let rowLabelWidth: CGFloat = 196
    private let cellWidth: CGFloat = 188
    private let rowHeight: CGFloat = 120
    private let headerHeight: CGFloat = 82
    private let boardSpacing: CGFloat = 12
    private let drawerWidth: CGFloat = 360
    private let cardHorizontalInset: CGFloat = 14
    private let availableWindowsMaxAge: TimeInterval = 3

    var body: some View {
        ZStack(alignment: .trailing) {
            boardPanel

            if let inspectorSelection {
                GridInspectorDrawer(onClose: { self.inspectorSelection = nil }) {
                    drawerContent(for: inspectorSelection)
                }
                .frame(width: drawerWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.18), value: inspectorSelection)
        .onAppear {
            syncInspectorSelection()
            updateDrawerMonitor()
        }
        .onReceive(gridStore.$layers) { _ in
            syncInspectorSelection()
        }
        .onReceive(gridStore.$columns) { _ in
            syncInspectorSelection()
        }
        .onReceive(gridStore.$standaloneApps) { _ in
            syncInspectorSelection()
        }
        .onChange(of: inspectorSelection) { _, _ in
            if inspectorSelection?.showsWindowPicker == true {
                refreshAvailableWindows()
            }
            updateDrawerMonitor()
        }
        .onDisappear {
            stopDrawerMonitor()
            availableWindowsTask?.cancel()
        }
    }

    private var boardPanel: some View {
        // A ScrollView centers content smaller than its viewport; pin the board to the top-left
        // by making the content at least as large as the viewport.
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: boardSpacing) {
                    reorderHint
                    gridHeaderRow

                    ForEach(gridStore.layers) { layer in
                        layerRow(layer)
                    }

                    addProjectRow
                    standaloneAppsRow
                }
                .padding(24)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    private var gridHeaderRow: some View {
        HStack(alignment: .top, spacing: boardSpacing) {
            Color.clear
                .frame(width: rowLabelWidth + (cardHorizontalInset * 2), height: headerHeight)

            ForEach(gridStore.columns) { column in
                columnHeaderCell(column)
            }

            addColumnCard
        }
    }

    private func columnHeaderCell(_ column: GridToolColumn) -> some View {
        Button {
            inspectorSelection = .column(columnID: column.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: column.iconSymbol)
                        .font(.system(size: 13, weight: .semibold))

                    Text(column.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }

                Text(column.kind == .custom ? "Custom column" : "Default column")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: cellWidth, height: headerHeight, alignment: .leading)
            .padding(.horizontal, 14)
            .cardBackground(
                fill: isSelectedColumn(column.id) ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06),
                stroke: isSelectedColumn(column.id) ? Color.secondary.opacity(0.28) : Color.clear,
                cornerRadius: 16
            )
        }
        .buttonStyle(.plain)
        .onDrag {
            draggedColumnID = column.id
            return NSItemProvider(object: NSString(string: column.id))
        } preview: {
            reorderPreview
        }
        .onDrop(
            of: [UTType.text],
            delegate: GridColumnDropDelegate(
                targetColumnID: column.id,
                columns: gridStore.columns,
                draggedColumnID: $draggedColumnID,
                gridStore: gridStore
            )
        )
    }

    private var addColumnCard: some View {
        Button {
            if let column = gridStore.addCustomColumn() {
                inspectorSelection = .column(columnID: column.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text("Add Column")
                        .font(.system(size: 12, weight: .medium))
                }

                Text("Shared across every project.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(width: cellWidth, height: headerHeight, alignment: .leading)
            .padding(.horizontal, cardHorizontalInset)
            .cardBackground(
                fill: Color.secondary.opacity(0.04),
                stroke: Color.secondary.opacity(0.22),
                dash: [6, 6],
                cornerRadius: 16
            )
        }
        .buttonStyle(.plain)
    }

    private func layerRow(_ layer: GridLayer) -> some View {
        HStack(alignment: .top, spacing: boardSpacing) {
            layerLabelCell(layer)

            ForEach(gridStore.columns) { column in
                slotCell(for: layer, column: column)
            }
        }
    }

    private func layerLabelCell(_ layer: GridLayer) -> some View {
        Button {
            inspectorSelection = .project(layerID: layer.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(layer.color.swiftUIColor)
                        .frame(width: 10, height: 10)

                    Text(layer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }

                Text("\(filledSlotCount(in: layer))/\(gridStore.columns.count) assigned")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: rowLabelWidth, height: rowHeight, alignment: .leading)
            .padding(.horizontal, cardHorizontalInset)
            .cardBackground(
                fill: isSelectedProject(layer.id) ? layer.color.swiftUIColor.opacity(0.14) : Color.secondary.opacity(0.06),
                stroke: isSelectedProject(layer.id) ? layer.color.swiftUIColor.opacity(0.30) : Color.clear,
                cornerRadius: 18
            )
        }
        .buttonStyle(.plain)
        .onDrag {
            draggedLayerID = layer.id
            return NSItemProvider(object: NSString(string: layer.id))
        } preview: {
            reorderPreview
        }
        .onDrop(
            of: [UTType.text],
            delegate: GridLayerDropDelegate(
                targetLayerID: layer.id,
                layers: gridStore.layers,
                draggedLayerID: $draggedLayerID,
                gridStore: gridStore
            )
        )
    }

    private func slotCell(for layer: GridLayer, column: GridToolColumn) -> some View {
        let binding = layer.group(for: column).activeBinding

        return ZStack(alignment: .topTrailing) {
            Button {
                inspectorSelection = .layerSlot(layerID: layer.id, columnID: column.id)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    if let binding {
                        let display = labelPolicy.displayLabel(label: binding.label, target: binding.target)

                        HStack(alignment: .center, spacing: 10) {
                            AppIconView(bundleId: bundleID(for: binding))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(display.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                Text(display.detail ?? binding.target.kindDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .help(binding.label)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)

                            Text("Bind App")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: cellWidth, height: rowHeight, alignment: .leading)
                .padding(.horizontal, cardHorizontalInset)
                .cardBackground(
                    fill: slotBackgroundColor(layer: layer, isSelected: isSelected(layerID: layer.id, columnID: column.id)),
                    stroke: slotBorderColor(layer: layer, isSelected: isSelected(layerID: layer.id, columnID: column.id), isEmpty: binding == nil),
                    dash: binding == nil ? [6, 6] : [],
                    cornerRadius: 18
                )
            }
            .buttonStyle(.plain)

            if let binding {
                Button {
                    gridStore.clearBinding(layerID: layer.id, tool: column, bindingID: binding.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                .buttonStyle(.plain)
                .help("Remove app")
            }
        }
    }

    private var addProjectRow: some View {
        HStack(alignment: .top, spacing: boardSpacing) {
            Button {
                if let layer = gridStore.addLayer() {
                    inspectorSelection = .project(layerID: layer.id)
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text("Add Project")
                            .font(.system(size: 12, weight: .medium))
                    }

                    Text("Create another project row.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(width: rowLabelWidth, height: rowHeight, alignment: .leading)
                .padding(.horizontal, cardHorizontalInset)
                .cardBackground(
                    fill: Color.secondary.opacity(0.04),
                    stroke: Color.secondary.opacity(0.22),
                    dash: [6, 6],
                    cornerRadius: 18
                )
            }
            .buttonStyle(.plain)
            .disabled(gridStore.layers.count >= 9)

            ForEach(gridStore.columns) { _ in
                Color.clear
                    .frame(width: cellWidth, height: rowHeight)
                    .padding(.horizontal, cardHorizontalInset)
                    .cardBackground(
                        fill: Color.secondary.opacity(0.025),
                        stroke: Color.secondary.opacity(0.08),
                        dash: [6, 6],
                        cornerRadius: 18
                    )
            }
        }
    }

    private var standaloneAppsRow: some View {
        HStack(alignment: .top, spacing: boardSpacing) {
            Button {
                // Row label intentionally opens no editor; actual standalone cards remain editable.
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Standalone Apps")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Cross-project shortcuts that stay the same everywhere.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rowLabelWidth, height: rowHeight, alignment: .leading)
                .padding(.horizontal, cardHorizontalInset)
                .cardBackground(
                    fill: Color.secondary.opacity(0.06),
                    cornerRadius: 18
                )
            }
            .buttonStyle(.plain)

            ForEach(gridStore.standaloneApps) { app in
                standaloneAppCard(app)
            }

            addStandaloneAppCard
        }
    }

    private func standaloneAppCard(_ app: GridStandaloneApp) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                inspectorSelection = .standaloneApp(id: app.id)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    if let binding = app.binding {
                        HStack(alignment: .center, spacing: 10) {
                            AppIconView(bundleId: bundleID(for: binding))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(labelPolicy.displayLabel(label: binding.label, target: binding.target).title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                standaloneShortcutText(for: app)
                            }
                        }
                    } else {
                        // A shortcut without an app: say what's missing and what clicking does.
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.shortcut.map { "\($0.displayString) has no app" } ?? "No app chosen")
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                Text("Click to choose one")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(width: cellWidth, height: rowHeight, alignment: .leading)
                .padding(.horizontal, cardHorizontalInset)
                .cardBackground(
                    fill: isSelectedStandaloneApp(app.id) ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.05),
                    stroke: isSelectedStandaloneApp(app.id) ? Color.secondary.opacity(0.32) : Color.clear,
                    cornerRadius: 18
                )
            }
            .buttonStyle(.plain)

            Button {
                gridStore.removeStandaloneApp(id: app.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
            .buttonStyle(.plain)
            .help("Remove standalone app")
        }
    }

    @ViewBuilder
    private func standaloneShortcutText(for app: GridStandaloneApp) -> some View {
        if let shortcut = app.shortcut,
           settings.hotkeyScheme == .grid,
           settings.unregisteredShortcuts.contains(shortcut) {
            Label("\(shortcut.displayString) unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .help(ShortcutRecorderRow.unregisteredDescription)
        } else {
            Text(app.shortcut?.displayString ?? "No shortcut")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var addStandaloneAppCard: some View {
        Button {
            inspectorSelection = .newStandaloneApp
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.secondary)

                Text("Add Standalone App")
                    .font(.system(size: 12, weight: .medium))

                Text("Create a cross-project shortcut app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: cellWidth, height: rowHeight, alignment: .leading)
            .padding(.horizontal, 14)
            .cardBackground(
                fill: Color.secondary.opacity(0.04),
                stroke: Color.secondary.opacity(0.22),
                dash: [6, 6],
                cornerRadius: 18
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func drawerContent(for selection: GridInspectorSelection) -> some View {
        switch selection {
        case .project(let layerID):
            if let layer = gridStore.layer(id: layerID) {
                projectEditor(layer)
            } else {
                drawerUnavailableState("This project is no longer available.")
            }
        case .column(let columnID):
            if let column = gridStore.column(id: columnID) {
                columnEditor(column)
            } else {
                drawerUnavailableState("This column is no longer available.")
            }
        case .layerSlot(let layerID, let columnID):
            if let layer = gridStore.layer(id: layerID),
               let column = gridStore.column(id: columnID) {
                slotEditor(layer: layer, column: column)
            } else {
                drawerUnavailableState("This slot is no longer available.")
            }
        case .standaloneApp(let id):
            if let app = gridStore.standaloneApp(id: id) {
                standaloneAppEditor(app)
            } else {
                drawerUnavailableState("This standalone app is no longer available.")
            }
        case .newStandaloneApp:
            createStandaloneAppEditor
        }
    }

    private var createStandaloneAppEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            drawerTitle("Bind Standalone App", subtitle: "Standalone App")

            GridSettingsFieldSection(title: "Target") {
                Text("Pick a live app to create a standalone shortcut entry.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                GridAvailableWindowPicker(
                    windows: availableWindows,
                    mode: .app(selectedBundleID: nil),
                    isLoading: isLoadingWindows,
                    usageTags: { window in
                        usageTags(for: window)
                    },
                    onRefresh: forceRefreshAvailableWindows,
                    onSelect: { window in
                        let app = gridStore.createStandaloneApp(
                            target: .app(
                                AppTarget(
                                    bundleId: window.bundleId,
                                    appName: window.appName
                                )
                            )
                        )
                        inspectorSelection = .standaloneApp(id: app.id)
                    }
                )
            }

            Spacer()
        }
    }

    private func drawerUnavailableState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func projectEditor(_ layer: GridLayer) -> some View {
        let action = projectShortcutAction(for: layer)

        return VStack(alignment: .leading, spacing: 18) {
            drawerTitle(layer.name, subtitle: "Project")

            GridSettingsFieldSection(title: "Project") {
                CommitTextField("Project name", value: layer.name) {
                    gridStore.renameLayer(id: layer.id, name: $0)
                }
                .id(layer.id)
                .fieldResetButton {
                    gridStore.renameLayer(id: layer.id, name: defaultLayerName(for: layer))
                }

                HStack(spacing: 8) {
                    Picker("Color", selection: Binding(
                        get: { layer.color },
                        set: { gridStore.setColor($0, forLayerID: layer.id) }
                    )) {
                        ForEach(GridLayerColor.allCases) { color in
                            Text(color.title).tag(color)
                        }
                    }
                    .pickerStyle(.menu)

                    resetFieldButton {
                        gridStore.setColor(defaultLayerColor(for: layer), forLayerID: layer.id)
                    }
                }
            }

            if let action {
                GridSettingsFieldSection(title: "Shortcut") {
                    shortcutEditorSection(
                        action: action,
                        title: "Jump to \(layer.name)",
                        description: "Triggers this project row directly from anywhere."
                    )
                }
            }

            Button("Remove Project", role: .destructive) {
                guard gridStore.layers.count > 1 else {
                    return
                }
                gridStore.removeLayer(id: layer.id)
                inspectorSelection = nil
            }
            .buttonStyle(.borderless)
            .disabled(gridStore.layers.count == 1)

            Spacer()
        }
    }

    private func columnEditor(_ column: GridToolColumn) -> some View {
        let action = HotkeyAction(kind: .gridFocusColumn, slot: nil, referenceID: column.id)

        return VStack(alignment: .leading, spacing: 18) {
            drawerTitle(column.title, subtitle: column.kind == .custom ? "Shared Custom Column" : "Shared Default Column")

            GridSettingsFieldSection(title: "Column") {
                CommitTextField("Column name", value: column.title) {
                    gridStore.renameColumn(columnID: column.id, name: $0)
                }
                .id(column.id)
                .fieldResetButton {
                    gridStore.renameColumn(columnID: column.id, name: defaultColumnName(for: column))
                }

                HStack(spacing: 8) {
                    Picker("Icon", selection: Binding(
                        get: { column.iconSymbol },
                        set: { gridStore.setColumnIcon(columnID: column.id, iconSymbol: $0) }
                    )) {
                        ForEach(GridToolColumn.iconOptions, id: \.self) { icon in
                            Label(icon, systemImage: icon).tag(icon)
                        }
                    }
                    .pickerStyle(.menu)

                    resetFieldButton {
                        gridStore.setColumnIcon(columnID: column.id, iconSymbol: defaultColumnIcon(for: column))
                    }
                }
            }

            GridSettingsFieldSection(title: "Shortcut") {
                shortcutEditorSection(
                    action: action,
                    title: "Focus \(column.title)",
                    description: "Jumps straight to this column inside the current project."
                )
            }

            if gridStore.columns.count > 1 {
                Button("Remove Column", role: .destructive) {
                    gridStore.removeColumn(columnID: column.id)
                    inspectorSelection = nil
                }
                .buttonStyle(.borderless)
            }

            Spacer()
        }
    }

    private func slotEditor(layer: GridLayer, column: GridToolColumn) -> some View {
        let binding = layer.group(for: column).activeBinding

        return VStack(alignment: .leading, spacing: 18) {
            drawerTitle(column.title, subtitle: layer.name)

            GridSettingsFieldSection(title: "Slot") {
                if let binding {
                    CommitTextField("Label", value: binding.label) {
                        gridStore.renameBinding(layerID: layer.id, tool: column, bindingID: binding.id, label: $0)
                    }
                    .id(binding.id)
                    .fieldResetButton {
                        gridStore.renameBinding(layerID: layer.id, tool: column, bindingID: binding.id, label: defaultBindingLabel(for: binding))
                    }

                    Text(binding.target.kindDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No app is assigned to this slot yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                GridAvailableWindowPicker(
                    windows: availableWindows,
                    mode: .window(selectedID: selectedWindowID(for: binding?.target)),
                    isLoading: isLoadingWindows,
                    usageTags: { window in
                        usageTags(for: window, excludingSlot: (layer.id, column.id))
                    },
                    onRefresh: forceRefreshAvailableWindows,
                    onSelect: { window in
                        _ = gridStore.replaceBinding(
                            layerID: layer.id,
                            tool: column,
                            bindingID: binding?.id,
                            target: target(for: window)
                        )
                    }
                )
            }

            Button("Clear Target", role: .destructive) {
                guard let binding else {
                    return
                }
                gridStore.clearBinding(layerID: layer.id, tool: column, bindingID: binding.id)
            }
            .buttonStyle(.borderless)
            .disabled(binding == nil)

            Spacer()
        }
    }

    private func standaloneAppEditor(_ app: GridStandaloneApp) -> some View {
        GridStandaloneAppInspector(
            app: app,
            settings: settings,
            gridStore: gridStore,
            availableWindows: availableWindows,
            isLoadingWindows: isLoadingWindows,
            refreshAvailableWindows: forceRefreshAvailableWindows,
            activeRecorderID: $activeRecorderID
        )
    }

    private func drawerTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var reorderHint: some View {
        Label("Drag project rows and column headers to reorder.", systemImage: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    private var reorderPreview: some View {
        Label("Reordering", systemImage: "arrow.up.arrow.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }

    private func filledSlotCount(in layer: GridLayer) -> Int {
        gridStore.columns.reduce(into: 0) { count, column in
            if layer.group(for: column).activeBinding != nil {
                count += 1
            }
        }
    }

    private func syncInspectorSelection() {
        guard let inspectorSelection else {
            return
        }

        switch inspectorSelection {
        case .project(let layerID):
            guard gridStore.layer(id: layerID) != nil else {
                self.inspectorSelection = nil
                return
            }
        case .column(let columnID):
            guard gridStore.column(id: columnID) != nil else {
                self.inspectorSelection = nil
                return
            }
        case .layerSlot(let layerID, let columnID):
            guard gridStore.layer(id: layerID) != nil,
                  gridStore.column(id: columnID) != nil else {
                self.inspectorSelection = nil
                return
            }
        case .standaloneApp(let id):
            guard gridStore.standaloneApp(id: id) != nil else {
                self.inspectorSelection = nil
                return
            }
        case .newStandaloneApp:
            break
        }
    }

    /// Loads live windows off the main thread. Recent results are reused so hopping between
    /// cells doesn't rescan every app; the picker's refresh button forces a new scan.
    private func refreshAvailableWindows(force: Bool = false) {
        if !force,
           let availableWindowsLoadedAt,
           Date.now.timeIntervalSince(availableWindowsLoadedAt) < availableWindowsMaxAge {
            return
        }

        availableWindowsTask?.cancel()
        isLoadingWindows = true
        availableWindowsTask = Task {
            let windows = await availableWindowsProvider()
            guard !Task.isCancelled else {
                return
            }

            availableWindows = windows
            availableWindowsLoadedAt = .now
            isLoadingWindows = false
        }
    }

    private func forceRefreshAvailableWindows() {
        refreshAvailableWindows(force: true)
    }

    private func updateDrawerMonitor() {
        if inspectorSelection == nil {
            stopDrawerMonitor()
            return
        }

        guard drawerKeyMonitor == nil else {
            return
        }

        drawerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                inspectorSelection = nil
                return nil
            }

            return event
        }
    }

    private func stopDrawerMonitor() {
        guard let drawerKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(drawerKeyMonitor)
        self.drawerKeyMonitor = nil
    }

    private func isSelected(layerID: String, columnID: String) -> Bool {
        inspectorSelection == .layerSlot(layerID: layerID, columnID: columnID)
    }

    private func isSelectedProject(_ layerID: String) -> Bool {
        inspectorSelection == .project(layerID: layerID)
    }

    private func isSelectedColumn(_ columnID: String) -> Bool {
        inspectorSelection == .column(columnID: columnID)
    }

    private func isSelectedStandaloneApp(_ id: String) -> Bool {
        inspectorSelection == .standaloneApp(id: id)
    }

    private func slotBackgroundColor(layer: GridLayer, isSelected: Bool) -> Color {
        if isSelected {
            return layer.color.swiftUIColor.opacity(0.15)
        }

        return Color.secondary.opacity(0.05)
    }

    private func slotBorderColor(layer: GridLayer, isSelected: Bool, isEmpty: Bool) -> Color {
        if isSelected {
            return layer.color.swiftUIColor.opacity(0.38)
        }

        return isEmpty ? Color.secondary.opacity(0.24) : Color.clear
    }

    private func defaultLayerName(for layer: GridLayer) -> String {
        "Project \((gridStore.layers.firstIndex(where: { $0.id == layer.id }) ?? 0) + 1)"
    }

    private func projectShortcutAction(for layer: GridLayer) -> HotkeyAction? {
        guard let index = gridStore.layers.firstIndex(where: { $0.id == layer.id }) else {
            return nil
        }

        return HotkeyAction(kind: .gridJumpLayer, slot: index + 1)
    }

    private func defaultLayerColor(for layer: GridLayer) -> GridLayerColor {
        GridLayerColor.allCases[(gridStore.layers.firstIndex(where: { $0.id == layer.id }) ?? 0) % GridLayerColor.allCases.count]
    }

    private func defaultColumnName(for column: GridToolColumn) -> String {
        switch column.kind {
        case .terminal:
            return GridToolColumn.terminal.title
        case .ide:
            return GridToolColumn.ide.title
        case .browser:
            return GridToolColumn.browser.title
        case .custom:
            let customColumns = gridStore.columns.filter { $0.kind == .custom }
            let index = customColumns.firstIndex(where: { $0.id == column.id }) ?? 0
            return "Custom \(index + 1)"
        }
    }

    private func defaultColumnIcon(for column: GridToolColumn) -> String {
        switch column.kind {
        case .terminal:
            return GridToolColumn.terminal.iconSymbol
        case .ide:
            return GridToolColumn.ide.iconSymbol
        case .browser:
            return GridToolColumn.browser.iconSymbol
        case .custom:
            return "square.stack.3d.up"
        }
    }

    private func defaultBindingLabel(for binding: GridBinding) -> String {
        TargetLabelPolicy().label(for: binding.target)
    }

    private func shortcutEditorSection(
        action: HotkeyAction,
        title: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ShortcutRecorderRow(
                action: action,
                scheme: .grid,
                title: title,
                description: description,
                settings: settings,
                activeRecorderID: $activeRecorderID
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func selectedWindowID(for target: Target?) -> String? {
        guard let target else {
            return nil
        }

        return bestMatchingWindow(for: target, matchAppTargets: false, windows: availableWindows)?.id
    }

    private func usageTags(for window: LiveWindow, excludingSlot: (layerID: String, columnID: String)? = nil) -> [String] {
        var tags: [String] = []

        for layer in gridStore.layers {
            for column in gridStore.columns {
                guard let binding = layer.group(for: column).activeBinding,
                      matchesWindow(window, target: binding.target, matchAppTargets: false) else {
                    continue
                }

                if let excludingSlot,
                   excludingSlot.layerID == layer.id,
                   excludingSlot.columnID == column.id {
                    continue
                }

                tags.append("\(layer.name) · \(column.title)")
            }
        }

        for app in gridStore.standaloneApps {
            guard let binding = app.binding,
                  matchesWindow(window, target: binding.target, matchAppTargets: true) else {
                continue
            }

            tags.append("Standalone · \(app.name)")
        }

        return tags
    }

    private func matchesWindow(_ window: LiveWindow, target: Target, matchAppTargets: Bool) -> Bool {
        switch target {
        case .app(let appTarget):
            return matchAppTargets && appTarget.bundleId == window.bundleId
        case .window(let windowTarget):
            return windowMatchPolicy.match(window, to: windowTarget).isMatch
        }
    }

    private func bestMatchingWindow(
        for target: Target,
        matchAppTargets: Bool,
        windows: [LiveWindow]
    ) -> LiveWindow? {
        switch target {
        case .app(let appTarget):
            guard matchAppTargets else {
                return nil
            }

            return windows.first(where: { $0.bundleId == appTarget.bundleId })
        case .window(let windowTarget):
            for matchKind in [
                WindowTargetMatchKind.exactWindowID,
                .exactTitleAndFrame,
                .exactTitle,
                .exactFrame,
                .fuzzyTitle
            ] {
                if let window = windows.first(where: { windowMatchPolicy.match($0, to: windowTarget) == matchKind }) {
                    return window
                }
            }

            return nil
        }
    }

    private func target(for window: LiveWindow) -> Target {
        .window(
            WindowTarget(
                bundleId: window.bundleId,
                appName: window.appName,
                pid: window.pid,
                windowTitle: window.title,
                windowID: window.windowID,
                frame: window.frame,
                capturedAt: .now
            )
        )
    }
}

private struct GridInspectorDrawer<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: Content

    init(onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            Divider()
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1),
            alignment: .leading
        )
        .shadow(color: .black.opacity(0.14), radius: 18, x: -8, y: 0)
    }
}

/// Edits a local draft and only writes back on submit or when focus leaves, so each keystroke
/// doesn't hit the store (and its persistence/hotkey pipeline) or get normalized mid-typing.
private struct CommitTextField: View {
    let title: String
    let value: String
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(_ title: String, value: String, onCommit: @escaping (String) -> Void) {
        self.title = title
        self.value = value
        self.onCommit = onCommit
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commit()
                }
            }
            .onChange(of: value) { _, newValue in
                draft = newValue
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard draft != value else {
            return
        }

        onCommit(draft)
    }
}

private struct GridSettingsFieldSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct GridStandaloneAppInspector: View {
    let app: GridStandaloneApp

    @ObservedObject var settings: SettingsStore
    @ObservedObject var gridStore: GridStore
    let availableWindows: [LiveWindow]
    let isLoadingWindows: Bool
    let refreshAvailableWindows: @MainActor () -> Void
    @Binding var activeRecorderID: String?
    private let windowMatchPolicy = WindowTargetMatchPolicy()

    private var recorderID: String {
        "grid-standalone-\(app.id)"
    }

    private func usageTags(for window: LiveWindow, excludingStandaloneAppID: String) -> [String] {
        var tags: [String] = []

        for layer in gridStore.layers {
            for column in gridStore.columns {
                guard let binding = layer.group(for: column).activeBinding,
                      matchesWindow(window, target: binding.target, matchAppTargets: false) else {
                    continue
                }

                tags.append("\(layer.name) · \(column.title)")
            }
        }

        for standaloneApp in gridStore.standaloneApps {
            guard standaloneApp.id != excludingStandaloneAppID,
                  let binding = standaloneApp.binding,
                  matchesWindow(window, target: binding.target, matchAppTargets: true) else {
                continue
            }

            tags.append("Standalone · \(standaloneApp.name)")
        }

        return tags
    }

    private func matchesWindow(_ window: LiveWindow, target: Target, matchAppTargets: Bool) -> Bool {
        switch target {
        case .app(let appTarget):
            return matchAppTargets && appTarget.bundleId == window.bundleId
        case .window(let windowTarget):
            return windowMatchPolicy.match(window, to: windowTarget).isMatch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.binding?.label ?? "Standalone App")
                    .font(.system(size: 18, weight: .semibold))

                Text("Standalone App")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            GridSettingsFieldSection(title: "App") {
                HStack(spacing: 8) {
                    Picker("Icon", selection: Binding(
                        get: { app.iconSymbol },
                        set: { gridStore.setStandaloneAppIcon(id: app.id, iconSymbol: $0) }
                    )) {
                        ForEach(GridToolColumn.iconOptions, id: \.self) { icon in
                            Label(icon, systemImage: icon).tag(icon)
                        }
                    }
                    .pickerStyle(.menu)

                    resetFieldButton {
                        gridStore.setStandaloneAppIcon(id: app.id, iconSymbol: "app.fill")
                    }
                }
            }

            GridSettingsFieldSection(title: "Shortcut") {
                VStack(alignment: .leading, spacing: 0) {
                    ShortcutRecorderRow(
                        recorderID: recorderID,
                        title: "Launch \(app.binding?.label ?? app.name)",
                        description: "Triggers this standalone app shortcut from anywhere.",
                        currentShortcut: app.shortcut,
                        resetButtonHelp: "Reset shortcut",
                        isUnregistered: settings.hotkeyScheme == .grid &&
                            app.shortcut.map(settings.unregisteredShortcuts.contains) == true,
                        activeRecorderID: $activeRecorderID,
                        applyShortcut: { shortcut in
                            if let conflict = settings.conflictDescription(for: shortcut, in: .grid, includeAppShortcuts: false) {
                                return conflict
                            }

                            if let duplicateApp = gridStore.standaloneApps.first(where: {
                                $0.id != app.id && $0.shortcut == shortcut
                            }) {
                                return "Already assigned to \(duplicateApp.name)."
                            }

                            gridStore.setStandaloneAppShortcut(id: app.id, shortcut: shortcut)
                            return nil
                        },
                        clearShortcut: {
                            gridStore.setStandaloneAppShortcut(id: app.id, shortcut: nil)
                        },
                        resetShortcut: {
                            gridStore.setStandaloneAppShortcut(id: app.id, shortcut: nil)
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            GridSettingsFieldSection(title: "Target") {
                Text(app.binding?.target.kindDescription ?? "No app target saved.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                GridAvailableWindowPicker(
                    windows: availableWindows,
                    mode: .app(selectedBundleID: app.binding?.target.bundleId),
                    isLoading: isLoadingWindows,
                    usageTags: { window in
                        usageTags(for: window, excludingStandaloneAppID: app.id)
                    },
                    onRefresh: refreshAvailableWindows,
                    onSelect: { window in
                        _ = gridStore.replaceStandaloneAppBinding(
                            id: app.id,
                            target: .app(
                                AppTarget(
                                    bundleId: window.bundleId,
                                    appName: window.appName
                                )
                            )
                        )
                    }
                )
            }

            HStack(spacing: 12) {
                Button("Clear Target", role: .destructive) {
                    gridStore.clearStandaloneAppBinding(id: app.id)
                }
                .buttonStyle(.borderless)
                .disabled(app.binding == nil)

                Button("Remove Standalone App", role: .destructive) {
                    gridStore.removeStandaloneApp(id: app.id)
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Searchable list of live windows grouped by app. In `.app` mode (standalone apps bind to an
/// app, not a window) each app is a single row.
private struct GridAvailableWindowPicker: View {
    enum Mode {
        case window(selectedID: String?)
        case app(selectedBundleID: String?)
    }

    let windows: [LiveWindow]
    let mode: Mode
    let isLoading: Bool
    let usageTags: (LiveWindow) -> [String]
    let onRefresh: @MainActor () -> Void
    let onSelect: (LiveWindow) -> Void

    @State private var query = ""

    private struct AppGroup: Identifiable {
        let bundleId: String
        let appName: String
        let windows: [LiveWindow]

        var id: String { bundleId }
    }

    var body: some View {
        // Matching a window against every bound target is relatively costly, so compute each
        // window's tags once per render.
        let tagsByWindowID = Dictionary(
            windows.map { ($0.id, usageTags($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        let groups = filteredGroups

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(isAppMode ? "Running Apps" : "Available Windows")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(isAppMode ? "Refresh running apps" : "Refresh available windows")
                .disabled(isLoading)
            }

            TextField(isAppMode ? "Search apps" : "Search apps and windows", text: $query)
                .textFieldStyle(.roundedBorder)

            if groups.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups) { group in
                        if isAppMode {
                            appRow(group, tags: Self.uniqueTags(group.windows.flatMap { tagsByWindowID[$0.id] ?? [] }))
                        } else {
                            windowGroup(group, tagsByWindowID: tagsByWindowID)
                        }
                    }
                }
            }
        }
    }

    private var isAppMode: Bool {
        if case .app = mode {
            return true
        }
        return false
    }

    private var emptyMessage: String {
        if !query.isEmpty {
            return "Nothing matches “\(query)”."
        }
        if isLoading {
            return "Looking for windows…"
        }
        return isAppMode ? "No running apps with windows right now." : "No live windows are available right now."
    }

    private var filteredGroups: [AppGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let grouped = Dictionary(grouping: windows, by: \.bundleId)

        return grouped.compactMap { bundleId, appWindows -> AppGroup? in
            guard let appName = appWindows.first?.appName else {
                return nil
            }

            let appMatches = needle.isEmpty || appName.localizedCaseInsensitiveContains(needle)
            let matchingWindows = appMatches
                ? appWindows
                : appWindows.filter { ($0.title ?? "").localizedCaseInsensitiveContains(needle) }

            guard !matchingWindows.isEmpty else {
                return nil
            }

            return AppGroup(bundleId: bundleId, appName: appName, windows: matchingWindows)
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private func windowGroup(_ group: AppGroup, tagsByWindowID: [String: [String]]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppIconView(bundleId: group.bundleId)
                Text(group.appName)
                    .font(.system(size: 12, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.windows) { window in
                    pickerRow(
                        title: window.title?.isEmpty == false ? window.title! : "Untitled window",
                        tags: tagsByWindowID[window.id] ?? [],
                        isSelected: isSelected(window),
                        indent: 28
                    ) {
                        onSelect(window)
                    }
                }
            }
        }
    }

    private func appRow(_ group: AppGroup, tags: [String]) -> some View {
        pickerRow(
            title: group.appName,
            tags: tags,
            isSelected: isSelected(group),
            indent: 0,
            icon: group.bundleId
        ) {
            if let window = group.windows.first {
                onSelect(window)
            }
        }
    }

    private func pickerRow(
        title: String,
        tags: [String],
        isSelected: Bool,
        indent: CGFloat,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                if let icon {
                    AppIconView(bundleId: icon)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(tags.prefix(2)), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
                            }

                            if tags.count > 2 {
                                Text("+\(tags.count - 2)")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, indent + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .cardBackground(
                fill: isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                cornerRadius: 8
            )
        }
        .buttonStyle(.plain)
        .help(tags.isEmpty ? title : "\(title)\nUsed by: \(tags.joined(separator: ", "))")
    }

    private func isSelected(_ window: LiveWindow) -> Bool {
        if case .window(let selectedID) = mode {
            return selectedID == window.id
        }
        return false
    }

    private func isSelected(_ group: AppGroup) -> Bool {
        if case .app(let selectedBundleID) = mode {
            return selectedBundleID == group.bundleId
        }
        return false
    }

    private static func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }
    }
}

private struct GridLayerDropDelegate: DropDelegate {
    let targetLayerID: String
    let layers: [GridLayer]
    @Binding var draggedLayerID: String?
    let gridStore: GridStore

    func dropEntered(info: DropInfo) {
        guard let draggedLayerID,
              draggedLayerID != targetLayerID,
              let fromIndex = layers.firstIndex(where: { $0.id == draggedLayerID }),
              let toIndex = layers.firstIndex(where: { $0.id == targetLayerID }) else {
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            gridStore.moveLayers(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedLayerID = nil
        return true
    }
}

private struct GridColumnDropDelegate: DropDelegate {
    let targetColumnID: String
    let columns: [GridToolColumn]
    @Binding var draggedColumnID: String?
    let gridStore: GridStore

    func dropEntered(info: DropInfo) {
        guard let draggedColumnID,
              draggedColumnID != targetColumnID,
              let fromIndex = columns.firstIndex(where: { $0.id == draggedColumnID }),
              let toIndex = columns.firstIndex(where: { $0.id == targetColumnID }) else {
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            gridStore.moveColumns(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedColumnID = nil
        return true
    }
}

private func bundleID(for binding: GridBinding) -> String {
    switch binding.target {
    case .app(let target):
        return target.bundleId
    case .window(let target):
        return target.bundleId
    }
}

@MainActor
private func resetFieldButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 28, height: 28)
    }
    .buttonStyle(.borderless)
    .help("Reset field")
}

@MainActor
private extension View {
    func fieldResetButton(action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            self
            resetFieldButton(action: action)
        }
    }
}

private struct CardBackgroundModifier: ViewModifier {
    let fill: Color
    let stroke: Color
    let dash: [CGFloat]
    let cornerRadius: CGFloat

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fill)

                    if isHovered {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke, style: StrokeStyle(lineWidth: 1, dash: dash))
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func cardBackground(fill: Color, stroke: Color = .clear, dash: [CGFloat] = [], cornerRadius: CGFloat = 16) -> some View {
        modifier(CardBackgroundModifier(fill: fill, stroke: stroke, dash: dash, cornerRadius: cornerRadius))
    }
}
