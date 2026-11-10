import Foundation
import AppKit
import SwiftUI
import Testing
@testable import RestPilot

@MainActor
@Test func pauseExtendsDeadlineByPausedDuration() {
    let start = Date(timeIntervalSince1970: 1_000)
    let engine = ScheduleEngine(settings: .default, now: start)
    let originalDeadline = engine.snapshot.deadline

    engine.setPaused(true, reason: .manual, now: start.addingTimeInterval(10))
    engine.setPaused(false, reason: .manual, now: start.addingTimeInterval(40))

    #expect(engine.snapshot.deadline == originalDeadline.addingTimeInterval(30))
}

@MainActor
@Test func overlappingPauseReasonsResumeOnlyAfterAllClear() {
    let start = Date(timeIntervalSince1970: 2_000)
    let engine = ScheduleEngine(settings: .default, now: start)

    engine.setPaused(true, reason: .idle, now: start.addingTimeInterval(10))
    engine.setPaused(true, reason: .screenLocked, now: start.addingTimeInterval(20))
    engine.setPaused(false, reason: .idle, now: start.addingTimeInterval(30))
    #expect(engine.snapshot.pausedAt != nil)
    engine.setPaused(false, reason: .screenLocked, now: start.addingTimeInterval(50))

    #expect(engine.snapshot.pausedAt == nil)
    #expect(engine.snapshot.pauseReasons.isEmpty)
    #expect(engine.snapshot.deadline == start.addingTimeInterval(20 * 60 + 40))
}

@MainActor
@Test func workDeadlineStartsEyeBreak() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    let start = Date(timeIntervalSince1970: 3_000)
    let engine = ScheduleEngine(settings: settings, now: start)

    engine.tick(now: start.addingTimeInterval(61))

    #expect(engine.snapshot.phase == .resting(.eye))
}

@MainActor
@Test func standBreakAfterConfiguredEyeBreakCount() {
    var settings = AppSettings.default
    settings.standAfterEyeBreaks = 1
    settings.eyeBreakSeconds = 5
    let start = Date(timeIntervalSince1970: 4_000)
    let engine = ScheduleEngine(settings: settings, now: start)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.snapshot.phase == .resting(.eye))
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))

    #expect(engine.snapshot.phase == .resting(.stand))
}

@MainActor
@Test func standBreakResetsScheduledEyeBreakCadence() {
    var settings = AppSettings.default
    settings.standAfterEyeBreaks = 1
    settings.eyeBreakSeconds = 5
    settings.standBreakMinutes = 1
    let start = Date(timeIntervalSince1970: 5_000)
    let engine = ScheduleEngine(settings: settings, now: start)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.snapshot.phase == .resting(.stand))
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))

    #expect(engine.snapshot.phase == .working)
    #expect(engine.snapshot.scheduledEyeBreaksSinceStand == 0)
    #expect(engine.nextScheduledBreakKind() == .eye)
}

@MainActor
@Test func configuredTwoEyeBreaksProducesEyeEyeStandWithoutExtraEyeBreak() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 5
    settings.standAfterEyeBreaks = 2
    settings.standBreakMinutes = 1
    let engine = ScheduleEngine(settings: settings, now: Date(timeIntervalSince1970: 5_500))
    var observed: [BreakKind] = []

    for _ in 0..<3 {
        engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
        guard case .resting(let kind) = engine.snapshot.phase else {
            Issue.record("工作周期结束后没有进入休息")
            return
        }
        observed.append(kind)
        engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
        #expect(engine.snapshot.phase == .working)
    }

    #expect(observed == [.eye, .eye, .stand])
}

@MainActor
@Test func plannedStandBreakSurvivesRelaunchAfterSecondEyeBreak() throws {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 5
    settings.standAfterEyeBreaks = 2
    let engine = ScheduleEngine(settings: settings, now: Date(timeIntervalSince1970: 5_600))

    for _ in 0..<2 {
        engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
        #expect(engine.snapshot.phase == .resting(.eye))
        engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    }
    #expect(engine.nextScheduledBreakKind() == .stand)

    let data = try JSONEncoder().encode(engine.snapshot)
    let restoredSnapshot = try JSONDecoder().decode(ScheduleSnapshot.self, from: data)
    let restored = ScheduleEngine(settings: settings, snapshot: restoredSnapshot)
    restored.tick(now: restored.snapshot.deadline.addingTimeInterval(1))

    #expect(restored.snapshot.phase == .resting(.stand))
}

