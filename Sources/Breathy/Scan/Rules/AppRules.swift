import Foundation

/// Uygulamalarla ilgili kurallar: kaldırılmış uygulama artıkları, büyük uygulama verileri,
/// uzun süredir açılmamış uygulamalar.
extension Scanner {
    func libraryAppData(_ ctx: ScanContext) throws -> [Finding] {
        let fm = FileManager.default
        let installed = installedBundleIDs()
        let rulePaths = Self.locationRules.map { homePath($0.path) }
        var out: [Finding] = []

        let roots: [(path: String, leftoverCandidate: Bool)] = [
            ("Library/Application Support", true),
            ("Library/Containers", true),
            ("Library/Group Containers", false),  // adları ekip kimliğiyle başlar, eşleştirme güvenilmez
        ]

        for root in roots {
            let dir = env.home.appending(path: root.path)
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }

            for child in children {
                try ctx.checkpoint(nil)
                let name = child.lastPathComponent
                let lower = name.lowercased()
                if name == ".DS_Store" || lower.contains("com.apple") || lower == env.ownBundleID.lowercased() { continue }
                // Bilinen kuralların ölçtüğü yerleri (Adobe önbelleği, Docker, iPhone yedekleri) iki kez sayma.
                let childPath = child.path
                if rulePaths.contains(where: { $0.hasPrefix(childPath + "/") }) { continue }

                ctx.setFolder(child)
                let bytes = try measure(child, ctx)
                ctx.addSize("\(root.path)/\(name)", bytes)

                if root.leftoverCandidate, Self.looksLikeBundleID(name), !isInstalled(lower, installed) {
                    if bytes >= limits.minItemBytes,
                       let f = makeFinding(child, .appLeftovers, .review, bytes: bytes,
                                           note: "Kurulu bir uygulamaya ait görünmüyor", ctx: ctx) {
                        out.append(f)
                    }
                } else if bytes >= limits.appDataBytes,
                          let f = makeFinding(child, .appData, .info, bytes: bytes,
                                              note: Self.appDataTip(for: lower), ctx: ctx) {
                    out.append(f)
                }
            }
        }
        return out
    }

    func unusedApps(_ ctx: ScanContext) throws -> [Finding] {
        var candidates: [(url: URL, lastUsed: Date?)] = []
        for url in appBundles(in: env.applicationDirs) {
            guard let id = Bundle(url: url)?.bundleIdentifier?.lowercased() else { continue }
            if id.hasPrefix("com.apple.") || id == env.ownBundleID.lowercased() || env.runningApps[id] != nil { continue }
            candidates.append((url, env.lastUsed(url) ?? env.dateAdded(url)))
        }
        // Spotlight hiçbir uygulama için tarih vermiyorsa dizin kapalıdır; bu kategori güvenilmez → atla.
        guard candidates.contains(where: { $0.lastUsed != nil }) else { return [] }

        var out: [Finding] = []
        for candidate in candidates {
            guard let date = candidate.lastUsed, daysSince(date) >= limits.unusedDays else { continue }
            try ctx.checkpoint(nil)
            ctx.setFolder(candidate.url)
            let bytes = try measure(candidate.url, ctx)
            guard bytes >= limits.minItemBytes else { continue }
            // Otomatik işaretlenmez: açılışta kendiliğinden çalışan araçlar (VPN, pencere yöneticisi…)
            // "açılmamış" görünebilir. Karar kullanıcının.
            if let f = makeFinding(candidate.url, .unusedApps, .review, bytes: bytes, suggested: false, lastUsed: date,
                                   note: "Uzun süredir açılmamış — ihtiyacın yoksa kaldırabilirsin", ctx: ctx) {
                out.append(f)
            }
        }
        return out
    }

    // MARK: - Yardımcılar

    /// Klasörlerdeki .app paketleri; Adobe gibi kendi alt klasörüne kurulanlar için bir seviye derine de bakar.
    func appBundles(in dirs: [URL]) -> [URL] {
        let fm = FileManager.default
        var apps: [URL] = []
        for dir in dirs {
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for child in children {
                if child.pathExtension.lowercased() == "app" {
                    apps.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          let inner = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil) {
                    apps += inner.filter { $0.pathExtension.lowercased() == "app" }
                }
            }
        }
        return apps
    }

    func installedBundleIDs() -> Set<String> {
        Set(appBundles(in: env.applicationDirs + env.systemApplicationDirs).compactMap {
            Bundle(url: $0)?.bundleIdentifier?.lowercased()
        })
    }

    /// Bir klasör adı (bundle ID) kurulu bir uygulamaya ya da onun bir eklentisine ait mi?
    func isInstalled(_ id: String, _ installed: Set<String>) -> Bool {
        if installed.contains(id) || env.runningApps[id] != nil { return true }
        if installed.contains(where: { id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) { return true }
        return env.isRegistered(id)
    }

    /// Büyük uygulama verisi için kullanıcıya nereden temizleyeceğini söyleyen ipucu.
    static func appDataTip(for lowercasedName: String) -> String {
        let tips: [(String, String)] = [
            ("whatsapp", "WhatsApp'ta Ayarlar → Depolama bölümünden büyük medya ve sohbetleri temizle"),
            ("telegram", "Telegram'da Ayarlar → Gelişmiş → Depolamayı yönet"),
            ("slack", "Slack'te Yardım → Sorun Giderme → Önbelleği temizle"),
            ("claude", "Claude uygulamasının sanal makine ve kod dosyaları — uygulama tarafından yönetilir"),
            ("google", "Chrome'da Ayarlar → Gizlilik → Tarama verilerini temizle"),
            ("spotify", "Spotify'da Ayarlar → Depolama → Önbelleği temizle"),
        ]
        return tips.first { lowercasedName.contains($0.0) }?.1 ?? "Uygulamanın kendi ayarlarından temizlenmeli"
    }

    /// "com.firma.uygulama" biçiminde mi? (en az üç parça)
    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}
