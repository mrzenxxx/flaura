import AuraCore
import Foundation
import IOKit
import IOKit.usb

/// Discovers Razer USB devices (and hot-plugs) via IOKit notifications on IOUSBHostDevice.
public final class RazerProvider: DeviceProvider, @unchecked Sendable {
    public let name = "Razer"

    private let queue = DispatchQueue(label: "aura.provider.razer")
    private var port: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var devices: [UInt64: RazerDevice] = [:]
    private var catalog: [UInt16: RazerDeviceDescriptor] = [:]
    private var onChange: (@Sendable ([any LightingDevice]) -> Void)?
    /// IOKit holds a raw pointer to us while notifications are armed; retained until `stop()`.
    private var retainedSelf: Unmanaged<RazerProvider>?
    private let log: @Sendable (String) -> Void

    public init(log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.log = log
    }

    public func start(onChange: @escaping @Sendable ([any LightingDevice]) -> Void) {
        queue.async {
            guard self.port == nil else { return }
            self.onChange = onChange
            self.catalog = RazerCatalog.load()
            guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
                self.log("Razer: cannot create IOKit notification port")
                return
            }
            self.port = port
            IONotificationPortSetDispatchQueue(port, self.queue)
            let retained = Unmanaged.passRetained(self)
            self.retainedSelf = retained
            let context = retained.toOpaque()

            let added: IOServiceMatchingCallback = { refcon, iterator in
                guard let refcon else { return }
                Unmanaged<RazerProvider>.fromOpaque(refcon).takeUnretainedValue().servicesAdded(iterator)
            }
            let removed: IOServiceMatchingCallback = { refcon, iterator in
                guard let refcon else { return }
                Unmanaged<RazerProvider>.fromOpaque(refcon).takeUnretainedValue().servicesRemoved(iterator)
            }
            IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, RazerProvider.matching(), added,
                                             context, &self.addedIterator)
            IOServiceAddMatchingNotification(port, kIOTerminatedNotification, RazerProvider.matching(), removed,
                                             context, &self.removedIterator)
            // Arm the notifications by draining the iterators; this also picks up devices already present.
            self.servicesAdded(self.addedIterator)
            self.servicesRemoved(self.removedIterator)
        }
    }

    public func stop() {
        queue.sync {
            if addedIterator != 0 { IOObjectRelease(addedIterator) }
            if removedIterator != 0 { IOObjectRelease(removedIterator) }
            addedIterator = 0
            removedIterator = 0
            if let port { IONotificationPortDestroy(port) }
            port = nil
            devices.removeAll()
            onChange = nil
            retainedSelf?.release()
            retainedSelf = nil
        }
    }

    /// IOUSBHostDevice with Razer's vendor id. A bare `idVendor` key is not a valid USB matching
    /// combination, so it goes through `IOPropertyMatch`.
    private static func matching() -> CFMutableDictionary {
        let dictionary = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        dictionary[kIOPropertyMatchKey] = [kUSBVendorID: Int(RazerCatalog.vendorID)]
        return dictionary as CFMutableDictionary
    }

    private func servicesAdded(_ iterator: io_iterator_t) {
        var changed = false
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            guard devices[entryID] == nil else { continue }
            let productID = UInt16(truncatingIfNeeded: RazerProvider.intProperty(service, kUSBProductID) ?? 0)
            guard let descriptor = catalog[productID] else {
                log(String(format: "Razer: unsupported product 0x%04X, skipping", productID))
                continue
            }
            do {
                let transport = try USBControlTransport(registryEntryID: entryID)
                let id = deviceID(for: productID)
                let probe = RazerDevice(descriptor: descriptor, transport: transport, id: id, detail: "")
                let firmware = (try? probe.firmwareVersion()) ?? "?"
                let detail = String(format: "USB 1532:%04X · fw %@", productID, firmware)
                devices[entryID] = RazerDevice(descriptor: descriptor, transport: transport, id: id, detail: detail)
                log("Razer: connected \(descriptor.name) (\(detail))")
                changed = true
            } catch {
                log("Razer: cannot open \(descriptor.name): \(error)")
            }
        }
        if changed { publish() }
    }

    private func servicesRemoved(_ iterator: io_iterator_t) {
        var changed = false
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            if let device = devices.removeValue(forKey: entryID) {
                log("Razer: disconnected \(device.info.name)")
                changed = true
            }
        }
        if changed { publish() }
    }

    /// "razer:025e", with a suffix if two identical models are connected.
    private func deviceID(for productID: UInt16) -> String {
        let base = String(format: "razer:%04x", productID)
        let taken = Set(devices.values.map(\.info.id))
        var id = base
        var n = 2
        while taken.contains(id) {
            id = "\(base)#\(n)"
            n += 1
        }
        return id
    }

    private func publish() {
        let list = devices.values.sorted { $0.info.id < $1.info.id }
        onChange?(list)
    }

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }
}
