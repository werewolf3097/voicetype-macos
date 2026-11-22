import SwiftUI

// MARK: - Depth Ladder (4 Levels, top-left light source)

enum PaperDepthLevel {
    case l1Inset     // Вдавлено: поля ввода, выбранный пункт сайдбара, блок расшифровки
    case l2OnPaper   // На бумаге: обычные кнопки, клавиша хоткея
    case l3Elevated  // Приподнято: главное действие, тёмные капсулы
    case l4Floating  // Парит: индикатор записи, меню и поповеры
}

private struct PaperSurfaceModifier: ViewModifier {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperDepth) private var depth
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let level: PaperDepthLevel
    let cornerRadius: CGFloat
    let isPressed: Bool

    private var effectiveLevel: PaperDepthLevel {
        isPressed ? .l1Inset : level
    }

    private var scaledDepth: Double {
        min(1, max(0, depth))
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                switch effectiveLevel {
                case .l1Inset:
                    shape
                        .fill(theme.insetColor)
                        .overlay(
                            // Inner top-left shadow + subtle bottom highlight
                            shape
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            theme.shadowRGB.color.opacity(theme.isDark ? 0.55 : 0.16 * (0.4 + 0.6 * scaledDepth)),
                                            Color.clear,
                                            theme.subtleHighlightColor.opacity(0.6)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [
                                    theme.shadowRGB.color.opacity(theme.isDark ? 0.28 : 0.08 * scaledDepth),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 5)
                            .clipShape(shape)
                        }

                case .l2OnPaper:
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    theme.surfaceColor,
                                    theme.surfaceColor.opacity(theme.isDark ? 0.92 : 0.86)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            shape.strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
                        )
                        .overlay(alignment: .top) {
                            shape
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [theme.subtleHighlightColor, Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    ),
                                    lineWidth: PaperTokens.hairline
                                )
                        }
                        .shadow(
                            color: theme.shadowRGB.color.opacity((theme.isDark ? 0.34 : 0.11) * scaledDepth),
                            radius: 2.5 * scaledDepth + 0.5,
                            x: 0.6 * scaledDepth,
                            y: 1.5 * scaledDepth
                        )

                case .l3Elevated:
                    shape
                        .fill(theme.surfaceColor)
                        .overlay(
                            shape.strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
                        )
                        .shadow(
                            color: theme.shadowRGB.color.opacity((theme.isDark ? 0.45 : 0.16) * scaledDepth),
                            radius: 6 * scaledDepth + 1,
                            x: 1.2 * scaledDepth,
                            y: 3 * scaledDepth
                        )

                case .l4Floating:
                    let fillOpacity: Double = reduceTransparency ? 1.0 : 0.96
                    shape
                        .fill(theme.surfaceColor.opacity(fillOpacity))
                        .overlay(
                            shape.strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
                        )
                        .shadow(
                            color: theme.shadowRGB.color.opacity((theme.isDark ? 0.55 : 0.22) * (0.4 + 0.6 * scaledDepth)),
                            radius: 14 * (0.4 + 0.6 * scaledDepth),
                            x: 1.5 * scaledDepth,
                            y: 6 * (0.4 + 0.6 * scaledDepth)
                        )
                }
            }
            .offset(y: isPressed ? 1 : 0)
    }
}

extension View {
    func paperSurface(
        level: PaperDepthLevel,
        cornerRadius: CGFloat = PaperTokens.controlRadius,
        isPressed: Bool = false
    ) -> some View {
        modifier(PaperSurfaceModifier(level: level, cornerRadius: cornerRadius, isPressed: isPressed))
    }
}

// MARK: - Paper Background

