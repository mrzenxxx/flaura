import Foundation
import simd

/// Picks the color for each reaction according to `ReactiveColorMode`.
struct ReactionColors {
    let mode: ReactiveColorMode
    private var counter = 0

    init(mode: ReactiveColorMode) { self.mode = mode }

    mutating func next(_ palette: PaletteLUT) -> RGB {
        switch mode {
        case .brightest: return palette.brightest
        case .white: return .white
        case .cycle:
            counter += 1
            return palette.colors[counter % palette.colors.count]
        }
    }
}

/// Expanding rings in desk space (millimetres), shared by key ripples and click pulses.
struct RingSet {
    struct Ring {
        var origin: SIMD2<Float>
        var device: Int
        var start: Double
        var color: RGB
    }

    /// OpenRazer's ripple travels ~24 key widths per second; a key is ~19 mm.
    var speed: Float = 460
    var thickness: Float = 30
    var lifetime: Float = 1.6
    var span = true
    private(set) var rings: [Ring] = []

    var isEmpty: Bool { rings.isEmpty }

    mutating func add(origin: SIMD2<Float>, device: Int, time: Double, color: RGB) {
        if rings.count >= 24 { rings.removeFirst() }
        rings.append(Ring(origin: origin, device: device, start: time, color: color))
    }

    mutating func render(time: Double, points: [ScenePoint], into output: inout [RGB]) {
        rings.removeAll { Float(time - $0.start) > lifetime }
        guard !rings.isEmpty else { return }
        let inverseThickness = 1 / thickness
        for ring in rings {
            let age = Float(time - ring.start)
            let radius = age * speed
            let fade = powf(max(0, 1 - age / lifetime), 1.5)
            for (i, point) in points.enumerated() where span || point.device == ring.device {
                let d = simd_distance(point.worldMM, ring.origin)
                let x = (d - radius) * inverseThickness
                let b = expf(-x * x) * fade
                if b > 0.004 {
                    output[i] = RGB.screen(output[i], ring.color * b)
                }
            }
        }
    }
}

/// A ring spreads out from each pressed key.
public final class RippleLayer: OverlayLayer {
    private var rings = RingSet()
    private var colors: ReactionColors

    public init(settings: ReactiveSettings) {
        colors = ReactionColors(mode: settings.colorMode)
        rings.lifetime = settings.seconds * 1.1
        rings.span = settings.spanDevices
    }

    public var isActive: Bool { !rings.isEmpty }

    public func handle(_ event: InputEvent, context: FrameContext) {
        guard case .keyDown(let keyCode) = event else { return }
        let scene = context.scene
        if let point = scene.points.first(where: { $0.keyCode == keyCode }) {
            rings.add(origin: point.worldMM, device: point.device, time: context.time, color: colors.next(context.palette))
        } else if let keyboard = scene.firstDevice(of: .keyboard) {
            rings.add(origin: scene.centre(ofDevice: keyboard), device: keyboard, time: context.time,
                      color: colors.next(context.palette))
        }
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        rings.render(time: context.time, points: points, into: &output)
    }
}

/// The pressed key lights up in the reaction color and fades back to the base effect.
public final class KeyGlowLayer: OverlayLayer {
    private var glow: [Float] = []
    private var tint: [RGB] = []
    private var colors: ReactionColors
    private let lifetime: Float
    private var active = 0

    public init(settings: ReactiveSettings) {
        colors = ReactionColors(mode: settings.colorMode)
        lifetime = settings.seconds
    }

    public var isActive: Bool { active > 0 }

    public func handle(_ event: InputEvent, context: FrameContext) {
        guard case .keyDown(let keyCode) = event else { return }
        resize(context.scene.points.count)
        let color = colors.next(context.palette)
        for (i, point) in context.scene.points.enumerated() where point.keyCode == keyCode {
            if glow[i] <= 0 { active += 1 }
            glow[i] = 1
            tint[i] = color
        }
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        guard active > 0 else { return }
        resize(points.count)
        let step = context.dt / lifetime
        for i in points.indices where glow[i] > 0 {
            output[i] = RGB.mix(output[i], tint[i], glow[i] * glow[i])
            glow[i] -= step
            if glow[i] <= 0 {
                glow[i] = 0
                active -= 1
            }
        }
    }

    private func resize(_ count: Int) {
        guard glow.count != count else { return }
        glow = Array(repeating: 0, count: count)
        tint = Array(repeating: .black, count: count)
        active = 0
    }
}

/// Mouse clicks flash the mouse and send a ring from the mouse across the mat.
public final class ClickPulseLayer: OverlayLayer {
    private var rings = RingSet()
    private var colors: ReactionColors
    private var flash: Float = 0
    private var flashColor: RGB = .white
    private let lifetime: Float

    public init(settings: ReactiveSettings) {
        colors = ReactionColors(mode: settings.colorMode)
        lifetime = settings.seconds
        rings.lifetime = settings.seconds * 1.1
        rings.speed = 380
        rings.thickness = 36
        rings.span = true
        spanDevices = settings.spanDevices
    }

    private let spanDevices: Bool

    public var isActive: Bool { flash > 0 || !rings.isEmpty }

    public func handle(_ event: InputEvent, context: FrameContext) {
        guard case .mouseDown = event else { return }
        let scene = context.scene
        let color = colors.next(context.palette)
        flash = 1
        flashColor = color
        guard let mouse = scene.firstDevice(of: .mouse) ?? scene.firstDevice(of: .mousepad) else { return }
        rings.add(origin: scene.centre(ofDevice: mouse), device: mouse, time: context.time, color: color)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let scene = context.scene
        if flash > 0 {
            for (i, point) in points.enumerated() where scene.devices[point.device].kind == .mouse {
                output[i] = RGB.mix(output[i], flashColor, flash * flash)
            }
            flash = max(0, flash - context.dt / lifetime)
        }
        guard !rings.isEmpty else { return }
        if spanDevices {
            rings.render(time: context.time, points: points, into: &output)
        } else {
            // Without spanning, the pulse stays on the mouse and the mat it sits on.
            var subset: [ScenePoint] = []
            var indices: [Int] = []
            for (i, point) in points.enumerated() where [.mouse, .mousepad].contains(scene.devices[point.device].kind) {
                subset.append(point)
                indices.append(i)
            }
            var colors = indices.map { output[$0] }
            rings.render(time: context.time, points: subset, into: &colors)
            for (k, i) in indices.enumerated() { output[i] = colors[k] }
        }
    }
}
