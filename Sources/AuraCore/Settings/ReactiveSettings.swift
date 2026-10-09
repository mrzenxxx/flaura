import Foundation

public enum ReactiveColorMode: String, Codable, CaseIterable, Sendable {
    /// The brightest palette color.
    case brightest
    /// Each press takes the next palette color.
    case cycle
    case white

    public var title: String {
        switch self {
        case .brightest: "Яркий из палитры"
        case .cycle: "По кругу палитры"
        case .white: "Белый"
        }
    }
}

/// Input-driven layers drawn over the base effect.
public struct ReactiveSettings: Hashable, Sendable {
    /// A ring spreads from the pressed key.
    public var ripple: Bool
    /// The pressed key flashes and fades.
    public var keyGlow: Bool
    /// Mouse clicks flash the mouse and send a ring across the mat.
    public var clickPulse: Bool
    /// Typing throws heat into Aura Flame effects.
    public var stoke: Bool
    public var colorMode: ReactiveColorMode
    /// 0…1, how long reactions take to fade.
    public var duration: Float
    /// Ripples and pulses continue onto the other devices.
    public var spanDevices: Bool

    public init(ripple: Bool = true, keyGlow: Bool = false, clickPulse: Bool = true, stoke: Bool = true,
                colorMode: ReactiveColorMode = .brightest, duration: Float = 0.5, spanDevices: Bool = true) {
        self.ripple = ripple
        self.keyGlow = keyGlow
        self.clickPulse = clickPulse
        self.stoke = stoke
        self.colorMode = colorMode
        self.duration = duration
        self.spanDevices = spanDevices
    }

    /// Whether any layer needs keyboard or mouse events (and therefore the Input Monitoring permission).
    public var needsInput: Bool { ripple || keyGlow || clickPulse || stoke }

    /// Reaction lifetime in seconds.
    public var seconds: Float { rate(duration, 0.35, 2.4) }
}

extension ReactiveSettings: Codable {
    enum CodingKeys: String, CodingKey { case ripple, keyGlow, clickPulse, stoke, colorMode, duration, spanDevices }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReactiveSettings()
        ripple = (try? c.decode(Bool.self, forKey: .ripple)) ?? d.ripple
        keyGlow = (try? c.decode(Bool.self, forKey: .keyGlow)) ?? d.keyGlow
        clickPulse = (try? c.decode(Bool.self, forKey: .clickPulse)) ?? d.clickPulse
        stoke = (try? c.decode(Bool.self, forKey: .stoke)) ?? d.stoke
        colorMode = (try? c.decode(ReactiveColorMode.self, forKey: .colorMode)) ?? d.colorMode
        duration = (try? c.decode(Float.self, forKey: .duration)) ?? d.duration
        spanDevices = (try? c.decode(Bool.self, forKey: .spanDevices)) ?? d.spanDevices
    }
}
