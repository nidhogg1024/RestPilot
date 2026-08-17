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
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                statusRow(state)
                timerRow(state)
                progressBar(state)
                nextBreakRow(state)
                if hasActivity(summary) {
                    activitySummaryRow(summary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()
            actionRow
        }
        .frame(width: MenuPopoverMetrics.width, height: MenuPopoverMetrics.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(RestPilotTheme.active)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func statusRow(_ state: ScheduleViewState) -> some View {
        HStack {
            Text(phaseTitle(state))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor(state))
                    .frame(width: 6, height: 6)
                Text(statusLabel(state))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(state))
            }
        }
    }

    private func timerRow(_ state: ScheduleViewState) -> some View {
        HStack(alignment: .center) {
            Text(state.isStopped ? "--:--" : formattedCountdown(state.remaining))
                .font(.system(size: 38, weight: .medium, design: .rounded))
                .monospacedDigit()
                .tracking(-0.8)

            Spacer()

            Button {
                engine.toggleManualPause()
            } label: {
                Label(primaryActionTitle(state), systemImage: primaryActionIcon(state))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func progressBar(_ state: ScheduleViewState) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(statusColor(state).opacity(0.82))
                    .frame(width: proxy.size.width * progress(state))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.3), value: progress(state))
    }

    private func nextBreakRow(_ state: ScheduleViewState) -> some View {
        HStack(spacing: 7) {
            Text(contextTitle(state))
                .foregroundStyle(.secondary)
            Text(contextDetail(state))
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }

    private func activitySummaryRow(_ summary: BreakSummary) -> some View {
        Text(activitySummaryText(summary))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hasActivity(_ summary: BreakSummary) -> Bool {
        summary.completed > 0 || summary.skipped > 0 || summary.snoozed > 0
    }

    private func activitySummaryText(_ summary: BreakSummary) -> String {
        var parts: [String] = []
        if summary.completed > 0 { parts.append("完成 \(summary.completed)") }
        if summary.skipped > 0 { parts.append("跳过 \(summary.skipped)") }
        if summary.snoozed > 0 { parts.append("延后 \(summary.snoozed)") }
        return "今日 " + parts.joined(separator: " · ")
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            Menu {
                if settings.eyeEnabled { Button("眼睛休息") { engine.startBreak(.eye) } }
                if settings.standEnabled { Button("站立休息") { engine.startBreak(.stand) } }
                Divider()
                Button("停止计时", role: .destructive) { engine.stopSchedule() }
            } label: {
                Label("休息", systemImage: "cup.and.saucer")
            }
            .menuStyle(.borderlessButton)

            Button { engine.resetWork() } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置")

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("退出 RestPilot")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 45)
    }

    private func nextBreakDescription() -> String {
        guard let kind = engine.nextScheduledBreakKind() else { return "未启用休息计划" }
        switch kind {
        case .eye: return "眼睛休息 · \(settings.eyeBreakSeconds) 秒"
        case .stand: return "站立休息 · \(settings.standBreakMinutes) 分钟"
        }
    }

    private func progress(_ state: ScheduleViewState) -> Double {
        guard state.duration > 0 else { return 0 }
        return min(1, max(0, 1 - state.remaining / state.duration))
    }

    private func phaseTitle(_ state: ScheduleViewState) -> String {
        if state.isPaused { return "已暂停" }
        switch state.phase {
        case .stopped: return "准备开始"
        case .working: return "专注中"
        case .snoozed: return "休息已延后"
        case .resting(let kind): return kind.displayName
        }
    }

    private func statusLabel(_ state: ScheduleViewState) -> String {
        if state.isStopped { return "已停止" }
        if state.isPaused { return "已暂停" }
        if case .resting = state.phase { return "休息中" }
        if case .snoozed = state.phase { return "等待提醒" }
        return "运行中"
    }

    private func statusColor(_ state: ScheduleViewState) -> Color {
        if state.isStopped { return Color.secondary.opacity(0.45) }
        if state.isPaused { return RestPilotTheme.warning }
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

    private func contextTitle(_ state: ScheduleViewState) -> String {
        if case .resting = state.phase { return "当前" }
        if case .snoozed = state.phase { return "到时" }
        return "下一次"
    }

    private func contextDetail(_ state: ScheduleViewState) -> String {
        if case .resting = state.phase {
            return state.content?.text ?? "休息一下"
        }
        if case .snoozed(let kind) = state.phase {
            return "\(kind.displayName)将再次出现"
        }
        return nextBreakDescription()
    }
}
