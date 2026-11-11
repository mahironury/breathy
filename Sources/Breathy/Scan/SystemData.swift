import Foundation

/// "Sistem Verileri neden bu kadar büyük?" — macOS'un Depolama ayarlarında tek bir kalem olarak
/// gösterdiği alanın Breathy'nin ölçebildiği parçaları. Apple bu sayının içini açıklamıyor; burada
/// son tarama ve anlık değerlerden (takas, macOS'un gerektiğinde sileceği alan) bir döküm çıkarılır.
struct SystemDataRow: Identifiable, Sendable, Equatable {
    let id: String
    let icon: String
    let title: String
    let bytes: Int64
    let note: String
    /// Doluysa "Detaylarda göster" bu kategoriyi açar.
    var category: ScanCategory? = nil
}

enum SystemData {
    static func rows(scan: ScanResult?, swapBytes: Int64?, purgeableBytes: Int64?, localSnapshots: [Date]) -> [SystemDataRow] {
        var rows: [SystemDataRow] = []
        let sizes = scan?.folderSizes ?? [:]
        let findings = scan?.findings ?? []
        /// Kategorideki bulguların toplamı; başka bir bulgunun içindeki bulgu iki kez sayılmaz
        /// (ör. "~/.gemini" ve içindeki "antigravity-ide").
        func total(_ category: ScanCategory, risk: Risk? = nil) -> Int64 {
            let items = findings.filter { $0.category == category && (risk == nil || $0.risk == risk) }
            let paths = Set(items.map(\.path))
            return items.filter { item in
                var parent = (item.path as NSString).deletingLastPathComponent
                while parent.count > 1 {
                    if paths.contains(parent) { return false }
                    parent = (parent as NSString).deletingLastPathComponent
                }
                return true
            }.reduce(0) { $0 + $1.bytes }
        }

        // Uygulama verileri: Application Support, Containers, Group Containers altındaki klasörler.
        let appRoots = ["Library/Application Support/", "Library/Containers/", "Library/Group Containers/"]
        let appFolders = sizes.filter { key, _ in
            appRoots.contains { key.hasPrefix($0) } && key.split(separator: "/").count == 3
        }
        let appTotal = appFolders.values.reduce(0, +)
        if appTotal > 0 {
            let top = appFolders.sorted { $0.value > $1.value }.prefix(3)
                .map { "\(Growth.displayName($0.key)) \(ByteFormat.string($0.value))" }
            rows.append(SystemDataRow(
                id: "apps", icon: "internaldrive", title: "Uygulama verileri", bytes: appTotal,
                note: "En büyükler: \(top.joined(separator: ", ")). Uygulamaların kendi ayarlarından temizlenir.",
                category: .appData))
        }

        let caches = (sizes["Library/Caches"] ?? 0) + (sizes["Library/Logs"] ?? 0)
        if caches > 0 {
            rows.append(SystemDataRow(
                id: "caches", icon: "archivebox", title: "Önbellekler ve loglar", bytes: caches,
                note: "Uygulamalar yeniden oluşturur. Breathy uzun süredir kullanılmayanları önerir.", category: .caches))
        }

        let developer = sizes.filter { $0.key.hasPrefix("Library/Developer/") }.values.reduce(0, +)
        if developer > 0 {
            rows.append(SystemDataRow(
                id: "developer", icon: "hammer.circle", title: "Xcode ve simülatörler", bytes: developer,
                note: "Derleme ara dosyaları, cihaz destek dosyaları ve iOS simülatörleri.", category: .xcode))
        }

        let docker = total(.docker)
        if docker > 0 {
            rows.append(SystemDataRow(
                id: "docker", icon: "shippingbox.circle", title: "Docker disk görüntüsü", bytes: docker,
                note: "İçindeki imaj ve önbellekler Detaylar'daki Docker kartından temizlenir.", category: .docker))
        }

        let hidden = total(.hiddenFolders, risk: .info)
        if hidden > 0 {
            rows.append(SystemDataRow(
                id: "hidden", icon: "questionmark.folder", title: "Gizli klasörler", bytes: hidden,
                note: "Geliştirici ve yapay zekâ araçlarının verisi (~/.gemini, ~/.colima…).", category: .hiddenFolders))
        }

        let backups = total(.iosBackups)
        if backups > 0 {
            rows.append(SystemDataRow(
                id: "backups", icon: "iphone", title: "iPhone ve iPad yedekleri", bytes: backups,
                note: "Finder'da cihazını seçip yedekleri oradan yönet.", category: .iosBackups))
        }

        if let swapBytes, swapBytes > 0 {
            rows.append(SystemDataRow(
                id: "swap", icon: "arrow.triangle.2.circlepath", title: "Takas dosyası", bytes: swapBytes,
                note: "Bellek yetmeyince macOS'un diske yazdığı alan. Mac yeniden başlatılınca küçülür."))
        }

        if let purgeableBytes, purgeableBytes > 0 {
            let snapshots = localSnapshots.isEmpty
                ? "Yerel Time Machine yedeği yok."
                : "\(localSnapshots.count) yerel Time Machine yedeği var."
            rows.append(SystemDataRow(
                id: "purgeable", icon: "clock.arrow.circlepath", title: "macOS'un gerektiğinde sileceği alan",
                bytes: purgeableBytes,
                note: "\(snapshots) iCloud önbelleği ve benzerleri de burada. macOS yer gerektiğinde bunları kendisi siler; Breathy'nin gösterdiği boş alan bunu zaten içeriyor."))
        }
        return rows.sorted { $0.bytes > $1.bytes }
    }

    /// `tmutil listlocalsnapshots /` çıktısındaki tarihler ("com.apple.TimeMachine.2026-11-11-010203.local").
    static func parseSnapshots(_ output: String) -> [Date] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return output.split(separator: "\n").compactMap { line in
            guard let range = line.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else { return nil }
            return formatter.date(from: String(line[range]))
        }
    }

    static func localSnapshots() async -> [Date] {
        let result = await Command.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 15)
        return result.status == 0 ? parseSnapshots(result.output) : []
    }
}
