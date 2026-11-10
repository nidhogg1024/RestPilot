import AppKit
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ScheduleEngineDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var preferencesWindow: NSWindow?

    private let store = SettingsStore()
    private var settings: AppSettings = .default
    private var engine: ScheduleEngine!
    private let overlays = OverlayController()
    private var monitors: SystemMonitors!
    private let logger = Logger(subsystem: "local.nidhogg.RestPilot", category: "schedule")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = store.loadSettings()
        engine = ScheduleEngine(settings: settings, snapshot: store.loadSnapshot())
        engine.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "RestPilot")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }
        rebuildPopover()

        monitors = SystemMonitors { [weak self] in self?.settings ?? .default }
        monitors.onIdleChanged = { [weak self] idle in
            guard let self else { return }
            switch self.engine.snapshot.phase {
            case .working, .snoozed:
                self.engine.setPaused(idle, reason: .idle)
            case .resting, .stopped:
                if !idle {
                    self.engine.setPaused(false, reason: .idle)
                }
            }
        }
        monitors.onLockChanged = { [weak self] locked in
            guard let self, self.settings.pauseWhenLocked else { return }
            self.engine.setPaused(locked, reason: .screenLocked)
        }
        monitors.onSleepChanged = { [weak self] sleeping in self?.engine.setPaused(sleeping, reason: .systemSleeping) }
        monitors.onDisplaysChanged = { [weak self] in
            guard let self, case .resting = self.engine.snapshot.phase else { return }
            self.overlays.show(engine: self.engine, settings: self.settings)
        }
        engine.clearTransientPauseReasons()
        monitors.start()
        engine.start()
        if case .resting = engine.snapshot.phase {
            overlays.show(engine: engine, settings: settings)
        }
        if CommandLine.arguments.contains("--show-settings") {
            openPreferences()
        }
        if CommandLine.arguments.contains("--preview-eye") {
            overlays.showPreview(kind: .eye, settings: settings)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveSnapshot(engine.snapshot)
        store.saveSettings(settings)
        monitors.stop()
        engine.stop()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            rebuildPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func rebuildPopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: MenuPopoverMetrics.width, height: MenuPopoverMetrics.height)
        popover.contentViewController = NSHostingController(rootView: MenuPopoverView(
            engine: engine,
            settings: settings,
            openSettings: { [weak self] in self?.openPreferences() }
        ))
    }

    private func openPreferences() {
        popover.performClose(nil)
        if preferencesWindow == nil {
            let view = PreferencesView(
                settings: settings,
                onSave: { [weak self] value in self?.applySettings(value) },
                onPreview: { [weak self] kind, value in
                    guard let self else { return }
                    let shouldRestorePreferences = self.preferencesWindow?.isVisible == true
                    self.overlays.showPreview(kind: kind, settings: value) { [weak self] in
                        guard shouldRestorePreferences, let self else { return }
                        self.preferencesWindow?.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            )
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "RestPilot 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 800, height: 560))
            window.minSize = NSSize(width: 760, height: 520)
            window.maxSize = NSSize(width: 940, height: 720)
            window.center()
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applySettings(_ value: AppSettings) {
        settings = value
        store.saveSettings(value)
        engine.updateSettings(value)
        rebuildPopover()
        updateStatusItem()
    }

    func scheduleEngineDidTick(_ engine: ScheduleEngine) {
        updateStatusItem()
    }

    func scheduleEngineDidChangeState(_ engine: ScheduleEngine) {
        store.saveSnapshot(engine.snapshot)
        updateStatusItem()
    }

    func scheduleEngine(_ engine: ScheduleEngine, didEnterBreak kind: BreakKind) {
        popover.performClose(nil)
        if let session = engine.activeBreakSession() {
            logger.info(
                "break_enter id=\(session.id.uuidString, privacy: .public) kind=\(kind.rawValue, privacy: .public) source=\(session.source.rawValue, privacy: .public) eye_slots=\(engine.snapshot.scheduledEyeBreaksSinceStand)"
            )
        }
        overlays.show(engine: engine, settings: settings)
    }

    func scheduleEngine(_ engine: ScheduleEngine, didEndBreak outcome: BreakOutcome) {
        logger.info(
            "break_end outcome=\(outcome.rawValue, privacy: .public) rest_debt_s=\(Int(engine.restDebt())) next=\(engine.nextScheduledBreakKind()?.rawValue ?? "none", privacy: .public)"
        )
        overlays.hide()
        if outcome == .completed, settings.playSoundWhenBreakEnds {
            NSSound(named: NSSound.Name(settings.endSoundName))?.play()
        }
    }

    private func updateStatusItem() {
        let state = engine.viewState()
        if settings.showTimeInMenuBar, !state.isStopped {
            let seconds = max(0, Int(ceil(state.remaining)))
            statusItem.button?.title = String(format: " %02d:%02d", seconds / 60, seconds % 60)
        } else {
            statusItem.button?.title = ""
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: state.isStopped ? "stop.circle" : (state.isPaused ? "pause.circle" : "figure.walk"),
            accessibilityDescription: "RestPilot"
        )
    }
}
