import Foundation

enum TheoColumnKind: String, Codable, Hashable {
    case terminal
    case ide
    case browser
    case custom
}

struct TheoToolColumn: Codable, Identifiable, Hashable {
    let id: String
    let kind: TheoColumnKind
    let name: String
    let iconSymbol: String

    static let terminal = TheoToolColumn(
        id: "terminal",
        kind: .terminal,
        name: "Terminal",
        iconSymbol: "terminal"
    )
    static let ide = TheoToolColumn(
        id: "ide",
        kind: .ide,
        name: "IDE",
        iconSymbol: "curlybraces"
    )
    static let browser = TheoToolColumn(
        id: "browser",
        kind: .browser,
        name: "Browser",
        iconSymbol: "globe"
    )
    static let defaults = [terminal, ide, browser]

    var title: String { name }

    var supportsMultipleBindings: Bool {
        switch kind {
        case .terminal, .browser:
            return true
        case .ide, .custom:
            return false
        }
    }

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

    func renaming(_ name: String) -> TheoToolColumn {
        TheoToolColumn(id: id, kind: kind, name: name, iconSymbol: iconSymbol)
    }

    func updatingIcon(_ iconSymbol: String) -> TheoToolColumn {
        TheoToolColumn(id: id, kind: kind, name: name, iconSymbol: iconSymbol)
    }

    static func custom(
        id: String = UUID().uuidString,
        name: String,
        iconSymbol: String = "square.stack.3d.up"
    ) -> TheoToolColumn {
        TheoToolColumn(id: id, kind: .custom, name: name, iconSymbol: iconSymbol)
    }
}

enum TheoLayerColor: String, CaseIterable, Codable, Identifiable, Hashable {
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

struct TheoBinding: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let target: Target
    let archetypeHint: String?
    let createdAt: Date
    let updatedAt: Date
}

struct TheoToolGroup: Codable, Hashable {
    let bindings: [TheoBinding]
    let activeBindingID: String?

    init(bindings: [TheoBinding] = [], activeBindingID: String? = nil) {
        self.bindings = bindings
        self.activeBindingID = activeBindingID
    }
}

struct TheoLayer: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: TheoLayerColor
    let columns: [TheoToolColumn]
    let groups: [String: TheoToolGroup]
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        color: TheoLayerColor,
        columns: [TheoToolColumn] = TheoToolColumn.defaults,
        groups: [String: TheoToolGroup] = TheoToolColumn.defaults.reduce(into: [:]) { $0[$1.id] = TheoToolGroup() },
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.columns = columns
        self.groups = groups
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func group(for column: TheoToolColumn) -> TheoToolGroup {
        groups[column.id] ?? TheoToolGroup()
    }

    func column(id: String) -> TheoToolColumn? {
        columns.first(where: { $0.id == id })
    }

    func defaultColumn(kind: TheoColumnKind) -> TheoToolColumn? {
        columns.first(where: { $0.kind == kind })
    }

    func updatingGroup(_ group: TheoToolGroup, for column: TheoToolColumn) -> TheoLayer {
        var groups = groups
        groups[column.id] = group
        return TheoLayer(
            id: id,
            name: name,
            color: color,
            columns: columns,
            groups: groups,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingName(_ name: String) -> TheoLayer {
        TheoLayer(
            id: id,
            name: name,
            color: color,
            columns: columns,
            groups: groups,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingColor(_ color: TheoLayerColor) -> TheoLayer {
        TheoLayer(
            id: id,
            name: name,
            color: color,
            columns: columns,
            groups: groups,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingColumns(_ columns: [TheoToolColumn]) -> TheoLayer {
        TheoLayer(
            id: id,
            name: name,
            color: color,
            columns: columns,
            groups: groups,
            createdAt: createdAt,
            updatedAt: .now
        )
    }
}

extension TheoToolGroup {
    var activeBinding: TheoBinding? {
        if let activeBindingID,
           let binding = bindings.first(where: { $0.id == activeBindingID }) {
            return binding
        }

        return bindings.first
    }

    func normalized() -> TheoToolGroup {
        let normalizedActiveID: String?

        if let activeBindingID,
           bindings.contains(where: { $0.id == activeBindingID }) {
            normalizedActiveID = activeBindingID
        } else {
            normalizedActiveID = bindings.first?.id
        }

        return TheoToolGroup(bindings: bindings, activeBindingID: normalizedActiveID)
    }
}
