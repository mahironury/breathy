import Foundation

struct DuplicateCandidate: Sendable {
    let url: URL
    /// Mantıksal boyut (içerik karşılaştırması için).
    let size: Int64
    /// Diskte ayrılan alan.
    let allocated: Int64
    /// Sert bağlantılar aynı kimliği paylaşır; onlar çift değildir.
    let fileID: UInt64?
    let created: Date?
}

/// Üç aşamalı çift bulma: aynı boyut → aynı kısmi parmak izi → aynı tam SHA-256.
/// Tam okuma sadece ilk iki aşamayı geçen az sayıda dosyaya yapılır.
enum DuplicateFinder {
    static func groups(_ candidates: [DuplicateCandidate], ctx: ScanContext) throws -> [[DuplicateCandidate]] {
        var bySize: [Int64: [DuplicateCandidate]] = [:]
        for candidate in candidates where candidate.size > 0 {
            bySize[candidate.size, default: []].append(candidate)
        }

        let hasher = FileHasher()
        var result: [[DuplicateCandidate]] = []

        for (size, sameSize) in bySize where sameSize.count > 1 {
            var seenIDs = Set<UInt64>()
            let unique = sameSize.filter { c in c.fileID.map { seenIDs.insert($0).inserted } ?? true }
            guard unique.count > 1 else { continue }

            var byPartial: [Data: [DuplicateCandidate]] = [:]
            for c in unique {
                try ctx.checkpoint(c.url)
                guard FileHasher.isSafeToRead(c.url), let hash = hasher.partial(c.url, size: size) else { continue }
                byPartial[hash, default: []].append(c)
            }

            for samePartial in byPartial.values where samePartial.count > 1 {
                if size <= Int64(FileHasher.partialSpan * 2) {  // kısmi iz zaten bütün dosya
                    result.append(samePartial)
                    continue
                }
                var byFull: [Data: [DuplicateCandidate]] = [:]
                for c in samePartial {
                    if let hash = try hasher.full(c.url, ctx: ctx) { byFull[hash, default: []].append(c) }
                }
                result += byFull.values.filter { $0.count > 1 }
            }
        }

        // Deterministik sıra: büyük gruplar önce.
        return result
            .map { $0.sorted { $0.url.path < $1.url.path } }
            .sorted { ($0[0].size, $0[0].url.path) > ($1[0].size, $1[0].url.path) }
    }

    // MARK: - Hangi kopya kalsın? (konuma göre)

    /// Korunacak kopyanın sırası. Öncelik: Belgeler/proje/medya klasörü > Masaüstü > İndirilenler;
    /// sonra adı "kopya" gibi olmayan; sonra en eski; sonra en kısa yol.
    static func keeperIndex(of group: [DuplicateCandidate], home: URL) -> Int {
        var best = 0
        for i in group.indices.dropFirst() where isBetter(group[i], than: group[best], home: home) {
            best = i
        }
        return best
    }

    static func isBetter(_ a: DuplicateCandidate, than b: DuplicateCandidate, home: URL) -> Bool {
        let (ra, rb) = (locationRank(a.url, home: home), locationRank(b.url, home: home))
        if ra != rb { return ra > rb }
        let (ca, cb) = (looksLikeCopy(a.url), looksLikeCopy(b.url))
        if ca != cb { return !ca }
        if let x = a.created, let y = b.created, x != y { return x < y }
        return a.url.path.count < b.url.path.count
    }

    /// 0: İndirilenler / geçici, 1: Masaüstü, 2: diğer her yer (Belgeler, projeler, Resimler, Filmler…)
    static func locationRank(_ url: URL, home: URL) -> Int {
        let path = url.path
        let homePath = home.path
        if path.hasPrefix(homePath + "/Downloads/") { return 0 }
        let lower = path.lowercased()
        if lower.contains("/tmp/") || lower.contains("/temp/") { return 0 }
        if path.hasPrefix(homePath + "/Desktop/") { return 1 }
        return 2
    }

