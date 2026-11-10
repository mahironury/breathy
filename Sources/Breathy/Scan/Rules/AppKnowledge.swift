import Foundation

/// Bir uygulamanın veri düzeni: hangi alt klasörler yeniden oluşur ya da sadece kayıttır
/// (temizlenebilir), hangileri geçmiştir (sohbetler, planlar, dosya geçmişi, oyun kayıtları).
/// Geçmiş asla önerilmez: kullanıcı GitHub'a göndermediği işleri orada bulabilir.
struct AppKnowledge: Sendable {
    struct Part: Sendable {
        /// Veri klasörüne göre yol.
        let path: String
        let risk: Risk
        /// true: klasörün her alt öğesi ayrı bulgu (ör. her ekran kaydı).
        var eachChild = false
        /// Doluysa sadece bu kadar günden eski öğeler otomatik işaretlenir.
        var suggestAfterDays: Double? = nil
        let note: String
    }

    let name: String
    /// Açık mı diye bakılan bundle ID ya da uygulama adı parçaları (küçük harf).
    let owners: [String]
    /// Ev klasörüne göre veri klasörleri. Sonda "*" varsa aynı yerdeki, bu adla başlayan bütün
    /// kardeşler (".gemini/antigravity*" → antigravity, antigravity-ide, antigravity-cli…).
    let roots: [String]
    var excludedRoots: [String] = []
    /// Bulguların kategorisi ve hangi kullanım alanlarında taranacağı.
    var category: ScanCategory = .devTools
    var areas: Set<UsageArea>
    let cleanable: [Part]
    /// Geçmiş (veri klasörüne göre). Breathy bunlara dokunmaz; notlarda adı geçer.
    let history: [String]
    /// true: uygulama klasörünün toplamı ayrıca "Büyük uygulama verileri"nde gösterilmez
    /// (bulgular zaten neyin yer kapladığını söylüyor, ör. kurulu oyunlar).
    var replacesAppDataInfo = false

    /// `rel` (ev klasörüne göre) bu aracın veri klasörlerinden biri mi?
    func isRoot(_ rel: String) -> Bool {
        guard !excludedRoots.contains(rel) else { return false }
        return roots.contains { root in
            guard root.hasSuffix("*") else { return rel == root }
            let base = root.dropLast()
            return rel.hasPrefix(base) && !rel.dropFirst(base.count).contains("/")
        }
    }
}

extension Scanner {
    /// VS Code ailesi editörlerin (VS Code, Cursor, Antigravity, Windsurf…) ortak düzeni.
    static let editorCaches: [AppKnowledge.Part] = [
        .init(path: "CachedData", risk: .safe, note: "Editörün eski sürümlerinden kalan önbellek — yeniden oluşur"),
        .init(path: "CachedExtensionVSIXs", risk: .safe, note: "İndirilmiş eklenti paketleri — gerekirse yeniden indirilir"),
        .init(path: "logs", risk: .safe, note: "Editör logları"),
        .init(path: "Cache", risk: .safe, note: "Tarayıcı önbelleği — yeniden oluşur"),
        .init(path: "Code Cache", risk: .safe, note: "Kod önbelleği — yeniden oluşur"),
        .init(path: "GPUCache", risk: .safe, note: "Grafik önbelleği — yeniden oluşur"),
    ]
    static let editorHistory = ["User/History", "User/workspaceStorage", "User/globalStorage"]

    /// Bilinen uygulamalar. Yeni bir uygulama eklemek için bir satır yeter.
    static let appKnowledge: [AppKnowledge] = [
        AppKnowledge(
            name: "Antigravity", owners: ["antigravity"],
            roots: [".gemini/antigravity*"], excludedRoots: [".gemini/antigravity-browser-profile"],
            areas: [.aiCoding],
            cleanable: [
                .init(path: "browser_recordings", risk: .review, eachChild: true, suggestAfterDays: 30,
                      note: "Tarayıcı ajanının ekran kaydı (sadece görüntü) — sohbetler, planlar ve kod etkilenmez"),
                .init(path: "crashes", risk: .safe, note: "Çökme raporları"),
            ],
            history: ["conversations", "brain", "code_tracker", "implicit", "knowledge", "annotations"]
        ),
        // VS Code ailesi: hem yazılım geliştirme hem yapay zekâ kodlama araçları (Cursor, Windsurf…).
        AppKnowledge(name: "Antigravity", owners: ["antigravity"], roots: ["Library/Application Support/Antigravity"],
                     areas: [.development, .aiCoding], cleanable: editorCaches, history: editorHistory),
        AppKnowledge(name: "Visual Studio Code", owners: ["com.microsoft.vscode"],
                     roots: ["Library/Application Support/Code", "Library/Application Support/Code - Insiders"],
                     areas: [.development, .aiCoding], cleanable: editorCaches, history: editorHistory),
        AppKnowledge(name: "Cursor", owners: ["cursor", "com.todesktop.230313mzl4w4u92"],
                     roots: ["Library/Application Support/Cursor"],
                     areas: [.development, .aiCoding], cleanable: editorCaches, history: editorHistory),
        AppKnowledge(name: "Windsurf", owners: ["windsurf"], roots: ["Library/Application Support/Windsurf"],
                     areas: [.development, .aiCoding], cleanable: editorCaches, history: editorHistory),
        AppKnowledge(name: "VSCodium", owners: ["vscodium"], roots: ["Library/Application Support/VSCodium"],
                     areas: [.development, .aiCoding], cleanable: editorCaches, history: editorHistory),
        // Oturum geçmişi ve hafıza: hiçbir şeyi temizlenebilir değil.
        AppKnowledge(name: "Claude Code", owners: [], roots: [".claude"], areas: [.aiCoding], cleanable: [],
                     history: ["projects", "file-history", "todos", "sessions"]),
        // Oyun: önbellekler yeniden oluşur; kurulu oyunlar sadece bilgi; kayıtlı oyunlara dokunulmaz.
        AppKnowledge(
            name: "Steam", owners: ["com.valvesoftware.steam"], roots: ["Library/Application Support/Steam"],
            category: .games, areas: [.gaming],
            cleanable: [
                .init(path: "appcache", risk: .safe, note: "Steam önbelleği — yeniden oluşur"),
                .init(path: "depotcache", risk: .safe, note: "İndirme önbelleği — yeniden oluşur"),
                .init(path: "logs", risk: .safe, note: "Steam logları"),
                .init(path: "steamapps/shadercache", risk: .safe,
                      note: "Gölgelendirici önbelleği — oyun açılınca yeniden oluşur"),
                .init(path: "steamapps/common", risk: .info, eachChild: true,
                      note: "Kurulu oyun — gerekmiyorsa Steam'den kaldır (Kitaplık → sağ tık → Yönet → Kaldır)"),
            ],
            history: ["userdata", "config"],
            replacesAppDataInfo: true
        ),
    ]

