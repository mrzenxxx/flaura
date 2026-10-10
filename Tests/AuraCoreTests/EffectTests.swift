import Foundation
import Testing
@testable import AuraCore

/// Renders `frames` frames of `effect` over the whole scene and returns the last frame.
@discardableResult
func run(_ effect: Effect, scene: SceneLayout, palette: Palette = .flame, frames: Int = 120,
         dt: Float = 1.0 / 30, check: ((Int, [RGB]) -> Void)? = nil) -> [RGB] {
    let lut = PaletteLUT(palette)
    var output = [RGB](repeating: .black, count: scene.points.count)
    for frame in 0..<frames {
        let context = FrameContext(time: Double(frame) * Double(dt), dt: dt, palette: lut, scene: scene)
        effect.render(context, points: scene.points, into: &output)
        check?(frame, output)
    }
    return output
}

@Suite struct EffectTests {
    let scene = sampleScene()

    @Test(arguments: EffectKind.allCases)
    func everyEffectProducesValidColors(kind: EffectKind) {
        for span in [false, true] {
            let effect = EffectFactory.make(EffectSettings(kind: kind, spanDevices: span))
            run(effect, scene: scene) { _, output in
                for c in output {
                    #expect(c.r.isFinite && c.g.isFinite && c.b.isFinite)
                    #expect(c.r >= -0.001 && c.r <= 1.01 && c.g >= -0.001 && c.g <= 1.01 && c.b >= -0.001 && c.b <= 1.01)
                }
            }
        }
    }

    @Test func staticAndOffAreNotAnimated() {
        #expect(!EffectFactory.make(EffectSettings(kind: .staticColor)).isAnimated)
        #expect(!EffectFactory.make(EffectSettings(kind: .off)).isAnimated)
        #expect(EffectFactory.make(EffectSettings(kind: .hearth)).isAnimated)
    }

    @Test func offIsBlack() {
        let output = run(OffEffect(), scene: scene, frames: 1)
        #expect(output.allSatisfy { $0 == .black })
    }

    @Test func staticSpreadsThePaletteAcross() {
        let output = run(StaticEffect(settings: EffectSettings(kind: .staticColor, spanDevices: true)), scene: scene, frames: 1)
        let leftmost = scene.points.indices.min { scene.points[$0].world.x < scene.points[$1].world.x }!
        let rightmost = scene.points.indices.max { scene.points[$0].world.x < scene.points[$1].world.x }!
        #expect(output[leftmost] != output[rightmost])
    }

    @Test(arguments: [EffectKind.hearth, .inferno, .wildfire])
    func flamesAreHotterAtTheBottom(kind: EffectKind) {
        let effect = EffectFactory.make(EffectSettings(kind: kind, intensity: 0.5))
        var bottom: Float = 0
        var top: Float = 0
        run(effect, scene: scene, frames: 240) { frame, output in
            guard frame >= 60 else { return }
            for i in scene.deviceRanges[0] {
                let row = scene.points[i].local.y
                if row > 0.85 { bottom += output[i].luma }
                if row < 0.15 { top += output[i].luma }
            }
        }
        #expect(bottom > 0)
        #expect(bottom > top * 1.5)
    }

    @Test func stokingAddsHeatToTheGrid() {
        let settings = EffectSettings(kind: .wildfire, speed: 0.5, intensity: 0.2)
        let calm = WildfireFlame(settings: settings)
        let stoked = WildfireFlame(settings: settings)
        let key = scene.points[scene.deviceRanges[0].lowerBound + 4 * 22 + 6]
        let context = FrameContext(time: 0, dt: 1.0 / 30, palette: PaletteLUT(.flame), scene: scene)
        stoked.handle(.keyDown(keyCode: 0), point: key, context: context)
        let column = Int(stoked.gridPosition(of: key, scene: scene).x.rounded())
        let heatCalm = (0..<3).map { calm.grid[column, $0] }.reduce(0, +)
        let heatStoked = (0..<3).map { stoked.grid[column, $0] }.reduce(0, +)
        #expect(heatStoked > heatCalm + 0.5)
    }

