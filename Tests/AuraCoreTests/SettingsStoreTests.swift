import Foundation
import Testing
@testable import AuraCore

@Suite(.serialized) struct SettingsStoreTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("aura-store-\(UUID().uuidString)")
    }

    /// Regression: the debounced save ran a main-actor-isolated closure on a background queue,
    /// and Swift 6's runtime isolation check killed the app 0.5 s after any settings change.
    @MainActor @Test func debouncedSaveFromTheMainActorWritesTheFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directory: directory)
        #expect(store.isFirstLaunch)
        var settings = AuraSettings()
        settings.brightness = 0.05
        settings.effect.kind = .inferno
        store.save(settings)
        let file = directory.appendingPathComponent("settings.json")
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: file.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(!store.isFirstLaunch)
        #expect(store.load() == settings)
    }

    @MainActor @Test func rapidSavesKeepTheLastValue() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directory: directory)
        var settings = AuraSettings()
        for step in 0...20 {
            settings.brightness = 0.2 + Float(step) / 100
            store.save(settings)
        }
        // Nothing is written while saves keep coming in…
        #expect(store.isFirstLaunch)
        Thread.sleep(forTimeInterval: SettingsStore.debounce + 0.4)
        // …then exactly the last value lands (0.4, not the 1.0 default).
        #expect(abs(store.load().brightness - 0.4) < 0.0001)
    }

    @MainActor @Test func flushWritesImmediatelyAndCancelsPendingSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directory: directory)
        var early = AuraSettings()
        early.brightness = 0.3
        store.save(early)
        var final = AuraSettings()
        final.brightness = 0.7
        store.flush(final)
        #expect(abs(store.load().brightness - 0.7) < 0.0001)
        Thread.sleep(forTimeInterval: SettingsStore.debounce + 0.4)
        // The earlier pending save must not overwrite the flushed value.
        #expect(abs(store.load().brightness - 0.7) < 0.0001)
    }
}
