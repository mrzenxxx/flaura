import AuraCore
import Foundation

public struct RazerError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
}

/// A Razer device driven through extended-matrix custom frames.
/// Confined to the engine's per-device queue (see `LightingDevice`).
public final class RazerDevice: LightingDevice, @unchecked Sendable {
    public let info: DeviceInfo
    public let layout: DeviceLayout
    public let descriptor: RazerDeviceDescriptor
    private let transport: ReportTransport
    private var lastRows: [ArraySlice<RGB8>]?
    private var driverModeActive = false

    /// Pause between SET_REPORT and GET_REPORT; OpenRazer waits 600–900 µs.
    static let responseDelay: useconds_t = 900

    public init(descriptor: RazerDeviceDescriptor, transport: ReportTransport, id: String, detail: String) {
        self.descriptor = descriptor
        self.transport = transport
        layout = descriptor.makeLayout()
        info = DeviceInfo(id: id, name: descriptor.name, vendor: "Razer", kind: descriptor.kind, detail: detail)
    }

    /// Reads the firmware version, e.g. "1.4". Doubles as a connectivity check.
    public func firmwareVersion() throws -> String {
        let reply = try query(RazerPacket.firmwareVersion(transactionID: descriptor.transactionID))
        let args = reply.arguments
        return "\(args[args.startIndex]).\(args[args.startIndex + 1])"
    }

    public func prepare() throws {
        if descriptor.driverMode {
            try send(RazerPacket.deviceMode(transactionID: descriptor.transactionID, mode: 0x03))
            driverModeActive = true
        }
        // Brightness is applied in software; the hardware stays at full so nothing is lost.
        for led in descriptor.ledIDs {
            try send(RazerPacket.brightness(transactionID: descriptor.transactionID, led: led, value: 0xFF))
        }
        lastRows = nil
    }

    public func write(_ frame: [RGB8]) throws {
        let columns = descriptor.columns
        let tid = descriptor.transactionID
        var rows: [ArraySlice<RGB8>] = []
        rows.reserveCapacity(descriptor.rows)
        var changed = false
        for row in 0..<descriptor.rows {
            let slice = frame[(row * columns)..<((row + 1) * columns)]
            rows.append(slice)
            if let lastRows, lastRows[row] == slice { continue }
            try send(RazerPacket.customFrameRow(transactionID: tid, row: row, startColumn: 0, colors: slice))
            changed = true
        }
        if changed {
            try send(RazerPacket.customFrameEffect(transactionID: tid))
        }
        lastRows = rows
    }

    public func shutdown(_ behaviour: ShutdownBehaviour, color: RGB8) {
        let tid = descriptor.transactionID
        for led in descriptor.ledIDs {
            switch behaviour {
            case .staticColor: try? send(RazerPacket.staticEffect(transactionID: tid, led: led, color: color))
            case .spectrum: try? send(RazerPacket.spectrumEffect(transactionID: tid, led: led))
            case .off: try? send(RazerPacket.noEffect(transactionID: tid, led: led))
            case .keep: break
            }
        }
        if driverModeActive && behaviour != .keep {
            try? send(RazerPacket.deviceMode(transactionID: tid, mode: 0x00))
            driverModeActive = false
        }
        lastRows = nil
    }

    // MARK: Transport

    func send(_ report: [UInt8]) throws {
        try transport.send(report, index: descriptor.controlIndex)
    }

    /// Sends a request and reads the reply, retrying while the device reports busy.
    func query(_ request: [UInt8]) throws -> RazerResponse {
        for _ in 0..<5 {
            try send(request)
            usleep(RazerDevice.responseDelay)
            let bytes = try transport.receive(length: RazerPacket.length, index: descriptor.controlIndex)
            if let reply = RazerResponse(bytes), reply.answers(request), reply.status == .success {
                return reply
            }
            usleep(10_000)
        }
        throw RazerError(message: "\(descriptor.name): no valid reply to command \(String(format: "%02X/%02X", request[6], request[7]))")
    }
}
