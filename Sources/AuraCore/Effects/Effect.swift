import Foundation

/// Everything an effect needs to draw one frame.
public struct FrameContext: Sendable {
    /// Seconds since the engine started. Shared by every device, which is what keeps them in sync.
    public var time: Double
    /// Seconds since the previous frame, clamped to a sane range.
    public var dt: Float
    public var palette: PaletteLUT
    public var scene: SceneLayout

    public init(time: Double, dt: Float, palette: PaletteLUT, scene: SceneLayout) {
        self.time = time
        self.dt = dt
        self.palette = palette
        self.scene = scene
    }
}

/// User input that reactive layers and some effects respond to.
public enum InputEvent: Sendable, Equatable {
    case keyDown(keyCode: UInt16)
    case mouseDown(button: Int)
}

/// A base lighting layer. Implementations are confined to the render queue.
public protocol Effect: AnyObject {
    /// False when the output never changes over time; lets the engine stop its timer.
    var isAnimated: Bool { get }
    /// Writes one color per point, `output[i]` for `points[i]`. `output.count == points.count`.
    func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB])
    /// Optional reaction to input (e.g. typing stokes the fire). `point` is the pressed key, if known.
    func handle(_ event: InputEvent, point: ScenePoint?, context: FrameContext)
}

extension Effect {
    public func handle(_ event: InputEvent, point: ScenePoint?, context: FrameContext) {}
}

/// A layer drawn on top of the base effect, typically driven by input (ripples, glows, pulses).
public protocol OverlayLayer: AnyObject {
    /// True while something is still animating; inactive overlays cost nothing.
    var isActive: Bool { get }
    func handle(_ event: InputEvent, context: FrameContext)
    /// Blends onto `output`, which already holds the base layer for `points`.
    func render(_ context: FrameContext, points: [ScenePoint], into output: inout [RGB])
}