    /// "rapor kopya.pdf", "rapor copy 2.pdf", "rapor (1).pdf" gibi adlar.
    static func looksLikeCopy(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        guard let pattern = try? Regex(#"(\s(copy|kopya|kopyası)(\s\d+)?|\s\(\d+\))$"#) else { return false }
        return stem.firstMatch(of: pattern) != nil
    }
}

extension Scanner {
    /// Kopyası silinmeye önerilebilecek kişisel klasörler.
    static let personalFolders = ["Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music"]
    /// Bir klasörün yazılım projesi olduğunu gösteren dosyalar. Proje içindeki aynı dosyalar
    /// (ör. bir eklentinin iki yerde kullandığı resim) bilinçlidir; silmek projeyi bozar.
    static let projectMarkers = [
        ".git", "package.json", "composer.json", "wp-config.php", "Cargo.toml", "pyproject.toml",
        "setup.py", "Gemfile", "go.mod", "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts",
    ]

    func duplicateFindings(_ candidates: [DuplicateCandidate], _ ctx: ScanContext) throws -> [Finding] {
        let groups = try DuplicateFinder.groups(candidates, ctx: ctx)
        let personal = Self.personalFolders.map { homePath($0) + "/" }
        var projectCache: [String: Bool] = [:]

        /// Ev klasörüne kadar üst klasörlerden biri proje mi?
        func isInsideProject(_ url: URL) -> Bool {
            var dir = url.deletingLastPathComponent()
            var visited: [String] = []
            while dir.path.count > env.home.path.count, dir.path.hasPrefix(env.home.path) {
                if let cached = projectCache[dir.path] {
                    for v in visited { projectCache[v] = cached }
                    return cached
                }
                visited.append(dir.path)
                if Self.projectMarkers.contains(where: { FileManager.default.fileExists(atPath: dir.appending(path: $0).path) }) {
                    for v in visited { projectCache[v] = true }
                    return true
                }
                dir = dir.deletingLastPathComponent()
            }
            for v in visited { projectCache[v] = false }
            return false
        }

        func isRemovable(_ copy: DuplicateCandidate) -> Bool {
            personal.contains { copy.url.path.hasPrefix($0) } && !isInsideProject(copy.url)
        }

        var out: [Finding] = []
        for (index, group) in groups.enumerated() {
            let groupID = "cift-\(index)"
            let keep = DuplicateFinder.keeperIndex(of: group, home: env.home)
            let kept = group[keep]
            let keptLabel = "\(kept.url.deletingLastPathComponent().lastPathComponent)/\(kept.url.lastPathComponent)"
            // Silinmeye aday kopya yoksa grubu hiç gösterme.
            let removable = group.indices.filter { $0 != keep && isRemovable(group[$0]) }
            guard !removable.isEmpty else { continue }

            for (i, copy) in group.enumerated() {
                if i == keep {
                    if let f = makeFinding(copy.url, .duplicates, .review, bytes: copy.allocated, suggested: false,
                                           note: "Korunacak kopya", groupID: groupID, ctx: ctx) {
                        out.append(f)
                    }
                    continue
                }
                guard removable.contains(i) else { continue }  // proje içi / kişisel olmayan kopyalara dokunma
                // APFS klonuysa silmek sadece özel blokları açar.
                let freed = FileHasher.privateSize(copy.url.path).map { min($0, copy.allocated) } ?? copy.allocated
                var note = "Aynısı: \(keptLabel)"
                if freed < copy.allocated / 2 {
                    note += " · APFS klonu, silince sadece \(ByteFormat.string(freed)) açılır"
                }
                if let f = makeFinding(copy.url, .duplicates, .review, bytes: freed,
                                       note: note, groupID: groupID, ctx: ctx) {
                    out.append(f)
                }
            }
        }
        return out
    }
}
