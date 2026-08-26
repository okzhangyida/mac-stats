import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    static func apply(_ rawValue: String) {
        let appearance = AppAppearance(rawValue: rawValue) ?? .system
        NSApplication.shared.appearance = appearance.nsAppearance
    }
}
