import AuraUSB
import Foundation

public struct USBError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let code: Int32

    public var description: String {
        String(format: "%@ failed (IOReturn 0x%08x)", operation, UInt32(bitPattern: code))
    }
}

/// Sends HID class reports as raw USB control transfers on the default pipe.
///
/// Going through IOUSBLib rather than IOHIDDevice avoids the Input Monitoring prompt: macOS gates
/// opening any HID interface that looks like a keyboard or mouse, but not control requests to
/// the USB device itself.
public protocol ReportTransport: AnyObject, Sendable {
    func send(_ report: [UInt8], index: UInt16) throws
    func receive(length: Int, index: UInt16) throws -> [UInt8]
}

public final class USBControlTransport: ReportTransport, @unchecked Sendable {
    private let handle: OpaquePointer
    private let timeoutMilliseconds: UInt32

    /// HID class request, interface recipient: SET_REPORT / GET_REPORT for feature report 0.
    private static let setReport: (type: UInt8, request: UInt8) = (0x21, 0x09)
    private static let getReport: (type: UInt8, request: UInt8) = (0xA1, 0x01)
    private static let featureReportValue: UInt16 = 0x0300

    public init(registryEntryID: UInt64, timeoutMilliseconds: UInt32 = 100) throws {
        var error: Int32 = 0
        guard let handle = aura_usb_open(registryEntryID, &error) else {
            throw USBError(operation: "open", code: error)
        }
        self.handle = handle
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    deinit {
        aura_usb_close(handle)
    }

    public func send(_ report: [UInt8], index: UInt16) throws {
        var bytes = report
        let result = bytes.withUnsafeMutableBytes { buffer in
            aura_usb_control(handle, Self.setReport.type, Self.setReport.request, Self.featureReportValue, index,
                             buffer.baseAddress, UInt16(buffer.count), timeoutMilliseconds, nil)
        }
        guard result == 0 else { throw USBError(operation: "SET_REPORT", code: result) }
    }

    public func receive(length: Int, index: UInt16) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        var transferred: UInt32 = 0
        let result = bytes.withUnsafeMutableBytes { buffer in
            aura_usb_control(handle, Self.getReport.type, Self.getReport.request, Self.featureReportValue, index,
                             buffer.baseAddress, UInt16(buffer.count), timeoutMilliseconds, &transferred)
        }
        guard result == 0 else { throw USBError(operation: "GET_REPORT", code: result) }
        return bytes
    }
}
