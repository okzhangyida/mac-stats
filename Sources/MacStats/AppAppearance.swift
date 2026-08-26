import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.string("appearance.system", fallback: "System")
        case .light: L10n.string("appearance.light", fallback: "Light")
        case .dark: L10n.string("appearance.dark", fallback: "Dark")
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
