import Foundation

/// A small heat field (row 0 = bottom) that flame simulations run on. It wraps horizontally,
/// so devices can sample it at different phases without seams. LEDs sample it bilinearly.
struct FlameGrid {
    static let width = 44
    static let height = 22

    var heat: [Float]
    /// Heat as displayed: eased towards `heat` each frame so LEDs glow rather than strobe.
    var display: [Float]

    init() {
        heat = Array(repeating: 0, count: FlameGrid.width * FlameGrid.height)
        display = heat
    }

    @inline(__always)
    static func index(_ x: Int, _ y: Int) -> Int {
        let wx = ((x % width) + width) % width
        return y * width + wx
    }

    @inline(__always)
    subscript(x: Int, y: Int) -> Float {
        get { heat[FlameGrid.index(x, y)] }
        set { heat[FlameGrid.index(x, y)] = newValue }
    }

    mutating func ease(dt: Float, rate: Float) {
        let k = min(1, dt * rate)
        for i in heat.indices {
            display[i] += (heat[i] - display[i]) * k
        }
    }

    /// Bilinear sample of the displayed heat. `gx` wraps; `gy` is clamped to the grid.
    func sample(_ gx: Float, _ gy: Float) -> Float {
        let w = FlameGrid.width
        let y = min(max(gy, 0), Float(FlameGrid.height - 1))
        let x0f = gx.rounded(.down)
        let y0 = Int(y.rounded(.down))
        let y1 = min(y0 + 1, FlameGrid.height - 1)
        let fx = gx - x0f
        let fy = y - Float(y0)
        let x0 = ((Int(x0f) % w) + w) % w
        let x1 = (x0 + 1) % w
        let a = display[y0 * w + x0] + (display[y0 * w + x1] - display[y0 * w + x0]) * fx
        let b = display[y1 * w + x0] + (display[y1 * w + x1] - display[y1 * w + x0]) * fx
        return a + (b - a) * fy
    }

    /// Box-filtered sample over an LED's footprint: the centre plus four taps `radius` cells away.
    /// Point sampling a coarse grid aliases into flicker, especially on sparse LEDs (mouse, mat).
    func sample(_ gx: Float, _ gy: Float, radius: Float) -> Float {
        guard radius > 0 else { return sample(gx, gy) }
        let r = radius * 0.7071
        return (sample(gx, gy) * 2 + sample(gx - r, gy - r) + sample(gx + r, gy - r)
            + sample(gx - r, gy + r) + sample(gx + r, gy + r)) / 6
    }

    /// Adds a burst of heat around column `gx` near the bottom (typing "stokes" the fire).
    mutating func stoke(at gx: Float, amount: Float) {
        let x = Int(gx.rounded())
        for dx in -1...1 {
            for y in 0..<3 {
                let falloff: Float = dx == 0 ? 1 : 0.6
                self[x + dx, y] = min(1, self[x + dx, y] + amount * falloff)
            }
        }
    }
}

/// Shared plumbing for flame effects: fixed-rate simulation steps, sampling LEDs into the grid,
/// palette mapping and stoking. Subclasses implement `step()`.
class FlameGridEffect: Effect {
    let isAnimated = true
    let settings: EffectSettings
    var grid = FlameGrid()
    var rng: SplitMix64
    let stepsPerSecond: Float
    /// How quickly displayed heat follows the simulation; lower is silkier.
    let easeRate: Float
    private var accumulator: Float = 0
    var simulatedTime: Float = 0

    init(settings: EffectSettings, seed: UInt64, slowSteps: Float = 16, fastSteps: Float = 60) {
        self.settings = settings
        rng = SplitMix64(seed: seed)
        stepsPerSecond = rate(settings.speed, slowSteps, fastSteps)
        easeRate = lerp(4, 9, settings.speed)
    }

    /// Advances the simulation by one fixed step.
    func step() {}

    /// Runs the simulation for a few seconds up front so a new flame starts already burning
    /// (switching effects or tweaking a slider would otherwise restart from a cold grid).
    func warmUp(seconds: Float = 3) {
        for _ in 0..<Int(seconds * stepsPerSecond) {
            simulatedTime += 1 / stepsPerSecond
            step()
        }
        grid.display = grid.heat
    }

    /// Converts heat to a color; Inferno overrides this to add a white-hot core.
    func color(heat: Float, palette: PaletteLUT) -> RGB {
        palette.ramp(heat)
    }

    func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        accumulator += context.dt * stepsPerSecond
        var steps = 0
        while accumulator >= 1 && steps < 4 {
            simulatedTime += 1 / stepsPerSecond
            step()
            accumulator -= 1
            steps += 1
        }
        if steps == 4 { accumulator = 0 }
        grid.ease(dt: context.dt, rate: easeRate)
        for (i, point) in points.enumerated() {
            let g = gridPosition(of: point, scene: context.scene)
            let kind = point.device < context.scene.devices.count ? context.scene.devices[point.device].kind : .other
            output[i] = color(heat: grid.sample(g.x, g.y, radius: FlameGridEffect.footprint(for: kind)), palette: context.palette)
        }
    }

    func handle(_ event: InputEvent, point: ScenePoint?, context: FrameContext) {
        guard case .keyDown = event, let point else { return }
        grid.stoke(at: gridPosition(of: point, scene: context.scene).x, amount: 0.9)
    }

    /// Where an LED lands in the heat field. Each device repeats the fire (shifted so they do not
    /// look identical) unless the effect spans the desk; small devices sit lower in the flames.
    func gridPosition(of point: ScenePoint, scene: SceneLayout) -> SIMD2<Float> {
        let c = point.coordinate(span: settings.spanDevices)
        let phase: Float = settings.spanDevices ? 0 : Float(point.device) * 0.37
        let kind = point.device < scene.devices.count ? scene.devices[point.device].kind : .other
        let reach: Float = settings.spanDevices ? 1 : FlameGridEffect.reach(for: kind)
        let gx = (c.x + phase) * Float(FlameGrid.width)
        let gy = (1 - c.y) * Float(FlameGrid.height - 1) * reach
        return SIMD2(gx, gy)
    }

    /// Sampling radius in grid cells: roughly the area one LED stands for.
    static func footprint(for kind: DeviceKind) -> Float {
        switch kind {
        case .keyboard: 1
        case .mouse: 2.5
        default: 2
        }
    }

    /// Vertical squeeze per device kind: a mouse is short, so it lives in the hot part of the fire.
    static func reach(for kind: DeviceKind) -> Float {
        switch kind {
        case .mouse: 0.4
        case .mousepad: 0.75
        default: 1
        }
    }
}
