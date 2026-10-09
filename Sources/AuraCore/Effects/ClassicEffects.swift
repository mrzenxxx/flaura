import Foundation

/// Maps a 0…1 control onto `slow…fast` exponentially, so the slider feels even across its range.
@inlinable
func rate(_ control: Float, _ slow: Float, _ fast: Float) -> Float {
    slow * powf(fast / slow, min(max(control, 0), 1))
}

@inlinable
func fraction(_ x: Double) -> Float {
    Float(x - x.rounded(.down))
}

extension ScenePoint {
    @inlinable
    func coordinate(span: Bool) -> SIMD2<Float> { span ? world : local }
}

public final class OffEffect: Effect {
    public let isAnimated = false
    public init() {}

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        for i in output.indices { output[i] = .black }
    }
}

/// Palette colors laid out as a gradient (a single color fills everything).
public final class StaticEffect: Effect {
    public let isAnimated = false
    let settings: EffectSettings

    public init(settings: EffectSettings) { self.settings = settings }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let single = context.palette.colors.count == 1
        for (i, point) in points.enumerated() {
            output[i] = single ? context.palette.colors[0] : context.palette.gradient(point.coordinate(span: settings.spanDevices).x)
        }
    }
}

/// Fades in and out; each breath moves on to the next palette color.
public final class BreathingEffect: Effect {
    public let isAnimated = true
    let period: Float

    public init(settings: EffectSettings) {
        period = rate(settings.speed, 9, 2.5)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let phase = context.time / Double(period)
        let index = Int(phase.rounded(.down)) % context.palette.colors.count
        let s = sinf(.pi * fraction(phase))
        let color = context.palette.colors[index] * (s * s)
        for i in output.indices { output[i] = color }
    }
}

/// Whole-spectrum cycling, identical on every device.
public final class SpectrumEffect: Effect {
    public let isAnimated = true
    let period: Float

    public init(settings: EffectSettings) {
        period = rate(settings.speed, 24, 3)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let color = RGB.hsv(fraction(context.time / Double(period)), 1, 1)
        for i in output.indices { output[i] = color }
    }
}

/// A travelling band of palette (or rainbow) colors.
public final class WaveEffect: Effect {
    public let isAnimated = true
    let settings: EffectSettings
    let cycles: Float
    let frequency: Float

    public init(settings: EffectSettings) {
        self.settings = settings
        cycles = lerp(2.6, 0.6, settings.intensity)
        frequency = rate(settings.speed, 0.08, 0.9)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let shift = fraction(context.time * Double(frequency))
        for (i, point) in points.enumerated() {
            let c = point.coordinate(span: settings.spanDevices)
            let along: Float
            switch settings.direction {
            case .right: along = c.x
            case .left: along = 1 - c.x
            case .down: along = c.y
            case .up: along = 1 - c.y
            }
            let phase = along * cycles - shift
            output[i] = settings.rainbow ? RGB.hsv(phase - phase.rounded(.down), 1, 1) : context.palette.loop(phase)
        }
    }
}

/// Palette colors flowing into each other like slow liquid (domain-warped noise).
public final class FlowEffect: Effect {
    public let isAnimated = true
    let settings: EffectSettings
    let scale: Float
    let speed: Float

    public init(settings: EffectSettings) {
        self.settings = settings
        scale = lerp(0.7, 3.2, settings.intensity)
        speed = rate(settings.speed, 0.03, 0.5)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let t = Float(context.time.truncatingRemainder(dividingBy: 10_000)) * speed
        let drift = fraction(context.time * Double(speed) * 0.15)
        for (i, point) in points.enumerated() {
            let c = point.coordinate(span: settings.spanDevices) * scale
            let warp = Noise.simplex(c.x * 0.7 + t * 0.6, c.y * 0.7 - t * 0.4)
            let n = Noise.fbm(c.x + warp * 0.9 + t * 0.3, c.y * 0.8 + warp * 0.6 - t * 0.2, octaves: 2)
            output[i] = context.palette.loop(n * 0.75 + 0.5 + drift)
        }
    }
}

/// The whole scene glides through the palette as one color.
public final class MorphEffect: Effect {
    public let isAnimated = true
    let secondsPerColor: Float

    public init(settings: EffectSettings) {
        secondsPerColor = rate(settings.speed, 12, 1.5)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let cycle = Double(secondsPerColor) * Double(context.palette.colors.count)
        let color = context.palette.loop(fraction(context.time / cycle))
        for i in output.indices { output[i] = color }
    }
}

/// Stars light up at random LEDs in palette colors and fade out over a dim background.
public final class StarlightEffect: Effect {
    public let isAnimated = true
    let spawnRate: Float
    let lifetime: Float
    private var life: [Float] = []
    private var colorIndex: [UInt8] = []
    private var rng = SplitMix64(seed: 0x57A2)

    public init(settings: EffectSettings) {
        spawnRate = lerp(0.03, 0.6, settings.intensity)
        lifetime = rate(settings.speed, 3.2, 0.5)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        if life.count != points.count {
            life = Array(repeating: 1, count: points.count)
            colorIndex = Array(repeating: 0, count: points.count)
        }
        let colors = context.palette.colors
        let background = context.palette.loop(fraction(context.time * 0.02)) * 0.035
        let step = context.dt / lifetime
        let p = spawnRate * context.dt
        for i in points.indices {
            if life[i] >= 1 {
                if rng.chance(p) {
                    life[i] = 0
                    colorIndex[i] = UInt8(rng.int(below: colors.count))
                }
            } else {
                life[i] = min(life[i] + step, 1)
            }
            if life[i] < 1 {
                let s = sinf(.pi * life[i])
                output[i] = RGB.screen(background, colors[Int(colorIndex[i]) % colors.count] * (s * s))
            } else {
                output[i] = background
            }
        }
    }
}

/// Two comets chasing each other around each device's edge.
public final class OrbitEffect: Effect {
    public let isAnimated = true
    let laps: Float
    let tail: Float

    public init(settings: EffectSettings) {
        laps = rate(settings.speed, 0.06, 0.7)
        tail = lerp(0.06, 0.45, settings.intensity)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let head = fraction(context.time * Double(laps))
        let first = context.palette.loop(head)
        let second = context.palette.loop(head + 0.5)
        for (i, point) in points.enumerated() {
            let base = context.palette.loop(point.perimeter) * 0.05
            let a = comet(head - point.perimeter)
            let b = comet(head + 0.5 - point.perimeter)
            output[i] = RGB.screen(RGB.screen(base, first * a), second * b)
        }
    }

    @inline(__always)
    private func comet(_ distance: Float) -> Float {
        let d = distance - distance.rounded(.down)
        guard d < tail else { return 0 }
        let k = 1 - d / tail
        return k * k
    }
}

/// Spectrum (or palette) rotating around each device's centre, like Synapse's Wheel.
public final class WheelEffect: Effect {
    public let isAnimated = true
    let settings: EffectSettings
    let turns: Float

    public init(settings: EffectSettings) {
        self.settings = settings
        let clockwise = settings.direction == .right || settings.direction == .down
        turns = rate(settings.speed, 0.05, 0.8) * (clockwise ? 1 : -1)
    }

    public func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let shift = fraction(context.time * Double(turns))
        for (i, point) in points.enumerated() {
            let phase = point.perimeter - shift
            output[i] = settings.rainbow ? RGB.hsv(phase - phase.rounded(.down), 1, 1) : context.palette.loop(phase)
        }
    }
}
