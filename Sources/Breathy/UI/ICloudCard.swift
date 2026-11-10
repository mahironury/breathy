import SwiftUI

/// iCloud durumu: bu Mac iCloud'u dolduruyor mu, iCloud Drive'da ne var, ekran görüntüleri nerede.
struct ICloudCard: View {
    let status: ICloudStatus
    let summary: ICloudSummary?
    let screenshotFolder: URL
    let screenshotsGoToICloud: Bool
    let moveScreenshots: () -> Void

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("iCloud", systemImage: status.macUploadsFiles ? "icloud.fill" : "icloud")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Depolamayı yönet") { SystemLinks.openICloudSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            if status.signedIn, !status.macUploadsFiles {
                Text("Bu Mac iCloud'a dosya göndermiyor. iCloud'u büyük ihtimalle iPhone yedekleri ya da Fotoğraflar dolduruyor; \"Depolamayı yönet\"ten bakabilirsin.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let summary, summary.driveBytes > 0 {
                Text("iCloud Drive: \(ByteFormat.string(summary.driveBytes)) · bu Mac'te \(ByteFormat.string(summary.driveLocalBytes)) indirilmiş")
                    .font(.caption)
                    .monospacedDigit()
                ForEach(summary.topFolders.prefix(3), id: \.self) { folder in
                    HStack {
                        Text("  \(folder.name)").lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(folder.bytes)).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let summary, summary.screenshotCount > 0 {
                Button { SystemLinks.open(screenshotFolder) } label: {
                    Label(
                        "Ekran görüntüleri: \(shortPath(screenshotFolder.path)) · \(summary.screenshotCount) adet · \(ByteFormat.string(summary.screenshotBytes))",
                        systemImage: "camera.viewfinder"
                    )
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .help("Klasörü Finder'da aç")
            }

            if screenshotsGoToICloud {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚠︎ Ekran görüntülerin \(shortPath(screenshotFolder.path)) klasörüne, oradan da iCloud'a gidiyor.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Resimler'e kaydet", action: moveScreenshots)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))
    }

    private var statusLine: String {
        guard status.signedIn else { return "Bu Mac'te iCloud oturumu yok." }
        let drive = status.driveEnabled ? "iCloud Drive açık" : "iCloud Drive kapalı"
        let desktop = status.desktopDocumentsEnabled ? "Masaüstü ve Belgeler eşitleniyor" : "Masaüstü ve Belgeler eşitlenmiyor"
        return "\(drive) · \(desktop)"
    }

    private func shortPath(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
