import Foundation

/// What the Mac's displays and power are doing, and the rule for when lighting pauses.
///
/// Lights follow the monitor: they stay on whenever a display is on — desktop, screensaver,
/// lock screen or login form — and go dark once the displays sleep (the user has walked away)
/// or the Mac itself sleeps. Locking alone does not dim: after waking, the lock screen is the
/// first thing people see, and the keyboard should already be lit for typing the password.
public struct PowerState: Equatable, Sendable {
    public var displaysAsleep: Bool
    public var locked: Bool
    public var systemAsleep: Bool

    public init(displaysAsleep: Bool = false, locked: Bool = false, systemAsleep: Bool = false) {
        self.displaysAsleep = displaysAsleep
        self.locked = locked
        self.systemAsleep = systemAsleep
    }

    public func shouldSuspend(dimWhenIdle: Bool) -> Bool {
        systemAsleep || (dimWhenIdle && displaysAsleep)
    }
}
