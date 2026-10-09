import AppKit
import AuraCore
import SwiftUI

/// `Aura --snapshot <directory>` renders the panel and settings window to PNGs and exits.
/// Used to review the UI without clicking through the menu bar; touches no hardware.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
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
