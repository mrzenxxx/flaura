import Foundation
import Testing
@testable import AuraCore

/// Records frames instead of talking to hardware.
final class FakeDevice: LightingDevice, @unchecked Sendable {
    let info: DeviceInfo
    let layout: DeviceLayout
    private let lock = NSLock()
    private var _frames: [[RGB8]] = []
    private var _shutdowns: [ShutdownBehaviour] = []
    var failWrites = false
    /// Fail this many writes, then succeed.
    var failuresRemaining = 0

    init(id: String, kind: DeviceKind, layout: DeviceLayout) {
        info = DeviceInfo(id: id, name: id, vendor: "Test", kind: kind, detail: "")
        self.layout = layout
    }

    var frames: [[RGB8]] { lock.withLock { _frames } }
    var shutdowns: [ShutdownBehaviour] { lock.withLock { _shutdowns } }

    func prepare() throws {}

    func write(_ frame: [RGB8]) throws {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        let fail = lock.withLock { () -> Bool in
            guard failuresRemaining > 0 else { return false }
            failuresRemaining -= 1
            return true
        }
        if fail { throw CocoaError(.fileWriteUnknown) }
        lock.withLock { _frames.append(frame) }
    }

    func shutdown(_ behaviour: ShutdownBehaviour, color: RGB8) {
        lock.withLock { _shutdowns.append(behaviour) }
    }
}

func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return condition()
}

@Suite struct OutputStageTests {
    @Test func linearGammaMapsEnds() {
        let stage = OutputStage(gamma: 1)
        #expect(stage.encode(.black, scale: 1) == RGB8(0, 0, 0))
        #expect(stage.encode(.white, scale: 1) == RGB8(255, 255, 255))
        let mid = stage.encode(RGB(0.5, 0.5, 0.5), scale: 1)
        #expect(abs(Int(mid.r) - 128) <= 1)
    }

    @Test func nanBecomesBlack() {
        let stage = OutputStage(gamma: 1.4)
        #expect(stage.encode(RGB(.nan, .infinity, 0.5), scale: 1).r == 0)
        #expect(stage.encode(RGB(1, 1, 1), scale: .nan) == RGB8(0, 0, 0))
    }

    @Test func gammaDarkensMidtonesAndScaleApplies() {
        let stage = OutputStage(gamma: 2)
        #expect(stage.encode(RGB(0.5, 0, 0), scale: 1).r < 70)
        #expect(stage.encode(.white, scale: 0.5).r < 70)
        #expect(stage.encode(RGB(3, -1, 1), scale: 1) == RGB8(255, 0, 255))
    }
}

@Suite struct CompositorTests {
    @Test func disabledDeviceStaysDarkAndOverrideIsUsed() {
        let scene = sampleScene()
        var settings = AuraSettings(effect: EffectSettings(kind: .staticColor))
        settings.palette = Palette(name: "red", colors: [RGB(1, 0, 0)])
        settings.devices["mat"] = DeviceSettings(enabled: false)
        settings.devices["mouse"] = DeviceSettings(effect: EffectSettings(kind: .off))
        let compositor = Compositor()
        compositor.rebuildEffects(scene: scene, settings: settings)
        compositor.rebuildOverlays(settings: ReactiveSettings(ripple: false, keyGlow: false, clickPulse: false, stoke: false))
        compositor.render(FrameContext(time: 0, dt: 0, palette: PaletteLUT(settings.palette), scene: scene))
        #expect(scene.deviceRanges[0].allSatisfy { compositor.output[$0] == RGB(1, 0, 0) })
        #expect(scene.deviceRanges[1].allSatisfy { compositor.output[$0] == .black })
        #expect(scene.deviceRanges[2].allSatisfy { compositor.output[$0] == .black })
        #expect(!compositor.isAnimated)
    }
}

@Suite(.serialized) struct RenderEngineTests {
    func makeDevices() -> (FakeDevice, FakeDevice) {
        (FakeDevice(id: "kb", kind: .keyboard, layout: .matrix(rows: 2, columns: 4, pitch: 19)),
         FakeDevice(id: "mat", kind: .mousepad, layout: .perimeter(count: 6, size: SIMD2(300, 200))))
    }