@MainActor
@Test func skippedBreakIsRecordedButStillAdvancesScheduledCadence() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 20
    settings.standAfterEyeBreaks = 2
    let start = Date(timeIntervalSince1970: 5_700)
    let engine = ScheduleEngine(settings: settings, now: start)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    let firstSkipAt = engine.snapshot.phaseStartedAt.addingTimeInterval(2)
    engine.skipBreak(now: firstSkipAt)
    #expect(engine.restDebt(now: firstSkipAt) == 18)
    #expect(engine.nextScheduledBreakKind() == .eye)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    let secondSkipAt = engine.snapshot.phaseStartedAt.addingTimeInterval(2)
    engine.skipBreak(now: secondSkipAt)

    #expect(engine.restDebt(now: secondSkipAt) == 36)
    #expect(engine.nextScheduledBreakKind() == .stand)
    #expect(engine.todaySummary(now: secondSkipAt).skipped == 2)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.snapshot.phase == .resting(.stand))
}

@MainActor
@Test func manualBreakDoesNotAdvanceAutomaticStandCadence() {
    var settings = AppSettings.default
    settings.standAfterEyeBreaks = 1
    settings.eyeBreakSeconds = 5
    let start = Date(timeIntervalSince1970: 5_900)
    let engine = ScheduleEngine(settings: settings, now: start)

    engine.startBreak(.eye, now: start)
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))

    #expect(engine.snapshot.scheduledEyeBreaksSinceStand == 0)
    #expect(engine.nextScheduledBreakKind() == .eye)
    #expect(engine.snapshot.recentBreaks.last?.source == .manual)
}

@MainActor
@Test func snoozedBreakReturnsAsSameKindWithoutAdvancingCadenceTwice() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 5
    settings.standAfterEyeBreaks = 2
    settings.strengthenSkipReminders = false
    let engine = ScheduleEngine(settings: settings, now: Date(timeIntervalSince1970: 6_100))

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.snapshot.scheduledEyeBreaksSinceStand == 1)
    #expect(engine.activeBreakSession()?.allowsSnooze == true)
    #expect(engine.restDebt(now: engine.snapshot.phaseStartedAt) == 0)
    let snoozeAt = engine.snapshot.phaseStartedAt.addingTimeInterval(1)
    engine.snoozeCurrentBreak(minutes: 5, now: snoozeAt)

    #expect(engine.snapshot.phase == .snoozed(.eye))
    #expect(engine.snapshot.deadline == snoozeAt.addingTimeInterval(5 * 60))
    #expect(engine.snapshot.recentBreaks.last?.outcome == .snoozed)
    let repeatedBreakAt = engine.snapshot.deadline.addingTimeInterval(1)
    engine.tick(now: repeatedBreakAt)

    #expect(engine.snapshot.phase == .resting(.eye))
    #expect(engine.snapshot.currentBreakSource == .snoozed)
    #expect(engine.snapshot.scheduledEyeBreaksSinceStand == 1)
    let completedAt = engine.snapshot.deadline.addingTimeInterval(1)
    engine.tick(now: completedAt)

    #expect(engine.snapshot.phase == .working)
    #expect(engine.snapshot.phaseStartedAt == completedAt)
    #expect(engine.snapshot.deadline == completedAt.addingTimeInterval(60))
    #expect(engine.nextScheduledBreakKind() == .eye)
}

/// A skipped 5-minute stand break shown for 90 seconds owes the remaining
/// 210 seconds; the partial rest is credited automatically.
@MainActor
@Test func partialStandBreakOwesOnlyTheUnshownRemainder() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeEnabled = false
    settings.standBreakMinutes = 5
    let engine = ScheduleEngine(settings: settings, now: Date(timeIntervalSince1970: 6_300))

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.snapshot.phase == .resting(.stand))
    let skippedAt = engine.snapshot.phaseStartedAt.addingTimeInterval(90)
    engine.skipBreak(now: skippedAt)

    #expect(engine.restDebt(now: skippedAt) == 210)
}

