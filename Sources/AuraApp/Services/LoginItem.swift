import ServiceManagement

/// Launch at login through SMAppService (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers Aura again if macOS has no login item for it (an earlier attempt failed or the
    /// item got lost). Leaves an item waiting for approval alone. Only a real app bundle can be a
    /// login item, so a bare `.build/debug/Aura` does nothing.
    static func restore() -> String? {
        let status = SMAppService.mainApp.status
        guard Bundle.main.bundleURL.pathExtension == "app",
              status == .notRegistered || status == .notFound else { return nil }
        return set(true, openSettingsIfNeeded: false)
    }

    /// Returns an error message, or nil on success.
    static func set(_ enabled: Bool, openSettingsIfNeeded: Bool = true) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if needsApproval && openSettingsIfNeeded { SMAppService.openSystemSettingsLoginItems() }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
