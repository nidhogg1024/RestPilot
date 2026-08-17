import Foundation

@MainActor
final class SettingsStore {
    private enum Keys {
        static let settings = "settings.v1"
        static let snapshot = "schedule.snapshot.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: Keys.settings),
              let value = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }
        return value
    }

    func saveSettings(_ settings: AppSettings) {
        if let data = try? encoder.encode(settings) { defaults.set(data, forKey: Keys.settings) }
    }

    func loadSnapshot() -> ScheduleSnapshot? {
        guard let data = defaults.data(forKey: Keys.snapshot) else { return nil }
        return try? decoder.decode(ScheduleSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: ScheduleSnapshot) {
        if let data = try? encoder.encode(snapshot) { defaults.set(data, forKey: Keys.snapshot) }
    }
}
