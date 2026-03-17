import Foundation

enum TheoToolColumn: String, CaseIterable, Codable, Identifiable, Hashable {
    case terminal
    case ide
    case browser

    var id: Self { self }

    var title: String {
        switch self {
        case .terminal:
            return "Terminal"
        case .ide:
            return "IDE"
        case .browser:
            return "Browser"
        }
    }

    var supportsMultipleBindings: Bool {
        switch self {
        case .terminal, .browser:
            return true
        case .ide:
            return false
        }
    }

    var suggestedLabels: [String] {
        switch self {
        case .terminal:
            return ["dev", "git", "agent"]
        case .ide:
            return ["workspace"]
        case .browser:
            return ["local", "repo", "docs"]
        }
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
    let terminalGroup: TheoToolGroup
    let ideGroup: TheoToolGroup
    let browserGroup: TheoToolGroup
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        color: TheoLayerColor,
        terminalGroup: TheoToolGroup = TheoToolGroup(),
        ideGroup: TheoToolGroup = TheoToolGroup(),
        browserGroup: TheoToolGroup = TheoToolGroup(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.terminalGroup = terminalGroup
        self.ideGroup = ideGroup
        self.browserGroup = browserGroup
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func group(for column: TheoToolColumn) -> TheoToolGroup {
        switch column {
        case .terminal:
            return terminalGroup
        case .ide:
            return ideGroup
        case .browser:
            return browserGroup
        }
    }

    func updatingGroup(_ group: TheoToolGroup, for column: TheoToolColumn) -> TheoLayer {
        TheoLayer(
            id: id,
            name: name,
            color: color,
            terminalGroup: column == .terminal ? group : terminalGroup,
            ideGroup: column == .ide ? group : ideGroup,
            browserGroup: column == .browser ? group : browserGroup,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingName(_ name: String) -> TheoLayer {
        TheoLayer(
            id: id,
            name: name,
            color: color,
            terminalGroup: terminalGroup,
            ideGroup: ideGroup,
            browserGroup: browserGroup,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingColor(_ color: TheoLayerColor) -> TheoLayer {
        TheoLayer(
            id: id,
            name: name,
            color: color,
            terminalGroup: terminalGroup,
            ideGroup: ideGroup,
            browserGroup: browserGroup,
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
