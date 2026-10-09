import Foundation

public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case keyboard
    case mouse
    case mousepad
    case headset
    case strip
    case other
}

/// One addressable light on a device.
public struct LEDPoint: Hashable, Sendable {
    /// Slot in the device frame: `write(frame:)` receives colors indexed by this value.
    public var slot: Int
    /// Physical position in millimetres, measured from the device's top-left corner.
    public var position: SIMD2<Float>
    /// Position along the outer edge, 0..<1 clockwise from the top-left corner (edge-lit devices).
    public var perimeter: Float?
    /// macOS virtual key code (`kVK_*`) for keyboard keys, used by reactive effects.
    public var keyCode: UInt16?

    public init(slot: Int, position: SIMD2<Float>, perimeter: Float? = nil, keyCode: UInt16? = nil) {
        self.slot = slot
        self.position = position
        self.perimeter = perimeter
        self.keyCode = keyCode
    }
}

/// Geometry of a device's lights, described as data so any vendor back-end can provide it.
public struct DeviceLayout: Hashable, Sendable {
    /// Device footprint in millimetres.
    public var size: SIMD2<Float>
    /// Number of slots in a frame. Slots without an `LEDPoint` are sent black.
    public var frameLength: Int
    public var leds: [LEDPoint]

    public init(size: SIMD2<Float>, frameLength: Int, leds: [LEDPoint]) {
        precondition(leds.allSatisfy { $0.slot >= 0 && $0.slot < frameLength }, "LED slot out of range")
        self.size = size
        self.frameLength = frameLength
        self.leds = leds
    }

    /// A rows × columns grid of LEDs with a fixed pitch, slots in row-major order.
    public static func matrix(rows: Int, columns: Int, pitch: Float) -> DeviceLayout {
        var leds: [LEDPoint] = []
        leds.reserveCapacity(rows * columns)
        for row in 0..<rows {
            for column in 0..<columns {
                leds.append(LEDPoint(
                    slot: row * columns + column,
                    position: SIMD2(Float(column) + 0.5, Float(row) + 0.5) * pitch
                ))
            }
        }
        return DeviceLayout(size: SIMD2(Float(columns), Float(rows)) * pitch, frameLength: rows * columns, leds: leds)
    }

    /// LEDs evenly spaced around the edge of a rectangle, clockwise.
    /// `start` is where slot 0 sits on the perimeter (0 = top-left corner, 0.25 ≈ top-right for a square).
    public static func perimeter(count: Int, size: SIMD2<Float>, start: Float = 0, clockwise: Bool = true) -> DeviceLayout {
        let leds = (0..<count).map { slot -> LEDPoint in
            let step = (Float(slot) + 0.5) / Float(count)
            var p = clockwise ? start + step : start - step
            p -= p.rounded(.down)
            return LEDPoint(slot: slot, position: DeviceLayout.pointOnPerimeter(p, size: size), perimeter: p)
        }
        return DeviceLayout(size: size, frameLength: count, leds: leds)
    }

    /// Maps 0..<1 (clockwise from the top-left corner) to a point on the rectangle's edge.
    public static func pointOnPerimeter(_ p: Float, size: SIMD2<Float>) -> SIMD2<Float> {
        let total = 2 * (size.x + size.y)
        var d = (p - p.rounded(.down)) * total
        if d < size.x { return SIMD2(d, 0) }
        d -= size.x
        if d < size.y { return SIMD2(size.x, d) }
        d -= size.y
        if d < size.x { return SIMD2(size.x - d, size.y) }
        d -= size.x
        return SIMD2(0, size.y - d)
    }
}