/// Completing a short eye break pays the debt down by its length instead of
/// clearing a much larger skipped stand break. Just under five minutes owed
/// already earns the first 20-second extension, which is paid back too.
@MainActor
@Test func completedBreakPaysDebtWithoutClearingIt() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 20
    settings.standAfterEyeBreaks = 1
    settings.standBreakMinutes = 5
    let engine = ScheduleEngine(
        settings: settings,
        snapshot: ScheduleSnapshot(
            phase: .working,
            phaseStartedAt: Date(timeIntervalSince1970: 6_400),
            deadline: Date(timeIntervalSince1970: 6_460),
            phaseDuration: 60,
            scheduledEyeBreaksSinceStand: 1
        )
    )

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.snapshot.phase == .resting(.stand))
    let skippedAt = engine.snapshot.phaseStartedAt.addingTimeInterval(2)
    engine.skipBreak(now: skippedAt)
    #expect(engine.restDebt(now: skippedAt) == 298)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.snapshot.phase == .resting(.eye))
    #expect(engine.snapshot.phaseDuration == 40)
    let completedAt = engine.snapshot.deadline.addingTimeInterval(1)
    engine.tick(now: completedAt)

    #expect(engine.restDebt(now: completedAt) == 258)
}

@MainActor
@Test func restTakenWithoutDebtIsNotBanked() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 20
    let engine = ScheduleEngine(settings: settings, now: Date(timeIntervalSince1970: 6_500))

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.restDebt(now: engine.snapshot.phaseStartedAt) == 0)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    let skippedAt = engine.snapshot.phaseStartedAt.addingTimeInterval(2)
    engine.skipBreak(now: skippedAt)

    #expect(engine.restDebt(now: skippedAt) == 18)
}

@MainActor
@Test func longAwayPeriodPaysDebtButShortOrManualPauseDoesNot() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeEnabled = false
    settings.standBreakMinutes = 5
    let engine = ScheduleEngine(settings: settings, now: Date(timeIntervalSince1970: 6_600))

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    let skippedAt = engine.snapshot.phaseStartedAt.addingTimeInterval(2)
    engine.skipBreak(now: skippedAt)
    #expect(engine.restDebt(now: skippedAt) == 298)

    let shortLockAt = skippedAt.addingTimeInterval(10)
    engine.setPaused(true, reason: .screenLocked, now: shortLockAt)
    engine.setPaused(false, reason: .screenLocked, now: shortLockAt.addingTimeInterval(5 * 60))
    #expect(engine.snapshot.awayPeriods.isEmpty)
    #expect(engine.restDebt(now: shortLockAt.addingTimeInterval(5 * 60)) == 298)

    let manualPauseAt = shortLockAt.addingTimeInterval(6 * 60)
    engine.setPaused(true, reason: .manual, now: manualPauseAt)
    engine.setPaused(false, reason: .manual, now: manualPauseAt.addingTimeInterval(20 * 60))
    #expect(engine.snapshot.awayPeriods.isEmpty)

    let awayAt = manualPauseAt.addingTimeInterval(21 * 60)
    engine.setPaused(true, reason: .idle, now: awayAt)
    engine.setPaused(true, reason: .screenLocked, now: awayAt.addingTimeInterval(60))
    engine.setPaused(false, reason: .idle, now: awayAt.addingTimeInterval(10 * 60))
    #expect(engine.snapshot.awayStartedAt == awayAt)
    let backAt = awayAt.addingTimeInterval(16 * 60)
    engine.setPaused(false, reason: .screenLocked, now: backAt)

    #expect(engine.snapshot.awayPeriods == [AwayPeriod(startedAt: awayAt, endedAt: backAt)])
    #expect(engine.restDebt(now: backAt) == 0)
}

@MainActor
@Test func debtExtendsAutomaticBreaksWithinCapsButNotManualOnes() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 20
    settings.standAfterEyeBreaks = 1
    settings.standBreakMinutes = 5
    let start = Date(timeIntervalSince1970: 7_100)
    // Two skipped stand breaks earlier today: about ten minutes owed.
    let skipped = (0..<2).map { index in
        BreakRecord(
            id: UUID(),
            kind: .stand,
            source: .scheduled,
            startedAt: start.addingTimeInterval(Double(index) * 600 - 1_300),
            endedAt: start.addingTimeInterval(Double(index) * 600 - 1_298),
            plannedDuration: 300,
            presentedDuration: 2,
            outcome: .skipped
        )
    }
    let engine = ScheduleEngine(
        settings: settings,
        snapshot: ScheduleSnapshot(
            phase: .working,
            phaseStartedAt: start,
            deadline: start.addingTimeInterval(60),
            phaseDuration: 60,
            recentBreaks: skipped
        )
    )
    #expect(engine.restDebt(now: start) == 596)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.snapshot.phase == .resting(.eye))
    #expect(engine.snapshot.phaseDuration == 20 + 20)
    let session = engine.activeBreakSession(now: engine.snapshot.phaseStartedAt)
    #expect(session?.restDebt == 596)
    #expect(session?.extendedBy == 20)
    #expect(session?.delaysSkip == true)
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    #expect(engine.restDebt(now: engine.snapshot.phaseStartedAt) == 556)

    engine.startBreak(.stand, now: engine.snapshot.phaseStartedAt.addingTimeInterval(5))
    #expect(engine.snapshot.phaseDuration == 300)
    #expect(engine.activeBreakSession()?.delaysSkip == false)
}

