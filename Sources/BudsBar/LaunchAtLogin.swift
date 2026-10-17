import Observation
import ServiceManagement

/// "Launch at login", backed by `SMAppService`.
///
/// This is the only supported mechanism on current macOS; the older login-items APIs are
/// deprecated and quietly stop working. Because the app hides its menu-bar item when the
/// buds are away, staying resident from login is what lets it catch a connect that happens
/// before you think to open it.
///
/// Registration is per copy of the bundle, so it points at wherever this app lives.
/// `set` reads the real status back rather than assuming the change took — `register()`
/// can fail (for example from a build directory the user later moves), and the toggle
/// should show what actually happened.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled: Bool
    private(set) var lastError: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
