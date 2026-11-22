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
                            shape.strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
                        )

                case .l2OnPaper:
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    theme.surfaceColor,
                                    theme.surfaceColor.opacity(theme.isDark ? 0.92 : 0.88)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: max(0, cornerRadius - 1), style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            theme.subtleHighlightColor.opacity(theme.isDark ? 0.55 : 0.45),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    ),
                                    lineWidth: 0.75
                                )
                                .padding(1)
                        )
                        .overlay(
                            shape.strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
                        )
                        .shadow(
                            color: theme.shadowRGB.color.opacity((theme.isDark ? 0.34 : 0.10) * scaledDepth),
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
    @Environment(\.paperTheme) private var theme

    let systemImage: String
    let tint: Color
    var size: CGFloat = 28
    var iconSize: CGFloat = 13

    private var resolvedForeground: Color {
        guard theme.isDark else { return tint }
        if tint == PaperTokens.settingsSlate {
            return Color(red: 0.82, green: 0.80, blue: 0.74)
        }
        if tint == PaperTokens.dictationBlue {
            return Color(red: 0.45, green: 0.67, blue: 1.0)
        }
        if tint == PaperTokens.historyGreen {
            return Color(red: 0.42, green: 0.84, blue: 0.52)
        }
        if tint == PaperTokens.dictionaryTeal {
            return Color(red: 0.38, green: 0.82, blue: 0.82)
        }
        if tint == PaperTokens.meetingsIndigo {
            return Color(red: 0.59, green: 0.66, blue: 0.96)
        }
        return tint
    }

    private var resolvedFill: Color {
        theme.isDark ? resolvedForeground.opacity(0.18) : tint.opacity(0.14)
    }

    private var resolvedBorder: Color {
        theme.isDark ? resolvedForeground.opacity(0.32) : tint.opacity(0.24)
    }

    var body: some View {
        let corner = size <= 24 ? PaperTokens.chipRadius : PaperTokens.controlRadius
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(resolvedFill)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(resolvedBorder, lineWidth: PaperTokens.hairline)
            )
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(resolvedForeground)
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
        let trackFill: Color = isOn
            ? theme.successColor
            : (theme.isDark ? Color.black.opacity(0.32) : theme.insetColor)
        let trackBorder: Color = isOn
            ? theme.successColor.opacity(0.85)
            : theme.borderColor
        let thumbFill: Color = Color.white

        HStack(spacing: 8) {
            configuration.label

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(trackFill)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(trackBorder, lineWidth: PaperTokens.hairline)
                        )
                        .frame(width: 38, height: 22)

                    Circle()
                        .fill(thumbFill)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black.opacity(0.10), lineWidth: PaperTokens.hairline)
                        )
                        .shadow(
                            color: Color.black.opacity(0.24 * (0.3 + 0.7 * scaledDepth)),
                            radius: 1.5 * scaledDepth + 0.5,
                            x: 0.3 * scaledDepth,
                            y: 1 * scaledDepth
                        )
                        .frame(width: 18, height: 18)
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
        let trackFill = theme.isDark ? Color.black.opacity(0.30) : theme.insetColor

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
                        .padding(.horizontal, compact ? 10 : 12)
                        .padding(.vertical, compact ? 4.5 : 5.5)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(theme.primaryButtonBackground)
                                    .shadow(
                                        color: theme.shadowRGB.color.opacity(0.22 * scaledDepth),
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
        .background(
            Capsule(style: .continuous)
                .fill(trackFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
        )
    }
}

// MARK: - Setting Group & Setting Row (clear separation on all papers)