    @Test func animatedEffectStreamsFramesToEveryDevice() {
        let (kb, mat) = makeDevices()
        let engine = RenderEngine()
        engine.apply(AuraSettings(effect: EffectSettings(kind: .spectrum, speed: 1), framesPerSecond: 60))
        engine.setDevices([kb, mat])
        #expect(waitUntil { kb.frames.count >= 5 && mat.frames.count >= 5 })
        #expect(kb.frames.last!.count == 8)
        #expect(mat.frames.last!.count == 6)
        engine.shutdown()
        #expect(kb.shutdowns == [.staticColor])
    }

    @Test func staticEffectStopsSending() {
        let (kb, mat) = makeDevices()
        let engine = RenderEngine()
        engine.apply(AuraSettings(effect: EffectSettings(kind: .staticColor),
                                  reactive: ReactiveSettings(ripple: false, keyGlow: false, clickPulse: false, stoke: false)))
        engine.setDevices([kb, mat])
        #expect(waitUntil { kb.frames.count >= 1 })
        Thread.sleep(forTimeInterval: 0.8)
        let settled = kb.frames.count
        Thread.sleep(forTimeInterval: 0.3)
        #expect(kb.frames.count == settled)
        #expect(settled <= 20)
        engine.shutdown()
    }

    @Test func suspendGoesDarkAndResumes() {
        let (kb, mat) = makeDevices()
        let engine = RenderEngine()
        var settings = AuraSettings(effect: EffectSettings(kind: .staticColor))
        settings.palette = Palette(name: "white", colors: [.white])
        engine.apply(settings)
        engine.setDevices([kb, mat])
        #expect(waitUntil { kb.frames.last?.contains { $0 != .black } == true })
        engine.setSuspended(true)
        #expect(waitUntil { kb.frames.last?.allSatisfy { $0 == .black } == true })
        engine.setSuspended(false)
        #expect(waitUntil { kb.frames.last?.contains { $0 != .black } == true })
        engine.shutdown()
    }

    @Test func staticFrameIsRetriedAfterAFailedWrite() {
        let (kb, mat) = makeDevices()
        kb.failuresRemaining = 1
        let engine = RenderEngine()
        engine.apply(AuraSettings(effect: EffectSettings(kind: .staticColor),
                                  reactive: ReactiveSettings(ripple: false, keyGlow: false, clickPulse: false, stoke: false)))
        engine.setDevices([kb, mat])
        // The engine renders the static scene once; the sink must retry on its own.
        #expect(waitUntil(timeout: 3) { kb.frames.count >= 1 })
        engine.shutdown()
    }

    @Test func nothingRestartsAfterShutdown() {
        let (kb, mat) = makeDevices()
        let engine = RenderEngine()
        engine.apply(AuraSettings(effect: EffectSettings(kind: .spectrum), framesPerSecond: 60))
        engine.setDevices([kb, mat])
        #expect(waitUntil { kb.frames.count >= 3 })
        engine.shutdown()
        let count = kb.frames.count
        engine.apply(AuraSettings(effect: EffectSettings(kind: .wave), framesPerSecond: 60))
        engine.post(.keyDown(keyCode: 0))
        Thread.sleep(forTimeInterval: 0.3)
        #expect(kb.frames.count == count)
    }

    @Test func offSceneShutsDownDark() {
        let (kb, mat) = makeDevices()
        let engine = RenderEngine()
        engine.apply(AuraSettings(effect: EffectSettings(kind: .off)))
        engine.setDevices([kb, mat])
        #expect(waitUntil { kb.frames.count >= 1 })
        engine.shutdown()
        #expect(kb.shutdowns == [.off])
    }

    @Test func failingDeviceDoesNotBlockOthers() {
        let (kb, mat) = makeDevices()
        kb.failWrites = true
        let engine = RenderEngine()
        engine.apply(AuraSettings(effect: EffectSettings(kind: .spectrum), framesPerSecond: 60))
        engine.setDevices([kb, mat])
        #expect(waitUntil { mat.frames.count >= 10 })
        engine.shutdown()
    }
}
