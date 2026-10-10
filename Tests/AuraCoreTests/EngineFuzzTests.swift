import Foundation
import Testing
@testable import AuraCore

/// Hammers the engine the way a user poking at the panel would — every control, in any order,
/// faster than any human — plus input events and devices coming and going.
@Suite(.serialized) struct EngineFuzzTests {
    func randomSettings(_ rng: inout SplitMix64) -> AuraSettings {
        var s = AuraSettings()
        s.enabled = rng.chance(0.9)
        let count = 1 + rng.int(below: Palette.maxColors)
        s.palette = Palette(name: "fuzz", colors: (0..<count).map { _ in RGB(rng.unit(), rng.unit(), rng.unit()) })
        s.paletteFlow = rng.chance(0.4)
        s.paletteFlowSpeed = rng.unit()
        s.effect = EffectSettings(kind: EffectKind.allCases[rng.int(below: EffectKind.allCases.count)],
                                  speed: rng.unit(), intensity: rng.unit(),
                                  direction: Direction.allCases[rng.int(below: 4)],
                                  spanDevices: rng.chance(0.5), rainbow: rng.chance(0.3))
        s.reactive = ReactiveSettings(ripple: rng.chance(0.5), keyGlow: rng.chance(0.5), clickPulse: rng.chance(0.5),
                                      stoke: rng.chance(0.5),
                                      colorMode: ReactiveColorMode.allCases[rng.int(below: 3)],
                                      duration: rng.unit(), spanDevices: rng.chance(0.5))
        s.brightness = rng.chance(0.2) ? 0.05 : rng.unit()
        s.gamma = rng.float(1...2.6)
        s.framesPerSecond = [20, 30, 45, 60][rng.int(below: 4)]
        s.dimWhenIdle = rng.chance(0.5)
        for id in ["kb", "mat", "mouse"] where rng.chance(0.3) {
            s.devices[id] = DeviceSettings(
                enabled: rng.chance(0.8), gain: rng.unit(),
                effect: rng.chance(0.5) ? EffectSettings(kind: EffectKind.allCases[rng.int(below: EffectKind.allCases.count)]) : nil,
                origin: rng.chance(0.2) ? SIMD2(rng.float(0...600), rng.float(0...300)) : nil
            )
        }
        return s
    }

    @Test func survivesRandomUseAndKeepsRendering() {
        var rng = SplitMix64(seed: 0xF00D)
        let keyboard = FakeDevice(id: "kb", kind: .keyboard, layout: {
            var layout = DeviceLayout.matrix(rows: 6, columns: 22, pitch: 19.05)
            for i in layout.leds.indices { layout.leds[i].keyCode = UInt16(i % 120) }
            return layout
        }())
        let mat = FakeDevice(id: "mat", kind: .mousepad, layout: .perimeter(count: 19, size: SIMD2(355, 255)))
        let mouse = FakeDevice(id: "mouse", kind: .mouse, layout: DeviceLayout(size: SIMD2(62, 130), frameLength: 2, leds: [
            LEDPoint(slot: 0, position: SIMD2(31, 28)), LEDPoint(slot: 1, position: SIMD2(31, 98)),
        ]))
        let all: [any LightingDevice] = [keyboard, mat, mouse]
        let engine = RenderEngine()
        engine.apply(AuraSettings())
        engine.setDevices(all)

        let deadline = Date().addingTimeInterval(4)
        var iteration = 0
        while Date() < deadline {
            switch rng.int(below: 10) {
            case 0...3: engine.apply(randomSettings(&rng))
            case 4...6: engine.post(rng.chance(0.7) ? .keyDown(keyCode: UInt16(rng.int(below: 130))) : .mouseDown(button: rng.int(below: 3)))
            case 7: engine.setDevices(all.filter { _ in rng.chance(0.7) })
            case 8: engine.setSuspended(rng.chance(0.5))
            default: engine.setDevices(all)
            }
            iteration += 1
            Thread.sleep(forTimeInterval: 0.002)
        }

        // Back to a known animated state: frames must still flow to every device.
        engine.setSuspended(false)
        engine.setDevices(all)
        engine.apply(AuraSettings(effect: EffectSettings(kind: .hearth), framesPerSecond: 60))
        let before = all.map { ($0 as! FakeDevice).frames.count }
        #expect(waitUntil(timeout: 2) {
            zip(all, before).allSatisfy { ($0.0 as! FakeDevice).frames.count > $0.1 + 3 }
        })
        for device in all {
            let frames = (device as! FakeDevice).frames
            #expect(frames.allSatisfy { $0.count == device.layout.frameLength })
        }
        #expect(iteration > 500)
        engine.shutdown()
    }
}
