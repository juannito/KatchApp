import SwiftUI

/// Light / dark / system, persisted. The header sun/moon toggles between light and dark.
@MainActor
final class AppTheme: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return L("System")
            case .light: return L("Light")
            case .dark: return L("Dark")
            }
        }
    }

    @Published var mode: Mode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "theme") } }

    init() {
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system
    }

    var colorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func isDark(systemScheme: ColorScheme) -> Bool {
        colorScheme.map { $0 == .dark } ?? (systemScheme == .dark)
    }

    func toggle(systemScheme: ColorScheme) {
        mode = isDark(systemScheme: systemScheme) ? .light : .dark
    }
}

struct ThemeToggleButton: View {
    @EnvironmentObject var theme: AppTheme
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let dark = theme.isDark(systemScheme: systemScheme)
        Button { theme.toggle(systemScheme: systemScheme) } label: {
            Image(systemName: dark ? "sun.max" : "moon")
        }
        .help(dark ? L("Switch to light mode") : L("Switch to dark mode"))
    }
}
