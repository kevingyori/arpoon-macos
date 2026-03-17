import Combine
import Foundation

@MainActor
final class TheoStore: ObservableObject {
    @Published private(set) var layers: [TheoLayer] = []
    @Published private(set) var standaloneApps: [TheoStandaloneApp] = []

    private let store: TheoLayerStore
    private let labelPolicy: TargetLabelPolicy
    private var persistenceTask: Task<Void, Never>?

    init(store: TheoLayerStore, labelPolicy: TargetLabelPolicy) {
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

    func layer(id: String) -> TheoLayer? {
        layers.first(where: { $0.id == id })
    }

    func layer(at position: Int) -> TheoLayer? {
        guard position >= 1, position <= layers.count else {
            return nil
        }

        return layers[position - 1]
    }

    func standaloneApp(id: String) -> TheoStandaloneApp? {
        standaloneApps.first(where: { $0.id == id })
    }

    @discardableResult
    func addLayer() -> TheoLayer? {
        guard layers.count < 9 else {
            return nil
        }

        let layer = TheoLayer(
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

    func setColor(_ color: TheoLayerColor, forLayerID id: String) {
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
    func addCustomColumn(layerID: String) -> TheoToolColumn? {
        var created: TheoToolColumn?
        updateLayer(id: layerID) { layer in
            let index = layer.columns.filter { $0.kind == .custom }.count + 1
            let column = TheoToolColumn.custom(name: "Custom \(index)")
            created = column
            return layer.updatingColumns(layer.columns + [column])
        }
        return created
    }

    func removeCustomColumn(layerID: String, columnID: String) {
        updateLayer(id: layerID) { layer in
            let columns = layer.columns.filter { $0.id != columnID }
            var groups = layer.groups
            groups.removeValue(forKey: columnID)
            return TheoLayer(
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
    func addStandaloneApp() -> TheoStandaloneApp {
        let app = TheoStandaloneApp(name: "Standalone App \(standaloneApps.count + 1)")
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
    func replaceStandaloneAppBinding(id: String, target: Target) -> TheoStandaloneApp? {
        var updatedApp: TheoStandaloneApp?
        updateStandaloneApp(id: id) { app in
            let existing = app.binding
            let binding = TheoBinding(
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

    func setActiveBinding(layerID: String, tool: TheoToolColumn, bindingID: String?) {
        updateToolGroup(layerID: layerID, tool: tool) { group in
            TheoToolGroup(bindings: group.bindings, activeBindingID: bindingID).normalized()
        }
    }

    func renameBinding(layerID: String, tool: TheoToolColumn, bindingID: String, label: String) {
        updateToolGroup(layerID: layerID, tool: tool) { group in
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let bindings = group.bindings.map { binding in
                guard binding.id == bindingID else {
                    return binding
                }

                return TheoBinding(
                    id: binding.id,
                    label: trimmed.isEmpty ? defaultLabel(for: tool, group: group) : trimmed,
                    target: binding.target,
                    archetypeHint: binding.archetypeHint,
                    createdAt: binding.createdAt,
                    updatedAt: .now
                )
            }

            return TheoToolGroup(bindings: bindings, activeBindingID: group.activeBindingID).normalized()
        }
    }

    func moveBindings(layerID: String, tool: TheoToolColumn, fromOffsets: IndexSet, toOffset: Int) {
        guard tool.supportsMultipleBindings else {
            return
        }

        updateToolGroup(layerID: layerID, tool: tool) { group in
            var bindings = group.bindings
            bindings.move(fromOffsets: fromOffsets, toOffset: toOffset)
            return TheoToolGroup(bindings: bindings, activeBindingID: group.activeBindingID).normalized()
        }
    }

    func clearBinding(layerID: String, tool: TheoToolColumn, bindingID: String) {
        updateToolGroup(layerID: layerID, tool: tool) { group in
            let bindings = group.bindings.filter { $0.id != bindingID }
            let activeBindingID = group.activeBindingID == bindingID ? nil : group.activeBindingID
            return TheoToolGroup(bindings: bindings, activeBindingID: activeBindingID).normalized()
        }
    }

    func appendBinding(layerID: String, tool: TheoToolColumn, target: Target) -> TheoBinding? {
        guard tool.supportsMultipleBindings else {
            return replaceBinding(layerID: layerID, tool: tool, bindingID: nil, target: target)
        }

        var createdBinding: TheoBinding?
        updateToolGroup(layerID: layerID, tool: tool) { group in
            let label = defaultLabel(for: tool, group: group)
            let binding = TheoBinding(
                id: UUID().uuidString,
                label: labelPolicy.label(for: target),
                target: target,
                archetypeHint: label,
                createdAt: .now,
                updatedAt: .now
            )
            createdBinding = binding
            return TheoToolGroup(bindings: group.bindings + [binding], activeBindingID: binding.id).normalized()
        }
        return createdBinding
    }

    @discardableResult
    func replaceBinding(layerID: String, tool: TheoToolColumn, bindingID: String?, target: Target) -> TheoBinding? {
        var updatedBinding: TheoBinding?
        updateToolGroup(layerID: layerID, tool: tool) { group in
            if !tool.supportsMultipleBindings {
                let existing = group.bindings.first
                let label = existing?.archetypeHint ?? tool.suggestedLabels.first ?? labelPolicy.label(for: target)
                let binding = TheoBinding(
                    id: existing?.id ?? UUID().uuidString,
                    label: labelPolicy.label(for: target),
                    target: target,
                    archetypeHint: label,
                    createdAt: existing?.createdAt ?? .now,
                    updatedAt: .now
                )
                updatedBinding = binding
                return TheoToolGroup(bindings: [binding], activeBindingID: binding.id).normalized()
            }

            if let resolvedBinding = resolveBinding(bindingID: bindingID, in: group) {
                let bindings = group.bindings.map { binding in
                    guard binding.id == resolvedBinding.id else {
                        return binding
                    }

                    let updated = TheoBinding(
                        id: binding.id,
                        label: labelPolicy.label(for: target),
                        target: target,
                        archetypeHint: binding.archetypeHint,
                        createdAt: binding.createdAt,
                        updatedAt: .now
                    )
                    updatedBinding = updated
                    return updated
                }

                return TheoToolGroup(bindings: bindings, activeBindingID: resolvedBinding.id).normalized()
            }

            let label = defaultLabel(for: tool, group: group)
            let binding = TheoBinding(
                id: UUID().uuidString,
                label: labelPolicy.label(for: target),
                target: target,
                archetypeHint: label,
                createdAt: .now,
                updatedAt: .now
            )
            updatedBinding = binding
            return TheoToolGroup(bindings: group.bindings + [binding], activeBindingID: binding.id).normalized()
        }
        return updatedBinding
    }

    private func resolveBinding(bindingID: String?, in group: TheoToolGroup) -> TheoBinding? {
        if let bindingID,
           let binding = group.bindings.first(where: { $0.id == bindingID }) {
            return binding
        }

        return group.activeBinding
    }

    private func updateLayer(id: String, transform: (TheoLayer) -> TheoLayer) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else {
            return
        }

        layers[index] = transform(layers[index])
        persist()
    }

    private func updateToolGroup(layerID: String, tool: TheoToolColumn, transform: (TheoToolGroup) -> TheoToolGroup) {
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
                    TheoWorkspaceState(
                        layers: layers,
                        standaloneApps: standaloneApps
                    )
                )
            } catch {
                // Keep the in-memory model authoritative for the current session.
            }
        }
    }

    private func updateStandaloneApp(id: String, transform: (TheoStandaloneApp) -> TheoStandaloneApp) {
        guard let index = standaloneApps.firstIndex(where: { $0.id == id }) else {
            return
        }

        standaloneApps[index] = transform(standaloneApps[index])
        persist()
    }

    private func defaultLabel(for tool: TheoToolColumn, group: TheoToolGroup) -> String {
        let taken = Set(group.bindings.compactMap(\.archetypeHint))
        if let label = tool.suggestedLabels.first(where: { !taken.contains($0) }) {
            return label
        }

        return "\(tool.title.lowercased()) \(group.bindings.count + 1)"
    }

    private static func seedLayers() -> [TheoLayer] {
        (0 ..< 3).map { index in
            TheoLayer(
                name: "Project \(index + 1)",
                color: defaultColor(for: index)
            )
        }
    }

    private static func defaultColor(for index: Int) -> TheoLayerColor {
        TheoLayerColor.allCases[index % TheoLayerColor.allCases.count]
    }

    private static func normalized(layers: [TheoLayer]) -> [TheoLayer] {
        let trimmed = Array(layers.prefix(9))
        let normalized = trimmed.map { layer in
            let defaults = TheoToolColumn.defaults.map { defaultColumn in
                if let existing = layer.columns.first(where: { $0.id == defaultColumn.id }) {
                    return existing
                }

                return defaultColumn
            }
            let defaultIDs = Set(TheoToolColumn.defaults.map(\.id))
            let customColumns = layer.columns.filter { column in
                column.kind == .custom && !defaultIDs.contains(column.id)
            }
            let columns = defaults + customColumns
            var groups: [String: TheoToolGroup] = [:]

            for column in columns {
                let existing = layer.groups[column.id] ?? TheoToolGroup()
                let normalizedGroup: TheoToolGroup
                if column.supportsMultipleBindings {
                    normalizedGroup = existing.normalized()
                } else {
                    normalizedGroup = TheoToolGroup(
                        bindings: Array(existing.bindings.prefix(1)),
                        activeBindingID: existing.activeBindingID
                    ).normalized()
                }
                groups[column.id] = normalizedGroup
            }

            return TheoLayer(
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

    private static func normalized(standaloneApps: [TheoStandaloneApp]) -> [TheoStandaloneApp] {
        standaloneApps.map { app in
            TheoStandaloneApp(
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
