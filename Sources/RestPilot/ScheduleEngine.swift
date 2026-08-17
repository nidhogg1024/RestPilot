import Foundation

@MainActor
protocol ScheduleEngineDelegate: AnyObject {
    func scheduleEngineDidTick(_ engine: ScheduleEngine)
    func scheduleEngineDidChangeState(_ engine: ScheduleEngine)
    func scheduleEngine(_ engine: ScheduleEngine, didEnterBreak kind: BreakKind)
    func scheduleEngine(_ engine: ScheduleEngine, didEndBreak outcome: BreakOutcome)
}

@MainActor
final class ScheduleEngine {
    weak var delegate: ScheduleEngineDelegate?

    private(set) var settings: AppSettings
    private(set) var snapshot: ScheduleSnapshot
    private var timer: Timer?

    init(settings: AppSettings, snapshot: ScheduleSnapshot? = nil, now: Date = Date()) {
        self.settings = settings
        if let snapshot {
            self.snapshot = snapshot
        } else {
            self.snapshot = ScheduleSnapshot(
                phase: .working,
                phaseStartedAt: now,
                deadline: now.addingTimeInterval(TimeInterval(max(1, settings.workMinutes) * 60)),
                phaseDuration: TimeInterval(max(1, settings.workMinutes) * 60)
            )
        }
        normalizeRestoredSnapshot()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
        if case .working = snapshot.phase {
            snapshot.plannedBreakKind = chooseNextScheduledBreak()
        }
        delegate?.scheduleEngineDidChangeState(self)
    }

    func viewState(now: Date = Date()) -> ScheduleViewState {
        let duration: TimeInterval
        switch snapshot.phase {
        case .stopped:
            duration = 0
        case .working, .snoozed:
            duration = snapshot.phaseDuration
        case .resting(let kind):
            duration = snapshot.phaseDuration > 0 ? snapshot.phaseDuration : settings.duration(for: kind)
        }
        let reference = snapshot.pausedAt ?? now
        return ScheduleViewState(
            phase: snapshot.phase,
            remaining: max(0, snapshot.deadline.timeIntervalSince(reference)),
            duration: duration,
            pauseReasons: snapshot.pauseReasons,
            content: currentContent()
        )
    }

    func nextScheduledBreakKind() -> BreakKind? {
        switch snapshot.phase {
        case .working:
            return snapshot.plannedBreakKind ?? chooseNextScheduledBreak()
        case .snoozed(let kind):
            return kind
        case .resting(let kind):
            return kind
        case .stopped:
            return chooseNextScheduledBreak()
        }
    }

    func activeBreakSession() -> BreakSession? {
        guard case .resting(let kind) = snapshot.phase,
              let id = snapshot.currentBreakID else { return nil }
        let fallback = kind == .eye ? "看看远处，让眼睛放松一下" : "站起来活动一下"
        return BreakSession(
            id: id,
            kind: kind,
            source: snapshot.currentBreakSource ?? .manual,
            startedAt: snapshot.phaseStartedAt,
            content: currentContent() ?? BreakContent(text: fallback),
            consecutiveSkippedBreaks: consecutiveSkippedBreaks()
        )
    }

    func remaining(for sessionID: UUID, now: Date = Date()) -> TimeInterval {
        guard snapshot.currentBreakID == sessionID,
              case .resting = snapshot.phase else { return 0 }
        let reference = snapshot.pausedAt ?? now
        return max(0, snapshot.deadline.timeIntervalSince(reference))
    }

    func todaySummary(now: Date = Date(), calendar: Calendar = .current) -> BreakSummary {
        snapshot.recentBreaks.reduce(into: BreakSummary()) { summary, record in
            guard calendar.isDate(record.endedAt, inSameDayAs: now) else { return }
            switch record.outcome {
            case .completed: summary.completed += 1
            case .skipped: summary.skipped += 1
            case .snoozed: summary.snoozed += 1
            case .cancelled: break
            }
        }
    }

    func consecutiveSkippedBreaks(now: Date = Date(), calendar: Calendar = .current) -> Int {
        var count = 0
        for record in snapshot.recentBreaks.reversed() {
            guard calendar.isDate(record.endedAt, inSameDayAs: now) else { break }
            guard record.source != .manual else { continue }
            switch record.outcome {
            case .skipped:
                count += 1
            case .snoozed, .cancelled:
                continue
            case .completed:
                return count
            }
        }
        return count
    }

