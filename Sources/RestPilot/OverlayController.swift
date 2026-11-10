import AppKit
import SwiftUI

@MainActor
final class InteractiveOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayTransitionState: ObservableObject {
    @Published var opacity: Double

    init(opacity: Double) {
        self.opacity = opacity
    }
}

private struct OverlayTransitionRoot: View {
    @ObservedObject var transition: OverlayTransitionState
    let content: AnyView

    var body: some View {
        content.opacity(transition.opacity)
    }
}

@MainActor
final class OverlayController {
    private var windows: [NSWindow] = []
    private var transitionState: OverlayTransitionState?
    private weak var engine: ScheduleEngine?
    private var settings: AppSettings = .default
    private var isPreview = false
    private var backgroundPath: String?
    private var transitionID = 0
    private var previewTimeout: DispatchWorkItem?
    private var previewDismissHandler: (() -> Void)?
    private let enterDuration: TimeInterval = 1.8
    private let exitDuration: TimeInterval = 0.65

    func show(engine: ScheduleEngine, settings: AppSettings) {
        guard let session = engine.activeBreakSession() else { return }
        cancelPreviewTimeout()
        previewDismissHandler = nil
        self.engine = engine
        self.settings = settings
        backgroundPath = settings.resolvedBackgroundPath()
        isPreview = false
        present(settings: settings) {
            AnyView(BreakOverlayView(
                session: session,
                engine: engine,
                settings: settings,
                backgroundPath: self.backgroundPath
            ))
        }
    }

    func showPreview(kind: BreakKind, settings: AppSettings, onDismiss: (() -> Void)? = nil) {
        cancelPreviewTimeout()
        previewDismissHandler = onDismiss
        self.settings = settings
        self.engine = nil
        backgroundPath = settings.resolvedBackgroundPath()
        isPreview = true
        let duration = settings.duration(for: kind)
        let deadline = Date().addingTimeInterval(duration)
        let content = settings.contents(for: kind).first ?? BreakContent(text: kind == .eye ? "看看远处，放松双眼" : "站起来活动一下")
        present(settings: settings) { [weak self] in
            AnyView(PreviewOverlayView(
                kind: kind,
                content: content,
                settings: settings,
                backgroundPath: self?.backgroundPath,
                deadline: deadline,
                close: { self?.hide() }
            ))
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard self?.isPreview == true else { return }
            self?.hide()
        }
        previewTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: timeout)
    }

    func rebuild() {
        guard let engine, let session = engine.activeBreakSession() else { return }
        present(settings: settings) {
            AnyView(BreakOverlayView(
                session: session,
                engine: engine,
                settings: self.settings,
                backgroundPath: self.backgroundPath
            ))
        }
    }

    private func present(settings: AppSettings, content: () -> AnyView) {
        transitionID &+= 1
        let currentTransition = transitionID
        let outgoing = windows
        let outgoingTransition = transitionState
        let incomingTransition = OverlayTransitionState(opacity: settings.fadeInOverlay ? 0 : 1)
        let incoming = buildWindows(settings: settings) {
            AnyView(OverlayTransitionRoot(
                transition: incomingTransition,
                content: content()
            ))
        }
        windows = incoming
        transitionState = incomingTransition

        guard settings.fadeInOverlay else {
            close(outgoing, transition: outgoingTransition, animated: false)
            return
        }

        close(outgoing, transition: outgoingTransition, animated: true)
        // Start after AppKit has committed a transparent frame. The entire
        // SwiftUI root shares one opacity value, keeping every display,
        // background and foreground element in the same transition.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.transitionID == currentTransition else { return }
            withAnimation(.easeInOut(duration: self.enterDuration)) {
                incomingTransition.opacity = 1
            }
        }
    }

    private func buildWindows(settings: AppSettings, content: () -> AnyView) -> [NSWindow] {
        let screens = settings.showOnAllDisplays ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        var result: [NSWindow] = []
        for screen in screens {
            let window = InteractiveOverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isMovable = false
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.contentView = OverlayHostingView(rootView: content())
            window.alphaValue = 1
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            window.displayIfNeeded()
            result.append(window)
        }
        result.first?.makeKey()
        return result
    }

    func hide() {
        cancelPreviewTimeout()
        transitionID &+= 1
        let outgoing = windows
        let outgoingTransition = transitionState
        windows.removeAll()
        transitionState = nil
        let onDismiss = isPreview ? previewDismissHandler : nil
        previewDismissHandler = nil
        isPreview = false
        close(
            outgoing,
            transition: outgoingTransition,
            animated: settings.fadeInOverlay,
            completion: onDismiss
        )
    }

    private func cancelPreviewTimeout() {
        previewTimeout?.cancel()
        previewTimeout = nil
    }

    private func close(
        _ windows: [NSWindow],
        transition: OverlayTransitionState?,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard !windows.isEmpty else {
            completion?()
            return
        }
        guard animated, let transition else {
            windows.forEach { $0.orderOut(nil) }
            completion?()
            return
        }
        withAnimation(.easeInOut(duration: exitDuration)) {
            transition.opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) {
            windows.forEach { $0.orderOut(nil) }
            completion?()
        }
    }
}

