import Foundation
import Testing
@testable import AuraCore

@Suite struct ColorTests {
    @Test func hexRoundTrip() throws {
        let color = try #require(RGB(hex: "#FF5A00"))
        #expect(color.hex == "#FF5A00")
        #expect(RGB(hex: "ff5a00") == color)
        #expect(RGB(hex: "nope") == nil)
        #expect(RGB(hex: "#12345") == nil)
    }

    @Test func okLabRoundTrip() {
        for color in [RGB(1, 0, 0), RGB(0, 1, 0), RGB(0, 0, 1), RGB(0.2, 0.5, 0.8), .white, .black] {
            let back = OKLab(color).rgb
            #expect(abs(back.r - color.r) < 0.01)
            #expect(abs(back.g - color.g) < 0.01)
            #expect(abs(back.b - color.b) < 0.01)
        }
    }

    @Test func hsvPrimaries() {
        #expect(RGB.hsv(0, 1, 1) == RGB(1, 0, 0))
        let green = RGB.hsv(1.0 / 3.0, 1, 1)
        #expect(green.g > 0.99 && green.r < 0.01 && green.b < 0.01)
        let blue = RGB.hsv(2.0 / 3.0, 1, 1)
        #expect(blue.b > 0.99 && blue.r < 0.01 && blue.g < 0.01)
        // Hue wraps around.
        #expect(RGB.hsv(1.25, 1, 1) == RGB.hsv(0.25, 1, 1))
    }

    @Test func screenNeverExceedsWhite() {
        let c = RGB.screen(RGB(0.9, 0.5, 1), RGB(0.9, 0.9, 1))
        #expect(c.r <= 1 && c.g <= 1 && c.b <= 1)
        #expect(c.r > 0.9)
    }
}

@Suite struct PaletteTests {
    @Test func normalisesColorCount() {
        #expect(Palette(name: "empty", colors: []).colors == [.white])
        let many = Palette(name: "many", colors: Array(repeating: RGB(1, 0, 0), count: 6))
        #expect(many.colors.count == Palette.maxColors)
    }

    @Test func rampStartsBlackAndEndsOnHottestColor() {
        let lut = PaletteLUT(.flame)
        #expect(lut.ramp(0).luma < 0.01)
        let last = Palette.flame.colors.last!
        let end = lut.ramp(1)
        #expect(abs(end.r - last.r) < 0.02 && abs(end.g - last.g) < 0.02 && abs(end.b - last.b) < 0.02)
        #expect(lut.ramp(-5) == lut.ramp(0))
        #expect(lut.ramp(7) == lut.ramp(1))
    }

    @Test func loopIsSeamless() {
        let lut = PaletteLUT(.synthwave)
        #expect(lut.loop(0) == lut.loop(1))
        #expect(lut.loop(0.25) == lut.loop(3.25))
        #expect(lut.loop(-0.75) == lut.loop(0.25))
        // Neighbouring entries are close: no hard seam at the wrap point.
        let a = lut.loopTable[PaletteLUT.size - 1]
        let b = lut.loopTable[0]
        #expect(abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) < 0.15)
    }

    @Test func gradientEndsOnFirstAndLastColors() {
        let lut = PaletteLUT(.ocean)
        let first = Palette.ocean.colors.first!
        #expect(abs(lut.gradient(0).g - first.g) < 0.02)
        #expect(PaletteLUT(Palette(name: "one", colors: [RGB(1, 0, 0)])).gradient(0.7).r > 0.99)
    }

    @Test func brightestByLuma() {
        let lut = PaletteLUT(Palette(name: "x", colors: [RGB(0.1, 0, 0), RGB(1, 1, 0.5), RGB(0, 0, 1)]))
        #expect(lut.brightest == RGB(1, 1, 0.5))
    }

    @Test func codableAsHex() throws {
        let data = try JSONEncoder().encode(Palette.ice)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("#0B2BFF"))
        let back = try JSONDecoder().decode(Palette.self, from: data)
        #expect(back.colors.map(\.hex) == Palette.ice.colors.map(\.hex))
    }
}

@Suite struct SettingsDecodingTests {
    @Test func clampsAndFallsBack() throws {
        let json = """
        {"brightness": 7, "gamma": 0.2, "effect": {"kind": "inferno", "speed": -3, "intensity": 2},
         "reactive": {"duration": 9}, "devices": {"x": {"gain": 5}}, "framesPerSecond": 500, "version": 2}
        """
        let s = try JSONDecoder().decode(AuraSettings.self, from: Data(json.utf8))
        #expect(s.brightness == 1)
        #expect(s.gamma == 1)
        #expect(s.effect.kind == .inferno && s.effect.speed == 0 && s.effect.intensity == 1)
        #expect(s.reactive.duration == 1)
        #expect(s.devices["x"]?.gain == 1)
        #expect(s.framesPerSecond == 60)
        #expect(s.palette == .flame)
    }

    @Test func migratesOldDefaults() throws {
        let old = #"{"brightness": 0.85, "gamma": 1.8}"#
        let migrated = try JSONDecoder().decode(AuraSettings.self, from: Data(old.utf8))
        #expect(migrated.gamma == AuraSettings().gamma)
        #expect(migrated.brightness == AuraSettings().brightness)
        // A user's own choice is kept, and v2 files are left alone.
        let custom = try JSONDecoder().decode(AuraSettings.self, from: Data(#"{"brightness": 0.5, "gamma": 2.0}"#.utf8))
        #expect(custom.brightness == 0.5 && custom.gamma == 2.0)
        let v2 = try JSONDecoder().decode(AuraSettings.self, from: Data(#"{"gamma": 1.8, "version": 2}"#.utf8))
        #expect(v2.gamma == 1.8)
    }

    @Test func roundTrips() throws {
        var settings = AuraSettings()
        settings.paletteFlow = true
        settings.devices["razer:025e"] = DeviceSettings(enabled: false, gain: 0.4,
                                                        effect: EffectSettings(kind: .orbit), origin: SIMD2(10, 20))
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AuraSettings.self, from: data) == settings)
    }
}
