import Foundation

/// Read/write the App Group payloads shared between app and widget extension.
final class SharedStore {
    private let defaults: UserDefaults
    private let snapshotKey = "shared.glucoseSnapshot"
    private let configKey = "shared.displayConfig"

    init(defaults: UserDefaults = SharedConstants.sharedDefaults) {
        self.defaults = defaults
    }

    func saveSnapshot(_ snapshot: GlucoseSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    func loadSnapshot() -> GlucoseSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(GlucoseSnapshot.self, from: data)
    }

    func saveConfig(_ config: DisplayConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: configKey)
        }
    }

    func loadConfig() -> DisplayConfig {
        guard let data = defaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(DisplayConfig.self, from: data)
        else { return DisplayConfig(units: .mgdl, thresholds: .defaults) }
        return config
    }
}
