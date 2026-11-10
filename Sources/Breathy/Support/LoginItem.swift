import Foundation
import ServiceManagement

/// "Açılışta başlat" (oturum açma öğesi). İlk açılışta bir kez kendiliğinden açılır;
/// kullanıcı panelden kapatırsa bir daha dokunulmaz.
enum LoginItem {
    enum State: Equatable, Sendable {
        case enabled
        case disabled
        /// Sistem Ayarları → Oturum Açma Öğeleri'nde kullanıcı onayı bekleniyor.
        case needsApproval
        /// Uygulama bir Applications klasöründen çalışmıyor (ör. build/ kopyası); ayar gösterilmez.
        case unavailable
    }

    private static let configuredKey = "loginItemConfigured"

    static var state: State {
        guard isInstalledCopy else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        default: return .disabled
        }
    }

    /// Sadece /Applications ya da ~/Applications'taki kopya oturum açma öğesi olur;
    /// derleme klasöründeki geçici kopyalar olmaz.
    static var isInstalledCopy: Bool {
        isInstallLocation(Bundle.main.bundlePath, home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    static func isInstallLocation(_ bundlePath: String, home: String) -> Bool {
        guard bundlePath.hasSuffix(".app") else { return false }
        let parent = (bundlePath as NSString).deletingLastPathComponent
        return parent == "/Applications" || parent == home + "/Applications"
    }

    /// Plandaki karar: Breathy açılışta başlar. İlk çalıştırmada bir kez kaydeder.
    static func configureOnFirstLaunch(defaults: UserDefaults = .standard) {
        guard isInstalledCopy, !defaults.bool(forKey: configuredKey) else { return }
        try? SMAppService.mainApp.register()
        defaults.set(true, forKey: configuredKey)
    }

    static func setEnabled(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