    @Test func stokingRaisesHearthFlamesAboveTheKey() {
        let settings = EffectSettings(kind: .hearth, intensity: 0.2)
        let calm = HearthFlame(settings: settings)
        let stoked = HearthFlame(settings: settings)
        let lut = PaletteLUT(.flame)
        let keyIndex = scene.deviceRanges[0].lowerBound + 4 * 22 + 6
        let context = FrameContext(time: 1, dt: 1.0 / 30, palette: lut, scene: scene)
        stoked.handle(.keyDown(keyCode: 0), point: scene.points[keyIndex], context: context)
        var a = [RGB](repeating: .black, count: scene.points.count)
        var b = a
        calm.render(context, points: scene.points, into: &a)
        stoked.render(context, points: scene.points, into: &b)
        // The keyboard column above the key (rows 0…3) gets hotter.
        let column = (0..<4).map { scene.deviceRanges[0].lowerBound + $0 * 22 + 6 }
        let calmHeat = column.map { a[$0].luma }.reduce(0, +)
        let stokedHeat = column.map { b[$0].luma }.reduce(0, +)
        #expect(stokedHeat > calmHeat + 0.2)
    }

    @Test func breathingReachesDarkAndBright() {
        var minLuma: Float = 1
        var maxLuma: Float = 0
        run(BreathingEffect(settings: EffectSettings(kind: .breathing, speed: 1)), scene: scene, frames: 200) { _, output in
            minLuma = min(minLuma, output[0].luma)
            maxLuma = max(maxLuma, output[0].luma)
        }
        #expect(minLuma < 0.05)
        #expect(maxLuma > 0.2)
    }

    @Test func effectsAreDeterministic() {
        let a = run(EffectFactory.make(EffectSettings(kind: .embers)), scene: scene, frames: 90)
        let b = run(EffectFactory.make(EffectSettings(kind: .embers)), scene: scene, frames: 90)
        #expect(a == b)
    }
}

@Suite struct ReactiveTests {
    let scene = sampleScene()

    func context(_ time: Double) -> FrameContext {
        FrameContext(time: time, dt: 1.0 / 30, palette: PaletteLUT(.flame), scene: scene)
    }

    @Test func rippleLightsUpAndFadesAway() {
        let layer = RippleLayer(settings: ReactiveSettings(colorMode: .white, duration: 0))
        #expect(!layer.isActive)
        let keyboardKey = scene.points[scene.deviceRanges[0]].first { $0.keyCode != nil }!
        layer.handle(.keyDown(keyCode: keyboardKey.keyCode!), context: context(0))
        #expect(layer.isActive)
        var output = [RGB](repeating: .black, count: scene.points.count)
        layer.render(context(0.1), points: scene.points, into: &output)
        #expect(output.contains { $0.luma > 0.3 })
        output = [RGB](repeating: .black, count: scene.points.count)
        layer.render(context(10), points: scene.points, into: &output)
        #expect(!layer.isActive)
        #expect(output.allSatisfy { $0 == .black })
    }

    @Test func keyGlowOnlyTouchesThatKey() {
        let layer = KeyGlowLayer(settings: ReactiveSettings(colorMode: .white))
        layer.handle(.keyDown(keyCode: 0), context: context(0))
        var output = [RGB](repeating: .black, count: scene.points.count)
        layer.render(context(0.01), points: scene.points, into: &output)
        let lit = output.indices.filter { output[$0].luma > 0.5 }
        #expect(lit.count == scene.points.filter { $0.keyCode == 0 }.count)
        #expect(lit.allSatisfy { scene.points[$0].keyCode == 0 })
    }

    @Test func clickFlashesTheMouse() {
        let layer = ClickPulseLayer(settings: ReactiveSettings(colorMode: .white, spanDevices: false))
        layer.handle(.mouseDown(button: 0), context: context(0))
        var output = [RGB](repeating: .black, count: scene.points.count)
        layer.render(context(0.02), points: scene.points, into: &output)
        for i in scene.deviceRanges[2] {
            #expect(output[i].luma > 0.5)
        }
        // Without spanning, the keyboard stays untouched.
        #expect(scene.deviceRanges[0].allSatisfy { output[$0] == .black })
    }
}
