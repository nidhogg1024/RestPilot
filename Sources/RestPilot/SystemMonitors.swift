import AppKit
import Foundation
import IOKit

@MainActor
final class SystemMonitors {
    var onIdleChanged: ((Bool) -> Void)?
    var onLockChanged: ((Bool) -> Void)?
    var onSleepChanged: ((Bool) -> Void)?
    var onDisplaysChanged: (() -> Void)?

    private var idleTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var settings: () -> AppSettings
    private var lastIdleState = false

    init(settings: @escaping () -> AppSettings) {
        self.settings = settings
    }

    func start() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollIdle() }
        }
        pollIdle()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onSleepChanged?(true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onSleepChanged?(false) }
        })

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onLockChanged?(true) }
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onLockChanged?(false) }
        })

        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onDisplaysChanged?() }
        })
    }

    func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
        observers.removeAll()
    }

    private func pollIdle() {
        let config = settings()
        guard config.pauseWhenIdle else {
            if lastIdleState { lastIdleState = false; onIdleChanged?(false) }
            return
        }
        let idle = idleSeconds() >= Double(max(1, config.idleMinutes) * 60)
        if idle != lastIdleState {
            lastIdleState = idle
            onIdleChanged?(idle)
        }
    }

    private func idleSeconds() -> Double {
        guard let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem")) as io_service_t?, service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any],
              let nanoseconds = dictionary["HIDIdleTime"] as? UInt64 else { return 0 }
        return Double(nanoseconds) / 1_000_000_000
    }
}
