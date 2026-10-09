import Foundation

/// An sRGB-encoded color with float components, nominally in 0...1.
/// Effects may produce values above 1 while compositing; `clamped` brings them back.
public struct RGB: Hashable, Sendable, Codable {
    public var r: Float
    public var g: Float
    public var b: Float

    @inlinable
    public init(_ r: Float, _ g: Float, _ b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(1, 1, 1)

    /// Creates a color from a hex string such as `#FF6A00` or `ff6a00`.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            Float((value >> 16) & 0xFF) / 255,
            Float((value >> 8) & 0xFF) / 255,
            Float(value & 0xFF) / 255
        )
    }

    public var hex: String {
        let c = clamped
        return String(format: "#%02X%02X%02X", Int(c.r * 255 + 0.5), Int(c.g * 255 + 0.5), Int(c.b * 255 + 0.5))
    }

    @inlinable
    public var clamped: RGB {
        RGB(min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }

    /// Rec. 709 luma of the encoded values; good enough for "which palette color is brightest".
    @inlinable
    public var luma: Float { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    @inlinable
    public static func * (color: RGB, scale: Float) -> RGB {
        RGB(color.r * scale, color.g * scale, color.b * scale)
    }

    @inlinable
    public static func + (lhs: RGB, rhs: RGB) -> RGB {
        RGB(lhs.r + rhs.r, lhs.g + rhs.g, lhs.b + rhs.b)
    }

    /// Linear interpolation in encoded space (cheap; palettes use OKLab for quality).
    @inlinable
    public static func mix(_ a: RGB, _ b: RGB, _ t: Float) -> RGB {
        RGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    /// Screen blend: brightens without blowing past white.
    @inlinable
    public static func screen(_ a: RGB, _ b: RGB) -> RGB {
        RGB(1 - (1 - a.r) * (1 - b.r), 1 - (1 - a.g) * (1 - b.g), 1 - (1 - a.b) * (1 - b.b))
    }

    /// Hue in 0..<1, saturation and value in 0...1.
    public static func hsv(_ h: Float, _ s: Float, _ v: Float) -> RGB {
        let hue = (h - h.rounded(.down)) * 6
        let sector = Int(hue) % 6
        let f = hue - Float(Int(hue))
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch sector {
        case 0: return RGB(v, t, p)
        case 1: return RGB(q, v, p)
        case 2: return RGB(p, v, t)
        case 3: return RGB(p, q, v)
        case 4: return RGB(t, p, v)
        default: return RGB(v, p, q)
        }
    }
}

/// Packed 8-bit color as sent to hardware.
public struct RGB8: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    @inlinable
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let black = RGB8(0, 0, 0)
}
