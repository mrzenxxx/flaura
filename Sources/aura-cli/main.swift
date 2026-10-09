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
