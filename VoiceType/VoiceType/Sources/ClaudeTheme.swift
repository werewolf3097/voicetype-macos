import AppKit
import SwiftUI

struct ClaudeTheme {
    let scheme: ColorScheme

    var canvas: Color {
        scheme == .dark
            ? Color(red: 0.118, green: 0.114, blue: 0.106) // #1E1D1B
            : Color(red: 0.980, green: 0.976, blue: 0.961) // #FAF9F5 (warm sand)
    }

    var sidebar: Color {
        scheme == .dark
            ? Color(red: 0.094, green: 0.090, blue: 0.082) // #181715
            : Color(red: 0.953, green: 0.945, blue: 0.925) // #F3F1EC (stone sand)
    }

    var surface: Color {
        scheme == .dark
            ? Color(red: 0.161, green: 0.157, blue: 0.145) // #292825
            : Color.white
    }

    var surfaceSubtle: Color {
        scheme == .dark
            ? Color.white.opacity(0.05)
            : Color(red: 0.937, green: 0.929, blue: 0.902) // #EFECE6 (sand track)
    }

    var hoverFill: Color {
        scheme == .dark
            ? Color.white.opacity(0.13)
            : Color(red: 0.14, green: 0.12, blue: 0.09).opacity(0.12)
    }

    var selectedFill: Color {
        scheme == .dark
            ? Color.white.opacity(0.18)
            : Color(red: 0.816, green: 0.800, blue: 0.765) // #D0CCC3
    }

    var ink: Color {
        scheme == .dark
            ? Color(red: 0.929, green: 0.922, blue: 0.898) // #EDEBE5
            : Color(red: 0.114, green: 0.110, blue: 0.102) // #1D1C1A
    }

    var secondaryInk: Color {
        scheme == .dark
            ? Color(red: 0.635, green: 0.616, blue: 0.576) // #A29D93
            : Color(red: 0.416, green: 0.404, blue: 0.376) // #6A6760
    }

    var tertiaryInk: Color {
        scheme == .dark
            ? Color.white.opacity(0.36)
            : Color.black.opacity(0.35)
    }

    var border: Color {
        scheme == .dark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.085)
    }

    /// Primary calm botanical sage green (replaces heavy orange)
    var accent: Color {
        scheme == .dark
            ? Color(red: 0.416, green: 0.643, blue: 0.482) // #6AA47B
            : Color(red: 0.306, green: 0.502, blue: 0.365) // #4E805D
    }

    /// Soft light-green / светло-салатовый for completed stages and gentle highlights
    var accentLight: Color {
        scheme == .dark
            ? Color(red: 0.553, green: 0.784, blue: 0.596) // #8DC898
            : Color(red: 0.518, green: 0.749, blue: 0.561) // #84BF8F
    }

    /// Light-sage tint for pills, tags, and subtle active highlights
    var accentSoft: Color {
        scheme == .dark
            ? Color(red: 0.451, green: 0.718, blue: 0.522).opacity(0.18)
            : Color(red: 0.878, green: 0.937, blue: 0.886) // #E0EFE2
    }

    /// High-contrast text color on `accentSoft` pills
    var accentInk: Color {
        scheme == .dark
            ? Color(red: 0.686, green: 0.886, blue: 0.733)
            : Color(red: 0.196, green: 0.376, blue: 0.251) // #326040
    }

    var success: Color {
        scheme == .dark
            ? Color(red: 0.451, green: 0.741, blue: 0.533)
            : Color(red: 0.259, green: 0.510, blue: 0.345) // #428258
    }

    var warning: Color {
        scheme == .dark
            ? Color(red: 0.835, green: 0.663, blue: 0.357)
            : Color(red: 0.659, green: 0.482, blue: 0.180) // #A87B2E (warm sand-ochre)
    }

    var danger: Color {
        scheme == .dark
            ? Color(red: 0.882, green: 0.412, blue: 0.392)
            : Color(red: 0.765, green: 0.275, blue: 0.255)
    }

    var cardShadow: Color {
        scheme == .dark
            ? Color.black.opacity(0.28)
            : Color.black.opacity(0.04)
    }

    static let windowBackgroundNSColor = NSColor(name: "ClaudeWindowCanvas") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(srgbRed: 0.118, green: 0.114, blue: 0.106, alpha: 1)
        }
        return NSColor(srgbRed: 0.980, green: 0.976, blue: 0.961, alpha: 1)
    }
}

struct ClaudePrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var compact: Bool = false
    var tintColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let theme = ClaudeTheme(scheme: colorScheme)
        let baseColor = tintColor ?? theme.accent
        configuration.label
            .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, compact ? 5 : 8)
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(configuration.isPressed ? baseColor.opacity(0.86) : baseColor)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ClaudeSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var compact: Bool = false
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let theme = ClaudeTheme(scheme: colorScheme)
        configuration.label
            .font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(isDestructive ? theme.danger : theme.ink)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(configuration.isPressed ? theme.selectedFill : theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Wrapping flow layout for metadata chips, template pills, and action toolbars so controls wrap gracefully instead of clipping or distorting on narrow windows.
struct ClaudeFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
            if currentX > 0 && currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            usedWidth = max(usedWidth, currentX + size.width)
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(
            width: maxWidth.isFinite ? maxWidth : usedWidth,
            height: currentY + lineHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if currentX > bounds.minX && currentX + size.width > bounds.maxX + 0.5 {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
            )
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

extension View {
    func claudeCard(_ theme: ClaudeTheme, cornerRadius: CGFloat = 14, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
            .shadow(color: theme.cardShadow, radius: 10, y: 3)
    }
}
