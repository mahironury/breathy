import Foundation

/// Breathy'nin asla silmediği hassas veriler: şifre kasaları, gizli anahtarlar, finans uygulamalarının verileri,
/// kurtarma kodları. Taramada "kritik" diye işaretlenir (otomatik seçilmez, seçilemez) ve her öğe
/// silinmeden hemen önce bir kez daha denetlenir. Yanlışlıkla korumak, yanlışlıkla silmekten iyidir.
enum CriticalData {
    enum Kind: Sendable, Equatable {
        case cryptoWallet, passwordVault, secretKey, recoveryCodes, cryptoContent

        var reason: String {
            switch self {
            case .cryptoWallet: "Kripto cüzdanıyla ilgili"
            case .passwordVault: "Şifre kasası ya da doğrulama uygulamasıyla ilgili"
            case .secretKey: "Gizli anahtar ya da sertifika"
            case .recoveryCodes: "Kurtarma ifadesi ya da yedek kodlar"
            case .cryptoContent: "İçinde kripto cüzdanı bilgisi var (adres, işlem geçmişi)"
            }
        }
    }

    // MARK: - Sözcükler

    /// Dosya ve klasör adlarında aranan kripto sözcükleri. Kısa olanlar (≤ 4 harf) tam sözcük olarak,
    /// uzunlar sözcük başı olarak aranır: "ledgerlive" ve "cüzdanım" eşleşir, "ethernet" eşleşmez.
    static let cryptoWords = [
        "wallet", "cuzdan", "crypto", "kripto", "bitcoin", "btc", "ethereum", "eth", "usdt", "usdc", "tether",
        "ledger", "trezor", "metamask", "electrum", "litecoin", "ltc", "dogecoin", "monero", "xmr", "xrp",
        "coinbase", "binance", "paribu", "btcturk", "bitexen", "icrypex", "okx", "bybit", "kucoin", "bitget",
        "blockchain", "txid", "satoshi", "koinly", "cointracking", "psbt",
    ]
    /// Cüzdan uygulamalarının adları. Sıradan sözcük de olabildikleri için ("Exodus" bir film,
    /// "Sparrow" bir kuş) sadece uygulama klasörlerinde ve klasör adlarında aranır, dosya adlarında değil.
    static let walletAppWords = cryptoWords + [
        // "keystone" bilerek yok: Google'ın güncelleyicisi de bu adı kullanıyor.
        "exodus", "sparrow", "wasabi", "walletwasabi", "phantom", "keplr", "rabby", "atomic", "safepal",
        "tangem", "bitbox", "onekey", "ellipal", "keepkey", "coldcard", "daedalus", "yoroi",
        "nunchuk", "specter", "blockstream", "bluewallet", "coinomi", "guarda", "trustwallet", "zengo",
        "solana", "cardano", "kraken", "bitmonero", "zcash", "lnd", "ledgerhq",
    ]
    static let vaultWords = [
        "password", "sifre", "parola", "1password", "onepassword", "agilebits", "bitwarden", "keepass",
        "macpass", "strongbox", "dashlane", "lastpass", "enpass", "nordpass", "protonpass", "authy",
        "authenticator", "2fas", "2fa",
    ]
    static let recoveryWords = ["seed", "mnemonic", "recovery", "kurtarma", "privatekey", "privkey"]
    /// Birden çok sözcükten oluşanlar (katlanmış, boşlukla ayrılmış).
    static let recoveryPhrases = [
        "seed phrase", "recovery phrase", "secret recovery", "secret phrase", "private key", "backup codes",
        "recovery codes", "yedek kod", "kurtarma ifade", "kurtarma kelime", "kurtarma kod", "gizli anahtar",
        "ozel anahtar",
    ]

