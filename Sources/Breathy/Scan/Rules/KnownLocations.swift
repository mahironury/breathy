import Foundation

/// Bilinen önbellek, log ve geliştirici/medya artığı konumları.
extension Scanner {
    struct LocationRule: Sendable {
        let path: String          // ev klasörüne göre
        let category: ScanCategory
        let risk: Risk
        let eachChild: Bool       // true: her alt klasör ayrı bulgu
        let note: String?

        init(_ path: String, _ category: ScanCategory, _ risk: Risk, eachChild: Bool = false, note: String? = nil) {
            self.path = path
            self.category = category
            self.risk = risk
            self.eachChild = eachChild
            self.note = note
        }
    }

    static let locationRules: [LocationRule] = [
        // Genel
        LocationRule("Library/Caches", .caches, .safe, eachChild: true),
        LocationRule("Library/Logs", .logs, .safe, eachChild: true),

        // Yazılım geliştirme
        LocationRule(".npm/_cacache", .devCaches, .safe, note: "npm önbelleği — gerektiğinde yeniden indirilir"),
        LocationRule(".cache", .devCaches, .safe, eachChild: true),
        LocationRule(".gradle/caches", .devCaches, .safe),
        LocationRule(".cargo/registry", .devCaches, .safe),
        LocationRule(".pnpm-store", .devCaches, .safe),
        LocationRule("Library/pnpm/store", .devCaches, .safe),
        LocationRule(".bun/install/cache", .devCaches, .safe),
        LocationRule(".cocoapods/repos", .devCaches, .safe),
        LocationRule(".m2/repository", .devCaches, .review, note: "Maven kütüphaneleri — projeler yeniden indirir"),
        LocationRule("go/pkg/mod", .devCaches, .review, note: "Go modülleri — projeler yeniden indirir"),
        LocationRule("Library/Developer/Xcode/DerivedData", .xcode, .safe, note: "Xcode derleme ara dosyaları"),
        LocationRule("Library/Developer/Xcode/iOS DeviceSupport", .xcode, .safe, eachChild: true),
        LocationRule("Library/Developer/Xcode/Archives", .xcode, .review, eachChild: true, note: "Uygulama arşivleri"),
        LocationRule("Library/Developer/CoreSimulator/Caches", .xcode, .safe),
        LocationRule("Library/Developer/CoreSimulator/Devices", .xcode, .review, note: "iOS simülatörleri"),

        // Fotoğraf / video / tasarım
        LocationRule("Library/Application Support/Adobe/Common/Media Cache Files", .mediaCaches, .safe, note: "Adobe medya önbelleği"),
        LocationRule("Library/Application Support/Adobe/Common/Media Cache", .mediaCaches, .safe, note: "Adobe medya önbelleği"),
        LocationRule("Movies/CacheClip", .mediaCaches, .safe, note: "DaVinci Resolve önbelleği"),

        // iPhone/iPad güncellemeleri (Finder'ın indirdiği .ipsw dosyaları)
        LocationRule("Library/iTunes/iPhone Software Updates", .oldInstallers, .safe, eachChild: true,
                     note: "iPhone yazılım güncellemesi — gerekirse yeniden indirilir"),
        LocationRule("Library/iTunes/iPad Software Updates", .oldInstallers, .safe, eachChild: true,
                     note: "iPad yazılım güncellemesi — gerekirse yeniden indirilir"),
        LocationRule("Library/iTunes/iPod Software Updates", .oldInstallers, .safe, eachChild: true,
                     note: "iPod yazılım güncellemesi — gerekirse yeniden indirilir"),

        // Sadece bilgi
        LocationRule("Library/Application Support/MobileSync/Backup", .iosBackups, .info, eachChild: true,
                     note: "Finder'da cihazını seçip yedekleri oradan yönet"),
        LocationRule("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", .docker, .info,
                     note: "Terminal'de 'docker system prune -a' ile küçültülebilir"),
        LocationRule("Library/Messages/Attachments", .appData, .info,
                     note: "Mesajlar ekleri — Mesajlar → Ayarlar → Genel → 'Mesajları sakla' süresini kısalt"),
    ]

    /// ~/Library/Caches altında geliştirici araçlarına ait klasörler.
    static let devCacheNames: Set<String> = [
        "pip", "homebrew", "yarn", "pnpm", "go-build", "ms-playwright", "node-gyp", "typescript",
        "cocoapods", "org.swift.swiftpm", "jetbrains", "deno", "bazel", "electron", "electron-builder",
    ]

    /// ~/.cache altında büyük yapay zekâ modelleri: silinirse yeniden indirmek gerekir.
    static let modelCacheNames: Set<String> = ["huggingface", "torch", "lm-studio", "whisper", "ollama"]

