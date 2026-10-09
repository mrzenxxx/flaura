import Foundation

/// Turns settings plus a scene into one color per scene point per frame:
/// base effect groups first, overlay layers on top, disabled devices forced dark.
final class Compositor {
    private struct Group {
        let effect: Effect
        let indices: [Int]
        let points: [ScenePoint]
        var buffer: [RGB]
    }

    private(set) var scene = SceneLayout.empty
    private(set) var output: [RGB] = []
    private var groups: [Group] = []
    private var overlays: [OverlayLayer] = []
    private var dark: [Int] = []
    private var stoke = false

    var isAnimated: Bool {
        groups.contains { $0.effect.isAnimated } || overlays.contains { $0.isActive }
    }

    /// Rebuilds the base effects. Simulation state (fire, stars) restarts, so callers only do
    /// this when effect-related settings or the device set actually changed.
    func rebuildEffects(scene: SceneLayout, settings: AuraSettings) {
        self.scene = scene
        output = Array(repeating: .black, count: scene.points.count)
        groups = []
        dark = []
        var followers: [Int] = []
        for (index, device) in scene.devices.enumerated() {
            let range = scene.deviceRanges[index]
            let deviceSettings = settings.device(device.id)
            if !deviceSettings.enabled {
                dark.append(contentsOf: range)
            } else if let own = deviceSettings.effect {
                groups.append(makeGroup(EffectFactory.make(own), indices: Array(range)))
            } else {
                followers.append(contentsOf: range)
            }
        }
        if !followers.isEmpty {
            groups.insert(makeGroup(EffectFactory.make(settings.effect), indices: followers), at: 0)
        }
    }

    func rebuildOverlays(settings: ReactiveSettings) {
        overlays = EffectFactory.overlays(settings)
        stoke = settings.stoke
    }

    func handle(_ event: InputEvent, context: FrameContext) {
        for overlay in overlays {
            overlay.handle(event, context: context)
        }
        guard stoke else { return }
        var pressed: ScenePoint?
        if case .keyDown(let keyCode) = event {
            pressed = scene.points.first { $0.keyCode == keyCode }
        }
        for group in groups {
            let point = pressed.flatMap { p in group.points.first { $0.device == p.device && $0.slot == p.slot } }
            group.effect.handle(event, point: point, context: context)
        }
    }

    func render(_ context: FrameContext) {
        for g in groups.indices {
            groups[g].effect.render(context, points: groups[g].points, into: &groups[g].buffer)
            let buffer = groups[g].buffer
            for (k, index) in groups[g].indices.enumerated() {
                output[index] = buffer[k]
            }
        }
        for overlay in overlays where overlay.isActive {
            overlay.render(context, points: scene.points, into: &output)
        }
        for index in dark {
            output[index] = .black
        }
    }

    private func makeGroup(_ effect: Effect, indices: [Int]) -> Group {
        Group(effect: effect, indices: indices, points: indices.map { scene.points[$0] },
              buffer: Array(repeating: .black, count: indices.count))
    }
}

/// Final color processing: brightness, per-device gain and gamma, down to 8-bit.
struct OutputStage {
    private static let resolution = 1024
    private let table: [UInt8]

    init(gamma: Float) {
        let g = min(max(gamma, 1), 3)
        table = (0..<OutputStage.resolution).map { i in
            let x = Float(i) / Float(OutputStage.resolution - 1)
            return UInt8(min(255, (powf(x, g) * 255).rounded()))
        }
    }

    @inline(__always)
    func encode(_ color: RGB, scale: Float) -> RGB8 {
        RGB8(channel(color.r * scale), channel(color.g * scale), channel(color.b * scale))
    }

    @inline(__always)
    private func channel(_ v: Float) -> UInt8 {
        let clamped = min(max(v, 0), 1)
        return table[Int(clamped * Float(OutputStage.resolution - 1) + 0.5)]
    }
}
