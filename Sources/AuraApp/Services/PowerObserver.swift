import AppKit
import AuraCore

/// Feeds `PowerState` from workspace and distributed notifications.
@MainActor
final class PowerObserver {
    typealias State = PowerState

    private(set) var state = PowerState() {
        didSet { if state != oldValue { onChange(state) } }
    }

    private let onChange: (State) -> Void
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(onChange: @escaping (State) -> Void) {
        self.onChange = onChange
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        // Undocumented but long-standing (Chromium relies on them).
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ update: @escaping @Sendable (inout State) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                var state = self.state
                update(&state)
                self.state = state
            }
        }
        tokens.append((center, token))
    }
}
