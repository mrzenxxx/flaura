import AuraCore
import Foundation

/// Persists settings as JSON in Application Support. Writes are debounced so dragging a slider
/// does not hammer the disk.
@MainActor
final class SettingsStore {
    private let url: URL
    private var pending: DispatchWorkItem?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("settings.json")
    }

    /// True until settings have been saved once: the very first launch.
    var isFirstLaunch: Bool {
        !FileManager.default.fileExists(atPath: url.path)
    }

    func load() -> AuraSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AuraSettings.self, from: data)
        else { return AuraSettings() }
        return settings
    }

    func save(_ settings: AuraSettings) {
        pending?.cancel()
        let url = url
        let work = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(settings) {
                try? data.write(to: url, options: .atomic)
            }
        }
        pending = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Writes immediately (used on quit).
    func flush(_ settings: AuraSettings) {
        pending?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