@MainActor
@Test func disablingRestDebtRemovesExtensionAndReminder() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 20
    settings.strengthenSkipReminders = false
    let start = Date(timeIntervalSince1970: 7_200)
    let engine = ScheduleEngine(
        settings: settings,
        snapshot: ScheduleSnapshot(
            phase: .working,
            phaseStartedAt: start,
            deadline: start.addingTimeInterval(60),
            phaseDuration: 60,
            recentBreaks: [BreakRecord(
                id: UUID(),
                kind: .stand,
                source: .scheduled,
                startedAt: start.addingTimeInterval(-700),
                endedAt: start.addingTimeInterval(-698),
                plannedDuration: 300,
                presentedDuration: 2,
                outcome: .skipped
            )]
        )
    )

    #expect(engine.restDebt(now: start) == 0)
    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))

    #expect(engine.snapshot.phaseDuration == 20)
    #expect(engine.activeBreakSession()?.delaysSkip == false)
}

@Test func restDebtPolicyStepsAreCapped() {
    #expect(RestDebtPolicy.extraDuration(for: .eye, debt: 2 * 60) == 0)
    #expect(RestDebtPolicy.extraDuration(for: .eye, debt: 3 * 60) == 20)
    #expect(RestDebtPolicy.extraDuration(for: .eye, debt: 45 * 60) == 40)
    #expect(RestDebtPolicy.extraDuration(for: .stand, debt: 9 * 60) == 0)
    #expect(RestDebtPolicy.extraDuration(for: .stand, debt: 10 * 60) == 60)
    #expect(RestDebtPolicy.extraDuration(for: .stand, debt: 60 * 60) == 120)
    #expect(formattedRestDebt(18) == "18 秒")
    #expect(formattedRestDebt(59.4) == "59 秒")
    #expect(formattedRestDebt(59.6) == "1 分钟")
    #expect(formattedRestDebt(298) == "5 分钟")
    #expect(formattedRestDebt(23 * 60 + 40) == "24 分钟")
}

@MainActor
@Test func snoozeDoesNotChangeDebtAndLaterSkipAddsToIt() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 5
    settings.standAfterEyeBreaks = 10
    let start = Date(timeIntervalSince1970: 100_000)
    let engine = ScheduleEngine(settings: settings, now: start)

    for _ in 0..<2 {
        engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
        engine.skipBreak(now: engine.snapshot.phaseStartedAt.addingTimeInterval(1))
    }
    let secondSkipAt = engine.snapshot.phaseStartedAt
    #expect(engine.restDebt(now: secondSkipAt) == 8)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    let snoozedAt = engine.snapshot.phaseStartedAt.addingTimeInterval(1)
    engine.snoozeCurrentBreak(minutes: 5, now: snoozedAt)
    #expect(engine.restDebt(now: snoozedAt) == 8)

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    let thirdSkipAt = engine.snapshot.phaseStartedAt.addingTimeInterval(1)
    engine.skipBreak(now: thirdSkipAt)
    #expect(engine.restDebt(now: thirdSkipAt) == 12)
}

@MainActor
@Test func restDebtDoesNotCarryIntoNextDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeBreakSeconds = 5
    settings.standAfterEyeBreaks = 10
    let firstDay = Date(timeIntervalSince1970: 100_000)
    let secondDay = firstDay.addingTimeInterval(24 * 60 * 60)
    let engine = ScheduleEngine(settings: settings, now: firstDay)

    for _ in 0..<2 {
        engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
        engine.skipBreak(now: engine.snapshot.phaseStartedAt.addingTimeInterval(1))
    }
    let firstDayCheckAt = engine.snapshot.phaseStartedAt

    #expect(engine.restDebt(now: firstDayCheckAt, calendar: calendar) == 8)
    #expect(engine.restDebt(now: secondDay, calendar: calendar) == 0)

    let secondDayEngine = ScheduleEngine(
        settings: settings,
        snapshot: ScheduleSnapshot(
            phase: .working,
            phaseStartedAt: secondDay,
            deadline: secondDay.addingTimeInterval(60),
            phaseDuration: 60,
            scheduledEyeBreaksSinceStand: engine.snapshot.scheduledEyeBreaksSinceStand,
            recentBreaks: engine.snapshot.recentBreaks
        )
    )
    secondDayEngine.tick(now: secondDayEngine.snapshot.deadline.addingTimeInterval(1))
    let secondDaySkipAt = secondDayEngine.snapshot.phaseStartedAt.addingTimeInterval(1)
    secondDayEngine.skipBreak(now: secondDaySkipAt)
    #expect(secondDayEngine.restDebt(now: secondDaySkipAt, calendar: calendar) == 4)
}

