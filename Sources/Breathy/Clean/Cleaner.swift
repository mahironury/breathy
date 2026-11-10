import Foundation

struct CleanIssue: Sendable, Equatable, Hashable {
    let path: String
    let reason: String
    var name: String { (path as NSString).lastPathComponent }
}

struct CleanReport: Sendable, Equatable {
    var deletedBytes: Int64 = 0
    var trashedBytes: Int64 = 0
    var deleted: [String] = []
    var trashed: [String] = []
    var skipped: [CleanIssue] = []
    var failed: [CleanIssue] = []
    /// Çöp'e taşımak için yönetici izni gerekenler (ör. /Applications'taki uygulamalar).
    var needsAuthorization: [String] = []
    var wasCancelled = false

    var cleanedPaths: Set<String> { Set(deleted + trashed) }
    var issues: [CleanIssue] { skipped + failed }
}

struct CleanProgress: Sendable, Equatable {
    var done = 0
    var total = 0
    var current = ""
}

/// Seçilen bulguları türüne göre temizler:
///   🟢 safe   → doğrudan silinir (kendiliğinden yeniden oluşur)
///   🟡 review → Çöp'e taşınır (geri alınabilir)
///   🔴 info   → asla
/// Her öğe silinmeden hemen önce yeniden denetlenir (PathGuard, açık uygulama, çift grubunda kalan kopya).
struct Cleaner: Sendable {
    let home: URL
    let appDirs: [URL]
    /// Temizlik anında açık uygulamalar: küçük harfli bundle ID → ad.
    let runningApps: [String: String]
    var moveToTrash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    var deletePermanently: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    func clean(_ selected: [Finding], allFindings: [Finding], progress: (CleanProgress) -> Void) -> CleanReport {
        var report = CleanReport()
        let selectedPaths = Set(selected.map(\.path))
        var queue = selected

        // Çift gruplarında en az bir kopya mutlaka kalır.
        let groups = Dictionary(grouping: allFindings.filter { $0.groupID != nil }) { $0.groupID! }
        for members in groups.values where members.allSatisfy({ selectedPaths.contains($0.path) }) {
            let keeper = members.first { !$0.suggested } ?? members[0]
            queue.removeAll { $0.path == keeper.path }
            report.skipped.append(CleanIssue(path: keeper.path, reason: "Bütün kopyalar seçilmişti; bu kopya korundu"))
        }
        let removing = Set(queue.map(\.path))

        var state = CleanProgress(total: queue.count)
        for finding in queue {
            if Task.isCancelled {
                report.wasCancelled = true
                break
            }
            state.current = finding.name
            progress(state)
            defer { state.done += 1 }

            if let reason = refusal(for: finding, groups: groups, removing: removing) {
                report.skipped.append(CleanIssue(path: finding.path, reason: reason))
                continue
            }
            do {
                switch finding.risk {
                case .safe:
                    try deletePermanently(finding.url)
                    report.deleted.append(finding.path)
                    report.deletedBytes += finding.bytes
                case .review:
                    try moveToTrash(finding.url)
                    report.trashed.append(finding.path)
                    report.trashedBytes += finding.bytes
                case .info:
                    continue
                }
            } catch {
                if finding.risk == .review, Self.isPermissionError(error) {
                    report.needsAuthorization.append(finding.path)
                } else {
                    report.failed.append(CleanIssue(path: finding.path, reason: Self.describe(error)))
                }
            }
        }
        state.current = ""
        progress(state)
        return report
    }

    /// Silmeye engel bir durum varsa nedenini döndürür.
    func refusal(for finding: Finding, groups: [String: [Finding]], removing: Set<String>) -> String? {
        let fm = FileManager.default
        if finding.risk == .info { return "Sadece bilgi; Breathy bunu silmez" }
        guard (try? fm.attributesOfItem(atPath: finding.path)) != nil else { return "Zaten yok" }
        guard PathGuard.canDelete(finding.url, home: home, appDirs: appDirs) else { return "Korunan konum" }
        if let owner = currentOwner(of: finding) { return "\(owner) açık — önce kapat" }
        if let groupID = finding.groupID {
            let survivors = (groups[groupID] ?? []).filter {
                !removing.contains($0.path) && fm.fileExists(atPath: $0.path)
            }
            if survivors.isEmpty { return "Korunacak kopya bulunamadı" }
        }
        return nil
    }

    /// Bu öğenin sahibi uygulama şu an açık mı? (tarama sonrası açılmış olabilir)
    func currentOwner(of finding: Finding) -> String? {
        switch finding.category {
        case .caches, .devCaches:
            let name = finding.name.lowercased()
            return runningApps[Scanner.cacheOwners[name] ?? name]
        case .unusedApps:
            guard let id = Bundle(url: finding.url)?.bundleIdentifier?.lowercased() else { return nil }
            return runningApps[id]
        case .mediaCaches:
            return Scanner.mediaCacheOwner(of: finding.path, runningApps: runningApps)
        case .hiddenFolders:
            return Scanner.hiddenFolderOwner(of: finding.path, home: home.path, runningApps: runningApps)
        default:
            return finding.inUseBy
        }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteNoPermissionError { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, [EACCES, EPERM].contains(Int32(underlying.code)) { return true }
        return ns.domain == NSPOSIXErrorDomain && [EACCES, EPERM].contains(Int32(ns.code))
    }

    static func describe(_ error: Error) -> String {
        if isPermissionError(error) { return "İzin yok" }
        return (error as NSError).localizedDescription
    }
}
