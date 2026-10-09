import Foundation
import Testing
@testable import AuraCore

/// A small scene resembling the real desk: keyboard, mat and mouse.
func sampleScene() -> SceneLayout {
    var keyboard = DeviceLayout.matrix(rows: 6, columns: 22, pitch: 19.05)
    for i in keyboard.leds.indices {
        keyboard.leds[i].keyCode = UInt16(keyboard.leds[i].slot)
    }
    let mat = DeviceLayout.perimeter(count: 19, size: SIMD2(355, 255))
    let mouse = DeviceLayout(size: SIMD2(62, 130), frameLength: 2, leds: [
        LEDPoint(slot: 0, position: SIMD2(31, 28)),
        LEDPoint(slot: 1, position: SIMD2(31, 98)),
    ])
    let entries = [
        (id: "kb", kind: DeviceKind.keyboard, size: keyboard.size),
        (id: "mat", kind: DeviceKind.mousepad, size: mat.size),
        (id: "mouse", kind: DeviceKind.mouse, size: mouse.size),
    ]
    let origins = DeskArrangement.origins(for: entries)
    return SceneLayout(devices: [
        SceneDevice(id: "kb", kind: .keyboard, layout: keyboard, origin: origins["kb"]!),
        SceneDevice(id: "mat", kind: .mousepad, layout: mat, origin: origins["mat"]!),
        SceneDevice(id: "mouse", kind: .mouse, layout: mouse, origin: origins["mouse"]!),
    ])
}

@Suite struct LayoutTests {
    @Test func matrixSlotsAreRowMajor() {
        let layout = DeviceLayout.matrix(rows: 2, columns: 3, pitch: 10)
        #expect(layout.frameLength == 6)
        #expect(layout.size == SIMD2(30, 20))
        #expect(layout.leds.map(\.slot) == [0, 1, 2, 3, 4, 5])
        #expect(layout.leds[4].position == SIMD2(15, 15))
    }

    @Test func perimeterPointsSitOnTheEdge() {
        let size = SIMD2<Float>(300, 200)
        let layout = DeviceLayout.perimeter(count: 20, size: size)
        for led in layout.leds {
            let p = led.position
            let onEdge = abs(p.x) < 0.01 || abs(p.y) < 0.01 || abs(p.x - size.x) < 0.01 || abs(p.y - size.y) < 0.01
            #expect(onEdge)
            #expect(led.perimeter! >= 0 && led.perimeter! < 1)
        }
        // Clockwise from the top-left: the first LEDs are on the top edge.
        #expect(layout.leds[0].position.y == 0)
    }

    @Test func pointOnPerimeterCorners() {
        let size = SIMD2<Float>(4, 2)
        #expect(DeviceLayout.pointOnPerimeter(0, size: size) == SIMD2(0, 0))
        #expect(DeviceLayout.pointOnPerimeter(4.0 / 12, size: size) == SIMD2(4, 0))
        #expect(DeviceLayout.pointOnPerimeter(6.0 / 12, size: size) == SIMD2(4, 2))
        #expect(DeviceLayout.pointOnPerimeter(10.0 / 12, size: size) == SIMD2(0, 2))
    }

    @Test func sceneNormalisesCoordinates() {
        let scene = sampleScene()
        #expect(scene.points.count == 132 + 19 + 2)
        #expect(scene.deviceRanges.map(\.count) == [132, 19, 2])
        for point in scene.points {
            #expect(point.local.x >= 0 && point.local.x <= 1 && point.local.y >= 0 && point.local.y <= 1)
            #expect(point.world.x >= 0 && point.world.x <= 1 && point.world.y >= 0 && point.world.y <= 1)
            #expect(point.perimeter >= 0 && point.perimeter < 1)
            #expect(point.seed >= 0 && point.seed < 1)
        }
    }

    @Test func deskPutsKeyboardLeftMatRightMouseOnMat() {
        let scene = sampleScene()
        let kb = scene.devices[0]
        let mat = scene.devices[1]
        let mouse = scene.devices[2]
        #expect(kb.origin.x == 0)
        #expect(mat.origin.x > kb.layout.size.x)
        #expect(mouse.origin.x > mat.origin.x && mouse.origin.x + mouse.layout.size.x < mat.origin.x + mat.layout.size.x)
        #expect(mouse.origin.y > mat.origin.y && mouse.origin.y + mouse.layout.size.y < mat.origin.y + mat.layout.size.y)
    }

    @Test func deskOverridesWin() {
        let origins = DeskArrangement.origins(
            for: [(id: "kb", kind: .keyboard, size: SIMD2(400, 120))],
            overrides: ["kb": SIMD2(50, 60), "ghost": SIMD2(1, 1)]
        )
        #expect(origins == ["kb": SIMD2(50, 60)])
    }
}
