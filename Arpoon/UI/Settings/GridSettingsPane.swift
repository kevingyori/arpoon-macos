import AppKit
import Carbon
import SwiftUI

struct GridSettingsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var gridStore: GridStore
    @ObservedObject var gridSession: GridSession
    let commands: AppCommands
    @Binding var activeRecorderID: String?

    @State private var selectedLayerID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            layerSidebar

            VStack(alignment: .leading, spacing: 18) {
                editorPanel
                standaloneAppsPanel
            }
        }
        .onAppear {
            syncSelection(with: gridStore.layers)
        }
        .onReceive(gridStore.$layers) { layers in
            gridSession.sync(layers: layers)
            syncSelection(with: layers)
        }
    }

    private var layerSidebar: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Layers")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    Text("\(gridStore.layers.count)/9")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button("Add Layer") {
                    if let layer = gridStore.addLayer() {
                        selectedLayerID = layer.id
                    }
                }
                .disabled(gridStore.layers.count >= 9)

                VStack(spacing: 8) {
                    ForEach(Array(gridStore.layers.enumerated()), id: \.element.id) { index, layer in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                selectedLayerID = layer.id
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.secondary.opacity(0.14)))

                                    Circle()
                                        .fill(layer.color.swiftUIColor)
                                        .frame(width: 8, height: 8)

                                    Text(layer.name)
                                        .font(.system(size: 12.5, weight: selectedLayerID == layer.id ? .semibold : .medium))
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedLayerID == layer.id ? layer.color.swiftUIColor.opacity(0.14) : Color.secondary.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 6) {
                                Button {
                                    gridStore.moveLayers(fromOffsets: IndexSet(integer: index), toOffset: max(index - 1, 0))
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)

                                Button {
                                    gridStore.moveLayers(fromOffsets: IndexSet(integer: index), toOffset: min(index + 2, gridStore.layers.count))
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == gridStore.layers.count - 1)

                                Spacer()

                                Button("Remove") {
                                    gridStore.removeLayer(id: layer.id)
                                }
                                .buttonStyle(.borderless)
                                .disabled(gridStore.layers.count == 1)
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
            }
            .frame(width: 240, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var editorPanel: some View {
        if let layer = selectedLayer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The Grid")
                            .font(.system(size: 17, weight: .semibold))

                        Text("A digital frontier")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let index = layerIndex(layer) {
                        Button("Jump Here") {
                            commands.jumpToGridLayer(index + 1)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Add Custom Column") {
                        _ = gridStore.addCustomColumn(layerID: layer.id)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Layer name")
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
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Picker("Color", selection: Binding(
                            get: { layer.color },
                            set: { gridStore.setColor($0, forLayerID: layer.id) }
                        )) {
                            ForEach(GridLayerColor.allCases) { color in
                                Text(color.title).tag(color)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }
                }

                ForEach(layer.columns) { tool in
                    toolGroup(for: tool, in: layer)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            GroupBox {
                Text("Choose a project layer to edit.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 30)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var standaloneAppsPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Standalone Apps")
                            .font(.system(size: 17, weight: .semibold))

                        Text("The Grid keeps these app shortcuts fixed across every project layer.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Add Standalone App") {
                        _ = gridStore.addStandaloneApp()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if gridStore.standaloneApps.isEmpty {
                    Text("No standalone apps yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(gridStore.standaloneApps) { app in
                        GridStandaloneAppRow(
                            app: app,
                            settings: settings,
                            gridStore: gridStore,
                            commands: commands,
                            activeRecorderID: $activeRecorderID
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func toolGroup(for tool: GridToolColumn, in layer: GridLayer) -> some View {
        let group = layer.group(for: tool)

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(tool.title, systemImage: tool.iconSymbol)
                            .font(.system(size: 13, weight: .semibold))

                        Text("Single target for this layer.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Focus") {
                        if let index = layerIndex(layer) {
                            commands.jumpToGridLayer(index + 1)
                        }
                        commands.focusGridTool(tool)
                    }
                    .buttonStyle(.bordered)

                    Button("Use Current Target") {
                        commands.captureGridBinding(layer.id, tool, group.activeBinding?.id)
                    }
                    .buttonStyle(.borderedProminent)

                    if tool.kind == .custom {
                        Button("Remove") {
                            gridStore.removeCustomColumn(layerID: layer.id, columnID: tool.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Column name")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField(
                            "Column name",
                            text: Binding(
                                get: { tool.title },
                                set: { gridStore.renameColumn(layerID: layer.id, columnID: tool.id, name: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Picker("Icon", selection: Binding(
                            get: { tool.iconSymbol },
                            set: { gridStore.setColumnIcon(layerID: layer.id, columnID: tool.id, iconSymbol: $0) }
                        )) {
                            ForEach(GridToolColumn.iconOptions, id: \.self) { icon in
                                Label(icon, systemImage: icon).tag(icon)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }
                }

                if group.bindings.isEmpty {
                    Text("No targets yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                } else if let binding = group.activeBinding {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            TextField(
                                "Label",
                                text: Binding(
                                    get: { binding.label },
                                    set: { gridStore.renameBinding(layerID: layer.id, tool: tool, bindingID: binding.id, label: $0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            Button("Replace") {
                                commands.captureGridBinding(layer.id, tool, binding.id)
                            }
                            .buttonStyle(.bordered)

                            Button("Clear") {
                                gridStore.clearBinding(layerID: layer.id, tool: tool, bindingID: binding.id)
                            }
                            .buttonStyle(.borderless)
                        }

                        Text(binding.target.kindDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("No active target available.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedLayer: GridLayer? {
        guard let selectedLayerID else {
            return gridStore.layers.first
        }

        return gridStore.layer(id: selectedLayerID) ?? gridStore.layers.first
    }

    private func syncSelection(with layers: [GridLayer]) {
        if let selectedLayerID,
           layers.contains(where: { $0.id == selectedLayerID }) {
            return
        }

        selectedLayerID = layers.first?.id
    }

    private func layerIndex(_ layer: GridLayer) -> Int? {
        gridStore.layers.firstIndex(where: { $0.id == layer.id })
    }
}

private struct GridStandaloneAppRow: View {
    let app: GridStandaloneApp

    @ObservedObject var settings: SettingsStore
    @ObservedObject var gridStore: GridStore
    let commands: AppCommands
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Standalone app name",
                        text: Binding(
                            get: { app.name },
                            set: { gridStore.renameStandaloneApp(id: app.id, name: $0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Text(app.binding?.target.kindDescription ?? "No app target saved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Picker("Icon", selection: Binding(
                        get: { app.iconSymbol },
                        set: { gridStore.setStandaloneAppIcon(id: app.id, iconSymbol: $0) }
                    )) {
                        ForEach(GridToolColumn.iconOptions, id: \.self) { icon in
                            Label(icon, systemImage: icon).tag(icon)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                Spacer()

                Button("Jump") {
                    commands.jumpToGridStandaloneApp(app.id)
                }
                .buttonStyle(.bordered)

                Button("Use Current App") {
                    commands.captureGridStandaloneApp(app.id)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcut")
                        .font(.system(size: 11, weight: .semibold))
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
                    }
                }

                Spacer()

                Button("Clear Target") {
                    gridStore.clearStandaloneAppBinding(id: app.id)
                }
                .buttonStyle(.bordered)
                .disabled(app.binding == nil)

                Button("Remove") {
                    gridStore.removeStandaloneApp(id: app.id)
                }
                .buttonStyle(.borderless)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
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
