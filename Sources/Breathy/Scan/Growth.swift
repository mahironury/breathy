import AppKit

/// "Geçen taramadan beri ne büyüdü?": iki taramanın klasör boyutlarını karşılaştırır.
enum Growth {
    /// Bundan az büyüyen klasör gösterilmez.
    static let minDeltaBytes: Int64 = 300_000_000
    static let maxItems = 5

    static func compute(
        old: [String: Int64], new: [String: Int64],
        minDelta: Int64 = minDeltaBytes,
        title: (String) -> String = displayName
    ) -> [GrowthItem] {
        var candidates: [String: Int64] = [:]
        for (key, bytes) in new {
            let delta = bytes - (old[key] ?? 0)
            if delta >= minDelta { candidates[key] = delta }
        }

        // İç içe klasörlerden birini göster: alt klasör büyümenin çoğunu (%60) açıklıyorsa onu,
        // açıklamıyorsa üst klasörü. ("Belgeler +5 GB" ve "Belgeler/Proje +4,8 GB" ikisi birden çıkmasın.)
        for parent in candidates.keys.sorted(by: { depth($0) > depth($1) }) {
            guard let parentDelta = candidates[parent] else { continue }
            let children = candidates.filter { $0.key.hasPrefix(parent + "/") }
            guard let best = children.values.max() else { continue }
            if Double(best) >= 0.6 * Double(parentDelta) {
                candidates[parent] = nil
            } else {
                for child in children.keys { candidates[child] = nil }
            }
        }

        return candidates
            .map { GrowthItem(key: $0.key, title: title($0.key), bytes: new[$0.key] ?? 0, delta: $0.value) }
            .sorted { $0.delta != $1.delta ? $0.delta > $1.delta : $0.key < $1.key }
            .prefix(maxItems)
            .map { $0 }
    }

    private static func depth(_ key: String) -> Int {
        key.reduce(0) { $0 + ($1 == "/" ? 1 : 0) }
    }

    // MARK: - Görünen adlar

    static let homeFolderNames = [
        "Desktop": "Masaüstü", "Documents": "Belgeler", "Downloads": "İndirilenler", "Pictures": "Resimler",
        "Movies": "Filmler", "Music": "Müzik", "Public": "Ortak", "Applications": "Uygulamalar",
    ]

    static func displayName(_ key: String) -> String {
        let parts = key.split(separator: "/").map(String.init)
        if parts.count >= 3, parts[0] == "Library",
           ["Application Support", "Containers", "Group Containers"].contains(parts[1]) {
            return appName(forFolder: parts[2])
        }
        switch key {
        case "Library/Caches": return "Uygulama önbellekleri"
        case "Library/Logs": return "Loglar"
        case "Library/Messages/Attachments": return "Mesajlar ekleri"
        default: break
        }
        if let first = parts.first, let local = homeFolderNames[first] {
            return ([local] + parts.dropFirst()).joined(separator: "/")
        }
        return "~/" + key
    }

    /// "group.net.whatsapp.WhatsApp.shared" → "WhatsApp". Kurulu uygulamanın adını bulmaya çalışır;
    /// bulamazsa kimliğin en anlamlı parçasını döner.
    static func appName(forFolder name: String, lookup: (String) -> String? = installedAppName) -> String {
        var id = name
        if id.hasPrefix("group.") { id.removeFirst("group.".count) }
        if let range = id.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) { id.removeSubrange(range) }
        guard Scanner.looksLikeBundleID(id) else { return id }

        var parts = id.split(separator: ".").map(String.init)
        let all = parts
        while parts.count >= 2 {
            if let app = lookup(parts.joined(separator: ".")) { return app }
            parts.removeLast()
        }
        return all.count > 2 ? all[2] : all.last ?? name
    }

    static func installedAppName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

extension ScanResult {
    /// Önceki taramayla karşılaştırıp büyüyenleri ekler. Önceki kayıtta klasör boyutları yoksa
    /// (ilk tarama ya da 0.1 sürümünün kaydı) karşılaştırma yapılmaz.
    mutating func compareGrowth(with previous: ScanResult?, minDelta: Int64 = Growth.minDeltaBytes) {
        guard let previous, let old = previous.folderSizes, let new = folderSizes else { return }
        growth = Growth.compute(old: old, new: new, minDelta: minDelta)
        growthSince = previous.date
    }
}
