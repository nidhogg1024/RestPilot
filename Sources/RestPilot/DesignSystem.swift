import AppKit
import SwiftUI

enum RestPilotTheme {
    static let active = Color.accentColor
    static let activeSurface = Color.accentColor.opacity(0.10)
    static let inactive = Color.secondary
    static let inactiveSurface = Color.secondary.opacity(0.07)
    static let warning = Color(nsColor: .systemOrange)
    static let warningSurface = Color(nsColor: .systemOrange).opacity(0.10)
}

enum SettingsVisualState {
    case neutral
    case active
    case inactive
}

enum MenuPopoverMetrics {
    static let width: CGFloat = 286
    static let height: CGFloat = 251
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let state: SettingsVisualState
    let content: Content

    init(
        title: String,
        state: SettingsVisualState = .neutral,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.state = state
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(titleColor)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var titleColor: Color {
        switch state {
        case .neutral:
            return Color.primary.opacity(0.72)
        case .active:
            return RestPilotTheme.active
        case .inactive:
            return RestPilotTheme.inactive
        }
    }
}

struct SettingsStatusIcon: View {
    let systemImage: String
    let state: SettingsVisualState

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foregroundColor)
            .frame(width: 28, height: 28)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }

    private var foregroundColor: Color {
        switch state {
        case .active:
            return RestPilotTheme.active
        case .neutral, .inactive:
            return RestPilotTheme.inactive
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .active:
            return RestPilotTheme.activeSurface
        case .neutral, .inactive:
            return RestPilotTheme.inactiveSurface
        }
    }
}