    /// Bundle ID'si olmayan önbellek klasörlerinin sahibi uygulamalar.
    static let cacheOwners: [String: String] = [
        "google": "com.google.chrome",
        "firefox": "org.mozilla.firefox",
        "slack": "com.tinyspeck.slackmacgap",
        "microsoft edge": "com.microsoft.edgemac",
        "bravesoftware": "com.brave.browser",
        "spotify": "com.spotify.client",
    ]

    /// Ev klasörü taramasında içine girilmeyecek yollar (bu kurallar zaten ölçüyor).
    var walkSkipPaths: Set<String> {
        var skip: Set<String> = [homePath("Library"), homePath(".Trash")]
        for rule in Self.locationRules { skip.insert(homePath(rule.path)) }
        return skip
    }

    func knownLocations(_ ctx: ScanContext) throws -> [Finding] {
        let fm = FileManager.default
        var out: [Finding] = []

        for rule in Self.locationRules {
            // ~/.cache hem geliştiricinin hem yapay zekâ araçlarının (modeller) alanı.
            let ruleAreas: Set<UsageArea>? = rule.path == ".cache"
                ? [.development, .aiCoding] : rule.category.area.map { [$0] }
            if let ruleAreas, ruleAreas.isDisjoint(with: env.areas) { continue }
            let root = env.home.appending(path: rule.path)
            guard fm.fileExists(atPath: root.path) else { continue }

            let targets = rule.eachChild
                ? ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
                : [root]

            for target in targets {
                try ctx.checkpoint(nil)
                let name = target.lastPathComponent
                let lower = name.lowercased()
                if name == ".DS_Store" { continue }
                // Sistem önbelleklerine ve kendimize dokunmayız.
                if rule.eachChild, lower.hasPrefix("com.apple.") || lower == env.ownBundleID.lowercased() { continue }

                var category = rule.category
                var risk = rule.risk
                var note = rule.note
                var areas: Set<UsageArea>? = nil
                // Geliştirici değilse paket yöneticisi önbellekleri sıradan uygulama önbelleği sayılır.
                if rule.path == "Library/Caches", Self.devCacheNames.contains(lower), env.areas.contains(.development) {
                    category = .devCaches
                }
                if rule.path == ".cache", Self.modelCacheNames.contains(lower) {
                    risk = .review
                    note = "Yapay zekâ modelleri — silersen yeniden indirilir"
                    areas = [.development, .aiCoding]
                }
                if let required = areas ?? category.area.map({ [$0] }), required.isDisjoint(with: env.areas) { continue }

                ctx.setFolder(target)
                let bytes = try measure(target, ctx)
                ctx.addSize(rule.path, bytes)
                let isInfo = rule.risk == .info
                let threshold = rule.category == .appData ? limits.appDataBytes : isInfo ? 1 : limits.minItemBytes
                guard bytes >= threshold else { continue }
                let inUse: String? = switch category {
                case .caches, .devCaches: runningOwner(ofCache: lower)
                case .mediaCaches: Self.mediaCacheOwner(of: target.path, runningApps: env.runningApps)
                default: nil
                }

                if let f = makeFinding(target, category, risk, bytes: bytes, note: note, inUseBy: inUse,
                                       areas: areas, ctx: ctx) {
                    out.append(f)
                }
            }
        }
        return out
    }

    /// Önbellek klasörü açık bir uygulamaya mı ait? (klasör adı bundle ID ya da bilinen bir ad)
    func runningOwner(ofCache lowercasedName: String) -> String? {
        env.runningApps[Self.cacheOwners[lowercasedName] ?? lowercasedName]
    }

    /// Medya önbelleğini kullanan uygulama şu an açık mı? (Final Cut Pro, Lightroom, Adobe, DaVinci)
    /// Hem taramada hem de silmeden hemen önce (Cleaner) sorulur.
    static func mediaCacheOwner(of path: String, runningApps: [String: String]) -> String? {
        let lower = path.lowercased()
        let owners: [String]
        if lower.contains(".fcpbundle/") {
            owners = ["com.apple.finalcut"]
        } else if lower.hasSuffix(".lrdata") {
            owners = ["lightroom"]
        } else if lower.contains("/adobe/common/media cache") {
            owners = ["com.adobe.premiere", "com.adobe.aftereffects", "com.adobe.ame", "com.adobe.audition"]
        } else if lower.contains("/movies/cacheclip") {
            owners = ["davinciresolve"]
        } else {
            return nil
        }
        return runningApps.first { app in owners.contains { app.key.contains($0) } }?.value
    }
}
