import Foundation

/// Persists settings as JSON in Application Support. Writes are debounced so dragging a slider
/// does not hammer the disk.
///
/// Not actor-isolated on purpose: all file work happens on a private serial queue. (An earlier
/// `@MainActor` version built its debounce closure on the main actor and ran it on a background
/// queue, which Swift 6's runtime isolation check turns into a crash.)
public final class SettingsStore: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "aura.settings-store", qos: .utility)
    /// Bumped on every save/flush; a delayed write only runs if no newer request came in.
    private var generation: UInt64 = 0
    private let lock = NSLock()

    public static let debounce: TimeInterval = 0.5

    public init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = directory ?? base.appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("settings.json")
    }

    /// True until settings have been saved once: the very first launch.
    public var isFirstLaunch: Bool {
        !FileManager.default.fileExists(atPath: url.path)
    }

    public func load() -> AuraSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AuraSettings.self, from: data)
        else { return AuraSettings() }
        return settings
    }

    /// Writes `settings` after a short pause, superseded by any later save or flush.
    public func save(_ settings: AuraSettings) {
        let ticket = nextGeneration()
        queue.asyncAfter(deadline: .now() + SettingsStore.debounce) { [self] in
            guard currentGeneration() == ticket else { return }
            write(settings)
        }
    }

    /// Writes immediately and cancels any pending save (used on quit).
    public func flush(_ settings: AuraSettings) {
        _ = nextGeneration()
        queue.sync { write(settings) }
    }

    private func nextGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    private func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private func write(_ settings: AuraSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
