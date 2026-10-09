import Foundation

/// A device as seen by the engine: its geometry and where it sits on the virtual desk.
public struct SceneDevice: Sendable {
    public var id: String
    public var kind: DeviceKind
    public var layout: DeviceLayout
    /// Top-left corner on the desk, millimetres.
    public var origin: SIMD2<Float>

    public init(id: String, kind: DeviceKind, layout: DeviceLayout, origin: SIMD2<Float>) {
        self.id = id
        self.kind = kind
        self.layout = layout
        self.origin = origin
    }
}

/// One LED in scene space. Effects only ever see these.
public struct ScenePoint: Sendable {
    /// Position inside its own device, normalised to 0...1 (v grows downwards).
    public var local: SIMD2<Float>
    /// Position on the whole desk, normalised to 0...1 over the scene's bounding box.
    public var world: SIMD2<Float>
    /// Position on the whole desk in millimetres (ripples travel at physical speeds).
    public var worldMM: SIMD2<Float>
    /// Edge coordinate for edge-lit devices; for others, the angle around the device centre as 0..<1.
    public var perimeter: Float
    public var keyCode: UInt16?
    public var device: Int
    public var slot: Int
    /// Stable per-LED pseudo-random value in 0..<1, handy for twinkle phases.
    public var seed: Float
}

/// Flattened LED list for every device in the scene, rebuilt when devices come and go.
public struct SceneLayout: Sendable {
    public private(set) var devices: [SceneDevice]
    public private(set) var points: [ScenePoint]
    /// `points[deviceRanges[i]]` belong to `devices[i]`.
    public private(set) var deviceRanges: [Range<Int>]
    public private(set) var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)

    public static let empty = SceneLayout(devices: [])

    public init(devices: [SceneDevice]) {
        self.devices = devices
        var lower = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for device in devices {
            lower = pointwiseMin(lower, device.origin)
            upper = pointwiseMax(upper, device.origin + device.layout.size)
        }
        if devices.isEmpty {
            lower = .zero
            upper = SIMD2(1, 1)
        }
        bounds = (lower, upper)
        let extent = pointwiseMax(upper - lower, SIMD2(1, 1))

        var points: [ScenePoint] = []
        var ranges: [Range<Int>] = []
        for (deviceIndex, device) in devices.enumerated() {
            let start = points.count
            let size = pointwiseMax(device.layout.size, SIMD2(1, 1))
            let centre = size / 2
            for led in device.layout.leds {
                let mm = device.origin + led.position
                let perimeter = led.perimeter ?? SceneLayout.angle(of: led.position - centre)
                points.append(ScenePoint(
                    local: led.position / size,
                    world: (mm - lower) / extent,
                    worldMM: mm,
                    perimeter: perimeter,
                    keyCode: led.keyCode,
                    device: deviceIndex,
                    slot: led.slot,
                    seed: SceneLayout.hash(deviceIndex, led.slot)
                ))
            }
            ranges.append(start..<points.count)
        }
        self.points = points
        self.deviceRanges = ranges
    }

    /// Index of the first device of a kind, if present.
    public func firstDevice(of kind: DeviceKind) -> Int? {
        devices.firstIndex { $0.kind == kind }
    }

    /// Centre of a device on the desk, millimetres.
    public func centre(ofDevice index: Int) -> SIMD2<Float> {
        devices[index].origin + devices[index].layout.size / 2
    }

    static func angle(of v: SIMD2<Float>) -> Float {
        wrapUnit(atan2f(v.y, v.x) / (2 * .pi) + 0.25)
    }

    static func hash(_ a: Int, _ b: Int) -> Float {
        var x = UInt64(truncatingIfNeeded: a) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(truncatingIfNeeded: b) &* 0xC2B2_AE3D_27D4_EB4F
        x ^= x >> 31
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 29
        return Float(x >> 40) / Float(1 << 24)
    }
}
