import Foundation

/// Health of a device as seen by the engine, for the UI.
public enum DeviceHealth: Sendable, Equatable {
    case ok
    /// Writes keep failing; the sink backs off and retries.
    case failing(String)
}

/// Owns the serial queue a device is driven on. Frames are "latest wins": if the device is still
/// busy with the previous frame, a newer one replaces the pending one, so a slow device never
/// builds a backlog or holds up the others.
///
/// A frame that fails to reach the device is retried by the sink itself (with backoff), because
/// a static scene renders only once and the engine will not send it again.
final class DeviceSink: @unchecked Sendable {
    let device: any LightingDevice
    private let queue: DispatchQueue
    private let lock = NSLock()

    // Guarded by `lock`.
    private var pending: [RGB8]?
    private var lastSubmitted: [RGB8]?
    private var draining = false
    private var needsPrepare = true
    private var closed = false

    // Queue-confined.
    private var failures = 0
    private var reportedHealthy = false
    private var resumeAt: UInt64 = 0
    private let onHealth: @Sendable (String, DeviceHealth) -> Void

    static let retryDelay: UInt64 = 250_000_000

    init(device: any LightingDevice, onHealth: @escaping @Sendable (String, DeviceHealth) -> Void) {
        self.device = device
        self.onHealth = onHealth
        queue = DispatchQueue(label: "aura.device.\(device.info.id)", qos: .userInitiated)
    }

    /// Queues a frame; identical consecutive frames are dropped before reaching the device.
    func submit(_ frame: [RGB8]) {
        lock.lock()
        if closed || frame == lastSubmitted {
            lock.unlock()
            return
        }
        lastSubmitted = frame
        pending = frame
        let start = !draining
        draining = true
        lock.unlock()
        if start {
            queue.async { self.drain() }
        }
    }

    /// Makes the next frame go all the way to the hardware: re-runs `prepare()` (which also
    /// clears the device's own row cache and re-enters software mode) and skips deduplication.
    /// Used after wake, when a device may have reset its lighting without reconnecting.
    func reset() {
        lock.lock()
        lastSubmitted = nil
        needsPrepare = true
        lock.unlock()
    }

    func shutdown(_ behaviour: ShutdownBehaviour, color: RGB8, group: DispatchGroup) {
        lock.lock()
        closed = true
        pending = nil
        let prepared = !needsPrepare
        lock.unlock()
        group.enter()
        queue.async {
            if prepared {
                self.device.shutdown(behaviour, color: color)
            }
            group.leave()
        }
    }

    private func drain() {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if now < resumeAt {
                // Backing off: keep the frame and come back later.
                queue.asyncAfter(deadline: .init(uptimeNanoseconds: resumeAt)) { self.drain() }
                return
            }
            lock.lock()
            guard let frame = pending, !closed else {
                draining = false
                lock.unlock()
                return
            }
            pending = nil
            let prepare = needsPrepare
            needsPrepare = false
            lock.unlock()

            do {
                if prepare { try device.prepare() }
                try device.write(frame)
                if failures > 0 || !reportedHealthy {
                    failures = 0
                    reportedHealthy = true
                    onHealth(device.info.id, .ok)
                }
            } catch {
                failures += 1
                lock.lock()
                needsPrepare = true
                if pending == nil { pending = frame } // retry this frame unless a newer one arrived
                lock.unlock()
                let backoff: UInt64 = failures >= 3
                    ? min(UInt64(1) << UInt64(min(failures - 3, 4)), 10) * 1_000_000_000
                    : DeviceSink.retryDelay
                resumeAt = DispatchTime.now().uptimeNanoseconds + backoff
                if failures >= 3 {
                    reportedHealthy = false
                    onHealth(device.info.id, .failing(String(describing: error)))
                }
            }
        }
    }
}
