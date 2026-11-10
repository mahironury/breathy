import Foundation

/// Breathy'nin asla dokunmayacağı yerler. Her silme ve her tarama bu kontrolden geçer.
enum PathGuard {
    /// Ev klasörüne göre korunan yollar: içine girilmez, içindeki hiçbir şey silinmez.
    static let protectedRelative: [String] = [
        ".ssh", ".gnupg",
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Mobile Documents",      // iCloud Drive (ayrı ve dikkatli ele alınır)
        "Library/CloudStorage",          // Dropbox, Google Drive, OneDrive
        "Library/Safari",
        "Library/Cookies",
        "Library/Accounts",
        "Library/Calendars",
        "Library/IdentityServices",
        "Library/Photos",
        "Library/Preferences",
        "Library/Application Support/AddressBook",
        "Library/Application Support/com.apple.TCC",
        "Library/Containers/com.apple.mail",
    ]

    /// Kendisi silinemeyen ama içindekiler aday olabilen klasörler.
    static let undeletableRelative: Set<String> = [
        "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music",
        "Public", "Sites", "Applications", "Library",
        "Library/Caches", "Library/Logs", "Library/Application Support",
        "Library/Containers", "Library/Group Containers", "Library/Developer",
    ]

    /// Tarama sırasında bu klasörün içine girilebilir mi?
    static func isWalkable(_ url: URL, home: URL) -> Bool {
        guard let rel = relativePath(of: url, home: home) else { return true }
        return !isProtected(rel)
    }

    /// Bu öğe Breathy tarafından silinebilir / Çöp'e taşınabilir mi?
    static func canDelete(_ url: URL, home: URL, appDirs: [URL]) -> Bool {
        let path = normalize(url)
        // Fotoğraflar kütüphanesinin kendisi ve içi her zaman korunur.
        if url.pathComponents.contains(where: { $0.lowercased().hasSuffix(".photoslibrary") }) { return false }

        if let rel = relativePath(of: url, home: home) {
            if rel.isEmpty || undeletableRelative.contains(rel) || isProtected(rel) { return false }
            return true
        }
        // Ev klasörü dışında sadece uygulama klasörlerindeki .app paketleri.
        for dir in appDirs {
            let base = normalize(dir)
            if path.hasPrefix(base + "/"), path.lowercased().hasSuffix(".app") { return true }
        }
        return false
    }

    // MARK: -

    private static func isProtected(_ rel: String) -> Bool {
        protectedRelative.contains { rel == $0 || rel.hasPrefix($0 + "/") }
    }

    /// Sadece metin üzerinden "." ve ".." çözümlemesi. `standardizedFileURL` kullanılmaz:
    /// o, "/private" önekini dosya var mı yok mu diye bakarak kısalttığı için tutarsız sonuç verir.
    static func normalize(_ url: URL) -> String {
        var parts: [String] = []
        for component in url.pathComponents {
            switch component {
            case "/", ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(component)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Ev klasörünün içindeyse göreli yol ("" = ev klasörünün kendisi), değilse nil.
    private static func relativePath(of url: URL, home: URL) -> String? {
        let path = normalize(url)
        let homePath = normalize(home)
        if path == homePath { return "" }
        guard path.hasPrefix(homePath + "/") else { return nil }
        return String(path.dropFirst(homePath.count + 1))
    }
}
