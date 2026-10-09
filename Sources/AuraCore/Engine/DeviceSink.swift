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
final class DeviceSink: @unchecked Sendable {
    let device: any LightingDevice
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [RGB8]?
    private var lastSubmitted: [RGB8]?
    private var draining = false
    private var prepared = false
    private var failures = 0
    private var resumeAt: UInt64 = 0
    private let onHealth: @Sendable (String, DeviceHealth) -> Void

    init(device: any LightingDevice, onHealth: @escaping @Sendable (String, DeviceHealth) -> Void) {
        self.device = device
        self.onHealth = onHealth
        queue = DispatchQueue(label: "aura.device.\(device.info.id)", qos: .userInitiated)
    }

    /// Queues a frame; identical consecutive frames are dropped before reaching the device.
    func submit(_ frame: [RGB8]) {
        lock.lock()
        if frame == lastSubmitted {
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

    /// Forces the next frame through even if it equals the last one (after wake, reconnect…).
    func invalidate() {
        lock.lock()
        lastSubmitted = nil
        lock.unlock()
    }

    func shutdown(_ behaviour: ShutdownBehaviour, color: RGB8, group: DispatchGroup) {
        group.enter()
        queue.async {
            if self.prepared {
                self.device.shutdown(behaviour, color: color)
            }
            self.prepared = false
            group.leave()
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let frame = pending else {
                draining = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            write(frame)
        }
    }

    private func write(_ frame: [RGB8]) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= resumeAt else {
            // Backing off: let the frame go, but make sure a later one is not deduplicated away.
            invalidate()
            return
        }
        do {
            if !prepared {
                try device.prepare()
                prepared = true
            }
            try device.write(frame)
            if failures > 0 {
                failures = 0
                onHealth(device.info.id, .ok)
            }
        } catch {
            failures += 1
            prepared = false
            invalidate()
            if failures >= 3 {
                let backoff = min(UInt64(1) << UInt64(min(failures - 3, 4)), 10)
                resumeAt = now + backoff * 1_000_000_000
                onHealth(device.info.id, .failing(String(describing: error)))
            }
        }
    }
}
