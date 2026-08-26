import Foundation

enum L10n {
    static func string(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        let format = localizationBundle.localizedString(forKey: key, value: fallback, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static var localizationBundle: Bundle {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }
        return .module
    }
}