    func knownAppData(_ ctx: ScanContext) throws -> [Finding] {
        let fm = FileManager.default
        var out: [Finding] = []
        for tool in Self.appKnowledge where !tool.cleanable.isEmpty && !tool.areas.isDisjoint(with: env.areas) {
            let owner = Self.runningApp(matching: tool.owners, in: env.runningApps)
            for root in resolveRoots(of: tool) {
                for part in tool.cleanable {
                    let target = root.appending(path: part.path)
                    guard fm.fileExists(atPath: target.path) else { continue }
                    let items = part.eachChild
                        ? ((try? fm.contentsOfDirectory(at: target, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                            .filter { $0.lastPathComponent != ".DS_Store" }
                        : [target]
                    for item in items {
                        try ctx.checkpoint(item)
                        ctx.setFolder(item)
                        let bytes = try measure(item, ctx)
                        guard bytes >= limits.minItemBytes else { continue }
                        let modified = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                        let suggested = part.suggestAfterDays.map { days in modified.map { daysSince($0) >= days } ?? false } ?? true
                        if let f = makeFinding(item, tool.category, part.risk, bytes: bytes, suggested: suggested,
                                               lastUsed: modified, note: "\(tool.name): \(part.note)",
                                               inUseBy: owner, areas: tool.areas, ctx: ctx) {
                            out.append(f)
                        }
                    }
                }
            }
        }
        return out
    }

    /// Bir aracın gerçekte var olan veri klasörleri ("*" açılır).
    func resolveRoots(of tool: AppKnowledge) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for root in tool.roots {
            if root.hasSuffix("*") {
                let base = String(root.dropLast())
                let parentRel = (base as NSString).deletingLastPathComponent
                let parent = env.home.appending(path: parentRel, directoryHint: .isDirectory)
                for child in (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
                    let rel = parentRel + "/" + child.lastPathComponent
                    guard tool.isRoot(rel),
                          (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                    out.append(child)
                }
            } else {
                let url = env.home.appending(path: root, directoryHint: .isDirectory)
                if fm.fileExists(atPath: url.path) { out.append(url) }
            }
        }
        return out
    }

    /// Ev klasörüne göre yolu içeren araç ve onun veri klasörü (ör. ".gemini/antigravity-ide/brain" →
    /// Antigravity, ".gemini/antigravity-ide").
    static func knownApp(containing rel: String) -> (tool: AppKnowledge, root: String)? {
        let parts = rel.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return nil }
        for length in 1...parts.count {
            let candidate = parts.prefix(length).joined(separator: "/")
            if let tool = appKnowledge.first(where: { $0.isRoot(candidate) }) { return (tool, candidate) }
        }
        return nil
    }

    /// Verisi bilinen uygulama şu an açık mı? Silmeden hemen önce de sorulur.
    static func knownAppOwner(of path: String, home: String, runningApps: [String: String]) -> String? {
        guard path.hasPrefix(home + "/"), let match = knownApp(containing: String(path.dropFirst(home.count + 1))) else {
            return nil
        }
        return runningApp(matching: match.tool.owners, in: runningApps)
    }

    /// Verilen araca ait açık uygulama. Noktalı parça ("com.microsoft.vscode") bundle ID'nin başıyla,
    /// tek kelime ("antigravity", "cursor") bundle ID'nin bir parçasıyla ya da uygulamanın adıyla
    /// birebir eşleşmeli. Gevşek eşleşme macOS'un "com.apple.TextInputUI.xpc.CursorUIViewService"
    /// gibi sistem servislerini "Cursor" sanıyordu (gerçek taramada yakalandı).
    static func runningApp(matching needles: [String], in runningApps: [String: String]) -> String? {
        guard !needles.isEmpty else { return nil }
        return runningApps.first { id, name in
            let lowerName = name.lowercased()
            let components = id.split(separator: ".").map(String.init)
            return needles.contains { needle in
                needle.contains(".") ? id.hasPrefix(needle) : (components.contains(needle) || lowerName == needle)
            }
        }?.value
    }
}
