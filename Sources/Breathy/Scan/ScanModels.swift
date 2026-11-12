import Foundation

/// Bir bulgunun nasıl temizleneceği.
enum Risk: String, Codable, Sendable {
    /// Kendiliğinden yeniden oluşur → doğrudan silinir. 🟢
    case safe
    /// Kullanıcı dosyası → Çöp'e taşınır, geri alınabilir. 🟡
    case review
    /// Sadece bilgi; Breathy silmez. 🔴
    case info
}

enum ScanCategory: String, Codable, Sendable, CaseIterable {
    case caches, logs, devCaches, nodeModules, buildOutputs, pythonEnvs, xcode, mediaCaches
    case oldInstallers, largeFiles, unusedApps, appLeftovers
    case screenCaptures, duplicates
    case appData, iosBackups, docker, photosLibrary, iCloudArchive
    case hiddenFolders, devTools, games

    var title: String {
        switch self {
        case .screenCaptures: "Ekran görüntüleri ve kayıtları"
        case .duplicates: "Çift dosyalar"
        case .iCloudArchive: "iCloud Drive yerel arşivi"
        case .caches: "Uygulama önbellekleri"
        case .logs: "Loglar ve çökme raporları"
        case .devCaches: "Paket yöneticisi önbellekleri"
        case .nodeModules: "Eski projelerde node_modules"
        case .buildOutputs: "Eski derleme çıktıları"
        case .pythonEnvs: "Eski Python ortamları"
        case .xcode: "Xcode ve simülatör artıkları"
        case .mediaCaches: "Medya önbellekleri"
        case .oldInstallers: "Eski kurulum dosyaları"
        case .largeFiles: "Büyük dosyalar"
        case .unusedApps: "Kullanılmayan uygulamalar"
        case .appLeftovers: "Kaldırılmış uygulama artıkları"
        case .appData: "Büyük uygulama verileri"
        case .iosBackups: "iPhone/iPad yedekleri"
        case .docker: "Docker disk görüntüsü"
        case .photosLibrary: "Fotoğraflar kütüphanesi"
        case .hiddenFolders: "Büyük gizli klasörler"
        case .devTools: "Geliştirici araçlarının kayıtları"
        case .games: "Oyunlar ve oyun önbellekleri"
        }
    }

    /// Bilgi satırında kullanılan kısa ad.
    var shortTitle: String {
        switch self {
        case .appData: "Uygulama verileri"
        case .iosBackups: "iPhone yedekleri"
        case .docker: "Docker"
        case .photosLibrary: "Fotoğraflar"
        case .iCloudArchive: "iCloud arşivi"
        case .hiddenFolders: "Gizli klasörler"
        case .devTools: "Geliştirici araçları"
        case .games: "Oyunlar"
        default: title
        }
    }

    var icon: String {
        switch self {
        case .screenCaptures: "camera.viewfinder"
        case .duplicates: "doc.on.doc"
        case .iCloudArchive: "icloud.and.arrow.down"
        case .caches: "archivebox"
        case .logs: "doc.text"
        case .devCaches: "shippingbox"
        case .nodeModules: "folder.badge.gearshape"
        case .buildOutputs: "hammer"
        case .pythonEnvs: "chevron.left.forwardslash.chevron.right"
        case .xcode: "hammer.circle"
        case .mediaCaches: "film.stack"
        case .oldInstallers: "opticaldiscdrive"
        case .largeFiles: "scalemass"
        case .unusedApps: "app.dashed"
        case .appLeftovers: "puzzlepiece.extension"
        case .appData: "internaldrive"
        case .iosBackups: "iphone"
        case .docker: "shippingbox.circle"
        case .photosLibrary: "photo.on.rectangle"
        case .hiddenFolders: "questionmark.folder"
        case .devTools: "wrench.and.screwdriver"
        case .games: "gamecontroller"
        }
    }
}

struct Finding: Codable, Sendable, Hashable, Identifiable {
    let path: String
    let category: ScanCategory
    let risk: Risk
    /// Diskte kapladığı gerçek alan.
    let bytes: Int64
    var lastUsed: Date?
    /// Temizlik için otomatik işaretlensin mi?
    var suggested: Bool
    var note: String?
    /// Doluysa: bu önbelleğin sahibi uygulama şu an açık (önce kapatılmalı).
    var inUseBy: String?
    /// Çift dosyalarda aynı içerikteki kopyaları bağlar.
    var groupID: String?
    /// Doluysa kritik veri (şifre, anahtar, kurtarma kodu…) ve nedeni: Breathy silmez.
    var critical: String? = nil

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    /// Toplama dahil edilir mi: önerilmiş, bilgi değil, açık bir uygulamaya ait değil, kritik değil.
    var countsAsCleanable: Bool { suggested && risk != .info && inUseBy == nil && critical == nil }

