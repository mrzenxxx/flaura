import Foundation

/// Per-device options. The palette is never per device: every device shares the scene palette.
public struct DeviceSettings: Hashable, Sendable {
    /// When false the device is kept dark.
    public var enabled: Bool
    /// Brightness multiplier for this device (mats tend to look brighter than keyboards).
    public var gain: Float
    /// Own effect for this device; nil follows the scene effect.
    public var effect: EffectSettings?
    /// Top-left corner on the virtual desk, millimetres; nil uses the default arrangement.
    public var origin: SIMD2<Float>?

    public init(enabled: Bool = true, gain: Float = 1, effect: EffectSettings? = nil, origin: SIMD2<Float>? = nil) {
        self.enabled = enabled
        self.gain = gain
        self.effect = effect
        self.origin = origin
    }
}

extension DeviceSettings: Codable {
    enum CodingKeys: String, CodingKey { case enabled, gain, effect, origin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        gain = (try? c.decode(Float.self, forKey: .gain)) ?? 1
        effect = try? c.decode(EffectSettings.self, forKey: .effect)
        if let xy = try? c.decode([Float].self, forKey: .origin), xy.count == 2 {
            origin = SIMD2(xy[0], xy[1])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(gain, forKey: .gain)
        try c.encodeIfPresent(effect, forKey: .effect)
        try c.encodeIfPresent(origin.map { [$0.x, $0.y] }, forKey: .origin)
    }
}

/// Everything the user can configure, persisted as JSON.
public struct AuraSettings: Hashable, Sendable {
    public var enabled: Bool
    public var palette: Palette
    public var effect: EffectSettings
    public var reactive: ReactiveSettings
    /// Master brightness, 0…1.
    public var brightness: Float
    /// Output gamma: LEDs are linear, so ~2 makes fades and dark palette colors look like on screen.
    public var gamma: Float
    public var framesPerSecond: Int
    /// Turn the lights off while displays sleep or the screen is locked.
    public var dimWhenIdle: Bool
    /// What devices show after Aura quits.
    public var shutdownBehaviour: ShutdownBehaviour
    /// Keyed by `LightingDevice.id`.
    public var devices: [String: DeviceSettings]

    public init(enabled: Bool = true, palette: Palette = .flame, effect: EffectSettings = EffectSettings(),
                reactive: ReactiveSettings = ReactiveSettings(), brightness: Float = 0.85, gamma: Float = 1.8,
                framesPerSecond: Int = 30, dimWhenIdle: Bool = true,
                shutdownBehaviour: ShutdownBehaviour = .staticColor, devices: [String: DeviceSettings] = [:]) {
        self.enabled = enabled
        self.palette = palette
        self.effect = effect
        self.reactive = reactive
        self.brightness = brightness
        self.gamma = gamma
        self.framesPerSecond = framesPerSecond
        self.dimWhenIdle = dimWhenIdle
        self.shutdownBehaviour = shutdownBehaviour
        self.devices = devices
    }

    public func device(_ id: String) -> DeviceSettings {
        devices[id] ?? DeviceSettings()
    }

    public static let fpsRange = 15...60
}

extension AuraSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case enabled, palette, effect, reactive, brightness, gamma, framesPerSecond, dimWhenIdle, shutdownBehaviour, devices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AuraSettings()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        palette = (try? c.decode(Palette.self, forKey: .palette)) ?? d.palette
        effect = (try? c.decode(EffectSettings.self, forKey: .effect)) ?? d.effect
        reactive = (try? c.decode(ReactiveSettings.self, forKey: .reactive)) ?? d.reactive
        brightness = (try? c.decode(Float.self, forKey: .brightness)) ?? d.brightness
        gamma = (try? c.decode(Float.self, forKey: .gamma)) ?? d.gamma
        let fps = (try? c.decode(Int.self, forKey: .framesPerSecond)) ?? d.framesPerSecond
        framesPerSecond = min(max(fps, AuraSettings.fpsRange.lowerBound), AuraSettings.fpsRange.upperBound)
        dimWhenIdle = (try? c.decode(Bool.self, forKey: .dimWhenIdle)) ?? d.dimWhenIdle
        shutdownBehaviour = (try? c.decode(ShutdownBehaviour.self, forKey: .shutdownBehaviour)) ?? d.shutdownBehaviour
        devices = (try? c.decode([String: DeviceSettings].self, forKey: .devices)) ?? d.devices
    }
}
