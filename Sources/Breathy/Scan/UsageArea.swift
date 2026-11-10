import Foundation

/// Kullanıcının Mac'i ne için kullandığı. Seçilen alanların kuralları çalışır, diğerleri hiç ölçülmeden
/// atlanır (tarama hızlanır, sonuçlar odaklanır). Herkesi ilgilendiren yerler (önbellekler, kurulum
/// dosyaları, büyük ve çift dosyalar, gizli klasörler, iCloud) her zaman taranır.
enum UsageArea: String, Codable, CaseIterable, Sendable, Identifiable {
    case development, aiCoding, media, gaming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .development: "Yazılım geliştirme"
        case .aiCoding: "Yapay zekâ kodlama araçları"
        case .media: "Fotoğraf, video ve tasarım"
        case .gaming: "Oyun"
        }
    }

    var shortTitle: String {
        switch self {
        case .development: "Yazılım"
        case .aiCoding: "Yapay zekâ araçları"
        case .media: "Foto/video"
        case .gaming: "Oyun"
        }
    }

    /// Breathy bu alanda nelere bakar (kullanıcıya gösterilir).
    var details: String {
        switch self {
        case .development: "Eski projelerin node_modules ve derleme çıktıları, paket önbellekleri, Xcode ve simülatörler, Docker"
        case .aiCoding: "Antigravity, Cursor, VS Code önbellekleri ve eski ekran kayıtları. Sohbet geçmişine dokunulmaz."
        case .media: "Lightroom önizlemeleri, Final Cut Pro render dosyaları, Adobe ve DaVinci medya önbellekleri"
        case .gaming: "Steam önbellekleri ve kurulu oyunların kapladığı yer. Oyun kayıtlarına dokunulmaz."
        }
    }

    var icon: String {
        switch self {
        case .development: "chevron.left.forwardslash.chevron.right"
        case .aiCoding: "sparkles"
        case .media: "camera.aperture"
        case .gaming: "gamecontroller"
        }
    }
}

extension ScanCategory {
    /// Bu kategori hangi kullanım alanına ait? nil: herkes için, her zaman taranır.
    /// (Geliştirici araçları ve oyunlar uygulama bilgi tablosundaki alanlara göre süzülür.)
    var area: UsageArea? {
        switch self {
        case .nodeModules, .buildOutputs, .pythonEnvs, .devCaches, .xcode, .docker: .development
        case .mediaCaches: .media
        case .games: .gaming
        default: nil
        }
    }
}

/// Seçimin kaydı. Hiç seçilmediyse bütün alanlar taranır.
enum UsageProfile {
    private static let areasKey = "usageAreas"
    private static let askedKey = "usageAreasAsked"

    static func load(_ defaults: UserDefaults = .standard) -> Set<UsageArea> {
        guard let raw = defaults.stringArray(forKey: areasKey) else { return Set(UsageArea.allCases) }
        return Set(raw.compactMap(UsageArea.init(rawValue:)))
    }

    static func save(_ areas: Set<UsageArea>, _ defaults: UserDefaults = .standard) {
        defaults.set(areas.map(\.rawValue).sorted(), forKey: areasKey)
        defaults.set(true, forKey: askedKey)
    }

    /// İlk açılış ekranı gösterildi mi (kaydedildi ya da atlandı)?
    static func wasAsked(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: askedKey)
    }

    static func markAsked(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: askedKey)
    }
}

extension Scanner {
    /// Bulgu bu kullanım alanlarıyla taransaydı çıkar mıydı? (Seçim değişince eski sonuçları süzmek için.)
    static func isAllowed(_ finding: Finding, in areas: Set<UsageArea>, home: String) -> Bool {
        if finding.category == .devCaches, isModelCache(finding.path) {
            return !areas.isDisjoint(with: [.development, .aiCoding])
        }
        if let area = finding.category.area, !areas.contains(area) { return false }
        if [.devTools, .games].contains(finding.category), finding.path.hasPrefix(home + "/"),
           let known = knownApp(containing: String(finding.path.dropFirst(home.count + 1))) {
            return !known.tool.areas.isDisjoint(with: areas)
        }
        return true
    }

    /// ~/.cache altındaki yapay zekâ modeli mi (huggingface, ollama…)?
    static func isModelCache(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard let i = parts.lastIndex(of: ".cache"), i + 1 < parts.count else { return false }
        return modelCacheNames.contains(parts[i + 1].lowercased())
    }
}
