import Foundation

/// Default placement of devices on the virtual desk: keyboard on the left, the mat to its right,
/// the mouse resting on the mat. Matches how most people sit, and gives cross-device effects a
/// sensible direction of travel.
public enum DeskArrangement {
    static let gap: Float = 30

    /// Returns a desk origin (top-left, millimetres) for each device, honouring explicit overrides.
    public static func origins(for devices: [(id: String, kind: DeviceKind, size: SIMD2<Float>)],
                               overrides: [String: SIMD2<Float>] = [:]) -> [String: SIMD2<Float>] {
        var result: [String: SIMD2<Float>] = [:]
        let keyboard = devices.first { $0.kind == .keyboard }
        let mat = devices.first { $0.kind == .mousepad }
        let tallest = max(keyboard?.size.y ?? 0, mat?.size.y ?? 0)

        var cursorX: Float = 0
        if let keyboard {
            result[keyboard.id] = SIMD2(0, (tallest - keyboard.size.y) / 2)
            cursorX = keyboard.size.x + gap
        }
        var matOrigin = SIMD2<Float>(cursorX, 0)
        if let mat {
            matOrigin = SIMD2(cursorX, (tallest - mat.size.y) / 2)
            result[mat.id] = matOrigin
        }
        var lowestY = tallest + gap
        for device in devices where result[device.id] == nil {
            switch device.kind {
            case .mouse:
                if let mat {
                    result[device.id] = matOrigin + SIMD2(mat.size.x * 0.58 - device.size.x / 2, mat.size.y * 0.3)
                } else {
                    result[device.id] = SIMD2(cursorX, max(0, (tallest - device.size.y) / 2))
                    cursorX += device.size.x + gap
                }
            default:
                // Anything else lines up below the main row.
                result[device.id] = SIMD2(0, lowestY)
                lowestY += device.size.y + gap
            }
        }
        for (id, origin) in overrides where result[id] != nil {
            result[id] = origin
        }
        return result
    }
}