struct PaperSettingGroup<Content: View>: View {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperDepth) private var depth
    @Environment(\.paperFontPreset) private var fontPreset

    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let fonts = PaperFonts(preset: fontPreset)
        let cardFill = theme.isDark
            ? theme.surfaceColor.opacity(0.92)
            : theme.surfaceColor.opacity(0.84)
        let shape = RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(fonts.captionMedium)
                .foregroundStyle(theme.secondaryInkColor)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(cardFill, in: shape)
            .overlay(
                shape.strokeBorder(theme.borderColor, lineWidth: 0.75)
            )
            .shadow(
                color: theme.shadowRGB.color.opacity((theme.isDark ? 0.30 : 0.06) * min(1, max(0, depth))),
                radius: 6,
                y: 2
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
        HStack(alignment: .center, spacing: 16) {
            labelColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            control
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
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

final class SystemAppearanceObserver: ObservableObject {
    static let shared = SystemAppearanceObserver()

    @Published private(set) var isDark: Bool
    private var appObservation: NSKeyValueObservation?
    private var themeNotificationObserver: NSObjectProtocol?

    private init() {
        self.isDark = Self.currentSystemIsDark()
        appObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        themeNotificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let themeNotificationObserver {
            DistributedNotificationCenter.default().removeObserver(themeNotificationObserver)
        }
    }

    func refresh() {
        let next = Self.currentSystemIsDark()
        if isDark != next {
            isDark = next
        }
    }

    static func currentSystemIsDark() -> Bool {
        if let app = NSApp {
            return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
        return style?.caseInsensitiveCompare("Dark") == .orderedSame
    }
}

private struct PaperEnvironmentModifier: ViewModifier {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var systemAppearance = SystemAppearanceObserver.shared

    func body(content: Content) -> some View {
        let prefersDark: Bool = {
            switch settings.appearance {
            case .dark: return true
            case .light: return false
            case .system: return systemAppearance.isDark
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
            .preferredColorScheme(resolved.isDark ? .dark : .light)
    }
}

extension View {
    func applyPaperEnvironment(_ settings: SettingsStore) -> some View {
        modifier(PaperEnvironmentModifier(settings: settings))
    }
}

// MARK: - Cleanup Style Guide Popover Button

struct CleanupStyleGuideButton: View {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperFontPreset) private var fontPreset
    @State private var isPresented = false

    var body: some View {
        let fonts = PaperFonts(preset: fontPreset)

        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.secondaryInkColor)
                .frame(width: 20, height: 20)
                .paperSurface(level: .l2OnPaper, cornerRadius: 999)
        }
        .buttonStyle(.plain)
        .help("Как работают стили обработки текста")
        .accessibilityLabel("Памятка по стилям обработки")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Стили постобработки ИИ")
                        .font(fonts.uiSemibold)
                        .foregroundStyle(theme.inkColor)
                    Text("Во всех ИИ-стилях всегда проверяется пунктуация, исправляется орфография, удаляются слова-паразиты и самоисправления.")
                        .font(fonts.caption)
                        .foregroundStyle(theme.secondaryInkColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(theme.borderColor)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(CleanupStyle.allCases) { style in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(style.shortTitle)
                                    .font(fonts.uiMedium)
                                    .foregroundStyle(theme.inkColor)
                                Text("· \(style.loadLabel)")
                                    .font(fonts.microMedium)
                                    .foregroundStyle(theme.secondaryInkColor)
                            }
                            Text(style.tooltipText)
                                .font(fonts.caption)
                                .foregroundStyle(theme.secondaryInkColor)
                                .fixedSize(horizontal: false, vertical: true)
                            if style != .off {
                                Text("Пример: «\(style.exampleOutput)»")
                                    .font(fonts.micro)
                                    .italic()
                                    .foregroundStyle(theme.tertiaryInkColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 380, alignment: .leading)
            .background(theme.baseColor)
        }
    }
}

struct PaperLLMSummaryLine: View {
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperFontPreset) private var fontPreset
    let summary: String

    var body: some View {
        let fonts = PaperFonts(preset: fontPreset)
        let isError = summary.hasPrefix("Ошибка")
        let isSuccess = summary.hasPrefix("ИИ:")
        let icon = isError ? "exclamationmark.triangle" : (isSuccess ? "sparkles" : "minus.circle")
        let tint = isError ? theme.errorColor : (isSuccess ? theme.successColor : theme.secondaryInkColor)

        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
            Text(summary)
                .font(fonts.caption)
                .lineLimit(2)
        }
        .foregroundStyle(tint)
    }
}