    func setPaused(_ paused: Bool, reason: PauseReason, now: Date = Date()) {
        if paused {
            guard snapshot.pauseReasons.insert(reason).inserted else { return }
            if snapshot.pauseReasons.count == 1 { snapshot.pausedAt = now }
        } else {
            guard snapshot.pauseReasons.remove(reason) != nil else { return }
            if snapshot.pauseReasons.isEmpty, let pausedAt = snapshot.pausedAt {
                snapshot.deadline = snapshot.deadline.addingTimeInterval(now.timeIntervalSince(pausedAt))
                snapshot.pausedAt = nil
            }
        }
        delegate?.scheduleEngineDidChangeState(self)
    }

    func toggleManualPause() {
        if snapshot.phase == .stopped {
            resetWork()
            return
        }
        setPaused(!snapshot.pauseReasons.contains(.manual), reason: .manual)
    }

    func clearTransientPauseReasons(now: Date = Date()) {
        for reason in [PauseReason.idle, .screenLocked, .systemSleeping] {
            setPaused(false, reason: reason, now: now)
        }
    }

    func resetWork(now: Date = Date()) {
        beginWork(now: now)
        delegate?.scheduleEngineDidChangeState(self)
    }

    func stopSchedule(now: Date = Date()) {
        if case .resting = snapshot.phase {
            recordCurrentBreak(outcome: .cancelled, now: now)
            delegate?.scheduleEngine(self, didEndBreak: .cancelled)
        }
        snapshot.phase = .stopped
        snapshot.phaseStartedAt = now
        snapshot.deadline = now
        snapshot.phaseDuration = 0
        snapshot.pauseReasons = []
        snapshot.pausedAt = nil
        snapshot.currentContentID = nil
        snapshot.currentBreakID = nil
        snapshot.currentBreakSource = nil
        snapshot.plannedBreakKind = nil
        delegate?.scheduleEngineDidChangeState(self)
    }

    func startBreak(_ kind: BreakKind, now: Date = Date()) {
        beginBreak(kind, source: .manual, now: now)
    }

    func skipBreak(now: Date = Date()) {
        guard case .resting = snapshot.phase,
              snapshot.currentBreakSource != .manual else { return }
        finishBreak(outcome: .skipped, now: now)
    }

    func endManualBreak(now: Date = Date()) {
        guard case .resting = snapshot.phase,
              snapshot.currentBreakSource == .manual else { return }
        finishBreak(outcome: .cancelled, now: now)
    }

    func snoozeCurrentBreak(minutes: Int = 5, now: Date = Date()) {
        guard case .resting(let kind) = snapshot.phase,
              snapshot.currentBreakSource != .manual else { return }
        recordCurrentBreak(outcome: .snoozed, now: now)
        let duration = TimeInterval(max(1, minutes) * 60)
        snapshot.phase = .snoozed(kind)
        snapshot.phaseStartedAt = now
        snapshot.deadline = now.addingTimeInterval(duration)
        snapshot.phaseDuration = duration
        snapshot.pauseReasons = []
        snapshot.pausedAt = nil
        snapshot.currentBreakID = nil
        snapshot.currentBreakSource = nil
        snapshot.plannedBreakKind = nil
        delegate?.scheduleEngine(self, didEndBreak: .snoozed)
        delegate?.scheduleEngineDidChangeState(self)
    }

    func tick(now: Date = Date()) {
        guard snapshot.pauseReasons.isEmpty else {
            delegate?.scheduleEngineDidTick(self)
            return
        }
        guard snapshot.phase != .stopped else {
            delegate?.scheduleEngineDidTick(self)
            return
        }
        guard now >= snapshot.deadline else {
            delegate?.scheduleEngineDidTick(self)
            return
        }

        switch snapshot.phase {
        case .working:
            if let kind = snapshot.plannedBreakKind ?? chooseNextScheduledBreak() {
                beginBreak(kind, source: .scheduled, now: now)
            } else {
                stopSchedule(now: now)
            }
        case .snoozed(let kind):
            beginBreak(kind, source: .snoozed, now: now)
        case .resting:
            finishBreak(outcome: .completed, now: now)
        case .stopped:
            break
        }
    }