@MainActor
@Test func manualBreakCanOnlyEndAndItsRestPaysDebt() {
    let start = Date(timeIntervalSince1970: 200_000)
    let engine = ScheduleEngine(settings: .default, now: start)

    engine.startBreak(.eye, now: start)
    #expect(engine.activeBreakSession()?.allowsSnooze == false)

    engine.snoozeCurrentBreak(minutes: 5, now: start.addingTimeInterval(1))
    #expect(engine.snapshot.phase == .resting(.eye))
    #expect(engine.snapshot.recentBreaks.isEmpty)

    engine.skipBreak(now: start.addingTimeInterval(2))
    #expect(engine.snapshot.phase == .resting(.eye))
    #expect(engine.snapshot.recentBreaks.isEmpty)

    engine.endManualBreak(now: start.addingTimeInterval(3))
    #expect(engine.snapshot.phase == .working)
    #expect(engine.snapshot.recentBreaks.last?.source == .manual)
    #expect(engine.snapshot.recentBreaks.last?.outcome == .cancelled)
    #expect(engine.restDebt(now: start.addingTimeInterval(3)) == 0)
}

@MainActor
@Test func manualRestPaysDownExistingDebt() {
    var settings = AppSettings.default
    settings.workMinutes = 1
    settings.eyeEnabled = false
    settings.standBreakMinutes = 5
    let engine = ScheduleEngine(settings: settings, now: Date(timeIntervalSince1970: 210_000))

    engine.tick(now: engine.snapshot.deadline.addingTimeInterval(1))
    let skippedAt = engine.snapshot.phaseStartedAt.addingTimeInterval(2)
    engine.skipBreak(now: skippedAt)
    #expect(engine.restDebt(now: skippedAt) == 298)

    engine.startBreak(.stand, now: skippedAt.addingTimeInterval(60))
    let endedAt = skippedAt.addingTimeInterval(60 + 100)
    engine.endManualBreak(now: endedAt)

    #expect(engine.restDebt(now: endedAt) == 198)
}

@Test func overlayActionLayoutStaysSeparatedOnConnectedDisplays() throws {
    for height: CGFloat in [1_080, 1_117, 1_152] {
        let positions = BreakPresentationLayout.positions(
            containerHeight: height,
            contentHeight: 631,
            actionHeight: OverlayActionControlSize.regular.height
        )
        let actionCenter = try #require(positions.actionCenterY)
        let halfAction = OverlayActionControlSize.regular.height / 2
        let visibleGap = actionCenter - halfAction - (positions.contentCenterY + 315.5)

        #expect(visibleGap >= 64)
        #expect(actionCenter + halfAction <= height - 72)
    }
}

@Test func compactOverlayPreviewUsesExplicitLegibleControlMetrics() throws {
    let positions = BreakPresentationLayout.positions(
        containerHeight: 360,
        contentHeight: 188,
        actionHeight: OverlayActionControlSize.compact.height
    )
    let actionCenter = try #require(positions.actionCenterY)
    let visibleGap = actionCenter
        - OverlayActionControlSize.compact.height / 2
        - (positions.contentCenterY + 94)

    #expect(visibleGap >= 32)
    #expect(OverlayActionControlSize.compact.fontSize == 13)
    #expect(OverlayActionControlSize.regular.fontSize == 15)
    #expect(OverlayActionControlSize.regular.height == 44)
}

