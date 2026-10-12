import Foundation

/// Drives every device from one clock, which is what keeps them in sync.
///
/// All state lives on a private serial queue; the public methods are thread-safe and return
/// immediately. The timer only runs while something animates: a static effect renders once and
/// then costs nothing until settings change or input arrives.
public final class RenderEngine: @unchecked Sendable {
    public typealias ActivityHandler = @Sendable (_ animating: Bool) -> Void
    public typealias HealthHandler = @Sendable (_ deviceID: String, _ health: DeviceHealth) -> Void

    private let queue = DispatchQueue(label: "aura.render", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var timerInterval: Double = 0
    private let compositor = Compositor()
    private var output = OutputStage(gamma: 1.8)
    private var settings = AuraSettings()
    private var palette = PaletteLUT(.flame)
    /// The palette as drawn this frame: `palette`, or a rotated copy while palette flow is on.
    private var framePalette = PaletteLUT(.flame)
    private var flowUpdatedAt: Double = -1
    /// Accumulated rather than derived from the clock, so changing the flow speed does not jump.
    private var flowPhase: Double = 0
    private var devices: [any LightingDevice] = []
    private var sinks: [DeviceSink] = []
    private var suspended = false
    private var dirty = true
    private var animating = false
    private var isShutDown = false
    /// Colors as last sent (after crossfading), so a new crossfade starts from what is visible.
    private var lastEmitted: [RGB] = []

    private let start = DispatchTime.now().uptimeNanoseconds
    private var lastTick: UInt64 = 0

    private var fadeFrom: [RGB] = []
    private var fadeStart: Double = -1
    private static let fadeDuration: Double = 0.45

    private var onActivity: ActivityHandler?
    private var onHealth: HealthHandler?

    public init() {}

    /// `activity` fires when the engine starts or stops animating (hold an App Nap assertion while
    /// true); `health` reports devices whose writes keep failing.
    public func setHandlers(activity: ActivityHandler?, health: HealthHandler?) {
        queue.async {
            self.onActivity = activity
            self.onHealth = health
        }
    }

    public func apply(_ newSettings: AuraSettings) {
        queue.async {
            guard !self.isShutDown else { return }
            self.applyOnQueue(newSettings)
        }
    }

    public func setDevices(_ newDevices: [any LightingDevice]) {
        queue.async {
            guard !self.isShutDown else { return }
            let known = Dictionary(uniqueKeysWithValues: self.sinks.map { ($0.device.info.id, $0) })
            self.devices = newDevices
            self.sinks = newDevices.map { device in
                if let sink = known[device.info.id], sink.device === device { return sink }
                return DeviceSink(device: device) { [weak self] id, health in
                    self?.queue.async { self?.onHealth?(id, health) }
                }
            }
            self.rebuildScene(crossfade: false)
        }
    }

    /// Keyboard and mouse input for reactive layers.
    public func post(_ event: InputEvent) {
        queue.async {
            guard self.settings.enabled, !self.suspended, !self.isShutDown else { return }
            self.compositor.handle(event, context: self.context(time: self.now(), dt: 0))
            self.dirty = true
            self.updateTimer()
        }
    }

    /// Pauses rendering (display sleep, screen lock). With `dimWhenIdle` the lights go dark.
    public func setSuspended(_ value: Bool) {
        queue.async {
            guard value != self.suspended, !self.isShutDown else { return }
            self.suspended = value
            if value {
                if self.settings.dimWhenIdle { self.sendBlack() }
            } else {
                // A device may have reset its lighting while asleep without reconnecting.
                self.sinks.forEach { $0.reset() }
                self.dirty = true
            }
            self.updateTimer()
        }
    }

    /// Stops rendering and hands every device back to its hardware. Blocks up to `timeout`.
    public func shutdown(timeout: TimeInterval = 1.5) {
        let group = DispatchGroup()
        queue.sync {
            guard !self.isShutDown else { return }
            self.isShutDown = true
            self.timer?.cancel()
            self.timer = nil
            self.updateTimer()
            // If the lights were meant to be off, do not switch them back on at exit.
            let lightsOff = !self.settings.enabled || self.settings.effect.kind == .off
            let behaviour = lightsOff && self.settings.shutdownBehaviour != .keep ? .off : self.settings.shutdownBehaviour
            // The middle palette color is the most representative (orange for Пламя); devices
            // keep it in memory and show it at the next power-on, before macOS starts.
            let colors = self.palette.colors
            let color = self.output.encode(colors[colors.count / 2], scale: self.settings.brightness)
            for sink in self.sinks {
                sink.shutdown(behaviour, color: color, group: group)
            }
        }
        _ = group.wait(timeout: .now() + timeout)
    }

    // MARK: - Queue-confined

    private func applyOnQueue(_ new: AuraSettings) {
        let old = settings
        settings = new
        if new.palette != old.palette {
            palette = PaletteLUT(new.palette)
            framePalette = palette
            flowUpdatedAt = -1
            beginCrossfade()
        }
        if new.paletteFlow != old.paletteFlow && !new.paletteFlow {
            framePalette = palette
            beginCrossfade()
        }
        if new.gamma != old.gamma {
            output = OutputStage(gamma: new.gamma)
        }
        let effectsChanged = new.effect != old.effect || deviceEffectsDiffer(old, new)
        let placementChanged = new.devices.mapValues(\.origin) != old.devices.mapValues(\.origin)
        if placementChanged {
            rebuildScene(crossfade: true)
        } else if effectsChanged {
            beginCrossfade()
            compositor.rebuildEffects(scene: compositor.scene, settings: settings)
        }
        if new.reactive != old.reactive {
            compositor.rebuildOverlays(settings: new.reactive)
        }
        if !new.enabled && old.enabled {
            sendBlack()
        }
        if new.enabled && !old.enabled {
            sinks.forEach { $0.reset() }
        }
        dirty = true
        updateTimer()
    }

    private func deviceEffectsDiffer(_ a: AuraSettings, _ b: AuraSettings) -> Bool {
        let ids = Set(a.devices.keys).union(b.devices.keys)
        return ids.contains { id in
            let x = a.device(id)
            let y = b.device(id)
            return x.enabled != y.enabled || x.effect != y.effect
        }
    }

    private func rebuildScene(crossfade: Bool) {
        let entries = devices.map { (id: $0.info.id, kind: $0.info.kind, size: $0.layout.size) }
        let overrides = settings.devices.compactMapValues(\.origin)
        let origins = DeskArrangement.origins(for: entries, overrides: overrides)
        let sceneDevices = devices.map { device in
            SceneDevice(id: device.info.id, kind: device.info.kind, layout: device.layout,
                        origin: origins[device.info.id] ?? .zero)
        }
        if crossfade { beginCrossfade() }
        compositor.rebuildEffects(scene: SceneLayout(devices: sceneDevices), settings: settings)
        compositor.rebuildOverlays(settings: settings.reactive)
        if !crossfade { fadeStart = -1 }
        dirty = true
        updateTimer()
    }

    private func beginCrossfade() {
        let from = lastEmitted.count == compositor.output.count ? lastEmitted : compositor.output
        guard !from.isEmpty else { return }
        fadeFrom = from
        fadeStart = now()
    }

    private var fading: Bool { fadeStart >= 0 }

    private func updateTimer() {
        let shouldRun = !isShutDown && settings.enabled && !suspended && !sinks.isEmpty
            && (dirty || fading || settings.paletteFlow || compositor.isAnimated)
        let interval = 1 / Double(min(max(settings.framesPerSecond, AuraSettings.fpsRange.lowerBound), AuraSettings.fpsRange.upperBound))
        if shouldRun {
            if timer == nil || interval != timerInterval {
                timer?.cancel()
                let source = DispatchSource.makeTimerSource(queue: queue)
                let leeway = max(1, Int(interval * 1000 / 10))
                source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(leeway))
                source.setEventHandler { [weak self] in self?.tick() }
                timer = source
                timerInterval = interval
                lastTick = DispatchTime.now().uptimeNanoseconds
                source.resume()
            }
        } else if let timer {
            timer.cancel()
            self.timer = nil
        }
        let nowAnimating = timer != nil
        if nowAnimating != animating {
            animating = nowAnimating
            onActivity?(nowAnimating)
        }
    }

