import Foundation

// The Aura Flame family. All variants map heat through the palette's ramp
// (black → first color → … → last color), so any palette turns into its own kind of fire.

/// Classic hearth fire: Fire2012-style heat diffusion on a 2D grid with lateral mixing.
final class HearthFlame: FlameGridEffect {
    private let cooling: Float
    private let sparkChance: Float

    init(settings: EffectSettings) {
        cooling = lerp(0.13, 0.05, settings.intensity)
        sparkChance = 0.22
        super.init(settings: settings, seed: 0x4EA27, slowSteps: 14, fastSteps: 55)
    }

    override func step() {
        let w = FlameGrid.width
        let h = FlameGrid.height
        for i in grid.heat.indices {
            grid.heat[i] = max(0, grid.heat[i] - rng.unit() * cooling)
        }
        for y in stride(from: h - 1, through: 2, by: -1) {
            for x in 0..<w {
                let rise = (grid[x, y - 1] + 2 * grid[x, y - 2]) / 3
                let side = (grid[x - 1, y - 1] + grid[x + 1, y - 1]) * 0.5
                grid[x, y] = rise * 0.82 + side * 0.18
            }
        }
        for x in 0..<w where rng.chance(sparkChance) {
            let y = rng.int(below: 3)
            grid[x, y] = min(1, grid[x, y] + rng.float(0.6...1))
        }
    }
}

/// Tall, aggressive Doom-style fire with a constant source and a white-hot core.
final class InfernoFlame: FlameGridEffect {
    private let decay: Float
    private var source: [Float] = Array(repeating: 1, count: FlameGrid.width)

    init(settings: EffectSettings) {
        decay = lerp(0.12, 0.045, settings.intensity)
        super.init(settings: settings, seed: 0x1F3E0, slowSteps: 20, fastSteps: 70)
    }

    override func step() {
        let w = FlameGrid.width
        let h = FlameGrid.height
        let t = simulatedTime
        for x in 0..<w {
            // The fire bed breathes slowly so it never reads as a flat band.
            let n = Noise.simplex(Float(x) * 0.18, t * 0.7)
            source[x] = min(1, 0.82 + 0.25 * n)
            grid[x, 0] = source[x]
        }
        for y in 1..<h {
            for x in 0..<w {
                let r = rng.int(below: 4)
                let below = grid[x, y - 1]
                let loss = Float(r & 1) * decay + rng.unit() * decay * 0.5
                grid[x - r + 1, y] = max(0, below - loss)
            }
        }
    }

    override func color(heat: Float, palette: PaletteLUT) -> RGB {
        let base = palette.ramp(heat)
        let core = smoothstep(0.82, 1, heat) * 0.55
        return RGB.mix(base, .white, core)
    }
}

/// Smouldering embers: a glowing, slowly pulsing coal bed with low flames and sparks drifting up.
final class EmbersFlame: FlameGridEffect {
    private struct Spark {
        var x: Float
        var y: Float
        var vy: Float
        var sway: Float
        var life: Float
    }

    private var sparks: [Spark] = []
    private let sparkRate: Float
    private var flame = FlameGrid()

    init(settings: EffectSettings) {
        sparkRate = lerp(0.05, 0.3, settings.intensity)
        super.init(settings: settings, seed: 0xE3BE5, slowSteps: 12, fastSteps: 40)
    }

    override func step() {
        let w = FlameGrid.width
        let h = FlameGrid.height
        let t = simulatedTime
        let dtStep = 1 / stepsPerSecond

        // Low licking flames: Fire2012 with strong cooling so they stay near the bottom.
        for i in flame.heat.indices {
            flame.heat[i] = max(0, flame.heat[i] - rng.unit() * 0.2)
        }
        for y in stride(from: h - 1, through: 2, by: -1) {
            for x in 0..<w {
                flame[x, y] = (flame[x, y - 1] + 2 * flame[x, y - 2]) / 3
            }
        }
        for x in 0..<w where rng.chance(0.12) {
            flame[x, rng.int(below: 2)] = rng.float(0.45...0.8)
        }

        if rng.chance(sparkRate) {
            sparks.append(Spark(x: rng.float(0...Float(w)), y: 1, vy: rng.float(5...11),
                                sway: rng.float(0...6.28), life: 1))
        }

        for x in 0..<w {
            let bed = 0.42 + 0.3 * Noise.fbm(Float(x) * 0.22, t * 0.35, octaves: 2)
            for y in 0..<h {
                let falloff = expf(-Float(y) * 0.55)
                grid[x, y] = max(bed * falloff, flame[x, y] * 0.85)
            }
        }

        var alive: [Spark] = []
        alive.reserveCapacity(sparks.count)
        for var spark in sparks {
            spark.y += spark.vy * dtStep
            spark.x += sinf(spark.sway + spark.y * 0.4) * 0.35
            spark.life -= dtStep * 0.55
            guard spark.life > 0, spark.y < Float(h) else { continue }
            let gx = Int(spark.x.rounded())
            let gy = Int(spark.y.rounded())
            grid[gx, gy] = min(1, grid[gx, gy] + spark.life)
            alive.append(spark)
        }
        sparks = alive
    }
}

