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

    /// Cream paper with faint peach, sage and sky washes. Every tone stays
    /// very light so the blends never turn muddy.
    private var calmLightBackground: some View {
        let wash = 0.55 + settings.overlayOpacity * 0.45
        return ZStack {
            Color(red: 0.969, green: 0.953, blue: 0.922)
            EllipticalGradient(
                colors: [Color(red: 1.0, green: 0.851, blue: 0.741).opacity(0.95 * wash), Color(red: 1.0, green: 0.851, blue: 0.741).opacity(0)],
                center: UnitPoint(x: 0.10, y: 0.06),
                startRadiusFraction: 0,
                endRadiusFraction: 0.62
            )
            EllipticalGradient(
                colors: [Color(red: 0.843, green: 0.902, blue: 0.812).opacity(0.85 * wash), Color(red: 0.843, green: 0.902, blue: 0.812).opacity(0)],
                center: UnitPoint(x: 0.94, y: 0.98),
                startRadiusFraction: 0,
                endRadiusFraction: 0.60
            )
            EllipticalGradient(
                colors: [Color(red: 0.863, green: 0.898, blue: 0.957).opacity(0.75 * wash), Color(red: 0.863, green: 0.898, blue: 0.957).opacity(0)],
                center: UnitPoint(x: 0.96, y: 0.02),
                startRadiusFraction: 0,
                endRadiusFraction: 0.48
            )
            EllipticalGradient(
                colors: [Color(red: 0.992, green: 0.906, blue: 0.851).opacity(0.70 * wash), Color(red: 0.992, green: 0.906, blue: 0.851).opacity(0)],
                center: UnitPoint(x: 0.04, y: 1.0),
                startRadiusFraction: 0,
                endRadiusFraction: 0.44
            )
        }
    }
}

enum OverlayActionControlSize {
    case regular
    case compact

    var fontSize: CGFloat { self == .regular ? 15 : 13 }
    var keycapFontSize: CGFloat { self == .regular ? 11 : 10 }
    var height: CGFloat { self == .regular ? 44 : 34 }
    var horizontalPadding: CGFloat { self == .regular ? 20 : 14 }
    var contentSpacing: CGFloat { self == .regular ? 10 : 7 }
    var actionSpacing: CGFloat { self == .regular ? 10 : 8 }
}

/// Pill used at the bottom of the break screen. The raised variant is a white
/// pill for the gentler choice; the quiet one is bare text so leaving the
/// break never looks like the main thing to do.
struct OverlayActionLabel: View {
    let title: String
    let usesLightText: Bool
    var raised = false
    var keycap: String? = nil
    var controlSize: OverlayActionControlSize = .regular

    var body: some View {
        HStack(spacing: controlSize.contentSpacing) {
            Text(title)
                .font(.system(size: controlSize.fontSize, weight: .medium))
                .lineLimit(1)
                .fixedSize()
            if let keycap {
                Text(keycap)
                    .font(.system(size: controlSize.keycapFontSize, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(keycapFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(labelColor)
        .padding(.horizontal, controlSize.horizontalPadding)
        .frame(height: controlSize.height)
        .background(
            Capsule()
                .fill(fillColor)
                .shadow(
                    color: raised && !usesLightText ? Color(red: 0.36, green: 0.29, blue: 0.2).opacity(0.10) : .clear,
                    radius: 12,
                    y: 4
                )
        )
        .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
        .contentShape(Capsule())
    }

    private var labelColor: Color {
        if usesLightText { return .white.opacity(raised ? 0.96 : 0.82) }
        return RestPilotTheme.overlayInk.opacity(raised ? 0.92 : 0.58)
    }

    private var fillColor: Color {
        guard raised else { return .clear }
        return usesLightText ? .black.opacity(0.24) : .white
    }

    private var strokeColor: Color {
        guard raised else { return .clear }
        return usesLightText ? .white.opacity(0.30) : RestPilotTheme.overlayInk.opacity(0.07)
    }

    private var keycapFill: Color {
        usesLightText ? .white.opacity(0.18) : RestPilotTheme.overlayInk.opacity(0.07)
    }
}

struct OverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.66 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct OverlayActionRow: View {
    let usesLightText: Bool
    let controlSize: OverlayActionControlSize
    let snoozeAction: (() -> Void)?
    let secondaryTitle: String?
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
                    title: "延后 5 分钟",
                    usesLightText: usesLightText,
                    raised: true,
                    controlSize: controlSize
                )
            }
            .buttonStyle(OverlayButtonStyle())
        }

        if let secondaryTitle, let secondaryAction {
            secondaryButton(title: secondaryTitle, action: secondaryAction)
        }
    }

    @ViewBuilder
    private func secondaryButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            OverlayActionLabel(
                title: title,
                usesLightText: usesLightText,
                // Without a snooze pill next to it this is the only control,
                // so it takes the raised look.
                raised: snoozeAction == nil,
                keycap: enablesEscapeShortcut ? "esc" : nil,
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
        let preferredContentCenter = containerHeight * 0.45
        let preferredActionCenter = containerHeight * 0.86
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

/// White pill holding the remaining-time ring and the countdown.
struct CountdownPill: View {
    let time: String
    let progress: Double
    let usesLightText: Bool
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 11 * scale) {
            ProgressRing(
                progress: progress,
                lineWidth: 3.2 * scale,
                tint: usesLightText ? .white : RestPilotTheme.overlayAccent,
                track: usesLightText ? .white.opacity(0.28) : RestPilotTheme.overlayInk.opacity(0.09)
            )
            .frame(width: 22 * scale, height: 22 * scale)
            Text(time)
                .font(.system(size: 24 * scale, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.leading, 16 * scale)
        .padding(.trailing, 20 * scale)
        .frame(height: 50 * scale)
        .background(
            Capsule()
                .fill(usesLightText ? Color.black.opacity(0.24) : Color.white)
                .shadow(
                    color: usesLightText ? .clear : Color(red: 0.36, green: 0.29, blue: 0.2).opacity(0.12),
                    radius: 18 * scale,
                    y: 6 * scale
                )
        )
        .overlay(
            Capsule().stroke(
                usesLightText ? Color.white.opacity(0.30) : RestPilotTheme.overlayInk.opacity(0.06),
                lineWidth: 1
            )
        )
    }
}

/// Small label above the headline naming the kind of break.
struct BreakKindChip: View {
    let title: String
    let usesLightText: Bool
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 7 * scale) {
            Circle()
                .fill(usesLightText ? Color.white : RestPilotTheme.overlayAccent)
                .frame(width: 6 * scale, height: 6 * scale)
            Text(title)
                .font(.system(size: 13 * scale, weight: .medium))
        }
        .padding(.horizontal, 12 * scale)
        .frame(height: 28 * scale)
        .background(
            usesLightText ? Color.black.opacity(0.22) : RestPilotTheme.overlayInk.opacity(0.055),
            in: Capsule()
        )
    }
}

struct BreakPresentation: View {
    let eyebrow: String
    let time: String
    /// Share of the break still remaining, drawn as the countdown ring.
    var progress: Double = 1
    let content: BreakContent
    let settings: AppSettings
    let hasBackgroundImage: Bool
    let reminderMessage: String?
    let snoozeAction: (() -> Void)?
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?
    var enablesEscapeShortcut = true