    static let secretFileNames: [String: Kind] = [
        "wallet.dat": .cryptoWallet, "default_wallet": .cryptoWallet,
        "id_rsa": .secretKey, "id_dsa": .secretKey, "id_ecdsa": .secretKey, "id_ed25519": .secretKey,
        "keystore": .secretKey,
    ]
    static let extensionKinds: [String: Kind] = [
        "wallet": .cryptoWallet, "psbt": .cryptoWallet,
        "kdbx": .passwordVault, "kdb": .passwordVault, "opvault": .passwordVault, "agilekeychain": .passwordVault,
        "1pif": .passwordVault, "1pux": .passwordVault, "keychain": .passwordVault, "keychain-db": .passwordVault,
        "pem": .secretKey, "p12": .secretKey, "pfx": .secretKey, "jks": .secretKey, "keystore": .secretKey,
        "ppk": .secretKey, "asc": .secretKey, "gpg": .secretKey, "pgp": .secretKey,
    ]

    static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "js", "jsx", "mjs", "cjs", "ts", "tsx", "vue", "svelte",
        "py", "rb", "go", "rs", "java", "kt", "kts", "php", "cs", "dart", "scala", "css", "scss", "sass", "less",
        "map", "lock", "sh",
    ]

    /// Kullanıcının kendi dosyaları: adlarına, üst klasörlerine, içlerine ve içeriklerine bakılır.
    /// Diğerleri (önbellek, node_modules…) yeniden oluşur; onlarda sadece sahibi uygulamaya bakılır.
    static let personalCategories: Set<ScanCategory> = [
        .largeFiles, .duplicates, .screenCaptures, .oldInstallers, .iCloudArchive, .appLeftovers, .hiddenFolders,
        .unusedApps,
    ]
    /// İçindeki dosyaların adlarına da bakılan klasör bulguları.
    static let containerCategories: Set<ScanCategory> = [.appLeftovers, .hiddenFolders, .iCloudArchive, .largeFiles]
    /// İçeriği okunan dosya bulguları (metin, PDF, görüntülerdeki yazı).
    static let contentCategories: Set<ScanCategory> = [.screenCaptures, .duplicates, .largeFiles, .iCloudArchive]

    // MARK: - Denetim

    /// Bulgu kritik mi? Konuma, ada, klasörün içine ve dosyanın içeriğine bakar.
    /// `budget` doluysa içerik okunmaz (tarama süresi uzamasın); silmeden önceki denetimde sınır yoktur.
    static func check(_ finding: Finding, home: String, budget: CriticalContent.Budget?) -> Kind? {
        let url = finding.url
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
        let isDirectory = values?.isDirectory == true
        if let kind = locationKind(path: finding.path, home: home, category: finding.category,
                                   isDirectory: isDirectory) {
            return kind
        }
        guard personalCategories.contains(finding.category), values?.isSymbolicLink != true else { return nil }
        if isDirectory {
            return containerCategories.contains(finding.category) ? containedKind(in: url) : nil
        }
        // Zip'in içindekiler listesi hızlı okunur; süre sınırına takılmaz.
        if url.pathExtension.lowercased() == "zip" { return archiveKind(url) }
        guard contentCategories.contains(finding.category) else { return nil }
        return CriticalContent.kind(of: url, budget: budget)
    }

    /// Yola göre: cüzdan/şifre uygulamasının klasörü, gizli klasörü ya da (kişisel dosyalarda)
    /// adı ve üst klasörleri.
    static func locationKind(path: String, home: String, category: ScanCategory, isDirectory: Bool) -> Kind? {
        guard path.hasPrefix(home + "/") else {
            // Ev klasörü dışında Breathy sadece uygulama paketlerine dokunur: uygulamanın adına bak.
            let name = (path as NSString).lastPathComponent
            return appKind((name as NSString).deletingPathExtension)
        }
        let components = path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        guard let first = components.first else { return nil }

        // ~/Library/<Application Support|Containers|Caches|…>/<uygulama> ve ~/Library/<uygulama>
        if first == "Library" {
            for component in components.dropFirst().prefix(2) {
                if let kind = appKind(component) { return kind }
            }
        }
        // ~/.electrum, ~/.bitcoin, ~/.config/solana …
        if first.hasPrefix(".") {
            for component in components {
                if let kind = appKind(component) { return kind }
            }
        }
        guard personalCategories.contains(category) else { return nil }
        for (index, component) in components.enumerated() {
            let isFile = index == components.count - 1 && !isDirectory
            if let kind = isFile ? nameKind(component) : appKind(component) ?? nameKind(component) {
                return kind
            }
        }
        return nil
    }

    /// Klasörün içinde kritik bir dosya ya da klasör var mı? Üretilmiş içeriğe (node_modules, .git…) girilmez.
    static func containedKind(in url: URL, limit: Int = 200_000) -> Kind? {
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: { _, _ in true }
        ) else { return nil }
        var seen = 0
        while let child = e.nextObject() as? URL {
            seen += 1
            if seen > limit { break }
            let name = child.lastPathComponent
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory, Scanner.generatedNames.contains(name) {
                e.skipDescendants()
                continue
            }
            if let kind = isDirectory ? appKind(name) ?? nameKind(name) : nameKind(name) { return kind }
        }
        return nil
    }

    /// Zip arşivinin içinde kritik bir dosya ya da klasör var mı? Arşiv açılmaz, sadece adlara bakılır.
    static func archiveKind(_ url: URL) -> Kind? {
        guard let entries = CriticalContent.zipEntryNames(url) else { return nil }
        for entry in entries {
            var components = entry.split(separator: "/").map(String.init)
            if components.first == "__MACOSX" { continue }  // Finder'ın eklediği gölge kopyalar
            let isDirectory = entry.hasSuffix("/")
            let file = isDirectory ? nil : components.popLast()
            for folder in components {
                if Scanner.generatedNames.contains(folder) { break }
                if let kind = appKind(folder) ?? nameKind(folder) { return kind }
            }
            if let file, let kind = nameKind(file) { return kind }
        }
        return nil
    }

    /// Cüzdan ya da şifre uygulamasının klasörü mü? ("Ledger Live", "com.bitwarden.desktop", ".electrum")
    static func appKind(_ name: String) -> Kind? {
        let words = tokens(name)
        if matches(words, walletAppWords) { return .cryptoWallet }
        if matches(words, vaultWords) { return .passwordVault }
        return nil
    }

    /// Dosya adına göre: bilinen gizli dosyalar, uzantılar ve addaki sözcükler.
    static func nameKind(_ name: String) -> Kind? {
        let lower = name.lowercased()
        if let kind = secretFileNames[lower] { return kind }
        if lower.hasPrefix("utc--") { return .cryptoWallet }  // Ethereum anahtar dosyası
        let ext = (lower as NSString).pathExtension
        if let kind = extensionKinds[ext] { return kind }
        // Kaynak kod dosyası cüzdan ya da kasa değildir: "WalletButton.tsx", "ForgotPassword.swift".
        if codeExtensions.contains(ext) { return nil }
        let words = tokens(ext.isEmpty ? lower : (lower as NSString).deletingPathExtension)
        if matches(words, recoveryWords) || containsPhrase(words, recoveryPhrases) { return .recoveryCodes }
        if matches(words, cryptoWords) { return .cryptoWallet }
        if matches(words, vaultWords) { return .passwordVault }
        return nil
    }

    // MARK: - Metin yardımcıları

    /// Büyük/küçük harf ve Türkçe işaretler yok sayılır: "ŞİFRELER" → "sifreler", "Cüzdanım" → "cuzdanim".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }

    static func tokens(_ text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func matches(_ tokens: [String], _ words: [String]) -> Bool {
        tokens.contains { token in
            words.contains { word in word.count <= 4 ? token == word : token.hasPrefix(word) }
        }
    }

    static func containsPhrase(_ tokens: [String], _ phrases: [String]) -> Bool {
        let spaced = " " + tokens.joined(separator: " ") + " "
        return phrases.contains { spaced.contains(" " + $0) }
    }
}
