import Foundation

enum BreakKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case eye
    case stand

    var id: String { rawValue }
    var displayName: String { self == .eye ? "眼睛休息" : "站立休息" }
}

enum BreakSource: String, Codable, Sendable {
    case scheduled
    case manual
    case snoozed

    var displayName: String {
        switch self {
        case .scheduled: return "自动计划"
        case .manual: return "手动开始"
        case .snoozed: return "延后提醒"
        }
    }
}

enum BreakOutcome: String, Codable, Sendable {
    case completed
    case skipped
    case snoozed
    case cancelled
}

struct BreakRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: BreakKind
    var source: BreakSource
    var startedAt: Date
    var endedAt: Date
    var plannedDuration: TimeInterval
    var presentedDuration: TimeInterval
    var outcome: BreakOutcome
}

struct BreakSession: Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: BreakKind
    var source: BreakSource
    var startedAt: Date
    var content: BreakContent
    var consecutiveSkippedBreaks: Int

    var allowsSnooze: Bool { source != .manual }
}

struct BreakSummary: Equatable, Sendable {
    var completed = 0
    var skipped = 0
    var snoozed = 0
}

func formattedCountdown(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(ceil(interval)))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

struct BreakContent: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var imagePath: String? = nil
    var isEnabled = true
}

enum OverlayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case softGradient
    case frosted
    case dimmed

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .softGradient: return "柔和渐变"
        case .frosted: return "玻璃模糊"
        case .dimmed: return "深色专注"
        }
    }
}

enum OverlayLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case card
    case minimal

    var id: String { rawValue }
    var displayName: String { self == .card ? "卡片" : "极简" }
}

enum BackgroundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case fixed
    case random

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "柔和浅色"
        case .fixed: return "固定一张"
        case .random: return "每次随机"
        }
    }
}