/// Ghostly, smooth flames from domain-warped noise. Looks best with cold palettes (Лёд, Аврора).
final class WispFlame: Effect {
    let isAnimated = true
    private let settings: EffectSettings
    private let speed: Float
    private let height: Float
    private var boosts: [(u: Float, device: Int, time: Double)] = []

    init(settings: EffectSettings) {
        self.settings = settings
        speed = rate(settings.speed, 0.35, 2.2)
        height = lerp(0.55, 1.15, settings.intensity)
    }

    func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB]) {
        let t = Float(context.time.truncatingRemainder(dividingBy: 10_000)) * speed
        boosts.removeAll { context.time - $0.time > 1.2 }
        for (i, point) in points.enumerated() {
            let c = point.coordinate(span: settings.spanDevices)
            let phase: Float = settings.spanDevices ? 0 : Float(point.device) * 0.37
            let kind = point.device < context.scene.devices.count ? context.scene.devices[point.device].kind : .other
            let reach = settings.spanDevices ? 1 : FlameGridEffect.reach(for: kind)
            let x = (c.x + phase) * 3.2
            let up = (1 - c.y) * reach
            let warp = Noise.simplex(x * 0.55 + t * 0.25, up * 1.4 - t * 0.9)
            let n = Noise.fbm(x + warp * 0.8, up * 2.4 - t * 1.6, octaves: 3) * 0.5 + 0.5
            let shape = max(0, 1 - up / height)
            var heat = n * (0.35 + 0.95 * shape) * shape * 1.25
            for boost in boosts where boost.device == point.device || settings.spanDevices {
                let age = Float(context.time - boost.time)
                let du = abs(c.x - boost.u)
                heat += expf(-du * du * 60) * max(0, 1 - age / 1.2) * shape * 0.8
            }
            output[i] = context.palette.ramp(min(heat, 1))
        }
    }

    func handle(_ event: InputEvent, point: ScenePoint?, context: FrameContext) {
        guard case .keyDown = event, let point else { return }
        boosts.append((point.coordinate(span: settings.spanDevices).x, point.device, context.time))
    }
}

/// Wind-blown wildfire: flames lean with gusts and a fire front wanders along the devices.
final class WildfireFlame: FlameGridEffect {
    private let cooling: Float

    init(settings: EffectSettings) {
        cooling = lerp(0.12, 0.05, settings.intensity)
        super.init(settings: settings, seed: 0x3D7F1, slowSteps: 16, fastSteps: 60)
    }

    override func step() {
        let w = FlameGrid.width
        let h = FlameGrid.height
        let t = simulatedTime
        let wind = Noise.fbm(t * 0.25, 3.7, octaves: 2) * 1.6
        let front = (Noise.simplex(t * 0.08, 9.1) * 0.5 + 0.5) * Float(w) * 1.5

        for i in grid.heat.indices {
            grid.heat[i] = max(0, grid.heat[i] - rng.unit() * cooling)
        }
        for y in stride(from: h - 1, through: 2, by: -1) {
            // Higher rows are pushed further by the wind, so flames lean and curl.
            let shift = wind * Float(y) / Float(h) * 1.4
            let sx = Int(shift.rounded(.down))
            let fx = shift - Float(sx)
            for x in 0..<w {
                let a = (grid[x - sx, y - 1] + 2 * grid[x - sx, y - 2]) / 3
                let b = (grid[x - sx - 1, y - 1] + 2 * grid[x - sx - 1, y - 2]) / 3
                grid[x, y] = a + (b - a) * fx
            }
        }
        for x in 0..<w {
            var d = abs(Float(x) - front.truncatingRemainder(dividingBy: Float(w)))
            d = min(d, Float(w) - d)
            let chance = 0.08 + 0.55 * expf(-d * d / 40)
            if rng.chance(chance) {
                let y = rng.int(below: 3)
                grid[x, y] = min(1, grid[x, y] + rng.float(0.55...1))
            }
        }
    }
}
