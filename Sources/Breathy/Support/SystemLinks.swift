import AppKit

/// Sistem Ayarları'na ve Finder'a kısayollar.
enum SystemLinks {
    /// Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi.
    static func openFullDiskAccess() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Sistem Ayarları → Apple Hesabı (iCloud → Depolamayı Yönet buradan).
    static func openICloudSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings",
            "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Klasörü Finder'da aç.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Breathy.app'i Finder'da seçili göster (izin listesine sürüklemek için).
    static func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// İzin verildikten sonra macOS bazen uygulamanın yeniden açılmasını ister.
    @MainActor
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        // Tamamlanma arka plan kuyruğunda çağrılır; @Sendable olmazsa ana aktör denetimi çökertir.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { @Sendable _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
