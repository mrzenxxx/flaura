import AuraCore
import Foundation

/// Razer's 90-byte control report (as used by OpenRazer / OpenRGB / librazermacos).
///
/// | byte  | field                                  |
/// |-------|----------------------------------------|
/// | 0     | status (0x00 in requests)              |
/// | 1     | transaction id                         |
/// | 2–3   | remaining packets (big endian)         |
/// | 4     | protocol type (0x00)                   |
/// | 5     | data size                              |
/// | 6     | command class                          |
/// | 7     | command id (bit 7 set = "get")         |
/// | 8–87  | arguments                              |
/// | 88    | CRC: XOR of bytes 2…87                 |
/// | 89    | reserved                               |
public enum RazerPacket {
    public static let length = 90
    public static let argumentCapacity = 80
    /// Extended-matrix custom frames carry at most 25 LEDs per packet.
    public static let maxLEDsPerRow = 25

    public enum Status: UInt8, Sendable {
        case new = 0x00
        case busy = 0x01
        case success = 0x02
        case failure = 0x03
        case timeout = 0x04
        case notSupported = 0x05
    }

    /// Storage byte for extended effects: 0x00 = do not persist, 0x01 = persist ("VARSTORE").
    public static let noStore: UInt8 = 0x00
    public static let varStore: UInt8 = 0x01

    public static func make(transactionID: UInt8, commandClass: UInt8, commandID: UInt8,
                            dataSize: UInt8, arguments: [UInt8] = []) -> [UInt8] {
        precondition(arguments.count <= argumentCapacity, "too many arguments")
        var report = [UInt8](repeating: 0, count: length)
        report[1] = transactionID
        report[5] = dataSize
        report[6] = commandClass
        report[7] = commandID
        for (i, byte) in arguments.enumerated() {
            report[8 + i] = byte
        }
        report[88] = crc(report)
        return report
    }

    public static func crc(_ report: [UInt8]) -> UInt8 {
        var value: UInt8 = 0
        for i in 2..<88 {
            value ^= report[i]
        }
        return value
    }

    // MARK: Commands

    /// Get firmware version (class 0x00, id 0x81): reply args[0].args[1].
    public static func firmwareVersion(transactionID: UInt8) -> [UInt8] {
        make(transactionID: transactionID, commandClass: 0x00, commandID: 0x81, dataSize: 0x02)
    }

    /// Set device mode (class 0x00, id 0x04): 0x00 normal, 0x03 driver.
    public static func deviceMode(transactionID: UInt8, mode: UInt8) -> [UInt8] {
        make(transactionID: transactionID, commandClass: 0x00, commandID: 0x04, dataSize: 0x02, arguments: [mode, 0x00])
    }

    /// Extended-matrix brightness (class 0x0F, id 0x04).
    public static func brightness(transactionID: UInt8, led: UInt8, value: UInt8, store: UInt8 = varStore) -> [UInt8] {
        make(transactionID: transactionID, commandClass: 0x0F, commandID: 0x04, dataSize: 0x03, arguments: [store, led, value])
    }

    /// One row of an extended-matrix custom frame (class 0x0F, id 0x03).
    public static func customFrameRow(transactionID: UInt8, row: Int, startColumn: Int, colors: ArraySlice<RGB8>) -> [UInt8] {
        precondition(!colors.isEmpty && colors.count <= maxLEDsPerRow, "row must hold 1…25 LEDs")
        var arguments: [UInt8] = [0x00, 0x00, UInt8(row), UInt8(startColumn), UInt8(startColumn + colors.count - 1)]
        arguments.reserveCapacity(5 + colors.count * 3)
        for color in colors {
            arguments.append(color.r)
            arguments.append(color.g)
            arguments.append(color.b)
        }
        return make(transactionID: transactionID, commandClass: 0x0F, commandID: 0x03,
                    dataSize: UInt8(arguments.count), arguments: arguments)
    }

    /// Switches the device to show the uploaded custom frame (class 0x0F, id 0x02, effect 0x08).
    public static func customFrameEffect(transactionID: UInt8) -> [UInt8] {
        make(transactionID: transactionID, commandClass: 0x0F, commandID: 0x02, dataSize: 0x0C, arguments: [noStore, 0x00, 0x08])
    }

    /// Hardware static color (extended effect 0x01).
    public static func staticEffect(transactionID: UInt8, led: UInt8, color: RGB8) -> [UInt8] {
        make(transactionID: transactionID, commandClass: 0x0F, commandID: 0x02, dataSize: 0x09,
             arguments: [varStore, led, 0x01, 0x00, 0x00, 0x01, color.r, color.g, color.b])
    }

    /// Hardware spectrum cycling (extended effect 0x03).
    public static func spectrumEffect(transactionID: UInt8, led: UInt8) -> [UInt8] {
        make(transactionID: transactionID, commandClass: 0x0F, commandID: 0x02, dataSize: 0x06,
             arguments: [varStore, led, 0x03, 0x00, 0x00, 0x00])
    }

    /// No effect: lights off (extended effect 0x00).
    public static func noEffect(transactionID: UInt8, led: UInt8) -> [UInt8] {
        make(transactionID: transactionID, commandClass: 0x0F, commandID: 0x02, dataSize: 0x06,
             arguments: [varStore, led, 0x00, 0x00, 0x00, 0x00])
    }
}

/// A parsed reply to a request.
public struct RazerResponse: Sendable {
    public let bytes: [UInt8]

    public init?(_ bytes: [UInt8]) {
        guard bytes.count >= RazerPacket.length else { return nil }
        self.bytes = Array(bytes.prefix(RazerPacket.length))
    }

    public var status: RazerPacket.Status? { RazerPacket.Status(rawValue: bytes[0]) }
    public var commandClass: UInt8 { bytes[6] }
    public var commandID: UInt8 { bytes[7] }
    public var arguments: ArraySlice<UInt8> { bytes[8..<88] }

    /// Whether this is the answer to `request` (same class and id) and it succeeded.
    public func answers(_ request: [UInt8]) -> Bool {
        commandClass == request[6] && commandID == request[7] && (status == .success || status == .busy)
    }
}
