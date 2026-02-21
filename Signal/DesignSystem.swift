import SwiftUI

// MARK: - Typography

enum AppFont {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - App Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case dark
    case light
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return L10n.appearanceSystem
        case .dark: return L10n.appearanceDark
        case .light: return L10n.appearanceLight
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// MARK: - Color Tokens

extension Color {
    // Core surfaces (dark mode defaults - these are for backwards compatibility)
    static let surface = Color.white.opacity(0.06)
    static let inputField = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.25)
    static let trackStroke = Color.white.opacity(0.15)

    // Glass tokens
    static let glassBorder = Color.white.opacity(0.12)
    static let glassHighlight = Color.white.opacity(0.08)
    static let glassShadow = Color.black.opacity(0.3)
}

// MARK: - Theme-Aware Colors

struct AppColors {
    let colorScheme: ColorScheme
    
    // Background colors
    var background: Color {
        colorScheme == .dark ? .black : Color(white: 0.94)
    }
    
    var secondaryBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : .white
    }
    
    // Card background - more visible in light mode
    var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : .white
    }
    
    // Text colors
    var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var secondaryText: Color {
        colorScheme == .dark ? .gray : Color(white: 0.4)
    }
    
    var mutedText: Color {
        colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.4)
    }
    
    // Surface colors
    var surface: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }
    
    var inputField: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    
    var divider: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.12)
    }
    
    // Glass tokens
    var glassBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.15)
    }
    
    var glassShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.15)
    }
    
    // Selection/highlight
    var selection: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }
    
    // Toolbar background
    var toolbarBackground: Color {
        colorScheme == .dark ? .black : Color(white: 0.94)
    }
    
    // Chat message backgrounds
    var userMessageBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
    }
    
    var modelMessageBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }
    
    // Stronger glass border (for highlights/focus states)
    var glassBorderStrong: Color {
        colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.25)
    }
}

// Environment key for theme colors
struct AppColorsKey: EnvironmentKey {
    static let defaultValue = AppColors(colorScheme: .dark)
}

extension EnvironmentValues {
    var appColors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }
}

// MARK: - Layout Constants

enum AppLayout {
    static let horizontalPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 32
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 14
    static let inputRadius: CGFloat = 12
    static let fabSize: CGFloat = 56
    static let fabBottomMargin: CGFloat = 32
    static let glassBorderWidth: CGFloat = 0.5
    static let sheetCornerRadius: CGFloat = 28
}

// MARK: - Glass Modifiers

struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = AppLayout.cardRadius
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        let colors = AppColors(colorScheme: colorScheme)
        content
            .padding(padding)
            .background(
                colorScheme == .dark
                    ? AnyShapeStyle(.ultraThinMaterial.opacity(0.5))
                    : AnyShapeStyle(.ultraThinMaterial.opacity(0.15))
            )
            .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(colors.glassBorder, lineWidth: colorScheme == .dark ? AppLayout.glassBorderWidth : 0.8)
            )
            .shadow(color: colors.glassShadow, radius: colorScheme == .dark ? 0 : 3, y: colorScheme == .dark ? 0 : 1)
    }
}

struct GlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        let colors = AppColors(colorScheme: colorScheme)
        content
            .background {
                ZStack {
                    colors.background
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.3 : 0.15))
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func glassCard(radius: CGFloat = AppLayout.cardRadius, padding: CGFloat = 0) -> some View {
        modifier(GlassCard(radius: radius, padding: padding))
    }

    func glassBackground() -> some View {
        modifier(GlassBackground())
    }
    
    /// Applies the new Liquid Glass effect with optional interactivity
    @ViewBuilder
    func liquidGlass(in shape: some Shape = Capsule(), interactive: Bool = false) -> some View {
        if interactive {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.glassEffect(.regular, in: shape)
        }
    }
}

// MARK: - Theme-Aware Logo

struct AppLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 20
    
    var body: some View {
        Image(colorScheme == .dark ? "SignalLogoINv" : "TraceLogoBlackNoBG")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }
}

// MARK: - Label Style Helper

struct TrackedLabel: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let kerning: CGFloat

    init(_ text: String, size: CGFloat = 11, weight: Font.Weight = .medium, kerning: CGFloat = 1.5) {
        self.text = text
        self.size = size
        self.weight = weight
        self.kerning = kerning
    }

    var body: some View {
        Text(text.uppercased())
            .font(AppFont.mono(size: size, weight: weight))
            .kerning(kerning)
            .foregroundStyle(Color.gray)
    }
}

// MARK: - Shared Time Formatting

extension TimeInterval {
    /// Formats as "0:00", "12:34", or "1:02:34"
    var formatted: String {
        let total = Int(self)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 { return String(format: "%d:%02d:%02d", hrs, mins, secs) }
        return String(format: "%d:%02d", mins, secs)
    }

    /// Formats as "00:00" or "1:02:34" with padded minutes
    var formattedPadded: String {
        let total = Int(self)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 { return String(format: "%d:%02d:%02d", hrs, mins, secs) }
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Formats as "5m", "1h 23m"
    var durationLabel: String {
        let mins = Int(self) / 60
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins)m"
    }
}

// MARK: - On-Device Badge

/// Badge indicating content was processed on-device
struct OnDeviceBadge: View {
    enum BadgeType {
        case transcription
        case summarization
        case both
    }
    
    let type: BadgeType
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: compact ? 9 : 10))
            if !compact {
                Text(labelText)
                    .font(AppFont.mono(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, compact ? 5 : 6)
        .padding(.vertical, 3)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.6), Color.green.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private var iconName: String {
        switch type {
        case .transcription:
            return "waveform"
        case .summarization:
            return "apple.intelligence"
        case .both:
            return "checkmark.shield.fill"
        }
    }
    
    private var labelText: String {
        switch type {
        case .transcription:
            return L10n.onDeviceBadge
        case .summarization:
            return L10n.appleAIBadge
        case .both:
            return L10n.onDeviceBadge
        }
    }
}

/// Convenience view for showing on-device status
struct OnDeviceIndicator: View {
    let wasTranscribedOnDevice: Bool?
    let wasSummarizedOnDevice: Bool?
    var compact: Bool = false
    
    var body: some View {
        if wasTranscribedOnDevice == true && wasSummarizedOnDevice == true {
            OnDeviceBadge(type: .both, compact: compact)
        } else if wasTranscribedOnDevice == true {
            OnDeviceBadge(type: .transcription, compact: compact)
        } else if wasSummarizedOnDevice == true {
            OnDeviceBadge(type: .summarization, compact: compact)
        }
    }
}
