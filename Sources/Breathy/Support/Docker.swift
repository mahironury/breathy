import AppKit

/// `docker system df` çıktısı: imajlar, container'lar, volume'lar, derleme önbelleği.
struct DockerUsage: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        let type: String
        let total: Int
        let active: Int
        let size: Int64
        let reclaimable: Int64
    }

    let rows: [Row]

    func row(_ type: String) -> Row? { rows.first { $0.type == type } }
    /// Hiçbir container'ın kullanmadığı imajlar.
    var unusedImages: Int64 { row("Images")?.reclaimable ?? 0 }
    var buildCache: Int64 { row("Build Cache")?.reclaimable ?? 0 }
    /// Breathy'nin temizlediği: kullanılmayan imajlar + derleme önbelleği. Container ve volume'lara dokunulmaz.
    var cleanable: Int64 { unusedImages + buildCache }
    var volumes: Int64 { row("Local Volumes")?.size ?? 0 }
}

enum DockerState: Sendable, Equatable {
    case unknown
    case notInstalled
    case notRunning
    case ready(DockerUsage)
    case cleaning
}

/// Docker komut satırı aracı üzerinden kullanım bilgisi ve güvenli temizlik.
/// Sadece kullanılmayan imajlar ve derleme önbelleği silinir; container'lara (durmuş olsalar bile,
/// içlerinde veri olabilir) ve volume'lara (veritabanları) asla dokunulmaz.
enum Docker {
    static func cliPath(home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String? {
        [
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            home + "/.docker/bin/docker",
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// "1.153GB" → 1_153_000_000 (Docker SI birimleri kullanır).
    static func parseSize(_ text: String) -> Int64 {
        let value = text.split(separator: " ").first.map(String.init) ?? text
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (suffix, factor) in units where value.hasSuffix(suffix) {
            guard let number = Double(value.dropLast(suffix.count)) else { return 0 }
            return Int64((number * factor).rounded())
        }
        return Int64(value) ?? 0
    }

    /// `docker system df --format '{{json .}}'` çıktısı (her satır bir JSON).
    static func parseDF(_ output: String) -> DockerUsage? {
        let rows: [DockerUsage.Row] = output.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let type = object["Type"] else { return nil }
            return DockerUsage.Row(type: type,
                                   total: Int(object["TotalCount"] ?? "") ?? 0,
                                   active: Int(object["Active"] ?? "") ?? 0,
                                   size: parseSize(object["Size"] ?? ""),
                                   reclaimable: parseSize(object["Reclaimable"] ?? ""))
        }
        return rows.isEmpty ? nil : DockerUsage(rows: rows)
    }

    static func usage() async -> DockerState {
        guard let cli = cliPath() else { return .notInstalled }
        let result = await Command.run(cli, ["system", "df", "--format", "{{json .}}"], timeout: 20)
        guard result.status == 0, let usage = parseDF(result.output) else { return .notRunning }
        return .ready(usage)
    }

    /// Kullanılmayan imajlar + derleme önbelleği. Başarılıysa true.
    static func pruneUnused() async -> Bool {
        guard let cli = cliPath() else { return false }
        let images = await Command.run(cli, ["image", "prune", "--all", "--force"], timeout: 600)
        let builder = await Command.run(cli, ["builder", "prune", "--all", "--force"], timeout: 600)
        return images.status == 0 && builder.status == 0
    }

    static func openDockerDesktop() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
    }

}

/// Komut satırı aracını arka planda çalıştırır.
enum Command {
    /// Zaman aşımında durdurur. Çıktı (stdout) ve çıkış kodu döner.
    static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval) async -> (status: Int32, output: String) {
        await Task.detached(priority: .utility) { () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            environment["PATH"] = [home + "/.docker/bin", "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
                .joined(separator: ":")
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, "") }
            let deadline = DispatchTime.now() + timeout
            DispatchQueue.global().asyncAfter(deadline: deadline) { if process.isRunning { process.terminate() } }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
