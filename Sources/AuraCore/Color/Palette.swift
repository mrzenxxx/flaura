import Foundation

/// The scene-wide set of colors. Every device samples the same palette, which is what keeps
/// the keyboard, mouse and mat visually unified.
///
/// Colors are ordered "cool → hot": fire effects treat the first color as the outer flame and
/// the last one as the hottest core.
public struct Palette: Hashable, Sendable, Codable {
    public static let maxColors = 4

    public var name: String
    public var colors: [RGB] {
        didSet { colors = Palette.normalized(colors) }
    }

    public init(name: String, colors: [RGB]) {
        self.name = name
        self.colors = Palette.normalized(colors)
    }

    public init(name: String, hex: [String]) {
        self.init(name: name, colors: hex.compactMap(RGB.init(hex:)))
    }

    private static func normalized(_ colors: [RGB]) -> [RGB] {
        let trimmed = Array(colors.prefix(maxColors)).map(\.clamped)
        return trimmed.isEmpty ? [RGB.white] : trimmed
    }

    enum CodingKeys: String, CodingKey { case name, colors }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            colors: try container.decode([String].self, forKey: .colors).compactMap(RGB.init(hex:))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(colors.map(\.hex), forKey: .colors)
    }
}

extension Palette {
    public static let flame = Palette(name: "Пламя", hex: ["#C21000", "#FF5A00", "#FFC22E"])
    public static let ice = Palette(name: "Лёд", hex: ["#0B2BFF", "#00B4FF", "#BFF6FF"])
    public static let toxic = Palette(name: "Токсик", hex: ["#0F7A00", "#39FF14", "#E6FF7A"])
    public static let sunset = Palette(name: "Закат", hex: ["#6A00FF", "#FF2E7E", "#FFB347"])
    public static let ocean = Palette(name: "Океан", hex: ["#003F7F", "#00A6C0", "#6EF2D0"])
    public static let synthwave = Palette(name: "Синтвейв", hex: ["#7A00FF", "#FF00C8", "#00E5FF"])
    public static let aurora = Palette(name: "Аврора", hex: ["#00FF9C", "#00B3FF", "#A600FF"])
    public static let blood = Palette(name: "Кровь", hex: ["#3A0000", "#B00012", "#FF2B2B"])
    public static let amethyst = Palette(name: "Аметист", hex: ["#3B0A99", "#8E2DE2", "#F0B7FF"])

    public static let presets: [Palette] = [flame, ice, toxic, sunset, ocean, synthwave, aurora, blood, amethyst]
}

/// Precomputed lookup tables so effects can sample the palette per LED per frame for free.
public struct PaletteLUT: Sendable {
    public static let size = 256

    /// The palette's own colors.
    public let colors: [RGB]
    /// Closed cycle c0 → c1 → … → cN → c0, for colors flowing into each other.
    public let loopTable: [RGB]
    /// Open gradient c0 → … → cN.
    public let gradientTable: [RGB]
    /// Heat map: black → c0 → … → cN. Used by fire, starlight and other "intensity" effects.
    public let rampTable: [RGB]
    /// The color with the highest luma; reactive layers default to it.
    public let brightest: RGB

    public init(_ palette: Palette) {
        let colors = palette.colors
        let labs = colors.map(OKLab.init)
        self.colors = colors
        loopTable = PaletteLUT.table(stops: labs + [labs[0]], closed: true)
        gradientTable = PaletteLUT.table(stops: labs.count == 1 ? labs + labs : labs)
        rampTable = PaletteLUT.table(stops: [OKLab(.black)] + labs)
        brightest = colors.max(by: { $0.luma < $1.luma }) ?? .white
    }

    /// The palette with every color shifted `phase` of the way around its own loop, so colors
    /// glide into their neighbours. `phase` 1 is a full turn.
    public func rotated(by phase: Float) -> PaletteLUT {
        let n = Float(colors.count)
        let shifted = colors.indices.map { loop(Float($0) / n + phase) }
        return PaletteLUT(Palette(name: "", colors: shifted))
    }

    /// `t` wraps around, so callers can feed `time * speed + position` directly.
    @inlinable
    public func loop(_ t: Float) -> RGB {
        loopTable[PaletteLUT.wrappedIndex(t)]
    }

    @inlinable
    public func gradient(_ t: Float) -> RGB {
        gradientTable[PaletteLUT.clampedIndex(t)]
    }

    @inlinable
    public func ramp(_ t: Float) -> RGB {
        rampTable[PaletteLUT.clampedIndex(t)]
    }

    @inlinable
    static func clampedIndex(_ t: Float) -> Int {
        guard t.isFinite else { return 0 }
        return Int(min(max(t, 0), 1) * Float(size - 1) + 0.5)
    }

    @inlinable
    static func wrappedIndex(_ t: Float) -> Int {
        guard t.isFinite else { return 0 }
        let fraction = t - t.rounded(.down)
        return Int(fraction * Float(size)) & (size - 1)
    }

    /// A closed table never reaches its last stop: index `size - 1` sits just before the
    /// wrap-around, so cycling through it has no duplicated seam.
    private static func table(stops: [OKLab], closed: Bool = false) -> [RGB] {
        let segments = stops.count - 1
        let span = Float(closed ? size : size - 1)
        return (0..<size).map { index in
            let position = Float(index) / span * Float(segments)
            let segment = min(Int(position), segments - 1)
            let local = position - Float(segment)
            return OKLab.mix(stops[segment], stops[segment + 1], local).rgb
        }
    }
}
