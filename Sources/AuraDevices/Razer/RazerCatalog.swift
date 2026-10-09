import AuraCore
import Foundation

/// Everything needed to drive one Razer model. Plain data, so extra models can be added from
/// JSON files in `~/Library/Application Support/Aura/devices/` without rebuilding the app.
public struct RazerDeviceDescriptor: Codable, Sendable, Hashable {
    public enum LayoutStyle: String, Codable, Sendable {
        /// Full-size keyboard matrix with key codes.
        case keyboard
        /// Lights along the mouse body (scroll wheel first).
        case mouse
        /// Firefly V2's measured LED positions.
        case fireflyV2
        /// Generic edge-lit mat, LEDs evenly spaced clockwise.
        case mat
        /// Plain grid.
        case matrix
    }

    public var productID: UInt16
    public var name: String
    public var kind: DeviceKind
    public var rows: Int
    public var columns: Int
    /// Transaction id byte the firmware expects.
    public var transactionID: UInt8
    /// `wIndex` of the SET_REPORT/GET_REPORT control transfers.
    public var controlIndex: UInt16
    /// LED ids for brightness and hardware effects (e.g. 0x05 backlight, 0x01 wheel, 0x04 logo).
    public var ledIDs: [UInt8]
    /// Whether to switch to "driver" device mode (0x03) while Aura runs.
    public var driverMode: Bool
    public var layoutStyle: LayoutStyle

    public init(productID: UInt16, name: String, kind: DeviceKind, rows: Int, columns: Int, transactionID: UInt8,
                controlIndex: UInt16, ledIDs: [UInt8], driverMode: Bool, layoutStyle: LayoutStyle) {
        self.productID = productID
        self.name = name
        self.kind = kind
        self.rows = rows
        self.columns = columns
        self.transactionID = transactionID
        self.controlIndex = controlIndex
        self.ledIDs = ledIDs
        self.driverMode = driverMode
        self.layoutStyle = layoutStyle
    }

    public func makeLayout() -> DeviceLayout {
        switch layoutStyle {
        case .keyboard: RazerLayouts.keyboard(rows: rows, columns: columns)
        case .mouse: RazerLayouts.mouse(columns: rows * columns)
        case .fireflyV2: RazerLayouts.fireflyV2()
        case .mat: RazerLayouts.mat(count: rows * columns)
        case .matrix: DeviceLayout.matrix(rows: rows, columns: columns, pitch: RazerLayouts.keyPitch)
        }
    }
}

public enum RazerCatalog {
    public static let vendorID: UInt16 = 0x1532

    /// Models verified on hardware. Values from OpenRazer / OpenRGB, checked against the devices.
    public static let builtIn: [RazerDeviceDescriptor] = [
        RazerDeviceDescriptor(productID: 0x025E, name: "Razer Cynosa V2", kind: .keyboard, rows: 6, columns: 22,
                              transactionID: 0x1F, controlIndex: 0x01, ledIDs: [0x05], driverMode: false,
                              layoutStyle: .keyboard),
        RazerDeviceDescriptor(productID: 0x0085, name: "Razer Basilisk V2", kind: .mouse, rows: 1, columns: 2,
                              transactionID: 0x1F, controlIndex: 0x00, ledIDs: [0x01, 0x04], driverMode: false,
                              layoutStyle: .mouse),
        RazerDeviceDescriptor(productID: 0x0C04, name: "Razer Firefly V2", kind: .mousepad, rows: 1, columns: 19,
                              transactionID: 0x3F, controlIndex: 0x00, ledIDs: [0x00], driverMode: true,
                              layoutStyle: .fireflyV2),
    ]

    /// Built-in models plus any user-supplied descriptors (user files win on matching product id).
    public static func load(userDirectory: URL? = RazerCatalog.userDirectory) -> [UInt16: RazerDeviceDescriptor] {
        var result = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.productID, $0) })
        guard let userDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: userDirectory, includingPropertiesForKeys: nil)
        else { return result }
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file) else { continue }
            let descriptors = (try? decoder.decode([RazerDeviceDescriptor].self, from: data))
                ?? (try? decoder.decode(RazerDeviceDescriptor.self, from: data)).map { [$0] }
                ?? []
            for descriptor in descriptors where descriptor.rows > 0 && descriptor.columns > 0
                && descriptor.columns <= RazerPacket.maxLEDsPerRow {
                result[descriptor.productID] = descriptor
            }
        }
        return result
    }

    public static var userDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aura/devices", isDirectory: true)
    }
}
