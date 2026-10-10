import AppKit
import AuraCore
import SwiftUI

/// `Aura --snapshot <directory>` renders the panel and settings window to PNGs and exits.
/// Used to review the UI without clicking through the menu bar; touches no hardware.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            selfTest()
            return true
        }
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return false }
        let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(live: false)
        model.setPreviewDevices([
            DeviceInfo(id: "razer:025e", name: "Razer Cynosa V2", vendor: "Razer", kind: .keyboard, detail: "USB 1532:025E · fw 1.0"),
            DeviceInfo(id: "razer:0085", name: "Razer Basilisk V2", vendor: "Razer", kind: .mouse, detail: "USB 1532:0085 · fw 1.4"),
            DeviceInfo(id: "razer:0c04", name: "Razer Firefly V2", vendor: "Razer", kind: .mousepad, detail: "USB 1532:0C04 · fw 1.0"),
        ])
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"
            render(PanelView(model: model, openSettings: {}, quit: {}), appearance: appearance,
                   to: directory.appendingPathComponent("panel-\(suffix).png"))
            render(SettingsView(model: model), appearance: appearance,
                   to: directory.appendingPathComponent("settings-\(suffix).png"))
        }
        return true
    }

    /// `Aura --selftest`: drives the real AppModel through hundreds of random settings changes
    /// on the main actor (as the panel would) with the main run loop spinning, so debounced saves
    /// and engine updates actually run. No hardware, settings in a temporary folder. Exit 0 = pass.
    private static func selfTest() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aura-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(live: false, storeDirectory: directory)
        var rng = SystemRandomNumberGenerator()
        let deadline = Date().addingTimeInterval(4)
        var changes = 0
        while Date() < deadline {
            var s = model.settings
            switch Int.random(in: 0..<9, using: &rng) {
            case 0: s.brightness = Float.random(in: 0.05...1, using: &rng)
            case 1: s.effect.kind = EffectKind.allCases.randomElement(using: &rng)!
            case 2: s.palette = Palette.presets.randomElement(using: &rng)!
            case 3: s.paletteFlow.toggle()
            case 4: s.effect.speed = Float.random(in: 0...1, using: &rng)
            case 5: s.reactive.ripple.toggle(); s.reactive.stoke.toggle()
            case 6: s.enabled.toggle()
            case 7: s.dimWhenIdle.toggle()
            default: s.devices["razer:025e"] = DeviceSettings(gain: Float.random(in: 0...1, using: &rng))
            }
            model.settings = s
            changes += 1
            // Let timers, debounced saves and main-queue work run between changes.
            RunLoop.main.run(until: Date().addingTimeInterval(Double.random(in: 0.001...0.03, using: &rng)))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(SettingsStore.debounce + 0.5))
        let saved = SettingsStore(directory: directory).load()
        guard saved == model.settings else {
            print("selftest FAILED: saved settings differ from the model")
            exit(1)
        }
        print("selftest passed: \(changes) settings changes")
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