    private func normalizeRestoredSnapshot() {
        snapshot.scheduledEyeBreaksSinceStand = max(0, snapshot.scheduledEyeBreaksSinceStand)
        if snapshot.recentBreaks.count > 120 {
            snapshot.recentBreaks = Array(snapshot.recentBreaks.suffix(120))
        }

        switch snapshot.phase {
        case .working:
            if snapshot.plannedBreakKind == nil {
                snapshot.plannedBreakKind = chooseNextScheduledBreak()
            }
        case .resting(let kind):
            // Older snapshots did not persist a break identity or source. Treat
            // an already-visible legacy break as the scheduled break for this
            // cycle so relaunching cannot display the same kind a second time.
            if snapshot.currentBreakID == nil {
                snapshot.currentBreakID = UUID()
                snapshot.currentBreakSource = .scheduled
                advanceCadence(for: kind)
            }
            snapshot.plannedBreakKind = nil
        case .snoozed, .stopped:
            snapshot.plannedBreakKind = nil
        }
    }

    private func beginBreak(_ kind: BreakKind, source: BreakSource, now: Date) {
        if case .resting = snapshot.phase { return }
        if source == .scheduled {
            advanceCadence(for: kind)
        }
        let duration = settings.duration(for: kind)
        snapshot.phase = .resting(kind)
        snapshot.phaseStartedAt = now
        snapshot.deadline = now.addingTimeInterval(duration)
        snapshot.phaseDuration = duration
        snapshot.pauseReasons = []
        snapshot.pausedAt = nil
        if source != .snoozed || snapshot.currentContentID == nil {
            snapshot.currentContentID = selectContent(for: kind)?.id
        }
        snapshot.currentBreakID = UUID()
        snapshot.currentBreakSource = source
        snapshot.plannedBreakKind = nil
        delegate?.scheduleEngine(self, didEnterBreak: kind)
        delegate?.scheduleEngineDidChangeState(self)
    }

    private func finishBreak(outcome: BreakOutcome, now: Date) {
        recordCurrentBreak(outcome: outcome, now: now)
        beginWork(now: now)
        delegate?.scheduleEngine(self, didEndBreak: outcome)
        delegate?.scheduleEngineDidChangeState(self)
    }

    private func beginWork(now: Date) {
        let duration = TimeInterval(max(1, settings.workMinutes) * 60)
        snapshot.phase = .working
        snapshot.phaseStartedAt = now
        snapshot.deadline = now.addingTimeInterval(duration)
        snapshot.phaseDuration = duration
        snapshot.pauseReasons = []
        snapshot.pausedAt = nil
        snapshot.currentContentID = nil
        snapshot.currentBreakID = nil
        snapshot.currentBreakSource = nil
        snapshot.plannedBreakKind = chooseNextScheduledBreak()
    }

    private func recordCurrentBreak(outcome: BreakOutcome, now: Date) {
        guard case .resting(let kind) = snapshot.phase,
              let id = snapshot.currentBreakID else { return }
        let elapsed = min(
            snapshot.phaseDuration,
            max(0, now.timeIntervalSince(snapshot.phaseStartedAt))
        )
        snapshot.recentBreaks.append(BreakRecord(
            id: id,
            kind: kind,
            source: snapshot.currentBreakSource ?? .manual,
            startedAt: snapshot.phaseStartedAt,
            endedAt: now,
            plannedDuration: snapshot.phaseDuration,
            presentedDuration: elapsed,
            outcome: outcome
        ))
        if snapshot.recentBreaks.count > 120 {
            snapshot.recentBreaks.removeFirst(snapshot.recentBreaks.count - 120)
        }
    }

    private func chooseNextScheduledBreak() -> BreakKind? {
        if !settings.eyeEnabled && !settings.standEnabled { return nil }
        guard settings.standEnabled else { return settings.eyeEnabled ? .eye : nil }
        guard settings.eyeEnabled else { return .stand }
        let threshold = max(1, settings.standAfterEyeBreaks)
        return snapshot.scheduledEyeBreaksSinceStand >= threshold ? .stand : .eye
    }

    private func advanceCadence(for kind: BreakKind) {
        switch kind {
        case .eye:
            snapshot.scheduledEyeBreaksSinceStand += 1
        case .stand:
            snapshot.scheduledEyeBreaksSinceStand = 0
        }
    }

    private func selectContent(for kind: BreakKind) -> BreakContent? {
        let values = settings.contents(for: kind)
        guard !values.isEmpty else { return nil }
        if values.count == 1 { return values[0] }
        let alternatives = values.filter { $0.id != snapshot.currentContentID }
        return alternatives.randomElement() ?? values.randomElement()
    }

    private func currentContent() -> BreakContent? {
        let kind: BreakKind
        switch snapshot.phase {
        case .resting(let value), .snoozed(let value):
            kind = value
        case .working, .stopped:
            return nil
        }
        let values = settings.contents(for: kind)
        return values.first { $0.id == snapshot.currentContentID } ?? values.first
    }
}
