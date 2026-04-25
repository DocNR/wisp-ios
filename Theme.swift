import SwiftUI

struct ThemePalette: Equatable {
    let primary: Color
    let secondary: Color
    let background: Color
    let surface: Color
    let surfaceVariant: Color
    let onBackground: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let outline: Color
    let zap: Color
    let repost: Color
    let bookmark: Color
    let paid: Color
}

struct ThemePreset: Identifiable, Equatable {
    let id: String
    let displayName: String
    let dark: ThemePalette
    let light: ThemePalette
}

struct ResolvedTheme: Equatable {
    let presetId: String
    let isDark: Bool
    let palette: ThemePalette
    let primary: Color

    static let `default` = ResolvedTheme(
        presetId: "custom",
        isDark: true,
        palette: Themes.get("custom").dark,
        primary: Color.hex(0xFFFF9800)
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: ResolvedTheme = .default
}

extension EnvironmentValues {
    var theme: ResolvedTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

@MainActor
extension AppSettings {
    func resolveTheme(systemColorScheme: ColorScheme?) -> ResolvedTheme {
        let preset = Themes.get(themeName)
        let useDark: Bool
        switch colorScheme {
        case .system:
            useDark = (systemColorScheme ?? .dark) == .dark
        case .light:
            useDark = false
        case .dark:
            useDark = true
        }
        let palette = useDark ? preset.dark : preset.light
        let primary: Color
        if preset.id == "custom" {
            primary = Color(argb: accentColorARGB)
        } else {
            primary = palette.primary
        }
        return ResolvedTheme(
            presetId: preset.id,
            isDark: useDark,
            palette: palette,
            primary: primary
        )
    }
}
