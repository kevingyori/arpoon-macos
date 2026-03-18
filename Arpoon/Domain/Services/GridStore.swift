import Combine
import Foundation

@MainActor
final class GridStore: ObservableObject {
    @Published private(set) var columns: [GridToolColumn] = GridToolColumn.defaults
    @Published private(set) var layers: [GridLayer] = []
    @Published private(set) var standaloneApps: [GridStandaloneApp] = []

    private let store: GridLayerStore
    private let labelPolicy: TargetLabelPolicy
    private var persistenceTask: Task<Void, Never>?
    private var pendingState: GridWorkspaceState?

    init(store: GridLayerStore, labelPolicy: TargetLabelPolicy) {
        self.store = store
        self.labelPolicy = labelPolicy
    }

    func load() async {
        do {
            let loaded = try await store.loadState()
            if loaded.layers.isEmpty {
                columns = GridToolColumn.defaults
                layers = Self.seedLayers()
                standaloneApps = Self.normalized(standaloneApps: loaded.standaloneApps)
                persist()
            } else {
                let normalizedState = Self.normalized(state: loaded)
                columns = normalizedState.columns
                layers = normalizedState.layers
                standaloneApps = Self.normalized(standaloneApps: loaded.standaloneApps)
            }
        } catch {
            columns = GridToolColumn.defaults
            layers = Self.seedLayers()
            standaloneApps = []
            persist()
        }
    }

    func layer(id: String) -> GridLayer? {
        layers.first(where: { $0.id == id })
    }

    func layer(at position: Int) -> GridLayer? {
        guard position >= 1, position <= layers.count else {
            return nil
        }

        return layers[position - 1]
    }

    func standaloneApp(id: String) -> GridStandaloneApp? {
        standaloneApps.first(where: { $0.id == id })
    }

    func column(id: String) -> GridToolColumn? {
        columns.first(where: { $0.id == id })
    }

    func defaultColumn(kind: GridColumnKind) -> GridToolColumn? {
        columns.first(where: { $0.kind == kind })
    }

    @discardableResult
    func addLayer() -> GridLayer? {
        guard layers.count < 9 else {
            return nil
        }

        let layer = GridLayer(
            name: "Project \(layers.count + 1)",
            color: Self.defaultColor(for: layers.count),
            groups: Self.emptyGroups(for: columns)
        )
        layers.append(layer)
        persist()
        return layer
    }

    func removeLayer(id: String) {
        guard layers.count > 1 else {
            return
        }

        layers.removeAll { $0.id == id }
        persist()
    }

    func moveLayers(fromOffsets: IndexSet, toOffset: Int) {
        layers.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist()
    }

    func renameLayer(id: String, name: String) {
        updateLayer(id: id) { $0.updatingName(name.isEmpty ? "Untitled Project" : name) }
    }

    func setColor(_ color: GridLayerColor, forLayerID id: String) {
        updateLayer(id: id) { $0.updatingColor(color) }
    }

    func renameColumn(columnID: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        columns = columns.map { column in
            guard column.id == columnID else { return column }
            return column.renaming(trimmed.isEmpty ? "Untitled" : trimmed)
        }
        persist()
    }

    func setColumnIcon(columnID: String, iconSymbol: String) {
        columns = columns.map { column in
            guard column.id == columnID else { return column }
            return column.updatingIcon(iconSymbol)
        }
        persist()
    }

    @discardableResult
    func addCustomColumn() -> GridToolColumn? {
        let index = columns.filter { $0.kind == .custom }.count + 1
        let column = GridToolColumn.custom(name: "Custom \(index)")
        columns.append(column)
        persist()
        return column
    }

    func moveColumns(fromOffsets: IndexSet, toOffset: Int) {
        columns.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist()
    }

    func removeColumn(columnID: String) {
        guard columns.count > 1,
              column(id: columnID) != nil else {
            return
        }

        columns.removeAll { $0.id == columnID }
        layers = layers.map { layer in
            var groups = layer.groups
            groups.removeValue(forKey: columnID)
            return GridLayer(
                id: layer.id,
                name: layer.name,
                color: layer.color,
                groups: groups,
                createdAt: layer.createdAt,
                updatedAt: .now
            )
        }
        persist()
    }