@MainActor
@Test func overlayRendersAtConnectedDisplaySizes() throws {
    let displaySizes: [(name: String, size: CGSize)] = [
        ("laptop", CGSize(width: 1_728, height: 1_117)),
        ("external-1080p", CGSize(width: 1_920, height: 1_080)),
        ("external-2k", CGSize(width: 2_048, height: 1_152))
    ]
    let outputDirectory = ProcessInfo.processInfo.environment[
        "RESTPILOT_VISUAL_OUTPUT_DIR"
    ]

    if let outputDirectory {
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )
    }

    for display in displaySizes {
        let settings = AppSettings.default
        // One display also shows the rest-debt line so that state is covered.
        let owesRest = display.name == "laptop"
        let view = ZStack {
            OverlayBackground(settings: settings, backgroundPath: nil)
            BreakPresentation(
                eyebrow: "眼睛休息",
                time: owesRest ? "00:26" : "00:20",
                progress: owesRest ? 0.65 : 1,
                content: BreakContent(text: "看看远处，让眼睛放松一下"),
                settings: settings,
                hasBackgroundImage: false,
                reminderMessage: owesRest ? "今天还欠 23 分钟休息 · 这次延长 20 秒" : nil,
                snoozeAction: {},
                secondaryTitle: "跳过",
                secondaryAction: {}
            )
        }
        .frame(width: display.size.width, height: display.size.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(display.size)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)

        #expect(image.size == display.size)

        if let outputDirectory {
            let output = URL(fileURLWithPath: outputDirectory)
                .appendingPathComponent("\(display.name).png")
            try writePNG(image, to: output)
        }
    }

    // Photo backgrounds switch the whole presentation to light text. Bundle
    // resources are missing under `swift test`, so read the repo copy.
    let photo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Backgrounds/lake.jpg")
    if FileManager.default.fileExists(atPath: photo.path) {
        var settings = AppSettings.default
        settings.backgroundMode = .fixed
        let size = CGSize(width: 1_728, height: 1_117)
        let view = ZStack {
            OverlayBackground(settings: settings, backgroundPath: photo.path)
            BreakPresentation(
                eyebrow: "站立休息",
                time: "04:12",
                progress: 0.84,
                content: BreakContent(text: "站起来走一走"),
                settings: settings,
                hasBackgroundImage: true,
                reminderMessage: nil,
                snoozeAction: {},
                secondaryTitle: "跳过",
                secondaryAction: {}
            )
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        let image = try #require(renderer.nsImage)
        #expect(image.size == size)

        if let outputDirectory {
            try writePNG(
                image,
                to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("photo-background.png")
            )
        }
    }
}

@MainActor
@Test func settingsSemanticStatesRenderInLightAndDarkModes() throws {
    let outputDirectory = ProcessInfo.processInfo.environment[
        "RESTPILOT_VISUAL_OUTPUT_DIR"
    ]

    if let outputDirectory {
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )
    }

    var disabledPlans = AppSettings.default
    disabledPlans.eyeEnabled = false
    disabledPlans.standEnabled = false
    disabledPlans.strengthenSkipReminders = false

    var mixedAppearance = AppSettings.default
    mixedAppearance.backgroundMode = .none
    mixedAppearance.showOnAllDisplays = true
    mixedAppearance.showSkipButton = false
    mixedAppearance.fadeInOverlay = true
    mixedAppearance.showCountdown = false
    mixedAppearance.showTimeInMenuBar = true
    mixedAppearance.playSoundWhenBreakEnds = false

    var mixedGeneral = AppSettings.default
    mixedGeneral.launchAtLogin = false
    mixedGeneral.pauseWhenLocked = true
    mixedGeneral.pauseWhenIdle = false

    var mixedContent = AppSettings.default
    mixedContent.eyeContents = [
        BreakContent(text: "看看远处，让眼睛放松一下"),
        BreakContent(text: "闭上眼睛，做三次缓慢呼吸", isEnabled: false)
    ]

    let variants: [(
        name: String,
        settings: AppSettings,
        selection: SettingsSection,
        colorScheme: ColorScheme,
        size: CGSize
    )] = [
        (
            "settings-plans-enabled-light",
            .default,
            .plans,
            .light,
            SettingsWindowMetrics.defaultSize
        ),
        (
            "settings-plans-disabled-dark",
            disabledPlans,
            .plans,
            .dark,
            CGSize(width: 940, height: 720)
        ),
        (
            "settings-general-mixed-light",
            mixedGeneral,
            .general,
            .light,
            CGSize(width: 800, height: 560)
        ),
        (
            "settings-appearance-mixed-dark",
            mixedAppearance,
            .appearance,
            .dark,
            CGSize(width: 800, height: 560)
        ),
        (
            "settings-content-mixed-light",
            mixedContent,
            .content,
            .light,
            SettingsWindowMetrics.defaultSize
        )
    ]

    for variant in variants {
        let view = PreferencesView(
            settings: variant.settings,
            initialSelection: variant.selection,
            onSave: { _ in },
            onPreview: { _, _ in }
        )
        .environment(\.colorScheme, variant.colorScheme)
        .frame(width: variant.size.width, height: variant.size.height)

        let image = try renderAppKitSnapshot(view, size: variant.size)

        #expect(image.size == variant.size)

        if let outputDirectory {
            let output = URL(fileURLWithPath: outputDirectory)
                .appendingPathComponent("\(variant.name).png")
            try writePNG(image, to: output)
        }
    }
}

