import Foundation

public enum EffectKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case staticColor = "static"
    case breathing
    case spectrum
    case wave
    case flow
    case morph
    case starlight
    case orbit
    case wheel
    case hearth
    case inferno
    case embers
    case wisp
    case wildfire

    public var id: String { rawValue }

    /// The Aura Flame family.
    public static let flames: [EffectKind] = [.hearth, .inferno, .embers, .wisp, .wildfire]
    public static let classics: [EffectKind] = [.staticColor, .breathing, .spectrum, .wave, .flow, .morph, .starlight, .orbit, .wheel, .off]

    public var isFlame: Bool { EffectKind.flames.contains(self) }

    public var title: String {
        switch self {
        case .off: "Выключено"
        case .staticColor: "Статика"
        case .breathing: "Дыхание"
        case .spectrum: "Спектр"
        case .wave: "Волна"
        case .flow: "Перелив"
        case .morph: "Морфинг"
        case .starlight: "Звёзды"
        case .orbit: "Орбита"
        case .wheel: "Колесо"
        case .hearth: "Hearth"
        case .inferno: "Inferno"
        case .embers: "Embers"
        case .wisp: "Wisp"
        case .wildfire: "Wildfire"
        }
    }

    public var subtitle: String {
        switch self {
        case .off: "Подсветка погашена"
        case .staticColor: "Цвета палитры градиентом"
        case .breathing: "Вдох-выдох, цвет меняется с каждым вдохом"
        case .spectrum: "Весь спектр синхронно"
        case .wave: "Бегущая волна через все устройства"
        case .flow: "Цвета палитры плавно перетекают"
        case .morph: "Вся подсветка меняет цвет по кругу"
        case .starlight: "Мерцающие звёзды"
        case .orbit: "Комета бежит по контуру"
        case .wheel: "Спектр вращается вокруг центра"
        case .hearth: "Классический огонь очага"
        case .inferno: "Высокое яростное пламя с белым ядром"
        case .embers: "Тлеющие угли и летящие искры"
        case .wisp: "Призрачный мягкий огонь"
        case .wildfire: "Пламя гуляет на ветру"
        }
    }

    /// SF Symbol for the effect picker.
    public var symbol: String {
        switch self {
        case .off: "power"
        case .staticColor: "circle.fill"
        case .breathing: "wind"
        case .spectrum: "rainbow"
        case .wave: "water.waves"
        case .flow: "drop.halffull"
        case .morph: "circle.lefthalf.filled"
        case .starlight: "sparkles"
        case .orbit: "circle.dashed"
        case .wheel: "arrow.clockwise.circle"
        case .hearth: "flame"
        case .inferno: "flame.fill"
        case .embers: "fireplace"
        case .wisp: "smoke"
        case .wildfire: "tornado"
        }
    }

    /// Which controls make sense for this effect in the UI.
    public var usesSpeed: Bool { ![.off, .staticColor].contains(self) }
    public var usesIntensity: Bool { isFlame || [.starlight, .wave, .orbit, .flow].contains(self) }
    public var usesDirection: Bool { self == .wave || self == .wheel }
    public var usesSpan: Bool { [.staticColor, .wave, .flow].contains(self) || isFlame }

    public var intensityTitle: String {
        switch self {
        case .starlight: "Плотность"
        case .wave: "Ширина волны"
        case .orbit: "Длина хвоста"
        case .flow: "Масштаб"
        default: "Высота пламени"
        }
    }
}

public enum Direction: String, Codable, CaseIterable, Sendable {
    case left, right, up, down

    public var title: String {
        switch self {
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        }
    }
}

public struct EffectSettings: Hashable, Sendable {
    public var kind: EffectKind
    /// 0…1, mapped to effect-specific rates.
    public var speed: Float
    /// 0…1: flame height, star density, wave width, tail length…
    public var intensity: Float
    public var direction: Direction
    /// Draw one continuous effect across the desk instead of repeating it per device.
    public var spanDevices: Bool
    /// Wave and spectrum-like effects can use the rainbow instead of the palette.
    public var rainbow: Bool

    public init(kind: EffectKind = .hearth, speed: Float = 0.5, intensity: Float = 0.5,
                direction: Direction = .right, spanDevices: Bool = false, rainbow: Bool = false) {
        self.kind = kind
        self.speed = speed
        self.intensity = intensity
        self.direction = direction
        self.spanDevices = spanDevices
        self.rainbow = rainbow
    }
}

extension EffectSettings: Codable {
    enum CodingKeys: String, CodingKey { case kind, speed, intensity, direction, spanDevices, rainbow }

    /// Tolerant decoding: unknown or missing fields fall back to defaults, so old settings files keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EffectSettings()
        kind = (try? c.decode(EffectKind.self, forKey: .kind)) ?? defaults.kind
        speed = unitClamped((try? c.decode(Float.self, forKey: .speed)) ?? defaults.speed, fallback: defaults.speed)
        intensity = unitClamped((try? c.decode(Float.self, forKey: .intensity)) ?? defaults.intensity, fallback: defaults.intensity)
        direction = (try? c.decode(Direction.self, forKey: .direction)) ?? defaults.direction
        spanDevices = (try? c.decode(Bool.self, forKey: .spanDevices)) ?? defaults.spanDevices
        rainbow = (try? c.decode(Bool.self, forKey: .rainbow)) ?? defaults.rainbow
    }
}

/// Clamps a decoded 0…1 control; NaN or infinity falls back to the default.
func unitClamped(_ value: Float, fallback: Float, range: ClosedRange<Float> = 0...1) -> Float {
    value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
}