struct OverlayBackground: View {
    let settings: AppSettings
    let backgroundPath: String?
    @State private var ambientExpanded = false

    var body: some View {
        ZStack {
            if let backgroundPath, let image = NSImage(contentsOfFile: backgroundPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(isAmbient(backgroundPath) && ambientExpanded ? 1.018 : 1)
                    .ignoresSafeArea()
                    .onAppear {
                        guard isAmbient(backgroundPath) else { return }
                        withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                            ambientExpanded = true
                        }
                    }
                imageEffect
            } else {
                fallbackBackground
            }
        }
        .clipped()
    }

    private func isAmbient(_ path: String) -> Bool {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent == "ambient"
    }

    @ViewBuilder private var imageEffect: some View {
        switch settings.overlayStyle {
        case .softGradient:
            LinearGradient(
                colors: [
                    Color.black.opacity(settings.backgroundDim * 0.65),
                    Color.black.opacity(settings.backgroundDim)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .frosted:
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(settings.backgroundDim * 0.55)
        case .dimmed:
            Color.black.opacity(max(0.34, settings.backgroundDim))
        }
    }

    @ViewBuilder private var fallbackBackground: some View {
        switch settings.overlayStyle {
        case .softGradient:
            calmLightBackground
        case .frosted:
            Rectangle().fill(.thickMaterial)
            Color(red: 0.965, green: 0.958, blue: 0.94)
                .opacity(0.56 + settings.overlayOpacity * 0.30)
        case .dimmed:
            Color.black.opacity(max(0.68, settings.overlayOpacity))
        }
    }

    private var calmLightBackground: some View {
        ZStack {
            Color(red: 0.91, green: 0.92, blue: 0.92)
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.975, green: 0.969, blue: 0.949), location: 0),
                    .init(color: Color(red: 0.951, green: 0.951, blue: 0.943), location: 0.52),
                    .init(color: Color(red: 0.925, green: 0.936, blue: 0.943), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.70 + settings.overlayOpacity * 0.30)
            RadialGradient(
                colors: [Color.white.opacity(0.30), Color.white.opacity(0)],
                center: UnitPoint(x: 0.36, y: 0.28),
                startRadius: 20,
                endRadius: 820
            )
        }
    }
}

enum OverlayActionControlSize {
    case regular
    case compact

    var fontSize: CGFloat { self == .regular ? 16 : 13 }
    var symbolSize: CGFloat { self == .regular ? 18 : 14 }
    var minWidth: CGFloat { self == .regular ? 188 : 136 }
    var height: CGFloat { self == .regular ? 50 : 38 }
    var horizontalPadding: CGFloat { self == .regular ? 18 : 12 }
    var contentSpacing: CGFloat { self == .regular ? 8 : 6 }
    var actionSpacing: CGFloat { self == .regular ? 16 : 10 }
}

struct OverlayActionLabel: View {
    let title: String
    let systemImage: String
    let usesLightText: Bool
    var emphasized = false
    var controlSize: OverlayActionControlSize = .regular

    var body: some View {
        HStack(spacing: controlSize.contentSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: controlSize.symbolSize, weight: .semibold))
            Text(title)
                .font(.system(size: controlSize.fontSize, weight: .semibold))
        }
        .foregroundStyle(labelColor)
        .padding(.horizontal, controlSize.horizontalPadding)
        .frame(minWidth: controlSize.minWidth, minHeight: controlSize.height)
        .background(
            fillColor,
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                usesLightText ? Color.white.opacity(0.26) : Color.black.opacity(0.12),
                lineWidth: 1
            )
        )
        .contentShape(Capsule())
    }

    private var labelColor: Color {
        if emphasized { return .white.opacity(0.98) }
        return usesLightText
            ? .white.opacity(0.96)
            : Color(red: 0.17, green: 0.18, blue: 0.19).opacity(0.94)
    }

    private var fillColor: Color {
        if emphasized {
            return usesLightText ? .black.opacity(0.50) : .black.opacity(0.78)
        }
        return usesLightText ? .black.opacity(0.28) : .white.opacity(0.72)
    }
}