struct PaperBackground: View {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperGrainIntensity) private var grainIntensity

    @State private var tileImage: NSImage?
    @State private var loadedTextureID: String?

    var body: some View {
        ZStack {
            theme.baseColor

            if let procedural = theme.texture as? ProceduralPaperTexture,
               let tileImage,
               loadedTextureID == procedural.id,
               grainIntensity > 0.01 {
                Image(nsImage: tileImage)
                    .resizable(resizingMode: .tile)
                    .opacity(procedural.baseOpacity * min(1, max(0, grainIntensity)))
                    .blendMode(procedural.blendMode)
                    .allowsHitTesting(false)
            }

            if theme.id == PaperTheme.parchment.id {
                RadialGradient(
                    colors: [
                        Color.clear,
                        theme.shadowRGB.color.opacity(0.10 * min(1, max(0, grainIntensity)))
                    ],
                    center: .center,
                    startRadius: 120,
                    endRadius: 640
                )
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .task(id: theme.id) {
            guard let procedural = theme.texture as? ProceduralPaperTexture else {
                tileImage = nil
                loadedTextureID = nil
                return
            }
            if let sync = await PaperTextureCache.shared.cachedTileSync(for: procedural.id) {
                tileImage = sync
                loadedTextureID = procedural.id
                return
            }
            let generated = await PaperTextureCache.shared.tile(for: procedural)
            if !Task.isCancelled {
                tileImage = generated
                loadedTextureID = procedural.id
            }
        }
    }
}

// MARK: - Section Tile Icon

struct PaperSectionTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 28
    var iconSize: CGFloat = 13

    var body: some View {
        RoundedRectangle(cornerRadius: size <= 24 ? PaperTokens.chipRadius : PaperTokens.controlRadius, style: .continuous)
            .fill(tint.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: size <= 24 ? PaperTokens.chipRadius : PaperTokens.controlRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: PaperTokens.hairline)
            )
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Page Header

struct PaperPageHeader<Trailing: View>: View {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperFontPreset) private var fontPreset

    let title: String
    let subtitle: String?
    let systemImage: String
    let tileTint: Color
    let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        tileTint: Color,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tileTint = tileTint
        self.trailing = trailing()
    }

    var body: some View {
        let fonts = PaperFonts(preset: fontPreset)
        HStack(alignment: .center, spacing: 14) {
            PaperSectionTile(systemImage: systemImage, tint: tileTint, size: 36, iconSize: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(fonts.pageTitle)
                    .tracking(-0.3)
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(fonts.caption)
                        .foregroundStyle(theme.secondaryInkColor)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
    }
}

// MARK: - Paper Button Style

enum PaperButtonRole {
    case primary     // Dark ink capsule/button, L3 elevated
    case secondary   // Paper L2 button
    case destructive // Red destructive button
}

struct PaperButtonStyle: ButtonStyle {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperDepth) private var depth
    @Environment(\.paperFontPreset) private var fontPreset
    @Environment(\.isEnabled) private var isEnabled

    var role: PaperButtonRole = .secondary
    var compact: Bool = false
    var isCapsule: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let fonts = PaperFonts(preset: fontPreset)
        let cornerRadius: CGFloat = isCapsule ? 999 : PaperTokens.controlRadius
        let scaledDepth = min(1, max(0, depth))

        configuration.label
            .font(compact ? fonts.captionMedium : fonts.uiMedium)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .background {
                backgroundShape(cornerRadius: cornerRadius, pressed: configuration.isPressed, depth: scaledDepth)
            }
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch role {
        case .primary:
            return theme.primaryButtonForeground
        case .secondary:
            return theme.inkColor
        case .destructive:
            return theme.errorColor
        }
    }

    @ViewBuilder
    private func backgroundShape(cornerRadius: CGFloat, pressed: Bool, depth: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch role {
        case .primary:
            shape
                .fill(pressed ? theme.primaryButtonBackground.opacity(0.88) : theme.primaryButtonBackground)
                .overlay(
                    shape.strokeBorder(
                        theme.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.2),
                        lineWidth: PaperTokens.hairline
                    )
                )
                .shadow(
                    color: theme.shadowRGB.color.opacity((pressed ? 0.08 : (theme.isDark ? 0.45 : 0.22)) * depth),
                    radius: pressed ? 1 : (5 * depth + 1),
                    x: pressed ? 0 : 1 * depth,
                    y: pressed ? 0.5 : 2.5 * depth
                )
        case .secondary, .destructive:
            shape
                .fill(pressed ? theme.insetColor : theme.surfaceColor)
                .overlay(
                    shape.strokeBorder(
                        role == .destructive ? theme.errorColor.opacity(0.35) : theme.borderColor,
                        lineWidth: PaperTokens.hairline
                    )
                )
                .shadow(
                    color: theme.shadowRGB.color.opacity((pressed ? 0.0 : (theme.isDark ? 0.3 : 0.10)) * depth),
                    radius: pressed ? 0 : 2.5 * depth,
                    x: pressed ? 0 : 0.5 * depth,
                    y: pressed ? 0 : 1.5 * depth
                )
        }
    }
}

// MARK: - Paper Inset Field (L1)

struct PaperInsetField<Content: View>: View {
    var cornerRadius: CGFloat = PaperTokens.controlRadius
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 7
    let content: Content

    init(
        cornerRadius: CGFloat = PaperTokens.controlRadius,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 7,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .paperSurface(level: .l1Inset, cornerRadius: cornerRadius)
    }
}

