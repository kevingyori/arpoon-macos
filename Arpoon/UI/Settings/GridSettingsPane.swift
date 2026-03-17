import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

private enum GridInspectorSelection: Hashable {
    case layerSlot(layerID: String, columnID: String)
    case standaloneApp(id: String)
}

struct GridSettingsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var gridStore: GridStore
    @ObservedObject var gridSession: GridSession
    let availableWindowsProvider: @MainActor () -> [LiveWindow]
    @Binding var activeRecorderID: String?

    @State private var selectedLayerID: String?
    @State private var inspectorSelection: GridInspectorSelection?
    @State private var draggedLayerID: String?
    @State private var draggedColumnID: String?
    @State private var availableWindows: [LiveWindow] = []

    private let rowLabelWidth: CGFloat = 190
    private let cellWidth: CGFloat = 176

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            boardPanel

            if let inspectorSelection {
                inspectorPanel(for: inspectorSelection)
                    .frame(width: 340, alignment: .topLeading)
            }
        }
        .onAppear {
            refreshAvailableWindows()
            syncLayerSelection(with: gridStore.layers)
            syncInspectorSelection()
        }
        .onReceive(gridStore.$layers) { layers in
            gridSession.sync(layers: layers)
            syncLayerSelection(with: layers)
            syncInspectorSelection()
        }
        .onReceive(gridStore.$standaloneApps) { _ in
            syncInspectorSelection()
        }
        .onChange(of: inspectorSelection) { _, _ in
            refreshAvailableWindows()
        }
    }

    private var boardPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The Grid")
                            .font(.system(size: 17, weight: .semibold))

                        Text("A digital frontier")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Add Project") {
                        if let layer = gridStore.addLayer() {
                            selectedLayerID = layer.id
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(gridStore.layers.count >= 9)

                    Button("Add Column") {
                        guard let layerID = selectedLayer?.id else {
                            return
                        }

                        if let column = gridStore.addCustomColumn(layerID: layerID) {
                            selectedLayerID = layerID
                            inspectorSelection = .layerSlot(layerID: layerID, columnID: column.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedLayer == nil)
                }

                Text("Drag project rows or column headers to reorder. Click any slot or plus to open the inspector.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 14) {
                        gridHeaderRow

                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(gridStore.layers) { layer in
                                    layerRow(layer)
                                }

                                standaloneAppsRow
                            }
                            .padding(.trailing, 6)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var gridHeaderRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Projects")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(gridStore.layers.count)/9")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: rowLabelWidth, alignment: .leading)

            ForEach(visibleColumns) { column in
                columnHeaderCell(column)
            }
        }
    }

    private func columnHeaderCell(_ column: GridToolColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: column.iconSymbol)
                    .font(.system(size: 12, weight: .semibold))

                Text(column.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }

            Text(column.kind == .custom ? "Custom column" : "Default column")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: cellWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cardBackground(
            fill: headerColumnBackground(for: column),
            stroke: headerColumnStroke(for: column),
            cornerRadius: 14
        )
        .onDrag {
            draggedColumnID = column.id
            return NSItemProvider(object: NSString(string: column.id))
        }
        .onDrop(
            of: [UTType.text],
            delegate: GridColumnDropDelegate(
                targetColumnID: column.id,
                layerID: selectedLayer?.id ?? "",
                columns: visibleColumns,
                draggedColumnID: $draggedColumnID,
                gridStore: gridStore
            )
        )
    }

    private func layerRow(_ layer: GridLayer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            layerLabelCell(layer)

            ForEach(visibleColumns) { template in
                slotCell(for: layer, template: template)
            }
        }
    }

    private func layerLabelCell(_ layer: GridLayer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(layer.color.swiftUIColor)
                    .frame(width: 10, height: 10)

                Text(layer.name)
                    .font(.system(size: 13, weight: selectedLayerID == layer.id ? .semibold : .medium))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("Remove") {
                    gridStore.removeLayer(id: layer.id)
                    if selectedLayerID == layer.id {
                        selectedLayerID = gridStore.layers.first?.id
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(gridStore.layers.count == 1)
            }
        }
        .frame(width: rowLabelWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .cardBackground(
            fill: selectedLayerID == layer.id ? layer.color.swiftUIColor.opacity(0.14) : Color.secondary.opacity(0.06),
            stroke: selectedLayerID == layer.id ? layer.color.swiftUIColor.opacity(0.34) : Color.clear,
            cornerRadius: 16
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedLayerID = layer.id
        }
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

    @ViewBuilder
    private func slotCell(for layer: GridLayer, template: GridToolColumn) -> some View {
        if let column = layer.column(id: template.id) ?? matchingDefaultColumn(for: template, in: layer) {
            let group = layer.group(for: column)
            let binding = group.activeBinding

            Button {
                selectedLayerID = layer.id
                inspectorSelection = .layerSlot(layerID: layer.id, columnID: column.id)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: column.iconSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(binding == nil ? Color.secondary : layer.color.swiftUIColor)

                        Text(column.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }

                    if let binding {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                AppIconView(bundleId: bundleID(for: binding))

                                Text(binding.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                            }

                            Text(binding.target.kindDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)

                            Text("Add App")
                                .font(.system(size: 12, weight: .medium))

                            Text("Open the slot inspector")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: cellWidth, alignment: .leading)
                .frame(minHeight: 116, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .buttonStyle(CardButtonStyle(
                fill: slotBackgroundColor(layer: layer, isSelected: isSelected(layerID: layer.id, columnID: column.id)),
                stroke: slotBorderColor(layer: layer, isSelected: isSelected(layerID: layer.id, columnID: column.id), isEmpty: binding == nil),
                dash: binding == nil ? [6, 6] : []
            ))
        } else {
            Button {
                if let created = gridStore.addCustomColumn(layerID: layer.id, template: template) {
                    selectedLayerID = layer.id
                    inspectorSelection = .layerSlot(layerID: layer.id, columnID: created.id)
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text("Add \(template.title)")
                        .font(.system(size: 12, weight: .medium))

                    Text("Create this shared column in \(layer.name).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: cellWidth, alignment: .leading)
                .frame(minHeight: 116, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .buttonStyle(CardButtonStyle(
                fill: Color.secondary.opacity(0.04),
                stroke: Color.secondary.opacity(0.22),
                dash: [6, 6]
            ))
        }
    }

    private var standaloneAppsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Standalone Apps Project")
                    .font(.system(size: 13, weight: .semibold))

                Text("Shortcuts that stay the same between projects.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button("Add App") {
                    let app = gridStore.addStandaloneApp()
                    inspectorSelection = .standaloneApp(id: app.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(width: rowLabelWidth, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.06))
            )

            ForEach(gridStore.standaloneApps) { app in
                standaloneAppCard(app)
            }

            addStandaloneAppCard
        }
    }

    private func standaloneAppCard(_ app: GridStandaloneApp) -> some View {
        Button {
            inspectorSelection = .standaloneApp(id: app.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: app.iconSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(app.binding == nil ? Color.secondary : Color.primary)

                    Text(app.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }

                if let binding = app.binding {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            AppIconView(bundleId: bundleID(for: binding))

                            Text(binding.label)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }

                        Text(app.shortcut?.displayString ?? "No shortcut")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text("Add App")
                            .font(.system(size: 12, weight: .medium))

                        Text(app.shortcut?.displayString ?? "No shortcut")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: cellWidth, alignment: .leading)
            .frame(minHeight: 116, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .buttonStyle(CardButtonStyle(
            fill: isSelectedStandaloneApp(app.id) ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.05),
            stroke: isSelectedStandaloneApp(app.id) ? Color.secondary.opacity(0.35) : Color.clear
        ))
    }

    private var addStandaloneAppCard: some View {
        Button {
            let app = gridStore.addStandaloneApp()
            inspectorSelection = .standaloneApp(id: app.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.secondary)

                Text("Add Standalone App")
                    .font(.system(size: 12, weight: .medium))

                Text("Create a cross-project shortcut slot.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: cellWidth, alignment: .leading)
            .frame(minHeight: 116, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .buttonStyle(CardButtonStyle(
            fill: Color.secondary.opacity(0.04),
            stroke: Color.secondary.opacity(0.22),
            dash: [6, 6]
        ))
    }

    @ViewBuilder
    private func inspectorPanel(for selection: GridInspectorSelection) -> some View {
        GroupBox {
            switch selection {
            case .layerSlot(let layerID, let columnID):
                if let layer = gridStore.layer(id: layerID),
                   let column = layer.column(id: columnID) ?? selectedLayer?.column(id: columnID) {
                    slotInspector(layer: layer, column: column)
                } else {
                    Text("This slot is no longer available.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            case .standaloneApp(let id):
                if let app = gridStore.standaloneApp(id: id) {
                    GridStandaloneAppInspector(
                        app: app,
                        settings: settings,
                        gridStore: gridStore,
                        availableWindows: availableWindows,
                        refreshAvailableWindows: refreshAvailableWindows,
                        activeRecorderID: $activeRecorderID
                    )
                } else {
                    Text("This standalone app is no longer available.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack {
                Text("Inspector")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button("Close") {
                    inspectorSelection = nil
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func slotInspector(layer: GridLayer, column: GridToolColumn) -> some View {
        let binding = layer.group(for: column).activeBinding

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(column.title)
                    .font(.system(size: 17, weight: .semibold))

                Text(layer.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Project")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

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

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Column")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "Column name",
                    text: Binding(
                        get: { column.title },
                        set: { gridStore.renameColumn(layerID: layer.id, columnID: column.id, name: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .fieldResetButton {
                    gridStore.renameColumn(layerID: layer.id, columnID: column.id, name: defaultColumnName(for: column, in: layer))
                }

                HStack(spacing: 8) {
                    Picker("Icon", selection: Binding(
                        get: { column.iconSymbol },
                        set: { gridStore.setColumnIcon(layerID: layer.id, columnID: column.id, iconSymbol: $0) }
                    )) {
                        ForEach(GridToolColumn.iconOptions, id: \.self) { icon in
                            Label(icon, systemImage: icon).tag(icon)
                        }
                    }
                    .pickerStyle(.menu)

                    resetFieldButton {
                        gridStore.setColumnIcon(layerID: layer.id, columnID: column.id, iconSymbol: defaultColumnIcon(for: column))
                    }
                }

                if column.kind == .custom {
                    Button("Remove Column") {
                        gridStore.removeCustomColumn(layerID: layer.id, columnID: column.id)
                        inspectorSelection = nil
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Slot")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

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

                if let binding {
                    Button("Clear") {
                        gridStore.clearBinding(layerID: layer.id, tool: column, bindingID: binding.id)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedLayer: GridLayer? {
        guard let selectedLayerID else {
            return gridStore.layers.first
        }

        return gridStore.layer(id: selectedLayerID) ?? gridStore.layers.first
    }

    private var visibleColumns: [GridToolColumn] {
        selectedLayer?.columns ?? GridToolColumn.defaults
    }

    private func matchingDefaultColumn(for template: GridToolColumn, in layer: GridLayer) -> GridToolColumn? {
        guard template.kind != .custom else {
            return nil
        }

        return layer.defaultColumn(kind: template.kind)
    }

    private func syncLayerSelection(with layers: [GridLayer]) {
        if let selectedLayerID,
           layers.contains(where: { $0.id == selectedLayerID }) {
            return
        }

        selectedLayerID = layers.first?.id
    }

    private func syncInspectorSelection() {
        guard let inspectorSelection else {
            return
        }

        switch inspectorSelection {
        case .layerSlot(let layerID, let columnID):
            guard let layer = gridStore.layer(id: layerID),
                  layer.column(id: columnID) != nil else {
                self.inspectorSelection = nil
                return
            }
        case .standaloneApp(let id):
            guard gridStore.standaloneApp(id: id) != nil else {
                self.inspectorSelection = nil
                return
            }
        }
    }

    private func refreshAvailableWindows() {
        availableWindows = availableWindowsProvider()
    }

    private func layerIndex(_ layer: GridLayer) -> Int? {
        gridStore.layers.firstIndex(where: { $0.id == layer.id })
    }

    private func isSelected(layerID: String, columnID: String) -> Bool {
        inspectorSelection == .layerSlot(layerID: layerID, columnID: columnID)
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

    private func headerColumnBackground(for column: GridToolColumn) -> Color {
        selectedLayer?.column(id: column.id) == nil && column.kind == .custom
            ? Color.secondary.opacity(0.04)
            : Color.secondary.opacity(0.06)
    }

    private func headerColumnStroke(for column: GridToolColumn) -> Color {
        selectedLayer?.column(id: column.id) == nil && column.kind == .custom
            ? Color.secondary.opacity(0.22)
            : Color.clear
    }

    private func defaultLayerName(for layer: GridLayer) -> String {
        "Project \((layerIndex(layer) ?? 0) + 1)"
    }

    private func defaultLayerColor(for layer: GridLayer) -> GridLayerColor {
        GridLayerColor.allCases[(layerIndex(layer) ?? 0) % GridLayerColor.allCases.count]
    }

    private func defaultColumnName(for column: GridToolColumn, in layer: GridLayer) -> String {
        switch column.kind {
        case .terminal:
            return GridToolColumn.terminal.title
        case .ide:
            return GridToolColumn.ide.title
        case .browser:
            return GridToolColumn.browser.title
        case .custom:
            let customColumns = layer.columns.filter { $0.kind == .custom }
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

    private func selectedWindowID(for target: Target?) -> String? {
        guard let target else {
            return nil
        }

        return availableWindows.first(where: { matchesWindow($0, target: target, matchAppTargets: false) })?.id
    }

    private func usageTags(for window: LiveWindow, excludingSlot: (layerID: String, columnID: String)? = nil) -> [String] {
        var tags: [String] = []

        for layer in gridStore.layers {
            for column in layer.columns {
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

private struct GridStandaloneAppInspector: View {
    let app: GridStandaloneApp

    @ObservedObject var settings: SettingsStore
    @ObservedObject var gridStore: GridStore
    let availableWindows: [LiveWindow]
    let refreshAvailableWindows: @MainActor () -> Void
    @Binding var activeRecorderID: String?

    @State private var eventMonitor: Any?
    @State private var errorMessage: String?

    private var recorderID: String {
        "grid-standalone-\(app.id)"
    }

    private var isRecording: Bool {
        activeRecorderID == recorderID
    }

    private var shortcutLabel: String {
        if isRecording {
            return "Type Shortcut"
        }

        return app.shortcut?.displayString ?? "Disabled"
    }

    private var defaultAppName: String {
        let index = gridStore.standaloneApps.firstIndex(where: { $0.id == app.id }) ?? 0
        return "Standalone App \(index + 1)"
    }

    private func usageTags(for window: LiveWindow, excludingStandaloneAppID: String) -> [String] {
        var tags: [String] = []

        for layer in gridStore.layers {
            for column in layer.columns {
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 17, weight: .semibold))

                Text("Standalone Apps Project")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            TextField(
                "Standalone app name",
                text: Binding(
                    get: { app.name },
                    set: { gridStore.renameStandaloneApp(id: app.id, name: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .fieldResetButton {
                gridStore.renameStandaloneApp(id: app.id, name: defaultAppName)
            }

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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Shortcut")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    let shortcutButton = Button {
                        errorMessage = nil
                        activeRecorderID = isRecording ? nil : recorderID
                    } label: {
                        Text(shortcutLabel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(minWidth: 138)
                    }

                    if isRecording {
                        shortcutButton.buttonStyle(.borderedProminent)
                    } else {
                        shortcutButton.buttonStyle(.bordered)
                    }

                    Button("Clear Shortcut") {
                        errorMessage = nil
                        gridStore.setStandaloneAppShortcut(id: app.id, shortcut: nil)
                        activeRecorderID = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(app.shortcut == nil)

                    resetFieldButton {
                        errorMessage = nil
                        gridStore.setStandaloneAppShortcut(id: app.id, shortcut: nil)
                        activeRecorderID = nil
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Slot")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

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

                Button("Clear Target") {
                    gridStore.clearStandaloneAppBinding(id: app.id)
                }
                .buttonStyle(.bordered)
                .disabled(app.binding == nil)
            }

            Button("Remove Standalone App") {
                gridStore.removeStandaloneApp(id: app.id)
            }
            .buttonStyle(.borderless)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startRecording()
            } else {
                stopRecording()
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        guard let eventMonitor else {
            return
        }

        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)

        if keyCode == UInt32(kVK_Escape) {
            activeRecorderID = nil
            return
        }

        if keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            gridStore.setStandaloneAppShortcut(id: app.id, shortcut: nil)
            errorMessage = nil
            activeRecorderID = nil
            return
        }

        guard let shortcut = HotkeyShortcut(event: event) else {
            errorMessage = "Use at least one modifier key."
            return
        }

        if let duplicateAction = HotkeyAction.activeActions(for: .grid).first(where: { action in
            settings.shortcut(for: action) == shortcut
        }) {
            errorMessage = "Already assigned to \(duplicateAction.title)."
            return
        }

        if let duplicateApp = gridStore.standaloneApps.first(where: {
            $0.id != app.id && $0.shortcut == shortcut
        }) {
            errorMessage = "Already assigned to \(duplicateApp.name)."
            return
        }

        gridStore.setStandaloneAppShortcut(id: app.id, shortcut: shortcut)
        errorMessage = nil
        activeRecorderID = nil
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
    let layerID: String
    let columns: [GridToolColumn]
    @Binding var draggedColumnID: String?
    let gridStore: GridStore

    func dropEntered(info: DropInfo) {
        guard !layerID.isEmpty,
              let draggedColumnID,
              draggedColumnID != targetColumnID,
              let fromIndex = columns.firstIndex(where: { $0.id == draggedColumnID }),
              let toIndex = columns.firstIndex(where: { $0.id == targetColumnID }) else {
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            gridStore.moveColumns(
                layerID: layerID,
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

private struct CardButtonStyle: ButtonStyle {
    let fill: Color
    let stroke: Color
    let dash: [CGFloat]
    let cornerRadius: CGFloat
    
    init(fill: Color, stroke: Color = .clear, dash: [CGFloat] = [], cornerRadius: CGFloat = 16) {
        self.fill = fill
        self.stroke = stroke
        self.dash = dash
        self.cornerRadius = cornerRadius
    }

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fill)
                    
                    if isHovered {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.primary.opacity(0.04))
                    }
                    
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.primary.opacity(0.06))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke, style: StrokeStyle(lineWidth: 1, dash: dash))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}
