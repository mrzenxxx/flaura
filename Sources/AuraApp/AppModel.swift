import AppKit
import AuraCore
import AuraDevices
import Combine

/// The app's single source of truth: settings, connected devices and the wiring between the
/// device registry, the render engine, input monitoring and power state.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AuraSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    @Published private(set) var devices: [DeviceInfo] = []
    @Published private(set) var health: [String: DeviceHealth] = [:]
    @Published private(set) var inputAccess = InputMonitor.hasAccess
    @Published private(set) var launchAtLogin = LoginItem.isEnabled
    @Published var loginItemError: String?

    let engine = RenderEngine()
    private let store: SettingsStore
    private let registry: DeviceRegistry
    private var input: InputMonitor!
    private var power: PowerObserver!
    private var activity: NSObjectProtocol?
    private var accessPoll: Timer?
    private var accessPollDeadline = Date.distantPast

    /// `live: false` builds the model without touching hardware or input (UI snapshots, self-test).
    init(live: Bool = true, storeDirectory: URL? = nil) {
        store = SettingsStore(directory: storeDirectory)
        settings = store.load()
        registry = DeviceRegistry(providers: DeviceRegistry.standardProviders { message in
            NSLog("Aura: %@", message)
        })

        let engine = engine
        input = InputMonitor { event in engine.post(event) }
        power = PowerObserver { [weak self] _ in self?.updateSuspension() }

        engine.setHandlers(
            activity: { [weak self] animating in
                Task { @MainActor in self?.setAnimating(animating) }
            },
            health: { [weak self] id, health in
                Task { @MainActor in self?.health[id] = health }
            }
        )
        guard live else { return }
        if store.isFirstLaunch {
            // A background utility should come back after a reboot; the user can turn it off in settings.
            _ = LoginItem.set(true, openSettingsIfNeeded: false)
            launchAtLogin = LoginItem.isEnabled
            store.save(settings)
        }
        engine.apply(settings)
        registry.start { [weak self] devices in
            engine.setDevices(devices)
            let infos = devices.map(\.info)
            Task { @MainActor in
                guard let self else { return }
                self.devices = infos
                self.health = self.health.filter { id, _ in infos.contains { $0.id == id } }
            }
        }
        updateInputMonitor()
    }

    // MARK: Actions

    func requestInputAccess() {
        if !InputMonitor.requestAccess() {
            InputMonitor.openPrivacySettings()
        }
        startAccessPolling()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = LoginItem.set(enabled)
        launchAtLogin = LoginItem.isEnabled
    }

    func refreshPermissions() {
        inputAccess = InputMonitor.hasAccess
        launchAtLogin = LoginItem.isEnabled
        updateInputMonitor()
    }

    func shutdown() {
        store.flush(settings)
        input.stop()
        registry.stop()
        engine.shutdown()
    }

    /// Settings for a device, writable through a binding.
    func deviceSettings(_ id: String) -> DeviceSettings {
        settings.device(id)
    }

    /// Fake device list for UI snapshots.
    func setPreviewDevices(_ infos: [DeviceInfo]) {
        devices = infos
    }

    func updateDevice(_ id: String, _ change: (inout DeviceSettings) -> Void) {
        var device = settings.device(id)
        change(&device)
        settings.devices[id] = device
    }

    // MARK: Internals

    private func settingsDidChange(from old: AuraSettings) {
        guard settings != old else { return }
        engine.apply(settings)
        store.save(settings)
        if settings.reactive.needsInput != old.reactive.needsInput || settings.enabled != old.enabled {
            updateInputMonitor()
        }
        if settings.dimWhenIdle != old.dimWhenIdle {
            updateSuspension()
        }
    }

    private func updateInputMonitor() {
        let wanted = settings.enabled && settings.reactive.needsInput
        inputAccess = InputMonitor.hasAccess
        if wanted {
            input.start()
        } else {
            input.stop()
            stopAccessPolling()
        }
    }

    /// After "Разрешить…", pick up the System Settings switch without a relaunch. Runs for a few
    /// minutes at most; opening the panel re-checks anyway.
    private func startAccessPolling() {
        accessPollDeadline = Date().addingTimeInterval(180)
        guard accessPoll == nil else { return }
        accessPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollAccess() }
        }
    }

    private func stopAccessPolling() {
        accessPoll?.invalidate()
        accessPoll = nil
    }

    private func pollAccess() {
        inputAccess = InputMonitor.hasAccess
        if inputAccess {
            stopAccessPolling()
            updateInputMonitor()
        } else if Date() > accessPollDeadline {
            stopAccessPolling()
        }
    }

    private func updateSuspension() {
        let state = power.state
        let away = state.systemAsleep || (settings.dimWhenIdle && (state.displaysAsleep || state.locked))
        engine.setSuspended(away)
    }

    /// While animating, opt out of App Nap so the render timer is not throttled.
    private func setAnimating(_ animating: Bool) {
        if animating, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Animating keyboard, mouse and mat lighting"
            )
        } else if !animating, let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
    }
}
