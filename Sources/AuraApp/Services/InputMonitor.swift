import AppKit
import AuraCore
import CoreGraphics

/// Listens (never filters) to key presses and mouse clicks for reactive effects.
///
/// A listen-only session event tap needs the Input Monitoring permission. The tap is only
/// installed while a reactive layer is enabled, and the callback does nothing but hand a tiny
/// event to the render queue.
@MainActor
final class InputMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate let onEvent: @Sendable (InputEvent) -> Void

    init(onEvent: @escaping @Sendable (InputEvent) -> Void) {
        self.onEvent = onEvent
    }

    var isRunning: Bool { tap != nil }

    static var hasAccess: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; afterwards macOS only offers System Settings.
    @discardableResult
    static func requestAccess() -> Bool { CGRequestListenEventAccess() }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns false when the permission is missing.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard InputMonitor.hasAccess else { return false }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: inputMonitorCallback, userInfo: context)
        else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Pure translation from a raw event; runs inside the tap callback.
    nonisolated static func translate(type: CGEventType, event: CGEvent) -> InputEvent? {
        switch type {
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return nil }
            return .keyDown(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
        case .flagsChanged:
            // Modifiers arrive as flag changes; report the press, not the release.
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard let flag = modifierFlag(keyCode), keyCode == 57 || event.flags.contains(flag) else { return nil }
            return .keyDown(keyCode: keyCode)
        case .leftMouseDown:
            return .mouseDown(button: 0)
        case .rightMouseDown:
            return .mouseDown(button: 1)
        case .otherMouseDown:
            return .mouseDown(button: Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        default:
            return nil
        }
    }

    nonisolated private static func modifierFlag(_ keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 56, 60: .maskShift
        case 59, 62: .maskControl
        case 58, 61: .maskAlternate
        case 55, 54: .maskCommand
        case 57: .maskAlphaShift
        case 63: .maskSecondaryFn
        default: nil
        }
    }
}

/// The tap lives on the main run loop, so the callback runs on the main thread.
private func inputMonitorCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                  userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { monitor.reenable() }
    } else if let input = InputMonitor.translate(type: type, event: event) {
        monitor.onEvent(input)
    }
    return Unmanaged.passUnretained(event)
}
