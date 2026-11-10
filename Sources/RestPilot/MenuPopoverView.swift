import AppKit
import SwiftUI

struct MenuPopoverView: View {
    let engine: ScheduleEngine
    let settings: AppSettings
    let openSettings: () -> Void
    @State private var now = Date()

    var body: some View {
        let state = engine.viewState(now: now)
        let summary = engine.todaySummary(now: now)
        let debt = engine.restDebt(now: now)
        VStack(spacing: 10) {
            SoftCard(padding: 16, cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    statusRow(state)
                    timerRow(state)
                    progressBar(state)
                    activitySummaryRow(summary, debt: debt)
                }
            }
            if settings.eyeEnabled || settings.standEnabled {
                quickBreakRow
            } else {
                noPlanHint
            }
            Spacer(minLength: 0)
            footerRow(state)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(width: MenuPopoverMetrics.width, height: MenuPopoverMetrics.height)
        .background(RestPilotTheme.canvas)
        .tint(RestPilotTheme.active)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func statusRow(_ state: ScheduleViewState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(state))
                .frame(width: 6, height: 6)
            Text(statusLabel(state))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RestPilotTheme.inkSecondary)
            Spacer()
        }
    }

    private func timerRow(_ state: ScheduleViewState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.isStopped ? "--:--" : formattedCountdown(state.remaining))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.6)
                    .foregroundStyle(RestPilotTheme.ink)
                Text(contextLine(state))
                    .font(.system(size: 12))
                    .foregroundStyle(RestPilotTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                engine.toggleManualPause()
            } label: {
                Image(systemName: primaryActionIcon(state))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RestPilotTheme.active)
                    .frame(width: 44, height: 44)
                    .background(RestPilotTheme.activeSurface, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(SoftPressStyle())
            .help(primaryActionTitle(state))
            .accessibilityLabel(primaryActionTitle(state))
        }
    }

    private func progressBar(_ state: ScheduleViewState) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(RestPilotTheme.fill)
                Capsule()
                    .fill(statusColor(state))
                    .frame(width: max(4, proxy.size.width * progress(state)))
                    .opacity(progress(state) > 0 ? 1 : 0)
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.3), value: progress(state))
    }

    private func activitySummaryRow(_ summary: BreakSummary, debt: TimeInterval) -> some View {
        HStack(spacing: 0) {
            Text("今日完成 \(summary.completed)")
            Spacer(minLength: 8)
            Text("跳过 \(summary.skipped)")
            Spacer(minLength: 8)
            if debt > 0 {
                Text("还欠 \(formattedRestDebt(debt))")
                    .fontWeight(.medium)
                    .foregroundStyle(RestPilotTheme.active)
            } else {
                Text("延后 \(summary.snoozed)")
            }
        }
        .font(.system(size: 11.5))
        .monospacedDigit()
        .foregroundStyle(RestPilotTheme.inkSecondary)
        .lineLimit(1)
    }

    private var quickBreakRow: some View {
        HStack(spacing: 8) {
            if settings.eyeEnabled {
                quickBreakButton("眼睛休息", systemImage: "eye") { engine.startBreak(.eye) }
            }
            if settings.standEnabled {
                quickBreakButton("站立休息", systemImage: "figure.walk") { engine.startBreak(.stand) }
            }
        }
    }

    /// Shown in place of the quick-break buttons when both plans are off.
    private var noPlanHint: some View {
        Button(action: openSettings) {
            Text("还没有启用休息计划，去设置里打开")
                .font(.system(size: 12))
                .foregroundStyle(RestPilotTheme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RestPilotTheme.fill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    private func quickBreakButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(RestPilotTheme.active)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RestPilotTheme.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(SoftSurface(cornerRadius: 13, shadowRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    private func footerRow(_ state: ScheduleViewState) -> some View {
        HStack(spacing: 2) {
            footerButton("重新计时") { engine.resetWork() }
            if !state.isStopped {
                footerButton("停止") { engine.stopSchedule() }
            }
            Spacer()
            footerIcon("gearshape", help: "设置", action: openSettings)
            footerIcon("power", help: "退出 RestPilot") { NSApplication.shared.terminate(nil) }
        }
        .foregroundStyle(RestPilotTheme.inkSecondary)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }

    private func footerIcon(
        _ systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func contextLine(_ state: ScheduleViewState) -> String {
        if state.isStopped { return "计时已停止" }
        if case .resting = state.phase { return state.content?.text ?? "休息一下" }
        if case .snoozed(let kind) = state.phase { return "后再次提醒\(kind.displayName)" }
        guard let kind = engine.nextScheduledBreakKind() else { return "未启用休息计划" }
        switch kind {
        case .eye: return "后休息眼睛 \(settings.eyeBreakSeconds) 秒"
        case .stand: return "后站起来活动 \(settings.standBreakMinutes) 分钟"
        }
    }

    private func progress(_ state: ScheduleViewState) -> Double {
        guard state.duration > 0 else { return 0 }
        return min(1, max(0, 1 - state.remaining / state.duration))
    }

    private func statusLabel(_ state: ScheduleViewState) -> String {
        if state.isStopped { return "已停止" }
        if state.isPaused { return "已暂停" }
        if case .resting = state.phase { return "休息中" }
        if case .snoozed = state.phase { return "等待提醒" }
        return "专注中"
    }

    private func statusColor(_ state: ScheduleViewState) -> Color {
        if state.isStopped { return RestPilotTheme.inkTertiary }
        if state.isPaused { return RestPilotTheme.inkTertiary }
        if case .snoozed = state.phase { return RestPilotTheme.warning }
        return RestPilotTheme.active
    }

    private func primaryActionTitle(_ state: ScheduleViewState) -> String {
        if state.isStopped { return "开始" }
        return state.isPaused ? "继续" : "暂停"
    }

    private func primaryActionIcon(_ state: ScheduleViewState) -> String {
        state.isStopped || state.isPaused ? "play.fill" : "pause.fill"
    }
}