enum BuiltInBackground: String, CaseIterable, Identifiable, Sendable {
    case ambient
    case window
    case mountains
    case lake
    case forest
    case clouds
    case interior

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ambient: return "呼吸光场"
        case .window: return "草甸溪流"
        case .mountains: return "层叠山谷"
        case .lake: return "柔光湖面"
        case .forest: return "林间远眺"
        case .clouds: return "海岸草坡"
        case .interior: return "静谧河湾"
        }
    }

    var resourcePath: String? {
        Bundle.main.url(forResource: rawValue, withExtension: "jpg", subdirectory: "Backgrounds")?.path
    }

    var thumbnailPath: String? {
        Bundle.main.url(forResource: rawValue, withExtension: "jpg", subdirectory: "BackgroundThumbnails")?.path
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var eyeEnabled = true
    var workMinutes = 20
    var eyeBreakSeconds = 20
    var standEnabled = true
    var standAfterEyeBreaks = 2
    var standBreakMinutes = 5

    var showTimeInMenuBar = true
    var playSoundWhenBreakEnds = true
    var endSoundName = "Glass"
    var fadeInOverlay = true
    var pauseWhenIdle = true
    var idleMinutes = 5
    var pauseWhenLocked = true
    var launchAtLogin = false

    var showSkipButton = true
    var showOnAllDisplays = true
    var overlayOpacity = 0.90
    var overlayStyle: OverlayStyle = .softGradient
    // Kept for decoding settings saved by older builds. The full-screen overlay
    // now always uses the integrated layout.
    var overlayLayout: OverlayLayout = .minimal
    var showCountdown = true
    var textScale = 1.0
    var imageScale = 1.0
    var contentOrderRandom = true
    // Optional storage keeps settings saved by older builds decodable.
    var strengthenSkipRemindersValue: Bool? = nil
    // Optional storage keeps settings saved by older builds decodable.
    var backgroundModeValue: BackgroundMode? = nil
    var selectedBackgroundID: String? = nil
    var customBackgroundPath: String? = nil
    var backgroundDimValue: Double? = nil

    var eyeContents = [BreakContent(text: "看看远处，让眼睛放松一下")]
    var standContents = [
        BreakContent(text: "站起来走一走"),
        BreakContent(text: "喝点水，活动一下肩颈"),
        BreakContent(text: "伸展上半身，做几次深呼吸")
    ]

    static let `default` = AppSettings()

    var strengthenSkipReminders: Bool {
        get { strengthenSkipRemindersValue ?? true }
        set { strengthenSkipRemindersValue = newValue }
    }

    var backgroundMode: BackgroundMode {
        get {
            if let backgroundModeValue { return backgroundModeValue }
            // Older settings did not persist a background mode. Treat a saved
            // selection as intentional, otherwise use the calm light default.
            return selectedBackgroundID == nil && customBackgroundPath == nil ? .none : .fixed
        }
        set { backgroundModeValue = newValue }
    }

    var selectedBackground: BuiltInBackground {
        get { BuiltInBackground(rawValue: selectedBackgroundID ?? "") ?? .ambient }
        set { selectedBackgroundID = newValue.rawValue }
    }

    var backgroundDim: Double {
        get { backgroundDimValue ?? 0.10 }
        set { backgroundDimValue = min(0.70, max(0, newValue)) }
    }

    func resolvedBackgroundPath(randomSource: () -> BuiltInBackground = {
        BuiltInBackground.allCases.randomElement() ?? .mountains
    }) -> String? {
        switch backgroundMode {
        case .none:
            return nil
        case .fixed:
            if selectedBackgroundID == "custom",
               let customBackgroundPath,
               FileManager.default.fileExists(atPath: customBackgroundPath) {
                return customBackgroundPath
            }
            return selectedBackground.resourcePath
        case .random:
            var paths = BuiltInBackground.allCases.compactMap(\.resourcePath)
            if let customBackgroundPath,
               FileManager.default.fileExists(atPath: customBackgroundPath) {
                paths.append(customBackgroundPath)
            }
            return paths.randomElement() ?? randomSource().resourcePath
        }
    }

    func duration(for kind: BreakKind) -> TimeInterval {
        switch kind {
        case .eye: return TimeInterval(max(1, eyeBreakSeconds))
        case .stand: return TimeInterval(max(1, standBreakMinutes) * 60)
        }
    }

    func contents(for kind: BreakKind) -> [BreakContent] {
        let values = kind == .eye ? eyeContents : standContents
        return values.filter(\.isEnabled)
    }
}

enum ActivePhase: Codable, Equatable, Sendable {
    case stopped
    case working
    case snoozed(BreakKind)
    case resting(BreakKind)
}

enum PauseReason: String, Codable, Hashable, Sendable {
    case manual
    case idle
    case screenLocked
    case systemSleeping
}

struct ScheduleSnapshot: Codable, Equatable, Sendable {
    var phase: ActivePhase = .working
    var phaseStartedAt = Date()
    var deadline = Date().addingTimeInterval(20 * 60)
    var phaseDuration: TimeInterval = 20 * 60
    var pauseReasons: Set<PauseReason> = []
    var pausedAt: Date? = nil
    var currentContentID: UUID? = nil
    var scheduledEyeBreaksSinceStand = 0
    var plannedBreakKind: BreakKind? = nil
    var currentBreakID: UUID? = nil
    var currentBreakSource: BreakSource? = nil
    var recentBreaks: [BreakRecord] = []

    private enum CodingKeys: String, CodingKey {
        case phase
        case phaseStartedAt
        case deadline
        case phaseDuration
        case pauseReasons
        case pausedAt
        case currentContentID
        case scheduledEyeBreaksSinceStand
        case plannedBreakKind
        case currentBreakID
        case currentBreakSource
        case consecutiveSkippedBreaks
        case recentBreaks
        case completedEyeBreaks
    }

