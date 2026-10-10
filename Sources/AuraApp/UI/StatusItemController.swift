import AppKit
import Combine
import SwiftUI

/// Menu bar icon, the panel popover and the settings window.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var observation: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.toolTip = "Aura"
        }
        updateIcon(enabled: model.settings.enabled)
        observation = model.$settings
            .map(\.enabled)
            .removeDuplicates()
            .sink { [weak self] enabled in self?.updateIcon(enabled: enabled) }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func updateIcon(enabled: Bool) {
        let image = NSImage(systemSymbolName: enabled ? "flame.fill" : "flame", accessibilityDescription: "Aura")
        image?.isTemplate = true
        item.button?.image = image
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Build the SwiftUI tree fresh each time so nothing lingers while the panel is closed.
        let host = NSHostingController(rootView: PanelView(model: model, openSettings: { [weak self] in
            self?.popover.performClose(nil)
            self?.showSettings()
        }, quit: {
            NSApp.terminate(nil)
        }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        model.refreshPermissions()
        guard let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    /// Drop the window (and its SwiftUI tree observing the model) once closed.
    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Aura — настройки"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
