import AppKit
import SwiftUI

// MARK: - Font Presets

enum FontPreset: String, CaseIterable, Identifiable, Codable {
    case paperNewYork = "Бумага (New York + SF)"
    case editorialCormorant = "Редакционный (Cormorant + Inter)"
    case systemSF = "Системный (SF)"

    var id: String { rawValue }
}

struct PaperFonts {
    let preset: FontPreset

    init(preset: FontPreset = .paperNewYork) {
        self.preset = preset
    }

    var pageTitle: Font {
        switch preset {
        case .paperNewYork:
            return .system(size: 30, weight: .regular, design: .serif)
        case .editorialCormorant:
            return .custom("CormorantGaramond-Medium", size: 30)
        case .systemSF:
            return .system(size: 28, weight: .medium, design: .default)
        }
    }

    var heroTitle: Font {
        switch preset {
        case .paperNewYork:
            return .system(size: 30, weight: .regular, design: .serif)
        case .editorialCormorant:
            return .custom("CormorantGaramond-Medium", size: 32)
        case .systemSF:
            return .system(size: 28, weight: .medium, design: .default)
        }
    }

    var panelTitle: Font {
        switch preset {
        case .paperNewYork:
            return .system(size: 16, weight: .medium)
        case .editorialCormorant:
            return .custom("CormorantGaramond-Medium", size: 21)
        case .systemSF:
            return .system(size: 16, weight: .medium)
        }
    }

    var sectionTitle: Font {
        switch preset {
        case .paperNewYork, .systemSF:
            return .system(size: 13, weight: .medium)
        case .editorialCormorant:
            return .custom("Inter-Regular_Medium", size: 13)
        }
    }

    var body: Font {
        switch preset {
        case .paperNewYork, .systemSF:
            return .system(size: 13, weight: .regular)
        case .editorialCormorant:
            return .custom("Inter-Regular", size: 12.5)
        }
    }

    var bodyMedium: Font {
        switch preset {
        case .paperNewYork, .systemSF:
            return .system(size: 13, weight: .medium)
        case .editorialCormorant:
            return .custom("Inter-Regular_Medium", size: 12.5)
        }
    }

    var ui: Font {
        switch preset {
        case .paperNewYork, .systemSF:
            return .system(size: 13, weight: .regular)
        case .editorialCormorant:
            return .custom("Inter-Regular", size: 12)
        }
    }

    var uiMedium: Font {
        switch preset {
        case .paperNewYork, .systemSF:
            return .system(size: 13, weight: .medium)
        case .editorialCormorant:
            return .custom("Inter-Regular_Medium", size: 12)
        }
    }

    var caption: Font {
        switch preset {
        case .paperNewYork, .systemSF:
            return .system(size: 12, weight: .regular)
        case .editorialCormorant:
            return .custom("Inter-Regular", size: 11.5)
        }
    }

    var captionMedium: Font {
        switch preset {
        case .paperNewYork, .systemSF:
            return .system(size: 12, weight: .medium)
        case .editorialCormorant:
            return .custom("Inter-Regular_Medium", size: 11.5)
        }
    }

    var micro: Font {
        switch preset {
        case .paperNewYork, .systemSF:
            return .system(size: 11, weight: .regular)
        case .editorialCormorant:
            return .custom("Inter-Regular", size: 10.5)
        }
    }

    var statNumber: Font {
        switch preset {
        case .paperNewYork:
            return .system(size: 24, weight: .medium)
        case .editorialCormorant:
            return .custom("CormorantGaramond-Regular", size: 26)
        case .systemSF:
            return .system(size: 24, weight: .medium)
        }
    }
}

// MARK: - Design Tokens

enum PaperTokens {
    static let chipRadius: CGFloat = 6
    static let controlRadius: CGFloat = 8
    static let cardRadius: CGFloat = 12
    static let grid: CGFloat = 4
    static let contentPadding: CGFloat = 34
    static let hairline: CGFloat = 0.5

