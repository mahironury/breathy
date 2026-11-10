import Darwin
import Foundation

/// Ev klasörü taramasının çıktısı.
struct WalkOutput {
    var findings: [Finding] = []
    /// Çift dosya aramasına girecek dosyalar.
    var duplicateCandidates: [DuplicateCandidate] = []
}

/// Ev klasörünün tek geçişte taranması: eski projelerin node_modules / derleme çıktıları / Python
/// ortamları, ekran görüntüleri, eski kurulum dosyaları, büyük dosyalar, Fotoğraflar kütüphaneleri
/// ve çift dosya adayları.
extension Scanner {
    static let walkKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .fileIdentifierKey,
    ]

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "ipsw"]
    static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]
    /// İçi tek tek taranmayan ama büyük olabilen paketler (iMovie, Logic, GarageBand).
    /// Final Cut Pro kütüphaneleri (.fcpbundle) ayrıca ele alınır: render dosyaları ayrı bulgu olur.
    static let heavyPackageExtensions: Set<String> = ["imovielibrary", "logicx", "band"]

    /// macOS'un Türkçe ve İngilizce ekran görüntüsü/kaydı adları.
    static let screenshotPrefixes = [
        "ekran resmi ", "ekran görüntüsü ", "ekran kaydı ", "screenshot ", "screen shot ", "screen recording ",
    ]
    static let screenshotExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "mov", "mp4"]

    /// Derleme çıktısı klasörü → yanında bulunması gereken işaret dosyaları.
    /// İşaret yoksa klasör sıradan sayılır (ör. kişisel bir "build" klasörü).
    static let buildOutputMarkers: [String: [String]] = [
        ".next": ["package.json"], ".nuxt": ["package.json"], ".turbo": ["package.json"],
        ".parcel-cache": ["package.json"], ".svelte-kit": ["package.json"], ".angular": ["package.json"],
        "dist": ["package.json"],
        "build": ["package.json", "build.gradle", "build.gradle.kts"],
        "target": ["Cargo.toml", "pom.xml"],
        ".build": ["Package.swift"],
    ]
    static let venvNames: Set<String> = [".venv", "venv", "env"]

    /// Bir klasörün "geliştirme projesi" olduğunun kanıtı: paket yöneticisi kilit dosyaları.
    /// Yayınlanmış paketlerde (ör. IDE eklentileri) bunlar olmaz; bu yüzden `dist`/`node_modules`
    /// yanında `package.json` olması tek başına yetmez.
    static let lockfiles: [String] = [
        "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock",
        "Cargo.lock", "Package.resolved", "poetry.lock", "Pipfile.lock", "composer.lock", "Gemfile.lock", "go.sum",
    ]

    /// Arşivlerden sadece kurulum dosyası gibi görünenler otomatik işaretlenir.
    static func looksLikeInstallerArchive(_ name: String) -> Bool {
        let lower = name.lowercased()
        return [".app.", "macos", "-mac", "_mac", " mac", "installer", "setup", "darwin"].contains { lower.contains($0) }
    }
    /// Proje "eski mi?" kararında dikkate alınmayan, üretilmiş içerik.
    static let generatedNames: Set<String> = Set(buildOutputMarkers.keys)
        .union(venvNames).union(["node_modules", ".DS_Store", ".git"])

    func walkHome(_ ctx: ScanContext) throws -> WalkOutput {
        let fm = FileManager.default
        let skip = walkSkipPaths
        let keySet = Set(Self.walkKeys)
        let downloads = homePath("Downloads") + "/"
        let desktop = homePath("Desktop") + "/"
        let homePrefix = env.home.path + "/"

        /// "Ne büyüdü?" için: dosyanın boyutunu ev klasörünün ilk iki seviyesine ekler
        /// ("Documents" ve "Documents/Proje"). Klasör ölçümlerinde yolun sonuna "/" konur.
        func tally(_ path: String, _ bytes: Int64, modified: Date? = nil) {
            guard path.hasPrefix(homePrefix) else { return }
            let rel = path.dropFirst(homePrefix.count)
            guard let first = rel.firstIndex(of: "/") else { return }  // doğrudan ev klasöründeki dosya
            let top = String(rel[..<first])
            ctx.addSize(top, bytes)
            // Gizli klasörlerde en son ne zaman bir şey değişti? ("aylardır dokunulmamış kopya" için)
            let hidden = rel.first == "."
            if hidden, let modified { ctx.noteChange(top, modified) }
            if let second = rel[rel.index(after: first)...].firstIndex(of: "/") {
                let sub = String(rel[..<second])
                ctx.addSize(sub, bytes)
                if hidden, let modified { ctx.noteChange(sub, modified) }
            }
        }
        var staleCache: [String: Bool] = [:]
        var out = WalkOutput()
        var large: [(url: URL, bytes: Int64, modified: Date?)] = []
        /// İçinde bulunduğumuz git depolarının derinlikleri (depo içindeki dosyalar çift sayılmaz).
        var repoLevels: [Int] = []
        /// İçinde bulunduğumuz gizli (nokta ile başlayan) klasörlerin derinlikleri. Bunlar uygulama
        /// verisidir (~/.gemini, ~/.vscode…): içindeki dosyalar çift sayılmaz, büyükse sadece bilgi.
        var hiddenLevels: [Int] = []

        /// Eski VE gerçekten bir geliştirme projesi (kilit dosyası ya da git deposu var) mı?
        func isStaleDevProject(_ project: URL) -> Bool {
            if let cached = staleCache[project.path] { return cached }
            let isDev = !repoLevels.isEmpty
                || fm.fileExists(atPath: project.appending(path: ".git").path)
                || Self.lockfiles.contains { fm.fileExists(atPath: project.appending(path: $0).path) }
            let value = isDev && isStaleProject(project)
            staleCache[project.path] = value
            return value
        }

        guard let e = fm.enumerator(
            at: env.home, includingPropertiesForKeys: Self.walkKeys,
            options: [.skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return out }

        while let url = e.nextObject() as? URL {
            try ctx.visit(url)
            let level = e.level
            while let top = repoLevels.last, level <= top { repoLevels.removeLast() }
            while let top = hiddenLevels.last, level <= top { hiddenLevels.removeLast() }

            guard let v = try? url.resourceValues(forKeys: keySet), v.isSymbolicLink != true else { continue }
            let name = url.lastPathComponent

            // MARK: Klasörler
            if v.isDirectory == true {
                if skip.contains(url.path) || name == ".git" || !PathGuard.isWalkable(url, home: env.home) {
                    e.skipDescendants()
                    continue
                }
                let parent = url.deletingLastPathComponent()
                // IDE eklentileri (~/.vscode/extensions, ~/.cursor/extensions, ~/.antigravity/extensions…):
                // içleri yayınlanmış paketlerdir; `dist`/`node_modules` silmek eklentiyi bozar.
                if name == "extensions", parent.lastPathComponent.hasPrefix(".") {
                    e.skipDescendants()
                    continue
                }

                let ext = url.pathExtension.lowercased()
                // Final Cut Pro kütüphanesi: render ve dönüştürülmüş medya yeniden oluşturulabilir.
                // (Final Cut kurulu değilse macOS bunu paket saymaz; o yüzden uzantıya bakılır.)
                if ext == "fcpbundle" {
                    e.skipDescendants()
                    let caches = try finalCutCaches(in: url, ctx)
                    out.findings += caches
                    let total = try measure(url, ctx)
                    tally(url.path + "/", total)
                    let rest = total - caches.reduce(0) { $0 + $1.bytes }  // iki kez sayma
                    if rest >= limits.largeFileBytes { large.append((url, rest, v.contentModificationDate)) }
                    continue
                }
                // Lightroom Classic önizlemeleri (katalogun yanındaki .lrdata paketleri).
                if ext == "lrdata" {
                    e.skipDescendants()
                    let bytes = try measure(url, ctx)
                    tally(url.path + "/", bytes)
                    if let f = lightroomPreviews(url, name: name, bytes: bytes, ctx) { out.findings.append(f) }
                    continue
                }

                if v.isPackage == true {  // içine zaten girilmiyor
                    if ext == "photoslibrary" {
                        let bytes = try measure(url, ctx)
                        tally(url.path + "/", bytes)
                        if bytes > 0, let f = makeFinding(url, .photosLibrary, .info, bytes: bytes,
                                                          note: "Fotoğraflar → Çiftler albümünden temizleyebilirsin", ctx: ctx) {
                            out.findings.append(f)
                        }
                    } else if Self.heavyPackageExtensions.contains(ext) {
                        let bytes = try measure(url, ctx)
                        tally(url.path + "/", bytes)
                        if bytes >= limits.largeFileBytes { large.append((url, bytes, v.contentModificationDate)) }
                    }
                    continue
                }

                if name == "node_modules" {
                    e.skipDescendants()
                    if isStaleDevProject(parent) {
                        let bytes = try measure(url, ctx)
                        tally(url.path + "/", bytes)
                        if bytes >= limits.minItemBytes,
                           let f = makeFinding(url, .nodeModules, .safe, bytes: bytes,
                                               note: "Projede 'npm install' ile geri gelir", ctx: ctx) {
                            out.findings.append(f)
                        }
                    }
                    continue
                }

                if let markers = Self.buildOutputMarkers[name],
                   markers.contains(where: { fm.fileExists(atPath: parent.appending(path: $0).path) }) {
                    e.skipDescendants()  // derleme çıktısının içindeki dosyaları büyük dosya diye sayma
                    if isStaleDevProject(parent) {
                        let bytes = try measure(url, ctx)
                        tally(url.path + "/", bytes)
                        if bytes >= limits.minItemBytes,
                           let f = makeFinding(url, .buildOutputs, .review, bytes: bytes,
                                               note: "Proje yeniden derlenince oluşur", ctx: ctx) {
                            out.findings.append(f)
                        }
                    }
                    continue
                }

                if Self.venvNames.contains(name), fm.fileExists(atPath: url.appending(path: "pyvenv.cfg").path) {
                    e.skipDescendants()
                    if isStaleProject(parent) {  // pyvenv.cfg zaten bunun bir geliştirme ortamı olduğunu gösterir
                        let bytes = try measure(url, ctx)
                        tally(url.path + "/", bytes)
                        if bytes >= limits.minItemBytes,
                           let f = makeFinding(url, .pythonEnvs, .review, bytes: bytes,
                                               note: "'pip install -r requirements.txt' ile yeniden kurulur", ctx: ctx) {
                            out.findings.append(f)
                        }
                    }
                    continue
                }

                if fm.fileExists(atPath: url.appending(path: ".git").path) { repoLevels.append(level) }
                if name.hasPrefix(".") { hiddenLevels.append(level) }
                continue
            }
            let inHiddenFolder = !hiddenLevels.isEmpty

            // MARK: Dosyalar
            let bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            guard bytes > 0 else { continue }  // sadece iCloud'da duran dosyalar Mac'te yer kaplamaz
            let path = url.path
            tally(path, bytes, modified: v.contentModificationDate)
            let ext = url.pathExtension.lowercased()
            let modified = v.contentModificationDate

            if isScreenCapture(url, name: name, ext: ext) {
                let old = modified.map { daysSince($0) >= limits.screenshotDays } ?? false
                if let f = makeFinding(url, .screenCaptures, .review, bytes: bytes, suggested: old,
                                       lastUsed: modified, ctx: ctx) {
                    out.findings.append(f)
                }
                continue
            }

            let inDownloads = path.hasPrefix(downloads)
            let isInstaller = Self.installerExtensions.contains(ext) && (inDownloads || path.hasPrefix(desktop))
            let isArchive = Self.archiveExtensions.contains(ext) && inDownloads
            if isInstaller || isArchive, let modified, daysSince(modified) >= limits.installerDays {
                // Arşivlerin içinde kişisel dosyalar olabilir: sadece kurulum dosyasına benzeyenler işaretlenir.
                let installerLike = isInstaller || Self.looksLikeInstallerArchive(name)
                if let f = makeFinding(url, .oldInstallers, .review, bytes: bytes, suggested: installerLike,
                                       lastUsed: modified,
                                       note: installerLike ? "Kurulumdan sonra genelde gereksizdir"
                                                           : "Arşiv — içinde önemli dosyalar olabilir, açıp kontrol et",
                                       ctx: ctx) {
                    out.findings.append(f)
                }
                continue
            }

            // Gizli klasördeki büyük dosya bir uygulamanın verisidir (ör. sanal makine diski); ayrıca
            // gösterilmez, "Büyük gizli klasörler" kategorisinde klasörüyle birlikte görünür.
            if bytes >= limits.largeFileBytes, !inHiddenFolder {
                large.append((url, bytes, modified))
            }
            if bytes >= limits.duplicateMinBytes, repoLevels.isEmpty, !inHiddenFolder {
                out.duplicateCandidates.append(DuplicateCandidate(
                    url: url, size: Int64(v.fileSize ?? 0), allocated: bytes,
                    fileID: v.fileIdentifier, created: v.creationDate
                ))
            }
        }

        // Büyük dosyalar: son kullanım tarihi Spotlight'tan; yoksa değiştirilme tarihi.
        try ctx.phase("Son kullanım tarihleri")
        for item in large {
            try ctx.checkpoint(item.url)
            let used = [env.lastUsed(item.url), item.modified].compactMap { $0 }.max()
            let unused = used.map { daysSince($0) >= limits.unusedDays } ?? false
            if let f = makeFinding(item.url, .largeFiles, .review, bytes: item.bytes,
                                   suggested: unused, lastUsed: used, ctx: ctx) {
                out.findings.append(f)
            }
        }
        return out
    }

    /// Final Cut Pro kütüphanesindeki her etkinliğin render dosyaları (doğrudan silinir, gerektiğinde
    /// yeniden oluşur) ve optimize/proxy medyası (Çöp'e gider, işaretlenmez: yeniden oluşturmak uzun sürer).
    func finalCutCaches(in library: URL, _ ctx: ScanContext) throws -> [Finding] {
        let fm = FileManager.default
        let targets: [(rel: String, risk: Risk, suggested: Bool, note: String)] = [
            ("Render Files", .safe, true, "Final Cut Pro render dosyaları — gerektiğinde yeniden oluşturulur"),
            ("Transcoded Media/Optimized Media", .review, false, "Final Cut optimize medya — yeniden oluşturmak uzun sürer"),
            ("Transcoded Media/Proxy Media", .review, false, "Final Cut proxy medya — yeniden oluşturmak uzun sürer"),
        ]
        var out: [Finding] = []
        for event in (try? fm.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? [] {
            for target in targets {
                let dir = event.appending(path: target.rel)
                guard fm.fileExists(atPath: dir.path) else { continue }
                try ctx.checkpoint(dir)
                let bytes = try measure(dir, ctx)
                guard bytes >= limits.minItemBytes,
                      let f = makeFinding(dir, .mediaCaches, target.risk, bytes: bytes, suggested: target.suggested,
                                          note: target.note,
                                          inUseBy: Self.mediaCacheOwner(of: dir.path, runningApps: env.runningApps),
                                          ctx: ctx) else { continue }
                out.append(f)
            }
        }
        return out
    }

    /// Lightroom Classic: "… Previews.lrdata" yeniden oluşturulur (doğrudan silinir);
    /// "… Smart Previews.lrdata" orijinaller bağlı değilken düzenleme için gerekir (Çöp'e, işaretlenmez).
    func lightroomPreviews(_ url: URL, name: String, bytes: Int64, _ ctx: ScanContext) -> Finding? {
        guard bytes >= limits.minItemBytes else { return nil }
        let owner = Self.mediaCacheOwner(of: url.path, runningApps: env.runningApps)
        if name.hasSuffix("Smart Previews.lrdata") {
            return makeFinding(url, .mediaCaches, .review, bytes: bytes, suggested: false,
                               note: "Lightroom akıllı önizlemeleri — orijinaller bağlı değilken düzenlemek için gerekir",
                               inUseBy: owner, ctx: ctx)
        }
        if name.hasSuffix("Previews.lrdata") {
            return makeFinding(url, .mediaCaches, .safe, bytes: bytes,
                               note: "Lightroom önizlemeleri — Lightroom gerektiğinde yeniden oluşturur",
                               inUseBy: owner, ctx: ctx)
        }
        return nil
    }

    /// Ada bakar; ad tutmazsa macOS'un ekran görüntülerine koyduğu etiketi (xattr) kontrol eder.
    func isScreenCapture(_ url: URL, name: String, ext: String) -> Bool {
        guard Self.screenshotExtensions.contains(ext) else { return false }
        let lower = name.lowercased()
        if Self.screenshotPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        return getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, XATTR_NOFOLLOW) > 0
    }

    /// Proje uzun süredir dokunulmamış mı? Git etkinliğine ve kaynak dosyaların tarihlerine bakar;
    /// yakın tarihli tek bir dosya bulunca hemen "aktif" der. Emin olamazsa "aktif" kabul eder.
    func isStaleProject(_ dir: URL) -> Bool {
        let threshold = env.now.addingTimeInterval(-limits.staleProjectDays * 86_400)
        let fm = FileManager.default

        func modified(_ url: URL) -> Date? {
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        // index/HEAD/FETCH_HEAD her git işleminde (status, commit, pull) güncellenir.
        for rel in [".git/index", ".git/HEAD", ".git/FETCH_HEAD", ".git/logs/HEAD"] {
            if let date = modified(dir.appending(path: rel)), date > threshold { return false }
        }

        guard let e = fm.enumerator(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return false }

        var seen = 0
        while let url = e.nextObject() as? URL {
            if Self.generatedNames.contains(url.lastPathComponent) {
                e.skipDescendants()
                continue
            }
            if let date = modified(url), date > threshold { return false }
            seen += 1
            if seen >= 3_000 { break }
        }
        return true
    }
}
