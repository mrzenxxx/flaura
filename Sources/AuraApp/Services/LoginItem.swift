import ServiceManagement

/// Launch at login through SMAppService (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
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