    // Section tile accents (section 4.1)
    static let dictationBlue = Color(red: 0.204, green: 0.471, blue: 0.965)   // #3478F6
    static let historyGreen = Color(red: 0.204, green: 0.659, blue: 0.325)    // #34A853
    static let dictionaryTeal = Color(red: 0.184, green: 0.620, blue: 0.620)  // #2F9E9E
    static let meetingsIndigo = Color(red: 0.369, green: 0.424, blue: 0.788)  // #5E6CC9
    static let settingsSlate = Color(red: 0.420, green: 0.412, blue: 0.373)   // #6B695F

    // Recording accent (the only bright functional accent)
    static let recordingRed = Color(red: 0.847, green: 0.275, blue: 0.243)    // #D8463E
}

// MARK: - Pro Entitlement

protocol ProEntitlement {
    var isPro: Bool { get }
}

final class LocalProEntitlement: ObservableObject, ProEntitlement {
    @Published var debugOverridePro: Bool {
        didSet {
            UserDefaults.standard.set(debugOverridePro, forKey: Self.debugKey)
        }
    }

    private static let debugKey = "debugOverrideProEntitlement"

    var isPro: Bool {
        #if DEBUG
        return debugOverridePro
        #else
        return false
        #endif
    }

    init() {
        #if DEBUG
        self.debugOverridePro = UserDefaults.standard.bool(forKey: Self.debugKey)
        #else
        self.debugOverridePro = false
        #endif
    }
}

// MARK: - Paper Texture Protocol

protocol PaperTexture: Sendable {
    var id: String { get }
    var isDarkSurface: Bool { get }
}

// MARK: - Paper RGB & Contrast