    @discardableResult
    func addStandaloneApp() -> GridStandaloneApp {
        let app = GridStandaloneApp(name: "Standalone App \(standaloneApps.count + 1)")
        standaloneApps.append(app)
        persist()
        return app
    }

    @discardableResult
    func createStandaloneApp(target: Target, shortcut: HotkeyShortcut? = nil, iconSymbol: String = "app.fill") -> GridStandaloneApp {
        let app = GridStandaloneApp(
            name: labelPolicy.label(for: target),
            iconSymbol: iconSymbol,
            shortcut: shortcut,
            binding: GridBinding(
                id: UUID().uuidString,
                label: labelPolicy.label(for: target),
                target: target,
                archetypeHint: nil,
                createdAt: .now,
                updatedAt: .now
            )
        )
        standaloneApps.append(app)
        persist()
        return app
    }

    func removeStandaloneApp(id: String) {
        standaloneApps.removeAll { $0.id == id }
        persist()
    }

    func renameStandaloneApp(id: String, name: String) {
        updateStandaloneApp(id: id) {
            $0.updatingName(name.isEmpty ? "Untitled App" : name)
        }
    }

    func setStandaloneAppIcon(id: String, iconSymbol: String) {
        updateStandaloneApp(id: id) {
            $0.updatingIcon(iconSymbol)
        }
    }

    func setStandaloneAppShortcut(id: String, shortcut: HotkeyShortcut?) {
        updateStandaloneApp(id: id) {
            $0.updatingShortcut(shortcut)
        }
    }

    func clearStandaloneAppBinding(id: String) {
        updateStandaloneApp(id: id) {
            $0.updatingBinding(nil)
        }
    }

    @discardableResult
    func replaceStandaloneAppBinding(id: String, target: Target) -> GridStandaloneApp? {
        var updatedApp: GridStandaloneApp?
        updateStandaloneApp(id: id) { app in
            let existing = app.binding
            let binding = GridBinding(
                id: existing?.id ?? UUID().uuidString,
                label: labelPolicy.label(for: target),
                target: target,
                archetypeHint: app.name,
                createdAt: existing?.createdAt ?? .now,
                updatedAt: .now
            )
            let updated = app.updatingBinding(binding)
            updatedApp = updated
            return updated
        }
        return updatedApp
    }

    func renameBinding(layerID: String, tool: GridToolColumn, bindingID: String, label: String) {
        updateToolGroup(layerID: layerID, tool: tool) { group in
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let bindings = group.bindings.map { binding in
                guard binding.id == bindingID else {
                    return binding
                }

                return GridBinding(
                    id: binding.id,
                    label: trimmed.isEmpty ? defaultLabel(for: tool) : trimmed,
                    target: binding.target,
                    archetypeHint: binding.archetypeHint,
                    createdAt: binding.createdAt,
                    updatedAt: .now
                )
            }

            return GridToolGroup(bindings: bindings).normalized()
        }
    }

    func clearBinding(layerID: String, tool: GridToolColumn, bindingID: String) {
        updateToolGroup(layerID: layerID, tool: tool) { group in
            let bindings = group.bindings.filter { $0.id != bindingID }
            return GridToolGroup(bindings: bindings).normalized()
        }
    }

    @discardableResult
    func replaceBinding(layerID: String, tool: GridToolColumn, bindingID: String?, target: Target) -> GridBinding? {
        var updatedBinding: GridBinding?
        updateToolGroup(layerID: layerID, tool: tool) { group in
            let existing = group.bindings.first
            let label = existing?.archetypeHint ?? defaultLabel(for: tool)
            let binding = GridBinding(
                id: existing?.id ?? bindingID ?? UUID().uuidString,
                label: labelPolicy.label(for: target),
                target: target,
                archetypeHint: label,
                createdAt: existing?.createdAt ?? .now,
                updatedAt: .now
            )
            updatedBinding = binding
            return GridToolGroup(bindings: [binding]).normalized()
        }
        return updatedBinding
    }

