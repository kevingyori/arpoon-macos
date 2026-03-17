import Foundation

enum GridColumnKind: String, Codable, Hashable {
    case terminal
    case ide
    case browser
    case custom
}

struct GridToolColumn: Codable, Identifiable, Hashable {
    let id: String
    let kind: GridColumnKind
    let name: String
    let iconSymbol: String

    static let terminal = GridToolColumn(
        id: "terminal",
        kind: .terminal,
        name: "Terminal",
        iconSymbol: "terminal"
    )
    static let ide = GridToolColumn(
        id: "ide",
        kind: .ide,
        name: "IDE",
        iconSymbol: "curlybraces"
    )
    static let browser = GridToolColumn(
        id: "browser",
        kind: .browser,
        name: "Browser",
        iconSymbol: "globe"
    )
    static let defaults = [terminal, ide, browser]

    var title: String { name }

    var suggestedLabels: [String] {
        switch kind {
        case .terminal:
            return ["dev", "git", "agent"]
        case .ide:
            return ["workspace"]
        case .browser:
            return ["local", "repo", "docs"]
        case .custom:
            return [name.lowercased()]
        }
    }

    func renaming(_ name: String) -> GridToolColumn {
        GridToolColumn(id: id, kind: kind, name: name, iconSymbol: iconSymbol)
    }

    func updatingIcon(_ iconSymbol: String) -> GridToolColumn {
        GridToolColumn(id: id, kind: kind, name: name, iconSymbol: iconSymbol)
    }

    static func custom(
        id: String = UUID().uuidString,
        name: String,
        iconSymbol: String = "square.stack.3d.up"
    ) -> GridToolColumn {
        GridToolColumn(id: id, kind: .custom, name: name, iconSymbol: iconSymbol)
    }
}

enum GridLayerColor: String, CaseIterable, Codable, Identifiable, Hashable {
    case ember
    case amber
    case moss
    case mint
    case cyan
    case cobalt
    case rose
    case slate

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

struct GridBinding: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let target: Target
    let archetypeHint: String?
    let createdAt: Date
    let updatedAt: Date
}

struct GridToolGroup: Codable, Hashable {
    let bindings: [GridBinding]
    let activeBindingID: String?

    init(bindings: [GridBinding] = [], activeBindingID: String? = nil) {
        self.bindings = bindings
        self.activeBindingID = activeBindingID
    }
}

struct GridStandaloneApp: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let iconSymbol: String
    let shortcut: HotkeyShortcut?
    let binding: GridBinding?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        iconSymbol: String = "app.fill",
        shortcut: HotkeyShortcut? = nil,
        binding: GridBinding? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.shortcut = shortcut
        self.binding = binding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func updatingName(_ name: String) -> GridStandaloneApp {
        GridStandaloneApp(
            id: id,
            name: name,
            iconSymbol: iconSymbol,
            shortcut: shortcut,
            binding: binding,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingIcon(_ iconSymbol: String) -> GridStandaloneApp {
        GridStandaloneApp(
            id: id,
            name: name,
            iconSymbol: iconSymbol,
            shortcut: shortcut,
            binding: binding,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingShortcut(_ shortcut: HotkeyShortcut?) -> GridStandaloneApp {
        GridStandaloneApp(
            id: id,
            name: name,
            iconSymbol: iconSymbol,
            shortcut: shortcut,
            binding: binding,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingBinding(_ binding: GridBinding?) -> GridStandaloneApp {
        GridStandaloneApp(
            id: id,
            name: name,
            iconSymbol: iconSymbol,
            shortcut: shortcut,
            binding: binding,
            createdAt: createdAt,
            updatedAt: .now
        )
    }
}

struct GridWorkspaceState: Codable, Hashable {
    let columns: [GridToolColumn]
    let layers: [GridLayer]
    let standaloneApps: [GridStandaloneApp]

    init(columns: [GridToolColumn] = GridToolColumn.defaults, layers: [GridLayer] = [], standaloneApps: [GridStandaloneApp] = []) {
        self.columns = columns
        self.layers = layers
        self.standaloneApps = standaloneApps
    }
}

struct GridLayer: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: GridLayerColor
    let groups: [String: GridToolGroup]
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        color: GridLayerColor,
        groups: [String: GridToolGroup] = GridToolColumn.defaults.reduce(into: [:]) { $0[$1.id] = GridToolGroup() },
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.groups = groups
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func group(for column: GridToolColumn) -> GridToolGroup {
        groups[column.id] ?? GridToolGroup()
    }

    func updatingGroup(_ group: GridToolGroup, for column: GridToolColumn) -> GridLayer {
        var groups = groups
        groups[column.id] = group
        return GridLayer(
            id: id,
            name: name,
            color: color,
            groups: groups,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingName(_ name: String) -> GridLayer {
        GridLayer(
            id: id,
            name: name,
            color: color,
            groups: groups,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingColor(_ color: GridLayerColor) -> GridLayer {
        GridLayer(
            id: id,
            name: name,
            color: color,
            groups: groups,
            createdAt: createdAt,
            updatedAt: .now
        )
    }
}

extension GridToolGroup {
    var activeBinding: GridBinding? {
        return bindings.first
    }

    func normalized() -> GridToolGroup {
        let normalizedBindings = Array(bindings.prefix(1))
        return GridToolGroup(
            bindings: normalizedBindings,
            activeBindingID: normalizedBindings.first?.id
        )
    }
}