struct OverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct OverlayActionRow: View {
    let usesLightText: Bool
    let controlSize: OverlayActionControlSize
    let snoozeAction: (() -> Void)?
    let secondaryTitle: String?
    let secondarySystemImage: String?
    let secondaryAction: (() -> Void)?
    var enablesEscapeShortcut = true
    var stacksVertically = false

    var body: some View {
        let layout = stacksVertically
            ? AnyLayout(VStackLayout(spacing: controlSize.actionSpacing))
            : AnyLayout(HStackLayout(spacing: controlSize.actionSpacing))
        layout {
            actionButtons
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let snoozeAction {
            Button(action: snoozeAction) {
                OverlayActionLabel(
                    title: "5 分钟后再次提醒",
                    systemImage: "clock.arrow.circlepath",
                    usesLightText: usesLightText,
                    emphasized: true,
                    controlSize: controlSize
                )
            }
            .buttonStyle(OverlayButtonStyle())
        }

        if let secondaryTitle,
           let secondarySystemImage,
           let secondaryAction {
            secondaryButton(
                title: secondaryTitle,
                systemImage: secondarySystemImage,
                action: secondaryAction
            )
        }
    }

    @ViewBuilder
    private func secondaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            OverlayActionLabel(
                title: title,
                systemImage: systemImage,
                usesLightText: usesLightText,
                controlSize: controlSize
            )
        }
        .buttonStyle(OverlayButtonStyle())

        if enablesEscapeShortcut {
            button.keyboardShortcut(.escape, modifiers: [])
        } else {
            button
        }
    }
}

struct BreakPresentationPositions: Equatable {
    let contentCenterY: CGFloat
    let actionCenterY: CGFloat?
}

struct BreakPresentationLayout: Layout {
    static func positions(
        containerHeight: CGFloat,
        contentHeight: CGFloat,
        actionHeight: CGFloat?
    ) -> BreakPresentationPositions {
        guard let actionHeight else {
            return BreakPresentationPositions(
                contentCenterY: containerHeight / 2,
                actionCenterY: nil
            )
        }

        let compact = containerHeight < 700
        let topInset: CGFloat = compact ? 24 : 48
        let bottomInset: CGFloat = compact ? 24 : 72
        let preferredGap: CGFloat = compact ? 32 : 64
        let preferredContentCenter = containerHeight * 0.43
        let preferredActionCenter = containerHeight * 0.74
        let maximumActionCenter = containerHeight - bottomInset - actionHeight / 2
        var actionCenter = min(preferredActionCenter, maximumActionCenter)
        let minimumContentCenter = topInset + contentHeight / 2
        var maximumContentCenter = actionCenter
            - actionHeight / 2
            - preferredGap
            - contentHeight / 2

        if maximumContentCenter < minimumContentCenter {
            actionCenter = maximumActionCenter
            maximumContentCenter = actionCenter
                - actionHeight / 2
                - preferredGap
                - contentHeight / 2
        }

        return BreakPresentationPositions(
            contentCenterY: max(
                minimumContentCenter,
                min(preferredContentCenter, maximumContentCenter)
            ),
            actionCenterY: actionCenter
        )
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions(
            by: CGSize(width: 1280, height: 800)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let content = subviews.first else { return }
        let contentProposal = ProposedViewSize(
            width: min(1100, bounds.width),
            height: nil
        )
        let contentSize = content.sizeThatFits(contentProposal)
        let action = subviews.count > 1 ? subviews[1] : nil
        let actionSize = action?.sizeThatFits(
            ProposedViewSize(width: bounds.width, height: nil)
        )
        let positions = Self.positions(
            containerHeight: bounds.height,
            contentHeight: contentSize.height,
            actionHeight: actionSize?.height
        )

        content.place(
            at: CGPoint(
                x: bounds.midX,
                y: bounds.minY + positions.contentCenterY
            ),
            anchor: .center,
            proposal: contentProposal
        )

        if let action,
           let actionSize,
           let actionCenterY = positions.actionCenterY {
            action.place(
                at: CGPoint(
                    x: bounds.midX,
                    y: bounds.minY + actionCenterY
                ),
                anchor: .center,
                proposal: ProposedViewSize(
                    width: actionSize.width,
                    height: actionSize.height
                )
            )
        }
    }
}

struct BreakPresentation: View {
    let eyebrow: String
    let time: String
    let content: BreakContent
    let settings: AppSettings
    let hasBackgroundImage: Bool
    let reminderMessage: String?
    let snoozeAction: (() -> Void)?
    let secondaryTitle: String?
    let secondarySystemImage: String?
    let secondaryAction: (() -> Void)?
    var enablesEscapeShortcut = true

