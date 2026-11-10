import AppKit
import SwiftUI

extension Color {
    /// A colour that follows the light or dark appearance it is drawn in.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Warm paper palette taken from the app icon: cream ground, soft ink and the
/// robin's orange as the single accent.
enum RestPilotTheme {
    /// Window and popover ground.
    static let canvasNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(0x1C1B19) : rgb(0xF7F3EB)
    }
    static let canvas = Color(nsColor: canvasNSColor)
    /// Raised surfaces: cards, pills, selected sidebar rows.
    static let card = Color(light: rgb(0xFFFFFF), dark: rgb(0x282725))
    static let ink = Color(light: rgb(0x2D2A26), dark: rgb(0xEDE9E2))
    static let inkSecondary = Color(light: rgb(0x2D2A26, alpha: 0.62), dark: rgb(0xEDE9E2, alpha: 0.64))
    static let inkTertiary = Color(light: rgb(0x2D2A26, alpha: 0.40), dark: rgb(0xEDE9E2, alpha: 0.42))
    static let hairline = Color(light: rgb(0x2D2A26, alpha: 0.08), dark: rgb(0xFFFFFF, alpha: 0.09))
    /// Quiet fill for chips, tracks and pressed states.
    static let fill = Color(light: rgb(0x2D2A26, alpha: 0.055), dark: rgb(0xFFFFFF, alpha: 0.08))
    static let cardShadow = Color(light: rgb(0x5C4A32, alpha: 0.07), dark: rgb(0x000000, alpha: 0.30))

    static let active = Color(light: rgb(0xE0703A), dark: rgb(0xF08C58))
    static let activeSurface = Color(light: rgb(0xE0703A, alpha: 0.12), dark: rgb(0xF08C58, alpha: 0.18))
    /// Destructive actions such as removing an image.
    static let danger = Color(light: rgb(0xC0392B), dark: rgb(0xF0887A))
    static let warning = Color(light: rgb(0xB7791F), dark: rgb(0xE0B15A))
    static let warningSurface = Color(light: rgb(0xB7791F, alpha: 0.12), dark: rgb(0xE0B15A, alpha: 0.16))

    /// Fixed tones for the always-light break screen.
    static let overlayInk = Color(nsColor: rgb(0x2D2A26))
    static let overlayAccent = Color(nsColor: rgb(0xE0703A))
}

enum MenuPopoverMetrics {
    static let width: CGFloat = 304
    static let height: CGFloat = 284
}

/// White rounded surface that groups related rows on the cream ground.
struct SoftCard<Content: View>: View {
    var padding: CGFloat = 0
    var cornerRadius: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SoftSurface(cornerRadius: cornerRadius))
    }
}

/// Card fill with its hairline and shadow. The shadow sits on the shape alone
/// so text placed on top never picks up a halo of its own.
struct SoftSurface: View {
    var cornerRadius: CGFloat = 14
    var shadowRadius: CGFloat = 10
    var stroke: Color = RestPilotTheme.hairline
    var strokeWidth: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(RestPilotTheme.card)
            .shadow(color: RestPilotTheme.cardShadow, radius: shadowRadius, y: shadowRadius * 0.3)
            .overlay(shape.stroke(stroke, lineWidth: strokeWidth))
    }
}

/// Thin countdown ring. `progress` is the share still remaining.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3
    var tint: Color = RestPilotTheme.active
    var track: Color = RestPilotTheme.fill

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// Pressed feedback shared by the custom soft buttons.
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.66 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Switch drawn in the theme's own colours, so it reads the same whether or
/// not the window is active.
struct SoftSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? RestPilotTheme.active : RestPilotTheme.inkTertiary.opacity(0.45))
                .frame(width: 36, height: 21)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
                        .padding(2)
                }
                .animation(.easeOut(duration: 0.16), value: configuration.isOn)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// Section of the settings window: a small heading over a white card.
struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RestPilotTheme.inkSecondary)
                .padding(.horizontal, 4)
            SoftCard {
                VStack(alignment: .leading, spacing: 0) { content }
            }
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(RestPilotTheme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row inside a `SettingsGroup` card: title, optional detail, control.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(RestPilotTheme.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(RestPilotTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 46)
    }
}

/// Inset hairline between rows of a card.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(RestPilotTheme.hairline)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}