    init(
        phase: ActivePhase = .working,
        phaseStartedAt: Date = Date(),
        deadline: Date = Date().addingTimeInterval(20 * 60),
        phaseDuration: TimeInterval = 20 * 60,
        pauseReasons: Set<PauseReason> = [],
        pausedAt: Date? = nil,
        currentContentID: UUID? = nil,
        scheduledEyeBreaksSinceStand: Int = 0,
        plannedBreakKind: BreakKind? = nil,
        currentBreakID: UUID? = nil,
        currentBreakSource: BreakSource? = nil,
        recentBreaks: [BreakRecord] = []
    ) {
        self.phase = phase
        self.phaseStartedAt = phaseStartedAt
        self.deadline = deadline
        self.phaseDuration = phaseDuration
        self.pauseReasons = pauseReasons
        self.pausedAt = pausedAt
        self.currentContentID = currentContentID
        self.scheduledEyeBreaksSinceStand = scheduledEyeBreaksSinceStand
        self.plannedBreakKind = plannedBreakKind
        self.currentBreakID = currentBreakID
        self.currentBreakSource = currentBreakSource
        self.recentBreaks = recentBreaks
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        phase = try values.decodeIfPresent(ActivePhase.self, forKey: .phase) ?? .working
        phaseStartedAt = try values.decodeIfPresent(Date.self, forKey: .phaseStartedAt) ?? Date()
        deadline = try values.decodeIfPresent(Date.self, forKey: .deadline) ?? Date().addingTimeInterval(20 * 60)
        phaseDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .phaseDuration) ?? 20 * 60
        pauseReasons = try values.decodeIfPresent(Set<PauseReason>.self, forKey: .pauseReasons) ?? []
        pausedAt = try values.decodeIfPresent(Date.self, forKey: .pausedAt)
        currentContentID = try values.decodeIfPresent(UUID.self, forKey: .currentContentID)
        let legacyEyeBreaks = try values.decodeIfPresent(Int.self, forKey: .completedEyeBreaks) ?? 0
        scheduledEyeBreaksSinceStand = try values.decodeIfPresent(
            Int.self,
            forKey: .scheduledEyeBreaksSinceStand
        ) ?? legacyEyeBreaks
        plannedBreakKind = try values.decodeIfPresent(BreakKind.self, forKey: .plannedBreakKind)
        currentBreakID = try values.decodeIfPresent(UUID.self, forKey: .currentBreakID)
        currentBreakSource = try values.decodeIfPresent(BreakSource.self, forKey: .currentBreakSource)
        // Older builds persisted a streak indefinitely. Decode and discard it;
        // the current streak is derived from dated break records instead.
        _ = try values.decodeIfPresent(Int.self, forKey: .consecutiveSkippedBreaks)
        recentBreaks = try values.decodeIfPresent([BreakRecord].self, forKey: .recentBreaks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(phase, forKey: .phase)
        try values.encode(phaseStartedAt, forKey: .phaseStartedAt)
        try values.encode(deadline, forKey: .deadline)
        try values.encode(phaseDuration, forKey: .phaseDuration)
        try values.encode(pauseReasons, forKey: .pauseReasons)
        try values.encodeIfPresent(pausedAt, forKey: .pausedAt)
        try values.encodeIfPresent(currentContentID, forKey: .currentContentID)
        try values.encode(scheduledEyeBreaksSinceStand, forKey: .scheduledEyeBreaksSinceStand)
        try values.encodeIfPresent(plannedBreakKind, forKey: .plannedBreakKind)
        try values.encodeIfPresent(currentBreakID, forKey: .currentBreakID)
        try values.encodeIfPresent(currentBreakSource, forKey: .currentBreakSource)
        try values.encode(recentBreaks, forKey: .recentBreaks)
    }
}

struct ScheduleViewState: Equatable, Sendable {
    var phase: ActivePhase
    var remaining: TimeInterval
    var duration: TimeInterval
    var pauseReasons: Set<PauseReason>
    var content: BreakContent?

    var isPaused: Bool { !pauseReasons.isEmpty }
    var isStopped: Bool { phase == .stopped }
}