/// Content wider than the window is centred by SwiftUI, which pushes the
/// sidebar past the left edge and the page past the right one. At the
/// narrowest window both edges must show nothing but the window ground.
@MainActor
@Test func settingsPagesStayInsideTheNarrowestWindow() throws {
    var rich = AppSettings.default
    rich.backgroundMode = .fixed
    rich.pauseWhenIdle = true
    rich.eyeContents = [
        BreakContent(text: "看看二十英尺外的东西，慢慢眨几次眼睛，让睫状肌彻底放松下来再回来"),
        BreakContent(text: "闭上眼睛，做三次缓慢呼吸", isEnabled: false)
    ]
    let size = CGSize(
        width: SettingsWindowMetrics.minWidth,
        height: SettingsWindowMetrics.minHeight
    )

    for section in SettingsSection.allCases {
        let view = PreferencesView(
            settings: rich,
            initialSelection: section,
            onSave: { _ in },
            onPreview: { _, _ in }
        )
        .environment(\.colorScheme, .light)
        .frame(width: size.width, height: size.height)
        let image = try renderAppKitSnapshot(view, size: size)
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)

        #expect(
            edgeStripIsUniform(bitmap, leading: true),
            "\(section.rawValue) is clipped at the left edge"
        )
        #expect(
            edgeStripIsUniform(bitmap, leading: false),
            "\(section.rawValue) is clipped at the right edge"
        )
    }
}

/// True when the outermost 4pt column on one side has a single colour.
private func edgeStripIsUniform(_ bitmap: NSBitmapImageRep, leading: Bool) -> Bool {
    let scale = max(1, bitmap.pixelsWide / Int(bitmap.size.width))
    let strip = 4 * scale
    let columns = leading
        ? Array(0..<strip)
        : Array((bitmap.pixelsWide - strip)..<bitmap.pixelsWide)
    guard let reference = bitmap.colorAt(x: columns[0], y: 0)?.usingColorSpace(.sRGB) else {
        return false
    }
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
        for x in columns {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            let distance = abs(color.redComponent - reference.redComponent)
                + abs(color.greenComponent - reference.greenComponent)
                + abs(color.blueComponent - reference.blueComponent)
            if distance > 0.03 { return false }
        }
    }
    return true
}

@MainActor
@Test func menuPopoverSemanticStatusesRender() throws {
    let outputDirectory = ProcessInfo.processInfo.environment[
        "RESTPILOT_VISUAL_OUTPUT_DIR"
    ]
    if let outputDirectory {
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )
    }

    let now = Date()
    let running = ScheduleEngine(
        settings: .default,
        now: now.addingTimeInterval(-5 * 60)
    )
    let paused = ScheduleEngine(settings: .default, now: now)
    paused.setPaused(true, reason: .manual, now: now)

    var shortCycle = AppSettings.default
    shortCycle.workMinutes = 1
    let snoozed = ScheduleEngine(
        settings: shortCycle,
        now: now.addingTimeInterval(-61)
    )
    snoozed.tick(now: now)
    snoozed.snoozeCurrentBreak(minutes: 5, now: now)

    let stopped = ScheduleEngine(settings: .default, now: now)
    stopped.stopSchedule(now: now)

    let variants: [(name: String, engine: ScheduleEngine)] = [
        ("menu-running", running),
        ("menu-paused", paused),
        ("menu-snoozed", snoozed),
        ("menu-stopped", stopped)
    ]
    let size = CGSize(
        width: MenuPopoverMetrics.width,
        height: MenuPopoverMetrics.height
    )

    for variant in variants {
        let view = MenuPopoverView(
            engine: variant.engine,
            settings: variant.engine.settings,
            openSettings: {}
        )
        .environment(\.colorScheme, .light)
        .frame(width: size.width, height: size.height)

        let image = try renderAppKitSnapshot(view, size: size)
        #expect(image.size == size)

        if let outputDirectory {
            let output = URL(fileURLWithPath: outputDirectory)
                .appendingPathComponent("\(variant.name).png")
            try writePNG(image, to: output)
        }
    }
}

