import Combine
import Foundation

@MainActor
final class GridStore: ObservableObject {
    @Published private(set) var layers: [GridLayer] = []
    @Published private(set) var standaloneApps: [GridStandaloneApp] = []

    private let store: GridLayerStore
    private let labelPolicy: TargetLabelPolicy
    private var persistenceTask: Task<Void, Never>?

    init(store: GridLayerStore, labelPolicy: TargetLabelPolicy) {
        self.store = store
        self.labelPolicy = labelPolicy
    }

    func load() async {
        do {
            let loaded = try await store.loadState()
            if loaded.layers.isEmpty {
                layers = Self.seedLayers()
                standaloneApps = Self.normalized(standaloneApps: loaded.standaloneApps)
                persist()
            } else {
                layers = Self.normalized(layers: loaded.layers)
                standaloneApps = Self.normalized(standaloneApps: loaded.standaloneApps)
            }
        } catch {
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

    @discardableResult
    func addLayer() -> GridLayer? {
        guard layers.count < 9 else {
            return nil
        }

        let layer = GridLayer(
            name: "Project \(layers.count + 1)",
            color: Self.defaultColor(for: layers.count)
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

    func renameColumn(layerID: String, columnID: String, name: String) {
        updateLayer(id: layerID) { layer in
            let updatedColumns = layer.columns.map { column in
                guard column.id == columnID else { return column }
                return column.renaming(name.isEmpty ? "Untitled" : name)
            }
            return layer.updatingColumns(updatedColumns)
        }
    }

    func setColumnIcon(layerID: String, columnID: String, iconSymbol: String) {
        updateLayer(id: layerID) { layer in
            let updatedColumns = layer.columns.map { column in
                guard column.id == columnID else { return column }
                return column.updatingIcon(iconSymbol)
            }
            return layer.updatingColumns(updatedColumns)
        }
    }

    @discardableResult
    func addCustomColumn(layerID: String, template: GridToolColumn? = nil) -> GridToolColumn? {
        var created: GridToolColumn?
        updateLayer(id: layerID) { layer in
            if let template {
                guard !layer.columns.contains(where: { $0.id == template.id }) else {
                    created = template
                    return layer
                }

                let column = GridToolColumn.custom(
                    id: template.id,
                    name: template.name,
                    iconSymbol: template.iconSymbol
                )
                created = column
                return layer.updatingColumns(layer.columns + [column])
            }

            let index = layer.columns.filter { $0.kind == .custom }.count + 1
            let column = GridToolColumn.custom(name: "Custom \(index)")
            created = column
            return layer.updatingColumns(layer.columns + [column])
        }
        return created
    }

    func moveColumns(layerID: String, fromOffsets: IndexSet, toOffset: Int) {
        updateLayer(id: layerID) { layer in
            var columns = layer.columns
            columns.move(fromOffsets: fromOffsets, toOffset: toOffset)
            return layer.updatingColumns(columns)
        }
    }

    func removeCustomColumn(layerID: String, columnID: String) {
        updateLayer(id: layerID) { layer in
            let columns = layer.columns.filter { $0.id != columnID }
            var groups = layer.groups
            groups.removeValue(forKey: columnID)
            return GridLayer(
                id: layer.id,
                name: layer.name,
                color: layer.color,
                columns: columns,
                groups: groups,
                createdAt: layer.createdAt,
                updatedAt: .now
            )
        }
    }

    @discardableResult
    func addStandaloneApp() -> GridStandaloneApp {
        let app = GridStandaloneApp(name: "Standalone App \(standaloneApps.count + 1)")
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
        let layers = self.layers
        let standaloneApps = self.standaloneApps
        persistenceTask?.cancel()
        persistenceTask = Task {
            do {
                try await store.saveState(
                    GridWorkspaceState(
                        layers: layers,
                        standaloneApps: standaloneApps
                    )
                )
            } catch {
                // Keep the in-memory model authoritative for the current session.
            }
        }
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
                color: defaultColor(for: index)
            )
        }
    }

    private static func defaultColor(for index: Int) -> GridLayerColor {
        GridLayerColor.allCases[index % GridLayerColor.allCases.count]
    }

    private static func normalized(layers: [GridLayer]) -> [GridLayer] {
        let trimmed = Array(layers.prefix(9))
        let normalized = trimmed.map { layer in
            let defaults = GridToolColumn.defaults.map { defaultColumn in
                if let existing = layer.columns.first(where: { $0.id == defaultColumn.id }) {
                    return existing
                }

                return defaultColumn
            }
            let defaultIDs = Set(GridToolColumn.defaults.map(\.id))
            let customColumns = layer.columns.filter { column in
                column.kind == .custom && !defaultIDs.contains(column.id)
            }
            let columns = defaults + customColumns
            var groups: [String: GridToolGroup] = [:]

            for column in columns {
                let existing = layer.groups[column.id] ?? GridToolGroup()
                groups[column.id] = existing.normalized()
            }

            return GridLayer(
                id: layer.id,
                name: layer.name.isEmpty ? "Untitled Project" : layer.name,
                color: layer.color,
                columns: columns,
                groups: groups,
                createdAt: layer.createdAt,
                updatedAt: layer.updatedAt
            )
        }

        return normalized.isEmpty ? seedLayers() : normalized
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