    var body: some View {
        let usesLightText = hasBackgroundImage || settings.overlayStyle == .dimmed
        BreakPresentationLayout {
            VStack(spacing: 24) {
                Text(eyebrow)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(3)
                    .opacity(0.82)
                Text(content.text)
                    .font(.system(size: 56 * settings.textScale, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if settings.showCountdown {
                    Text(time)
                        .font(.system(size: 34 * settings.textScale, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .opacity(0.86)
                }
                if let reminderMessage {
                    Label(reminderMessage, systemImage: "exclamationmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            usesLightText ? Color.black.opacity(0.18) : Color.black.opacity(0.065),
                            in: Capsule()
                        )
                        .opacity(0.88)
                }
                if let path = content.imagePath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 440 * settings.imageScale, maxHeight: 240 * settings.imageScale)
                }
            }
            .frame(maxWidth: 1100)

            if snoozeAction != nil || secondaryAction != nil {
                OverlayActionRow(
                    usesLightText: usesLightText,
                    controlSize: .regular,
                    snoozeAction: snoozeAction,
                    secondaryTitle: secondaryTitle,
                    secondarySystemImage: secondarySystemImage,
                    secondaryAction: secondaryAction,
                    enablesEscapeShortcut: enablesEscapeShortcut
                )
            }
        }
        .padding(.horizontal, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(
            usesLightText
                ? Color.white.opacity(0.94)
                : Color(red: 0.16, green: 0.17, blue: 0.18)
        )
        .shadow(color: .black.opacity(hasBackgroundImage ? 0.22 : 0), radius: 14, y: 3)
    }
}

private struct BreakOverlayView: View {
    let session: BreakSession
    let engine: ScheduleEngine
    let settings: AppSettings
    let backgroundPath: String?
    @State private var now = Date()

    var body: some View {
        ZStack {
            OverlayBackground(settings: settings, backgroundPath: backgroundPath)
            BreakPresentation(
                eyebrow: session.kind.displayName,
                time: formattedCountdown(engine.remaining(for: session.id, now: now)),
                content: session.content,
                settings: settings,
                hasBackgroundImage: backgroundPath != nil,
                reminderMessage: reminderMessage,
                snoozeAction: session.allowsSnooze
                    ? { engine.snoozeCurrentBreak(minutes: 5) }
                    : nil,
                secondaryTitle: skipAvailable ? secondaryTitle : nil,
                secondarySystemImage: skipAvailable ? secondarySystemImage : nil,
                secondaryAction: skipAvailable ? secondaryAction : nil,
                enablesEscapeShortcut: !session.delaysSkip
            )
        }
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    /// Seconds until the skip button appears. Zero when skipping is immediate.
    private var skipDelayRemaining: TimeInterval {
        guard session.delaysSkip else { return 0 }
        return max(0, RestDebtPolicy.skipDelay - now.timeIntervalSince(session.startedAt))
    }

    private var skipAvailable: Bool { skipDelayRemaining <= 0 }

    private var reminderMessage: String? {
        guard session.restDebt > 0 else { return nil }
        var parts = ["今天还欠 \(formattedRestDebt(session.restDebt)) 休息"]
        if session.extendedBy > 0 {
            parts.append("这次延长 \(formattedRestDebt(session.extendedBy))")
        }
        if !skipAvailable, settings.showSkipButton {
            parts.append("\(Int(skipDelayRemaining.rounded(.up))) 秒后可跳过")
        }
        return parts.joined(separator: " · ")
    }

    private var secondaryTitle: String? {
        if session.source == .manual { return "结束休息" }
        return settings.showSkipButton ? "跳过这次休息" : nil
    }

    private var secondarySystemImage: String? {
        if session.source == .manual { return "xmark" }
        return settings.showSkipButton ? "forward.end" : nil
    }

    private var secondaryAction: (() -> Void)? {
        if session.source == .manual {
            return { engine.endManualBreak() }
        }
        guard settings.showSkipButton else { return nil }
        return { engine.skipBreak() }
    }
}

private struct PreviewOverlayView: View {
    let kind: BreakKind
    let content: BreakContent
    let settings: AppSettings
    let backgroundPath: String?
    let deadline: Date
    let close: () -> Void
    @State private var now = Date()

    var body: some View {
        ZStack {
            OverlayBackground(settings: settings, backgroundPath: backgroundPath)
            BreakPresentation(
                eyebrow: "预览 · \(kind.displayName)",
                time: formattedCountdown(deadline.timeIntervalSince(now)),
                content: content,
                settings: settings,
                hasBackgroundImage: backgroundPath != nil,
                reminderMessage: nil,
                snoozeAction: nil,
                secondaryTitle: "关闭预览",
                secondarySystemImage: "xmark",
                secondaryAction: close
            )
        }
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}