@MainActor
@Test func disablingAllPlansStopsAtDeadline() {
    var settings = AppSettings.default
    settings.eyeEnabled = false
    settings.standEnabled = false
    settings.workMinutes = 1
    let start = Date(timeIntervalSince1970: 6_000)
    let engine = ScheduleEngine(settings: settings, now: start)

    engine.tick(now: start.addingTimeInterval(61))

    #expect(engine.snapshot.phase == .stopped)
}

@MainActor
@Test func startingFromStoppedBeginsFreshWorkCycle() {
    let start = Date(timeIntervalSince1970: 7_000)
    let engine = ScheduleEngine(settings: .default, now: start)
    engine.stopSchedule(now: start)

    engine.toggleManualPause()

    #expect(engine.snapshot.phase == .working)
    #expect(engine.snapshot.phaseDuration == 20 * 60)
}

@MainActor
@Test func currentCycleKeepsOriginalDurationAfterSettingsChange() {
    let start = Date(timeIntervalSince1970: 8_000)
    let engine = ScheduleEngine(settings: .default, now: start)
    var changed = AppSettings.default
    changed.workMinutes = 45

    engine.updateSettings(changed)

    #expect(engine.viewState(now: start).duration == 20 * 60)
    #expect(engine.snapshot.deadline == start.addingTimeInterval(20 * 60))
}

@Test func defaultPresentationUsesCalmLightIntegratedLayout() {
    let settings = AppSettings.default

    #expect(settings.backgroundMode == .none)
    #expect(settings.resolvedBackgroundPath() == nil)
    #expect(settings.overlayLayout == .minimal)
    #expect(settings.fadeInOverlay)
    #expect(settings.strengthenSkipReminders)
}

@Test func legacySnapshotMigratesCompletedEyeBreakCountIntoScheduledCadence() throws {
    let original = ScheduleSnapshot(scheduledEyeBreaksSinceStand: 2)
    let encoded = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "scheduledEyeBreaksSinceStand")
    object["completedEyeBreaks"] = 2
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let migrated = try JSONDecoder().decode(ScheduleSnapshot.self, from: legacyData)

    #expect(migrated.scheduledEyeBreaksSinceStand == 2)
}

@Test func snapshotWithoutAwayPeriodsDecodesAndRoundTripsThem() throws {
    let original = ScheduleSnapshot()
    let encoded = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "awayPeriods")
    object.removeValue(forKey: "awayStartedAt")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let legacy = try JSONDecoder().decode(ScheduleSnapshot.self, from: legacyData)
    #expect(legacy.awayPeriods.isEmpty)
    #expect(legacy.awayStartedAt == nil)

    let away = AwayPeriod(
        startedAt: Date(timeIntervalSince1970: 300_000),
        endedAt: Date(timeIntervalSince1970: 301_000)
    )
    let withAway = ScheduleSnapshot(awayPeriods: [away], awayStartedAt: Date(timeIntervalSince1970: 302_000))
    let restored = try JSONDecoder().decode(ScheduleSnapshot.self, from: JSONEncoder().encode(withAway))
    #expect(restored.awayPeriods == [away])
    #expect(restored.awayStartedAt == Date(timeIntervalSince1970: 302_000))
}

@Test func legacyExplicitBackgroundSelectionRemainsFixed() {
    var settings = AppSettings.default
    settings.selectedBackgroundID = BuiltInBackground.lake.rawValue

    #expect(settings.backgroundMode == .fixed)
    #expect(settings.selectedBackground == .lake)
}

@Test func countdownFormattingRoundsUpWithoutGoingNegative() {
    #expect(formattedCountdown(20) == "00:20")
    #expect(formattedCountdown(19.01) == "00:20")
    #expect(formattedCountdown(19) == "00:19")
    #expect(formattedCountdown(-1) == "00:00")
}

@MainActor
@Test func overlayPanelsAcceptInteractionWithoutBecomingMainWindows() {
    let panel = InteractiveOverlayPanel(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    let hostingView = OverlayHostingView(rootView: AnyView(EmptyView()))

    #expect(panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(hostingView.acceptsFirstMouse(for: nil))
}

private func writePNG(_ image: NSImage, to output: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: output)
}

@MainActor
private func renderAppKitSnapshot<Content: View>(
    _ view: Content,
    size: CGSize
) throws -> NSImage {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)

    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
    window.orderFront(nil)

    hostingView.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))

    let representation = try #require(
        hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
    )
    hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

    let image = NSImage(size: size)
    image.addRepresentation(representation)
    window.orderOut(nil)
    return image
}