struct PaperRGB: Equatable, Hashable, Sendable {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.r = Double((hex >> 16) & 0xFF) / 255.0
        self.g = Double((hex >> 8) & 0xFF) / 255.0
        self.b = Double(hex & 0xFF) / 255.0
    }

    var color: Color {
        Color(red: r, green: g, blue: b)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    func blended(with other: PaperRGB, fraction: Double) -> PaperRGB {
        let t = min(1, max(0, fraction))
        return PaperRGB(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t
        )
    }

    /// Relative luminance per WCAG 2.1.
    var relativeLuminance: Double {
        func linearize(_ channel: Double) -> Double {
            channel <= 0.03928 ? (channel / 12.92) : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    func contrastRatio(with other: PaperRGB) -> Double {
        let l1 = max(relativeLuminance, other.relativeLuminance)
        let l2 = min(relativeLuminance, other.relativeLuminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

// MARK: - Paper Theme

struct PaperTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let isPro: Bool
    let base: PaperRGB
    let ink: PaperRGB
    let ink2: PaperRGB
    let shadowRGB: PaperRGB
    let isDark: Bool
    let texture: (any PaperTexture)?

    static func == (lhs: PaperTheme, rhs: PaperTheme) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.isPro == rhs.isPro
            && lhs.base == rhs.base
            && lhs.ink == rhs.ink
            && lhs.ink2 == rhs.ink2
            && lhs.shadowRGB == rhs.shadowRGB
            && lhs.isDark == rhs.isDark
            && lhs.texture?.id == rhs.texture?.id
    }

    // Derived surface tones
    var baseColor: Color { base.color }
    var inkColor: Color { ink.color }
    var secondaryInkColor: Color { ink2.color }

    var tertiaryInkColor: Color {
        ink2.color.opacity(0.68)
    }

    /// Sidebar is ~7% warm shadow over paper base (per section 4.1).
    var sidebarColor: Color {
        if isDark {
            return base.blended(with: shadowRGB, fraction: 0.16).color
        }
        return base.blended(with: shadowRGB, fraction: 0.07).color
    }

    /// Elevated control surface (L2/L3).
    var surfaceColor: Color {
        if isDark {
            return base.blended(with: PaperRGB(hex: 0xFFFFFF), fraction: 0.06).color
        }
        return base.blended(with: PaperRGB(hex: 0xFFFFFF), fraction: 0.58).color
    }

    /// Recessed surface (L1).
    var insetColor: Color {
        if isDark {
            return base.blended(with: PaperRGB(hex: 0x000000), fraction: 0.22).color
        }
        return base.blended(with: shadowRGB, fraction: 0.08).color
    }

    var hoverColor: Color {
        isDark ? Color.white.opacity(0.09) : shadowRGB.color.opacity(0.08)
    }

    var selectedSidebarColor: Color {
        isDark ? Color.white.opacity(0.12) : shadowRGB.color.opacity(0.11)
    }

    var borderColor: Color {
        isDark ? Color.white.opacity(0.13) : shadowRGB.color.opacity(0.16)
    }

    var subtleHighlightColor: Color {
        isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.75)
    }

    var primaryButtonBackground: Color {
        ink.color
    }

    var primaryButtonForeground: Color {
        base.color
    }

    // Semantic statuses (high contrast on paper)
    var successColor: Color {
        isDark ? Color(red: 0.45, green: 0.78, blue: 0.52) : Color(red: 0.16, green: 0.51, blue: 0.26)
    }

    var clipboardWarningColor: Color {
        isDark ? Color(red: 0.90, green: 0.72, blue: 0.30) : Color(red: 0.62, green: 0.42, blue: 0.06)
    }

    var errorColor: Color {
        isDark ? Color(red: 0.92, green: 0.42, blue: 0.39) : Color(red: 0.74, green: 0.22, blue: 0.19)
    }

    // MARK: - Paper Themes (section 4.3)

    static let cleanSheet = PaperTheme(
        id: "clean_sheet",
        name: "Чистый лист",
        isPro: false,
        base: PaperRGB(hex: 0xF7F6F1),
        ink: PaperRGB(hex: 0x2A2925),
        ink2: PaperRGB(hex: 0x6B695F),
        shadowRGB: PaperRGB(hex: 0x3D3528),
        isDark: false,
        texture: nil
    )

    static let cotton = PaperTheme(
        id: "cotton",
        name: "Хлопок",
        isPro: false,
        base: PaperRGB(hex: 0xF3F4F1),
        ink: PaperRGB(hex: 0x262824),
        ink2: PaperRGB(hex: 0x61635C),
        shadowRGB: PaperRGB(hex: 0x363831),
        isDark: false,
        texture: ProceduralPaperTexture(id: "cotton", kind: .cotton, isDarkSurface: false)
    )

    static let washi = PaperTheme(
        id: "washi",
        name: "Васи",
        isPro: true,
        base: PaperRGB(hex: 0xF0EADB),
        ink: PaperRGB(hex: 0x2B2720),
        ink2: PaperRGB(hex: 0x625B4E),
        shadowRGB: PaperRGB(hex: 0x423828),
        isDark: false,
        texture: ProceduralPaperTexture(id: "washi", kind: .washi, isDarkSurface: false)
    )

    static let kraft = PaperTheme(
        id: "kraft",
        name: "Крафт",
        isPro: true,
        base: PaperRGB(hex: 0xCDAA7F),
        ink: PaperRGB(hex: 0x2B1F14),
        ink2: PaperRGB(hex: 0x4A3825),
        shadowRGB: PaperRGB(hex: 0x2D1E10),
        isDark: false,
        texture: ProceduralPaperTexture(id: "kraft", kind: .kraft, isDarkSurface: false)
    )

    static let parchment = PaperTheme(
        id: "parchment",
        name: "Пергамент",
        isPro: true,
        base: PaperRGB(hex: 0xECDDB5),
        ink: PaperRGB(hex: 0x2C2416),
        ink2: PaperRGB(hex: 0x5D5038),
        shadowRGB: PaperRGB(hex: 0x3F3019),
        isDark: false,
        texture: ProceduralPaperTexture(id: "parchment", kind: .parchment, isDarkSurface: false)
    )

    static let linen = PaperTheme(
        id: "linen",
        name: "Лён",
        isPro: true,
        base: PaperRGB(hex: 0xEAE4D6),
        ink: PaperRGB(hex: 0x292620),
        ink2: PaperRGB(hex: 0x5E584B),
        shadowRGB: PaperRGB(hex: 0x3A3428),
        isDark: false,
        texture: ProceduralPaperTexture(id: "linen", kind: .linen, isDarkSurface: false)
    )

    static let watercolor = PaperTheme(
        id: "watercolor",
        name: "Акварельная",
        isPro: true,
        base: PaperRGB(hex: 0xF5F2EA),
        ink: PaperRGB(hex: 0x282621),
        ink2: PaperRGB(hex: 0x635F55),
        shadowRGB: PaperRGB(hex: 0x3D372B),
        isDark: false,
        texture: ProceduralPaperTexture(id: "watercolor", kind: .watercolor, isDarkSurface: false)
    )

    static let dotted = PaperTheme(
        id: "dotted",
        name: "Точечная",
        isPro: true,
        base: PaperRGB(hex: 0xF4F1E7),
        ink: PaperRGB(hex: 0x292722),
        ink2: PaperRGB(hex: 0x625F54),
        shadowRGB: PaperRGB(hex: 0x3B372B),
        isDark: false,
        texture: ProceduralPaperTexture(id: "dotted", kind: .dotted, isDarkSurface: false)
    )

    static let graphite = PaperTheme(
        id: "graphite",
        name: "Графит",
        isPro: true,
        base: PaperRGB(hex: 0x2A2927),
        ink: PaperRGB(hex: 0xECE7DB),
        ink2: PaperRGB(hex: 0xB3ADA0),
        shadowRGB: PaperRGB(hex: 0x000000),
        isDark: true,
        texture: ProceduralPaperTexture(id: "graphite", kind: .graphite, isDarkSurface: true)
    )

    static let allThemes: [PaperTheme] = [
        .cleanSheet, .cotton, .washi, .kraft, .parchment, .linen, .watercolor, .dotted, .graphite
    ]

    static func theme(withID id: String) -> PaperTheme {
        allThemes.first { $0.id == id } ?? .cleanSheet
    }

    static func resolved(
        themeID: String,
        prefersDark: Bool
    ) -> PaperTheme {
        let baseTheme = theme(withID: themeID)
        if prefersDark {
            return baseTheme.isDark ? baseTheme : .graphite
        }
        return baseTheme.isDark ? .cleanSheet : baseTheme
    }
}

// MARK: - Environment Keys

private struct PaperThemeKey: EnvironmentKey {
    static let defaultValue: PaperTheme = .cleanSheet
}

private struct PaperDepthKey: EnvironmentKey {
    static let defaultValue: Double = 0.6
}

private struct PaperGrainIntensityKey: EnvironmentKey {
    static let defaultValue: Double = 0.8
}

private struct PaperFontPresetKey: EnvironmentKey {
    static let defaultValue: FontPreset = .paperNewYork
}

private struct ProEntitlementKey: EnvironmentKey {
    static let defaultValue: any ProEntitlement = LocalProEntitlement()
}

extension EnvironmentValues {
    var paperTheme: PaperTheme {
        get { self[PaperThemeKey.self] }
        set { self[PaperThemeKey.self] = newValue }
    }

    var paperDepth: Double {
        get { self[PaperDepthKey.self] }
        set { self[PaperDepthKey.self] = newValue }
    }

    var paperGrainIntensity: Double {
        get { self[PaperGrainIntensityKey.self] }
        set { self[PaperGrainIntensityKey.self] = newValue }
    }

    var paperFontPreset: FontPreset {
        get { self[PaperFontPresetKey.self] }
        set { self[PaperFontPresetKey.self] = newValue }
    }

    var proEntitlement: any ProEntitlement {
        get { self[ProEntitlementKey.self] }
        set { self[ProEntitlementKey.self] = newValue }
    }
}