    mutating func markCritical(_ reason: String) {
        critical = reason
        suggested = false
    }
}

struct CategorySummary: Sendable, Identifiable {
    let category: ScanCategory
    let risk: Risk
    let bytes: Int64
    let cleanableBytes: Int64
    let count: Int
    var id: ScanCategory { category }
}

struct ICloudFolder: Codable, Sendable, Hashable {
    let name: String
    /// iCloud'da kapladığı (mantıksal boyut).
    let bytes: Int64
    /// Bu Mac'e indirilmiş kısmı.
    let localBytes: Int64
}

struct ICloudSummary: Codable, Sendable {
    var status: ICloudStatus
    /// iCloud Drive'ın bu Mac'ten görünen toplamı (mantıksal).
    var driveBytes: Int64 = 0
    var driveLocalBytes: Int64 = 0
    var topFolders: [ICloudFolder] = []
    /// macOS'un ekran görüntülerini kaydettiği klasör.
    var screenshotFolder: String
    var screenshotCount = 0
    var screenshotBytes: Int64 = 0
}

/// İki tarama arasında büyüyen bir klasör.
struct GrowthItem: Codable, Sendable, Hashable, Identifiable {
    /// Ev klasörüne göre yol, örn. "Downloads" ya da "Library/Group Containers/group.net.whatsapp…".
    let key: String
    /// Kullanıcıya gösterilen ad, örn. "İndirilenler", "WhatsApp".
    let title: String
    let bytes: Int64
    let delta: Int64
    var id: String { key }
}

struct ScanResult: Codable, Sendable {
    let date: Date
    let duration: TimeInterval
    let filesVisited: Int
    /// Temizlenenler çıkarılır (sonuç güncel kalsın diye değişkendir).
    var findings: [Finding]
    var iCloud: ICloudSummary?
    /// Klasör boyutları (ev klasörüne göre yol → bayt). Bir sonraki taramada "ne büyüdü?" için.
    /// 0.1 sürümünün kayıtlarında yoktur.
    var folderSizes: [String: Int64]? = nil
    /// Bir önceki taramadan bu yana büyüyenler, büyükten küçüğe.
    var growth: [GrowthItem]? = nil
    /// Karşılaştırılan önceki taramanın tarihi.
    var growthSince: Date? = nil

    /// Bulguları çıkarır; tek kopyası kalan çift grupları da listeden düşer.
    mutating func removeFindings(where shouldRemove: (Finding) -> Bool) {
        findings.removeAll(where: shouldRemove)
        let groupSizes = Dictionary(grouping: findings.compactMap(\.groupID)) { $0 }.mapValues(\.count)
        findings.removeAll { finding in finding.groupID.map { (groupSizes[$0] ?? 0) < 2 } ?? false }
    }

    var cleanableBytes: Int64 {
        findings.reduce(0) { $0 + ($1.countsAsCleanable ? $1.bytes : 0) }
    }

    /// Kritik diye korunan bulgular.
    var criticalFindings: [Finding] { findings.filter { $0.critical != nil } }

    /// Kategorilere göre özet, büyükten küçüğe.
    func summaries() -> [CategorySummary] {
        Dictionary(grouping: findings, by: \.category).map { category, items in
            let risk: Risk = items.allSatisfy { $0.risk == .info } ? .info
                : items.contains { $0.risk == .review } ? .review : .safe
            // Başka bir bulgunun içindeki bulgu toplama iki kez girmesin
            // (ör. "~/.gemini" ve onun içindeki eski "antigravity-backup").
            let paths = Set(items.map(\.path))
            let outermost = items.filter { item in
                var parent = (item.path as NSString).deletingLastPathComponent
                while parent.count > 1 {
                    if paths.contains(parent) { return false }
                    parent = (parent as NSString).deletingLastPathComponent
                }
                return true
            }
            return CategorySummary(
                category: category,
                risk: risk,
                bytes: outermost.reduce(0) { $0 + $1.bytes },
                cleanableBytes: items.reduce(0) { $0 + ($1.countsAsCleanable ? $1.bytes : 0) },
                count: items.count
            )
        }
        .sorted { ($0.cleanableBytes, $0.bytes) > ($1.cleanableBytes, $1.bytes) }
    }
}

struct ScanProgress: Sendable, Equatable {
    var phase = "Hazırlanıyor"
    var filesVisited = 0
    var currentFolder = ""
    var foundBytes: Int64 = 0
}
