import SwiftUI

extension TheoToolColumn {
    var systemImage: String {
        switch self {
        case .terminal:
            return "terminal"
        case .ide:
            return "curlybraces"
        case .browser:
            return "globe"
        }
    }
}

extension TheoLayerColor {
    var swiftUIColor: Color {
        switch self {
        case .ember:
            return Color(red: 0.82, green: 0.36, blue: 0.25)
        case .amber:
            return Color(red: 0.84, green: 0.60, blue: 0.16)
        case .moss:
            return Color(red: 0.42, green: 0.59, blue: 0.28)
        case .mint:
            return Color(red: 0.25, green: 0.67, blue: 0.55)
        case .cyan:
            return Color(red: 0.20, green: 0.62, blue: 0.80)
        case .cobalt:
            return Color(red: 0.30, green: 0.46, blue: 0.83)
        case .rose:
            return Color(red: 0.78, green: 0.39, blue: 0.50)
        case .slate:
            return Color(red: 0.43, green: 0.47, blue: 0.57)
        }
    }
}

extension Target {
    var kindDescription: String {
        switch self {
        case .app:
            return "App target"
        case .window:
            return "Window target"
        }
    }
}
