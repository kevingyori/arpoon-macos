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

struct GridSettingsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var gridStore: GridStore
    @ObservedObject var gridSession: GridSession
    let availableWindowsProvider: @MainActor () -> [LiveWindow]
    @Binding var activeRecorderID: String?

    @State private var inspectorSelection: GridInspectorSelection?
    @State private var draggedLayerID: String?
    @State private var draggedColumnID: String?
    @State private var availableWindows: [LiveWindow] = []
    @State private var drawerKeyMonitor: Any?

    private let rowLabelWidth: CGFloat = 196
    private let cellWidth: CGFloat = 188
    private let rowHeight: CGFloat = 120
    private let headerHeight: CGFloat = 82
    private let boardSpacing: CGFloat = 12
    private let drawerWidth: CGFloat = 360
    private let cardHorizontalInset: CGFloat = 14

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
            refreshAvailableWindows()
            syncInspectorSelection()
            updateDrawerMonitor()
        }
        .onReceive(gridStore.$layers) { _ in
            gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)
            syncInspectorSelection()
        }
        .onReceive(gridStore.$columns) { _ in
            gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)
            syncInspectorSelection()
        }
        .onReceive(gridStore.$standaloneApps) { _ in
            syncInspectorSelection()
        }
        .onChange(of: inspectorSelection) { _, _ in
            refreshAvailableWindows()
            updateDrawerMonitor()
        }
        .onDisappear {
            stopDrawerMonitor()
        }
    }

    private var boardPanel: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: boardSpacing) {
                gridHeaderRow

                ForEach(gridStore.layers) { layer in
                    layerRow(layer)
                }

                addProjectRow
                standaloneAppsRow
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        HStack(alignment: .center, spacing: 10) {
                            AppIconView(bundleId: bundleID(for: binding))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(binding.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                Text(binding.target.kindDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                                Text(binding.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                Text(app.shortcut?.displayString ?? "No shortcut")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)

                            Text("Bind App")
                                .font(.system(size: 12, weight: .medium))

                            Text(app.shortcut?.displayString ?? "No shortcut")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
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
                if app.binding != nil {
                    gridStore.clearStandaloneAppBinding(id: app.id)
                } else {
                    gridStore.removeStandaloneApp(id: app.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
            .buttonStyle(.plain)
            .help(app.binding != nil ? "Clear binding" : "Remove standalone app")
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
                    selectedWindowID: nil,
                    currentTargetDescription: nil,
                    usageTags: { window in
                        usageTags(for: window)
                    },
                    onRefresh: refreshAvailableWindows,
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
                TextField(
                    "Project name",
                    text: Binding(
                        get: { layer.name },
                        set: { gridStore.renameLayer(id: layer.id, name: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
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
                    shortcutEditorRow(
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
                TextField(
                    "Column name",
                    text: Binding(
                        get: { column.title },
                        set: { gridStore.renameColumn(columnID: column.id, name: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
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
                shortcutEditorRow(
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
                    TextField(
                        "Label",
                        text: Binding(
                            get: { binding.label },
                            set: { gridStore.renameBinding(layerID: layer.id, tool: column, bindingID: binding.id, label: $0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
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
                    selectedWindowID: selectedWindowID(for: binding?.target),
                    currentTargetDescription: nil,
                    usageTags: { window in
                        usageTags(for: window, excludingSlot: (layer.id, column.id))
                    },
                    onRefresh: refreshAvailableWindows,
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
            refreshAvailableWindows: refreshAvailableWindows,
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

    private func refreshAvailableWindows() {
        availableWindows = availableWindowsProvider()
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

    private func shortcutEditorRow(
        action: HotkeyAction,
        title: String,
        description: String
    ) -> some View {
        ShortcutRecorderRow(
            action: action,
            title: title,
            description: description,
            settings: settings,
            resetShortcut: action.defaultShortcut,
            activeRecorderID: $activeRecorderID
        )
    }

    private func selectedWindowID(for target: Target?) -> String? {
        guard let target else {
            return nil
        }

        return availableWindows.first(where: { matchesWindow($0, target: target, matchAppTargets: false) })?.id
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
            if let liveID = window.windowID, let targetID = windowTarget.windowID {
                return liveID == targetID && window.bundleId == windowTarget.bundleId
            }

            return window.bundleId == windowTarget.bundleId &&
                window.title == windowTarget.windowTitle &&
                window.frame == windowTarget.frame
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
    let refreshAvailableWindows: @MainActor () -> Void
    @Binding var activeRecorderID: String?

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
            if let liveID = window.windowID, let targetID = windowTarget.windowID {
                return liveID == targetID && window.bundleId == windowTarget.bundleId
            }

            return window.bundleId == windowTarget.bundleId &&
                window.title == windowTarget.windowTitle &&
                window.frame == windowTarget.frame
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
                ShortcutRecorderRow(
                    recorderID: recorderID,
                    title: "Launch \(app.binding?.label ?? app.name)",
                    description: "Triggers this standalone app shortcut from anywhere.",
                    currentShortcut: app.shortcut,
                    activeRecorderID: $activeRecorderID,
                    applyShortcut: { shortcut in
                        if let duplicateAction = settings.activeHotkeyActions(for: .grid).first(where: { action in
                            settings.shortcut(for: action) == shortcut
                        }) {
                            return "Already assigned to \(settings.title(for: duplicateAction))."
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
                    }
                )
            }

            GridSettingsFieldSection(title: "Target") {
                Text(app.binding?.target.kindDescription ?? "No app target saved.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                GridAvailableWindowPicker(
                    windows: availableWindows,
                    selectedWindowID: nil,
                    currentTargetDescription: nil,
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

private struct GridAvailableWindowPicker: View {
    let windows: [LiveWindow]
    let selectedWindowID: String?
    let currentTargetDescription: String?
    let usageTags: (LiveWindow) -> [String]
    let onRefresh: @MainActor () -> Void
    let onSelect: (LiveWindow) -> Void

    private let labelPolicy = TargetLabelPolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Available Windows")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh available windows")
            }

            if windows.isEmpty {
                Text("No live windows are available right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "Available Windows",
                    selection: Binding(
                        get: { selectedWindowID ?? "" },
                        set: { newValue in
                            guard let window = windows.first(where: { $0.id == newValue }) else {
                                return
                            }

                            onSelect(window)
                        }
                    )
                ) {
                    Text("Select a window")
                        .tag("")

                    ForEach(windows) { window in
                        windowOption(window)
                            .tag(window.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let currentTargetDescription, !currentTargetDescription.isEmpty {
                Text(currentTargetDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func windowOption(_ window: LiveWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(labelPolicy.label(for: window))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            if !usageTags(window).isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(usageTags(window).prefix(2)), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }

                    if usageTags(window).count > 2 {
                        Text("+\(usageTags(window).count - 2)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