    private func tick() {
        let nowNanos = DispatchTime.now().uptimeNanoseconds
        let dt = Float(min(max(Double(nowNanos &- lastTick) / 1e9, 0), 0.1))
        lastTick = nowNanos
        let time = Double(nowNanos - start) / 1e9
        updateFlow(time: time, dt: dt)
        let context = context(time: time, dt: dt)
        compositor.render(context)

        var colors = compositor.output
        if fading {
            let k = Float(min((time - fadeStart) / RenderEngine.fadeDuration, 1))
            if fadeFrom.count == colors.count && k < 1 {
                let eased = k * k * (3 - 2 * k)
                for i in colors.indices {
                    colors[i] = RGB.mix(fadeFrom[i], colors[i], eased)
                }
            } else {
                fadeStart = -1
            }
        }
        lastEmitted = colors
        emit(colors)
        dirty = false
        updateTimer()
    }

    private func emit(_ colors: [RGB]) {
        let scene = compositor.scene
        for (index, sink) in sinks.enumerated() where index < scene.devices.count {
            let layout = scene.devices[index].layout
            let scale = settings.brightness * settings.device(scene.devices[index].id).gain
            var frame = [RGB8](repeating: .black, count: layout.frameLength)
            for p in scene.deviceRanges[index] {
                frame[scene.points[p].slot] = output.encode(colors[p], scale: scale)
            }
            sink.submit(frame)
        }
    }

    /// Rotating the palette rebuilds its tables; ~15 times a second is visually continuous.
    private func updateFlow(time: Double, dt: Float) {
        guard settings.paletteFlow else { return }
        let secondsPerColor = Double(rate(settings.paletteFlowSpeed, 14, 1.5))
        flowPhase += Double(dt) / (secondsPerColor * Double(palette.colors.count))
        flowPhase -= flowPhase.rounded(.down)
        guard time - flowUpdatedAt >= 1.0 / 15 || flowUpdatedAt < 0 else { return }
        flowUpdatedAt = time
        framePalette = palette.rotated(by: Float(flowPhase))
    }

    private func sendBlack() {
        for sink in sinks {
            sink.submit([RGB8](repeating: .black, count: sink.device.layout.frameLength))
        }
    }

    private func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    private func context(time: Double, dt: Float) -> FrameContext {
        FrameContext(time: time, dt: dt, palette: framePalette, scene: compositor.scene)
    }
}
