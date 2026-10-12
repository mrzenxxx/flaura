import Foundation

/// What a device does when Aura stops driving it (quit, sleep).
public enum ShutdownBehaviour: String, Codable, CaseIterable, Sendable {
    /// Hardware static effect in the palette's middle color, stored in the device so it also shows
    /// at power-on; stays in sync because it does not move.
    case staticColor
    /// The device's own spectrum cycling.
    case spectrum
    /// Lights off.
    case off
    /// Leave the last frame on.
    case keep

    public var title: String {
        switch self {
        case .staticColor: "Статичный цвет палитры"
        case .spectrum: "Аппаратный спектр"
        case .off: "Погасить"
        case .keep: "Оставить последний кадр"
        }
    }
}

public struct DeviceInfo: Hashable, Sendable {
    /// Stable across reconnects: settings are keyed by it.
    public var id: String
    public var name: String
    public var vendor: String
    public var kind: DeviceKind
    /// Short technical note for the UI, e.g. "USB 1532:0085 · fw 1.4".
    public var detail: String

    public init(id: String, name: String, vendor: String, kind: DeviceKind, detail: String) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.kind = kind
        self.detail = detail
    }
}

/// Anything with addressable lights. Vendor back-ends implement this; the engine only sees this.
///
/// The engine calls every method on a serial queue owned by that device, so implementations
/// may block for the duration of a transfer and need no locking of their own.
public protocol LightingDevice: AnyObject, Sendable {
    var info: DeviceInfo { get }
    var layout: DeviceLayout { get }
    /// One-time setup before the first frame (switch to software mode, max hardware brightness…).
    func prepare() throws
    /// Shows a frame: `frame.count == layout.frameLength`, colors indexed by `LEDPoint.slot`.
    func write(_ frame: [RGB8]) throws
    /// Hands the lights back to the hardware.
    func shutdown(_ behaviour: ShutdownBehaviour, color: RGB8)
}

/// A source of devices for one family of hardware (Razer USB, and later OpenRGB, HID LampArray…).
public protocol DeviceProvider: AnyObject {
    var name: String { get }
    /// Starts discovery; `onChange` receives the provider's full current device list on every change.
    func start(onChange: @escaping @Sendable ([any LightingDevice]) -> Void)
    func stop()
}
