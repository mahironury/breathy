import AppKit
import Security

/// GitHub'daki son sürüm.
struct ReleaseInfo: Sendable, Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let zipURL: URL
}

enum UpdateError: LocalizedError, Equatable {
    case notConfigured
    case noPackage
    case unzipFailed
    case appNotFound
    /// İndirilen uygulama bu kopyayla aynı sertifikayla imzalı değil.
    case signatureMismatch
    /// Bu kopya yerel sertifikayla imzalı değil (ör. geçici imza): neyle karşılaştıracağımızı bilemeyiz.
    case unsignedCurrentApp
    case notNewer
    case cannotReplace

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Güncelleme kaynağı ayarlı değil"
        case .noPackage: "Sürümde indirilecek paket yok"
        case .unzipFailed: "Paket açılamadı"
        case .appNotFound: "Pakette Breathy.app bulunamadı"
        case .signatureMismatch: "İndirilen uygulamanın imzası tutmuyor; kurulmadı"
        case .unsignedCurrentApp: "Bu kopya yerel sertifikayla imzalı değil; güncellemeyi elle kur"
        case .notNewer: "İndirilen sürüm daha yeni değil"
        case .cannotReplace: "Uygulama yerine konamadı (yazma izni yok)"
        }
    }
}

/// Hafif güncelleyici: günde bir kez GitHub'daki son sürüme bakar. Kullanıcı "Güncelle"ye basınca
/// paketi indirir, imzasını bu kopyanınkiyle karşılaştırır, uygulamayı yerinde değiştirir.
/// İmza aynı olduğu için Tam Disk Erişimi izni korunur. Ağ isteği sadece api.github.com ve indirme.
enum Updater {
    /// Info.plist → BreathyUpdateRepo, örn. "kullanici/breathy". Boşsa güncelleme denetimi kapalı.
    static var repo: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "BreathyUpdateRepo") as? String
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Sürüm karşılaştırma

    /// "v0.10.2" → [0, 10, 2]
    static func versionParts(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { part in Int(part.prefix { $0.isNumber }) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = versionParts(candidate), b = versionParts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - GitHub

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    static func parseRelease(_ data: Data) throws -> ReleaseInfo {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let zip = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            throw UpdateError.noPackage
        }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return ReleaseInfo(version: version, notes: release.body ?? "", pageURL: release.html_url,
                           zipURL: zip.browser_download_url)
    }

    static func latestRelease() async throws -> ReleaseInfo {
        guard let repo, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw UpdateError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Breathy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parseRelease(data)
    }

    // MARK: - Kurulum

    /// İndirir, doğrular ve çalışan uygulamanın yerine koyar. Başarılıysa yeniden başlatmak çağırana kalır.
    static func install(_ release: ReleaseInfo) async throws {
        let current = Bundle.main.bundleURL
        let fm = FileManager.default
        // Uygulamayla aynı diskte geçici klasör: yer değiştirme tek adımda olsun.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
        defer { try? fm.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: release.zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let zip = work.appending(path: "update.zip")
        try fm.moveItem(at: downloaded, to: zip)

        let newApp = try prepare(zip: zip, in: work, requireNewerThan: currentVersion)
        do {
            _ = try fm.replaceItemAt(current, withItemAt: newApp)
        } catch {
            throw UpdateError.cannotReplace
        }
    }

    /// Paketi açar, içindeki Breathy.app'i bulur, imzasını ve sürümünü denetler.
    static func prepare(zip: URL, in work: URL, requireNewerThan current: String?) throws -> URL {
        let unzipped = work.appending(path: "unzipped", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unzipped, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unzipped.path]) else { throw UpdateError.unzipFailed }
        guard let app = findApp(in: unzipped) else { throw UpdateError.appNotFound }
        // İnternetten gelmiş gibi işaretlenmişse ilk açılışta macOS yeniden "Yine de Aç" ister.
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])

        guard let requirement = ownRequirement() else { throw UpdateError.unsignedCurrentApp }
        guard isSigned(app, satisfying: requirement) else { throw UpdateError.signatureMismatch }

        let info = Bundle(url: app)?.infoDictionary
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError.signatureMismatch
        }
        if let current {
            let version = info?["CFBundleShortVersionString"] as? String ?? "0"
            guard isNewer(version, than: current) else { throw UpdateError.notNewer }
        }
        return app
    }

    static func findApp(in folder: URL) -> URL? {
        let fm = FileManager.default
        let level1 = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        if let app = level1.first(where: { $0.lastPathComponent == "Breathy.app" }) { return app }
        for dir in level1 where dir.pathExtension.isEmpty {
            let level2 = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            if let app = level2.first(where: { $0.lastPathComponent == "Breathy.app" }) { return app }
        }
        return nil
    }

    // MARK: - İmza

    /// Çalışan kopyanın "atanmış gereksinimi": kimlik com.breathy.app + yerel sertifikanın parmak izi.
    /// Geçici (ad-hoc) imzalı kopyada sertifika yoktur; o durumda güncelleme yapılmaz.
    static func ownRequirement() -> SecRequirement? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var text: CFString?
        SecRequirementCopyString(requirement, [], &text)
        guard let text = text as String?, text.contains("certificate leaf") else { return nil }
        return requirement
    }

    static func isSigned(_ app: URL, satisfying requirement: SecRequirement) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return false
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
