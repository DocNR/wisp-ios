import SwiftUI

@MainActor
enum AppFont {
    private static var large: Bool { AppSettings.shared.largeText }

    static var titleLarge: Font {
        .system(size: large ? 22 : 20, weight: .bold)
    }
    static var titleMedium: Font {
        .system(size: large ? 18 : 16, weight: .semibold)
    }
    static var bodyLarge: Font {
        .system(size: large ? 17 : 15)
    }
    static var bodyMedium: Font {
        .system(size: large ? 16 : 14)
    }
    static var bodySmall: Font {
        .system(size: large ? 14 : 12)
    }
    static var labelSmall: Font {
        .system(size: large ? 13 : 11)
    }

    /// Scale an arbitrary point size by the same +2 (or 0) offset used for semantic tokens.
    static func scaled(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: large ? size + 2 : size, weight: weight)
    }
}

@MainActor
struct ScaledFontModifier: ViewModifier {
    let baseSize: CGFloat
    let weight: Font.Weight
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        let size = settings.largeText ? baseSize + 2 : baseSize
        return content.font(.system(size: size, weight: weight))
    }
}

extension View {
    /// Apply a font that scales with the global Large Text setting.
    @MainActor
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFontModifier(baseSize: size, weight: weight))
    }
}
