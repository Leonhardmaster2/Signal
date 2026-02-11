import SwiftUI

// MARK: - Typography

enum AppFont {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Color Tokens

extension Color {
    // Core surfaces
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
    var radius: CGFloat = AppLayout.cardRadius
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial.opacity(0.5))
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.glassBorder, lineWidth: AppLayout.glassBorderWidth)
            )
    }
}

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color.black
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.3))
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
            return "ON-DEVICE"
        case .summarization:
            return "APPLE AI"
        case .both:
            return "ON-DEVICE"
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
