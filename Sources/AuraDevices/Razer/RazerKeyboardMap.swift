import AuraCore
import Foundation

/// Where each key sits in Razer's 6 × 22 full-size keyboard matrix, keyed to macOS virtual key
/// codes (`kVK_*`). Taken from OpenRGB's Cynosa Chroma V2 layout, which matches Polychromatic's
/// cynosa_v2_en_US map and OpenRazer's generic KEY_MAPPING. Column 0 is empty (no macro keys).
/// Media keys reach macOS as system-defined events, not key codes, so they have no entry.
enum RazerKeyboardMap {
    struct Key {
        let row: Int
        let column: Int
        let keyCode: UInt16
    }

    static let fullSize: [Key] = {
        let rows: [[(Int, UInt16)]] = [
            // Esc, F1–F12, PrtSc→F13, ScrLk→F14, Pause→F15
            [(1, 53), (3, 122), (4, 120), (5, 99), (6, 118), (7, 96), (8, 97), (9, 98), (10, 100),
             (11, 101), (12, 109), (13, 103), (14, 111), (15, 105), (16, 107), (17, 113)],
            // ` 1–0 - = Backspace, Ins→Help, Home, PgUp, NumLock→Clear, KP / * -
            [(1, 50), (2, 18), (3, 19), (4, 20), (5, 21), (6, 23), (7, 22), (8, 26), (9, 28), (10, 25),
             (11, 29), (12, 27), (13, 24), (14, 51), (15, 114), (16, 115), (17, 116), (18, 71), (19, 75),
             (20, 67), (21, 78)],
            // Tab Q–P [ ] \, Del, End, PgDn, KP 7 8 9 +
            [(1, 48), (2, 12), (3, 13), (4, 14), (5, 15), (6, 17), (7, 16), (8, 32), (9, 34), (10, 31),
             (11, 35), (12, 33), (13, 30), (14, 42), (15, 117), (16, 119), (17, 121), (18, 89), (19, 91),
             (20, 92), (21, 69)],
            // Caps A–L ; ' Enter, KP 4 5 6
            [(1, 57), (2, 0), (3, 1), (4, 2), (5, 3), (6, 5), (7, 4), (8, 38), (9, 40), (10, 37),
             (11, 41), (12, 39), (14, 36), (18, 86), (19, 87), (20, 88)],
            // LShift, ISO §, Z–M , . /, RShift, Up, KP 1 2 3 Enter
            [(1, 56), (2, 10), (3, 6), (4, 7), (5, 8), (6, 9), (7, 11), (8, 45), (9, 46), (10, 43),
             (11, 47), (12, 44), (14, 60), (16, 126), (18, 83), (19, 84), (20, 85), (21, 76)],
            // LCtrl, Win→Cmd, Alt→Option, Space, RAlt→ROption, Fn, Menu, RCtrl, ← ↓ →, KP 0 .
            [(1, 59), (2, 55), (3, 58), (7, 49), (11, 61), (12, 63), (13, 110), (14, 62), (15, 123),
             (16, 125), (17, 124), (19, 82), (20, 65)],
        ]
        return rows.enumerated().flatMap { row, keys in
            keys.map { Key(row: row, column: $0.0, keyCode: $0.1) }
        }
    }()
}

/// Physical layouts for Razer devices.
enum RazerLayouts {
    /// Standard key pitch.
    static let keyPitch: Float = 19.05

    /// Full-size keyboard: every matrix cell is a light (fire looks continuous), keys carry codes.
    static func keyboard(rows: Int, columns: Int) -> DeviceLayout {
        var layout = DeviceLayout.matrix(rows: rows, columns: columns, pitch: keyPitch)
        var codes: [Int: UInt16] = [:]
        for key in RazerKeyboardMap.fullSize where key.row < rows && key.column < columns {
            codes[key.row * columns + key.column] = key.keyCode
        }
        for i in layout.leds.indices {
            layout.leds[i].keyCode = codes[layout.leds[i].slot]
        }
        return layout
    }

    /// Mouse with lights stacked front to back: column 0 = scroll wheel, column 1 = logo
    /// (OpenRGB zone order; SignalRGB agrees).
    static func mouse(columns: Int) -> DeviceLayout {
        let size = SIMD2<Float>(62, 130)
        let leds = (0..<columns).map { column -> LEDPoint in
            let y = columns == 1 ? 65 : 28 + Float(column) * (70 / Float(columns - 1))
            return LEDPoint(slot: column, position: SIMD2(31, y))
        }
        return DeviceLayout(size: size, frameLength: columns, leds: leds)
    }

    /// Firefly V2: 19 LEDs around the edge. Grid positions (9 × 7) from SignalRGB's Firefly V2
    /// plugin: LED 0 is on the top edge right of centre, then counter-clockwise.
    static let fireflyV2Grid: [SIMD2<Float>] = [
        [5, 0], [4, 0], [1, 0], [0, 2], [0, 3], [0, 4], [0, 5], [1, 6], [3, 6], [4, 6],
        [5, 6], [6, 6], [7, 6], [8, 5], [8, 4], [8, 2], [8, 0], [7, 0], [6, 0],
    ].map { SIMD2<Float>($0[0], $0[1]) }

    static func fireflyV2() -> DeviceLayout {
        let size = SIMD2<Float>(355, 255)
        let leds = fireflyV2Grid.enumerated().map { slot, cell -> LEDPoint in
            let position = SIMD2(cell.x / 8 * size.x, cell.y / 6 * size.y)
            return LEDPoint(slot: slot, position: position, perimeter: perimeterParameter(position, size: size))
        }
        return DeviceLayout(size: size, frameLength: leds.count, leds: leds)
    }

    /// Generic edge-lit mat with LEDs spread evenly clockwise from the top-left.
    static func mat(count: Int) -> DeviceLayout {
        DeviceLayout.perimeter(count: count, size: SIMD2(355, 255))
    }

    /// Inverse of `DeviceLayout.pointOnPerimeter`: clockwise 0..<1 from the top-left corner.
    static func perimeterParameter(_ p: SIMD2<Float>, size: SIMD2<Float>) -> Float {
        let total = 2 * (size.x + size.y)
        let distances: [(Float, Float)] = [
            (abs(p.y), p.x),                                        // top edge, left → right
            (abs(p.x - size.x), size.x + p.y),                      // right edge, top → bottom
            (abs(p.y - size.y), size.x + size.y + (size.x - p.x)),  // bottom edge, right → left
            (abs(p.x), 2 * size.x + size.y + (size.y - p.y)),       // left edge, bottom → top
        ]
        let along = distances.min { $0.0 < $1.0 }!.1
        return wrapUnit(along / total)
    }
}
