import Foundation

/// Bu Mac'te hangi iCloud servisleri açık? (~/Library/Preferences/MobileMeAccounts.plist)
/// Sadece servis adları ve açık/kapalı bilgisi okunur; hesap bilgileri okunmaz.
struct ICloudStatus: Codable, Sendable, Equatable {
    var signedIn: Bool
    /// iCloud Drive
    var driveEnabled: Bool
    /// "Masaüstü ve Belgeler Klasörleri" eşitlemesi
    var desktopDocumentsEnabled: Bool

    /// Bu Mac iCloud kotasına dosya gönderiyor mu?
    var macUploadsFiles: Bool { driveEnabled || desktopDocumentsEnabled }

    static func read() -> ICloudStatus {
        let accounts = CFPreferencesCopyAppValue("Accounts" as CFString, "MobileMeAccounts" as CFString)
        return parse(accounts as? [[String: Any]])
    }

    static func parse(_ accounts: [[String: Any]]?) -> ICloudStatus {
        guard let account = accounts?.first else {
            return ICloudStatus(signedIn: false, driveEnabled: false, desktopDocumentsEnabled: false)
        }
        let services = account["Services"] as? [[String: Any]] ?? []
        func isOn(_ name: String) -> Bool {
            services.contains { service in
                guard service["Name"] as? String == name else { return false }
                if let flag = service["Enabled"] as? Bool { return flag }
                return (service["Enabled"] as? Int) == 1
            }
        }
        return ICloudStatus(
            signedIn: true,
            driveEnabled: isOn("MOBILE_DOCUMENTS"),
            desktopDocumentsEnabled: isOn("CLOUDDESKTOP")
        )
    }
}

/// macOS ekran görüntüsü ayarı (com.apple.screencapture → location).
enum ScreenshotSettings {
    private static var domain: CFString { "com.apple.screencapture" as CFString }

    /// Ayar yoksa macOS Masaüstü'ne kaydeder.
    static func location(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let raw = CFPreferencesCopyAppValue("location" as CFString, domain) as? String, !raw.isEmpty {
            let expanded = raw.hasPrefix("~") ? home.path + raw.dropFirst() : raw
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return home.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    /// Önerilen iCloud dışı klasör: ~/Pictures/Ekran Görüntüleri
    static func suggestedFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Pictures/Ekran Görüntüleri", directoryHint: .isDirectory)
    }

    /// Sadece kullanıcı düğmeye basınca çağrılır.
    static func setLocation(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        CFPreferencesSetAppValue("location" as CFString, url.path as CFString, domain)
        CFPreferencesAppSynchronize(domain)
    }
}