    var body: some View {
        let usesLightText = hasBackgroundImage || settings.overlayStyle == .dimmed
        BreakPresentationLayout {
            VStack(spacing: 0) {
                BreakKindChip(title: eyebrow, usesLightText: usesLightText)
                Text(content.text)
                    .font(.system(size: 48 * settings.textScale, weight: .semibold))
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(hasBackgroundImage ? 0.30 : 0), radius: 14, y: 2)
                    .padding(.top, 26)
                if settings.showCountdown {
                    CountdownPill(
                        time: time,
                        progress: progress,
                        usesLightText: usesLightText,
                        scale: settings.textScale
                    )
                    .padding(.top, 36)
                }
                if let reminderMessage {
                    Text(reminderMessage)
                        .font(.system(size: 14))
                        .opacity(usesLightText ? 0.9 : 0.6)
                        .shadow(color: .black.opacity(hasBackgroundImage ? 0.35 : 0), radius: 8, y: 1)
                        .padding(.top, 22)
                }
                if let path = content.imagePath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 440 * settings.imageScale, maxHeight: 240 * settings.imageScale)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 32)
                }
            }
            .frame(maxWidth: 1100)

            if snoozeAction != nil || secondaryAction != nil {
                OverlayActionRow(
                    usesLightText: usesLightText,
                    controlSize: .regular,
                    snoozeAction: snoozeAction,
                    secondaryTitle: secondaryTitle,
                    secondaryAction: secondaryAction,
                    enablesEscapeShortcut: enablesEscapeShortcut
                )
            }
        }
        .padding(.horizontal, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(
            usesLightText
                ? Color.white.opacity(0.95)
                : RestPilotTheme.overlayInk
        )
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
                time: formattedCountdown(remaining),
                progress: totalDuration > 0 ? remaining / totalDuration : 1,
                content: session.content,
                settings: settings,
                hasBackgroundImage: backgroundPath != nil,
                reminderMessage: reminderMessage,
                snoozeAction: session.allowsSnooze
                    ? { engine.snoozeCurrentBreak(minutes: 5) }
                    : nil,
                secondaryTitle: skipAvailable ? secondaryTitle : nil,
                secondaryAction: skipAvailable ? secondaryAction : nil,
                enablesEscapeShortcut: !session.delaysSkip
            )
        }
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var remaining: TimeInterval {
        engine.remaining(for: session.id, now: now)
    }

    private var totalDuration: TimeInterval {
        engine.viewState(now: now).duration
    }

    /// Seconds until the skip button appears. Zero when skipping is immediate.
    private var skipDelayRemaining: TimeInterval {
        guard session.delaysSkip else { return 0 }
        return max(0, RestDebtPolicy.skipDelay - now.timeIntervalSince(session.startedAt))
    }

    private var skipAvailable: Bool { skipDelayRemaining <= 0 }

    private var reminderMessage: String? {
        guard session.restDebt > 0 else { return nil }
        var parts = ["今天还欠 \(formattedRestDebt(session.restDebt))休息"]
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
        return settings.showSkipButton ? "跳过" : nil
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
                progress: max(0, deadline.timeIntervalSince(now)) / max(1, settings.duration(for: kind)),
                content: content,
                settings: settings,
                hasBackgroundImage: backgroundPath != nil,
                reminderMessage: nil,
                snoozeAction: nil,
                secondaryTitle: "关闭预览",
                secondaryAction: close
            )
        }
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}