// MARK: - Paper Toggle Style

struct PaperToggleStyle: ToggleStyle {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperDepth) private var depth
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        let scaledDepth = min(1, max(0, depth))

        HStack(spacing: 8) {
            configuration.label

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(isOn ? theme.inkColor : theme.insetColor)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
                        )
                        .frame(width: 36, height: 20)

                    Circle()
                        .fill(isOn ? theme.baseColor : theme.surfaceColor)
                        .overlay(
                            Circle()
                                .strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
                        )
                        .shadow(
                            color: theme.shadowRGB.color.opacity(0.22 * scaledDepth),
                            radius: 1.5 * scaledDepth + 0.5,
                            x: 0.4 * scaledDepth,
                            y: 1 * scaledDepth
                        )
                        .frame(width: 16, height: 16)
                        .padding(2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "Включено" : "Выключено")
        }
    }
}

// MARK: - Paper Segmented Control

struct PaperSegmentedControl<SelectionValue: Hashable>: View {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperDepth) private var depth
    @Environment(\.paperFontPreset) private var fontPreset

    struct Option: Identifiable {
        let id: SelectionValue
        let title: String
    }

    let options: [Option]
    @Binding var selection: SelectionValue
    var compact: Bool = false

    init(
        options: [Option],
        selection: Binding<SelectionValue>,
        compact: Bool = false
    ) {
        self.options = options
        self._selection = selection
        self.compact = compact
    }

    var body: some View {
        let fonts = PaperFonts(preset: fontPreset)
        let scaledDepth = min(1, max(0, depth))

        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.id == selection
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        selection = option.id
                    }
                } label: {
                    Text(option.title)
                        .font(compact ? fonts.captionMedium : fonts.uiMedium)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? theme.primaryButtonForeground : theme.secondaryInkColor)
                        .padding(.horizontal, compact ? 9 : 11)
                        .padding(.vertical, compact ? 4 : 5)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(theme.primaryButtonBackground)
                                    .shadow(
                                        color: theme.shadowRGB.color.opacity(0.20 * scaledDepth),
                                        radius: 2 * scaledDepth + 0.5,
                                        y: 1 * scaledDepth
                                    )
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .paperSurface(level: .l1Inset, cornerRadius: 999)
    }
}

// MARK: - Setting Group & Setting Row (flat content, volume only on controls)

struct PaperSettingGroup<Content: View>: View {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperFontPreset) private var fontPreset

    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let fonts = PaperFonts(preset: fontPreset)
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(fonts.captionMedium)
                .foregroundStyle(theme.secondaryInkColor)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(theme.surfaceColor.opacity(0.55), in: RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                    .strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
            )
        }
    }
}

struct PaperSettingRow<Control: View>: View {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperFontPreset) private var fontPreset

    let title: String
    let caption: String?
    let systemImage: String?
    let tileTint: Color
    let control: Control

    init(
        _ title: String,
        caption: String? = nil,
        systemImage: String? = nil,
        tileTint: Color = PaperTokens.settingsSlate,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.caption = caption
        self.systemImage = systemImage
        self.tileTint = tileTint
        self.control = control()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                labelColumn
                    .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                control
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 10) {
                labelColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                control
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var labelColumn: some View {
        let fonts = PaperFonts(preset: fontPreset)
        return HStack(alignment: .top, spacing: 11) {
            if let systemImage {
                PaperSectionTile(systemImage: systemImage, tint: tileTint, size: 26, iconSize: 12)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(fonts.uiMedium)
                    .foregroundStyle(theme.inkColor)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(fonts.caption)
                        .foregroundStyle(theme.secondaryInkColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Paper Environment Applier

private struct PaperEnvironmentModifier: ViewModifier {
    @ObservedObject var settings: SettingsStore
    @Environment(\.colorScheme) private var systemColorScheme

    func body(content: Content) -> some View {
        let prefersDark: Bool = {
            switch settings.appearance {
            case .dark: return true
            case .light: return false
            case .system: return systemColorScheme == .dark
            }
        }()
        let resolved = PaperTheme.resolved(
            themeID: settings.paperThemeID,
            prefersDark: prefersDark
        )
        content
            .environment(\.paperTheme, resolved)
            .environment(\.paperDepth, settings.paperDepth)
            .environment(\.paperGrainIntensity, settings.paperGrainIntensity)
            .environment(\.paperFontPreset, settings.fontPreset)
    }
}

extension View {
    func applyPaperEnvironment(_ settings: SettingsStore) -> some View {
        modifier(PaperEnvironmentModifier(settings: settings))
    }
}
