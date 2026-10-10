import AuraCore
import AuraDevices
import Foundation

// Hardware diagnostics without the UI.
//
//   aura-cli list                              connected devices
//   aura-cli pattern                           orientation test pattern (see below)
//   aura-cli run <effect> [seconds] [palette]  run an effect through the real engine
//   aura-cli bench [frames]                    time full-frame writes per device
//   aura-cli restore [static|spectrum|off]     hand devices back to the hardware

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "list"

/// Waits for the provider's first device list (it arrives on the provider's queue).
func discover(timeout: TimeInterval = 3) -> [any LightingDevice] {
    let registry = DeviceRegistry(providers: DeviceRegistry.standardProviders { print("  · \($0)") })
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var found: [any LightingDevice] = []
    registry.start { devices in
        found = devices
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + timeout)
    // Let the remaining devices of the initial burst arrive.
    Thread.sleep(forTimeInterval: 0.2)
    return found
}

func frame(for device: any LightingDevice, _ color: (LEDPoint) -> RGB8) -> [RGB8] {
    var frame = [RGB8](repeating: .black, count: device.layout.frameLength)
    for led in device.layout.leds {
        frame[led.slot] = color(led)
    }
    return frame
}

switch command {
case "list":
    let devices = discover()
    if devices.isEmpty { print("No supported devices found.") }
    for device in devices {
        print("\(device.info.name)  [\(device.info.id)]  \(device.info.kind.rawValue)  \(device.info.detail)  LEDs: \(device.layout.leds.count)")
    }

case "pattern":
    // Keyboard: Esc red, F-row orange, W A S D green, arrows blue, everything else dim white.
    // Mouse: scroll wheel (slot 0) red, logo (slot 1) blue.
    // Mat: LED 0 red, LED 1 orange, LED 2 yellow, last LED green, others dim blue.
    let wasd: Set<UInt16> = [13, 0, 1, 2]
    let arrows: Set<UInt16> = [123, 124, 125, 126]
    let fRow: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
    for device in discover() {
        let last = device.layout.frameLength - 1
        let f = frame(for: device) { led in
            switch device.info.kind {
            case .keyboard:
                guard let code = led.keyCode else { return RGB8(0, 0, 0) }
                if code == 53 { return RGB8(255, 0, 0) }
                if fRow.contains(code) { return RGB8(255, 90, 0) }
                if wasd.contains(code) { return RGB8(0, 255, 0) }
                if arrows.contains(code) { return RGB8(0, 60, 255) }
                return RGB8(25, 25, 25)
            case .mouse:
                return led.slot == 0 ? RGB8(255, 0, 0) : RGB8(0, 60, 255)
            default:
                switch led.slot {
                case 0: return RGB8(255, 0, 0)
                case 1: return RGB8(255, 90, 0)
                case 2: return RGB8(255, 220, 0)
                case last: return RGB8(0, 255, 0)
                default: return RGB8(0, 0, 60)
                }
            }
        }
        do {
            try device.prepare()
            try device.write(f)
            print("pattern → \(device.info.name)")
        } catch {
            print("pattern failed on \(device.info.name): \(error)")
        }
    }

case "bench":
    let frames = Int(arguments.dropFirst().first ?? "") ?? 120
    for device in discover() {
        do {
            try device.prepare()
            let start = DispatchTime.now().uptimeNanoseconds
            for i in 0..<frames {
                // Alternate two frames so every row changes every time (worst case).
                let level = UInt8(i % 2 == 0 ? 40 : 0)
                try device.write(frame(for: device) { _ in RGB8(level, 0, 0) })
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(frames)
            print(String(format: "%@: %.2f ms per full frame (max %.0f FPS)", device.info.name, ms, 1000 / ms))
        } catch {
            print("bench failed on \(device.info.name): \(error)")
        }
    }

case "run":
    let kindName = arguments.dropFirst().first ?? "hearth"
    guard let kind = EffectKind(rawValue: kindName) else {
        print("Unknown effect '\(kindName)'. Effects: \(EffectKind.allCases.map(\.rawValue).joined(separator: ", "))")
        exit(1)
    }
    let seconds = Double(arguments.dropFirst(2).first ?? "") ?? 10
    let paletteName = arguments.dropFirst(3).first
    var settings = AuraSettings()
    settings.effect.kind = kind
    if let paletteName, let palette = Palette.presets.first(where: { $0.name.lowercased() == paletteName.lowercased() }) {
        settings.palette = palette
    }
    let devices = discover()
    let engine = RenderEngine()
    engine.setHandlers(activity: { print("  engine animating: \($0)") }, health: { print("  \($0): \($1)") })
    engine.apply(settings)
    engine.setDevices(devices)
    let usageStart = getrusage_self()
    let wallStart = Date()
    print("Running \(kind.rawValue) on \(devices.count) device(s) for \(seconds)s…")
    // Simulated typing so reactive layers and stoking can be seen without the app.
    var typing: DispatchSourceTimer?
    if arguments.contains("--typing") {
        let codes: [UInt16] = [0, 1, 2, 3, 13, 14, 15, 49, 36, 38, 40]
        nonisolated(unsafe) var n = 0
        let source = DispatchSource.makeTimerSource(queue: .global())
        source.schedule(deadline: .now() + 1, repeating: 0.7)
        source.setEventHandler { @Sendable in
            engine.post(n % 5 == 4 ? .mouseDown(button: 0) : .keyDown(keyCode: codes[n % codes.count]))
            n += 1
        }
        source.resume()
        typing = source
    }
    Thread.sleep(forTimeInterval: seconds)
    typing?.cancel()
    let usageEnd = getrusage_self()
    let cpu = usageEnd - usageStart
    let wall = Date().timeIntervalSince(wallStart)
    print(String(format: "CPU: %.1f%% of one core (%.2fs CPU over %.1fs)", cpu / wall * 100, cpu, wall))
    engine.shutdown()

case "profile":
    // Offline tuning aid. Per device: mean perceived level, "motion" (how much each LED moves over
    // time, wanted) and "jitter" (frame-to-frame jumps, unwanted). Keyboard rows listed top→bottom.
    let kinds = arguments.dropFirst().first.flatMap(EffectKind.init(rawValue:)).map { [$0] } ?? EffectKind.flames
    let speed = Float(arguments.dropFirst(2).first ?? "") ?? 0.5
    let intensity = Float(arguments.dropFirst(3).first ?? "") ?? 0.5
    let descriptors = RazerCatalog.builtIn
    let entries = descriptors.map { (id: String($0.productID), kind: $0.kind, size: $0.makeLayout().size) }
    let origins = DeskArrangement.origins(for: entries)
    let scene = SceneLayout(devices: descriptors.map {
        SceneDevice(id: String($0.productID), kind: $0.kind, layout: $0.makeLayout(), origin: origins[String($0.productID)]!)
    })
    let gamma = AuraSettings().gamma
    let lut = PaletteLUT(.flame)
    // Average of luma and peak channel: luma alone under-rates saturated reds, which carry fire.
    func level(_ c: RGB) -> Float {
        let luma = 0.2126 * powf(c.r, gamma) + 0.7152 * powf(c.g, gamma) + 0.0722 * powf(c.b, gamma)
        return (luma + powf(max(c.r, max(c.g, c.b)), gamma)) / 2
    }
    for kind in kinds {
        let effect = EffectFactory.make(EffectSettings(kind: kind, speed: speed, intensity: intensity))
        let n = scene.points.count
        var output = [RGB](repeating: .black, count: n)
        var previous = [Float](repeating: 0, count: n)
        var sum = [Float](repeating: 0, count: n)
        var sumSq = [Float](repeating: 0, count: n)
        var jitter = [Float](repeating: 0, count: n)
        let frames = 300
        for frame in 0..<frames {
            effect.render(FrameContext(time: Double(frame) / 30, dt: 1.0 / 30, palette: lut, scene: scene), points: scene.points, into: &output)
            for i in 0..<n {
                let l = level(output[i])
                sum[i] += l
                sumSq[i] += l * l
                if frame > 0 { jitter[i] += abs(l - previous[i]) }
                previous[i] = l
            }
        }
        func stats(_ indices: [Int]) -> (mean: Float, motion: Float, jitter: Float) {
            var m: Float = 0, sd: Float = 0, j: Float = 0
            for i in indices {
                let mean = sum[i] / Float(frames)
                m += mean
                sd += sqrtf(max(0, sumSq[i] / Float(frames) - mean * mean))
                j += jitter[i] / Float(frames - 1)
            }
            let c = Float(indices.count)
            return (m / c, sd / c, j / c)
        }
        let keyboard = scene.deviceRanges[0]
        let rows = (0..<6).map { row in
            String(format: "%.2f", stats(keyboard.filter { scene.points[$0].slot / 22 == row }).mean)
        }.joined(separator: " ")
        print("\(kind.rawValue)  rows \(rows)")
        for (d, range) in scene.deviceRanges.enumerated() {
            let s = stats(Array(range))
            print(String(format: "    %-9@ level %.2f  motion %.3f  jitter %.4f", scene.devices[d].kind.rawValue, s.mean, s.motion, s.jitter))
        }
    }

case "restore":
    let behaviour: ShutdownBehaviour
    switch arguments.dropFirst().first {
    case "spectrum": behaviour = .spectrum
    case "off": behaviour = .off
    default: behaviour = .staticColor
    }
    for device in discover() {
        try? device.prepare()
        device.shutdown(behaviour, color: RGB8(194, 16, 0))
        print("restored \(device.info.name) → \(behaviour.rawValue)")
    }

default:
    print("Usage: aura-cli list | pattern | run <effect> [seconds] [palette] [--typing] | bench [frames] | restore [static|spectrum|off]")
}

func getrusage_self() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    return user + system
}
