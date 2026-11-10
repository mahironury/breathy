import Foundation

/// Büyük gizli klasörler (~/.gemini, ~/.colima, ~/.ollama…). Bunlar uygulamaların verisidir:
/// klasörün kendisi sadece bilgi olarak gösterilir. İçinde aylardır hiçbir dosyası değişmemiş
/// büyük bir alt klasör varsa (ör. eski bir yedek kopya) o ayrıca listelenir; seçilirse Çöp'e
/// gider ve hiçbir zaman otomatik işaretlenmez.
extension Scanner {
    func hiddenFolders(_ ctx: ScanContext) -> [Finding] {
        let sizes = ctx.folderSizes
        // Bilinen kuralların zaten ölçtüğü gizli klasörler (ör. ~/.cache) iki kez gösterilmez.
        let rulePaths = Set(Self.locationRules.map(\.path))
        var out: [Finding] = []

        for (key, bytes) in sizes where key.hasPrefix(".") && !key.contains("/") {
            guard key != ".Trash", !rulePaths.contains(key), bytes >= limits.appDataBytes else { continue }
            let folder = env.home.appending(path: key, directoryHint: .isDirectory)
            let owner = Self.hiddenFolderOwner(of: folder.path, home: env.home.path, runningApps: env.runningApps)
            if let f = makeFinding(folder, .hiddenFolders, .info, bytes: bytes,
                                   lastUsed: ctx.latestChange[key], note: Self.hiddenFolderNote(key), ctx: ctx) {
                out.append(f)
            }

            for (sub, subBytes) in sizes where sub.hasPrefix(key + "/") && subBytes >= limits.appDataBytes {
                guard let latest = ctx.latestChange[sub], daysSince(latest) >= limits.staleProjectDays else { continue }
                let months = Int(daysSince(latest) / 30)
                let url = env.home.appending(path: sub, directoryHint: .isDirectory)
                if let f = makeFinding(url, .hiddenFolders, .review, bytes: subBytes, suggested: false, lastUsed: latest,
                                       note: "\(months) aydır hiçbir dosyası değişmemiş — eski bir kopya olabilir. "
                                           + "Kullanmadığından eminsen seç; Çöp'e taşınır.",
                                       inUseBy: owner, ctx: ctx) {
                    out.append(f)
                }
            }
        }
        return out
    }

    /// Hangi uygulamanın verisi olduğunu söyleyen kısa not.
    static func hiddenFolderNote(_ key: String) -> String {
        let notes: [String: String] = [
            ".gemini": "Gemini CLI ve Antigravity verisi (tarayıcı kayıtları, sohbetler)",
            ".antigravity": "Antigravity eklentileri",
            ".colima": "Colima sanal makinesi — 'colima delete' ile kaldırılır",
            ".docker": "Docker ayarları ve verisi",
            ".ollama": "Ollama yapay zekâ modelleri — 'ollama rm' ile kaldırılır",
            ".lmstudio": "LM Studio modelleri — uygulamadan yönet",
            ".vscode": "VS Code eklentileri",
            ".cursor": "Cursor eklentileri ve verisi",
            ".npm": "npm verisi",
            ".nvm": "Kurulu Node.js sürümleri (nvm)",
            ".pyenv": "Kurulu Python sürümleri (pyenv)",
            ".rustup": "Rust araç zincirleri — 'rustup toolchain list' ile yönet",
            ".cargo": "Rust paketleri ve araçları",
            ".gradle": "Gradle verisi",
            ".android": "Android emülatörleri ve SDK verisi",
            ".bun": "Bun verisi",
            ".claude": "Claude Code verisi",
            ".local": "Komut satırı araçlarının verisi",
            ".config": "Uygulama ayarları",
        ]
        return notes[key] ?? "Bir uygulamanın verisi — ilgili uygulamadan yönet"
    }

    /// Gizli klasörün sahibi uygulama şu an açık mı? Hem taramada hem silmeden hemen önce sorulur.
    static func hiddenFolderOwner(of path: String, home: String, runningApps: [String: String]) -> String? {
        let owners: [String: String] = [
            ".gemini": "antigravity", ".antigravity": "antigravity", ".cursor": "cursor",
            ".vscode": "com.microsoft.vscode", ".lmstudio": "lmstudio", ".ollama": "ollama",
            ".docker": "docker", ".android": "android",
        ]
        guard path.hasPrefix(home + "/") else { return nil }
        let top = path.dropFirst(home.count + 1).split(separator: "/").first.map(String.init) ?? ""
        guard let needle = owners[top] else { return nil }
        return runningApps.first { $0.key.contains(needle) }?.value
    }
}
