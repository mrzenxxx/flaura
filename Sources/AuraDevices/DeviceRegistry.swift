import AuraCore
import Foundation

/// Merges the device lists of all providers. New hardware families plug in here: implement
/// `DeviceProvider` and add it to `standardProviders`.
public final class DeviceRegistry: @unchecked Sendable {
    private let providers: [any DeviceProvider]
    private let lock = NSLock()
    private var lists: [ObjectIdentifier: [any LightingDevice]] = [:]

    public init(providers: [any DeviceProvider]) {
        self.providers = providers
    }

    public static func standardProviders(log: @escaping @Sendable (String) -> Void = { _ in }) -> [any DeviceProvider] {
        [RazerProvider(log: log)]
    }

    /// `onChange` receives the merged list (sorted by id) whenever any provider's list changes.
    public func start(onChange: @escaping @Sendable ([any LightingDevice]) -> Void) {
        for provider in providers {
            let key = ObjectIdentifier(provider)
            provider.start { [weak self] devices in
                guard let self else { return }
                self.lock.lock()
                self.lists[key] = devices
                let merged = self.lists.values.flatMap { $0 }.sorted { $0.info.id < $1.info.id }
                self.lock.unlock()
                onChange(merged)
            }
        }
    }

    public func stop() {
        providers.forEach { $0.stop() }
    }
}