    private func updateLayer(id: String, transform: (GridLayer) -> GridLayer) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else {
            return
        }

        layers[index] = transform(layers[index])
        persist()
    }

    private func updateToolGroup(layerID: String, tool: GridToolColumn, transform: (GridToolGroup) -> GridToolGroup) {
        updateLayer(id: layerID) { layer in
            let updatedGroup = transform(layer.group(for: tool)).normalized()
            return layer.updatingGroup(updatedGroup, for: tool)
        }
    }

    private func persist() {
        pendingState = GridWorkspaceState(
            columns: columns,
            layers: layers,
            standaloneApps: standaloneApps
        )

        guard persistenceTask == nil else {
            return
        }

        persistenceTask = Task { [weak self] in
            await self?.drainPersistenceQueue()
        }
    }

    func flushPersistence() async {
        await persistenceTask?.value
    }

    private func drainPersistenceQueue() async {
        while let state = pendingState {
            pendingState = nil

            do {
                try await store.saveState(state)
            } catch {
                // Keep the in-memory model authoritative for the current session.
            }
        }

        persistenceTask = nil
    }

    private func updateStandaloneApp(id: String, transform: (GridStandaloneApp) -> GridStandaloneApp) {
        guard let index = standaloneApps.firstIndex(where: { $0.id == id }) else {
            return
        }

        standaloneApps[index] = transform(standaloneApps[index])
        persist()
    }

    private func defaultLabel(for tool: GridToolColumn) -> String {
        tool.suggestedLabels.first ?? tool.title.lowercased()
    }

    private static func seedLayers() -> [GridLayer] {
        (0 ..< 3).map { index in
            GridLayer(
                name: "Project \(index + 1)",
                color: defaultColor(for: index),
                groups: emptyGroups(for: GridToolColumn.defaults)
            )
        }
    }

    private static func emptyGroups(for columns: [GridToolColumn]) -> [String: GridToolGroup] {
        columns.reduce(into: [:]) { groups, column in
            groups[column.id] = GridToolGroup()
        }
    }

    private static func defaultColor(for index: Int) -> GridLayerColor {
        GridLayerColor.allCases[index % GridLayerColor.allCases.count]
    }

    private static func normalized(state: GridWorkspaceState) -> GridWorkspaceState {
        let normalizedColumns = normalized(columns: state.columns)
        let trimmed = Array(state.layers.prefix(9))
        let normalizedLayers = trimmed.map { layer in
            var groups: [String: GridToolGroup] = [:]

            for column in normalizedColumns {
                let existing = layer.groups[column.id] ?? GridToolGroup()
                groups[column.id] = existing.normalized()
            }

            return GridLayer(
                id: layer.id,
                name: layer.name.isEmpty ? "Untitled Project" : layer.name,
                color: layer.color,
                groups: groups,
                createdAt: layer.createdAt,
                updatedAt: layer.updatedAt
            )
        }

        return GridWorkspaceState(
            columns: normalizedColumns,
            layers: normalizedLayers.isEmpty ? seedLayers() : normalizedLayers,
            standaloneApps: state.standaloneApps
        )
    }

    private static func normalized(columns: [GridToolColumn]) -> [GridToolColumn] {
        guard !columns.isEmpty else {
            return GridToolColumn.defaults
        }

        var ordered: [GridToolColumn] = []
        var seenIDs = Set<String>()

        for column in columns where !seenIDs.contains(column.id) {
            ordered.append(column)
            seenIDs.insert(column.id)
        }

        return ordered
    }

    private static func normalized(standaloneApps: [GridStandaloneApp]) -> [GridStandaloneApp] {
        standaloneApps.map { app in
            GridStandaloneApp(
                id: app.id,
                name: app.name.isEmpty ? "Untitled App" : app.name,
                iconSymbol: app.iconSymbol.isEmpty ? "app.fill" : app.iconSymbol,
                shortcut: app.shortcut,
                binding: app.binding,
                createdAt: app.createdAt,
                updatedAt: app.updatedAt
            )
        }
    }
}
