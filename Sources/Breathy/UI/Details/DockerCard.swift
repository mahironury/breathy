import SwiftUI

/// Detaylar → Docker: kullanılmayan imajlar ve derleme önbelleği, tek tıkla temizlik.
/// Container'lara (durmuş olsalar bile) ve volume'lara (veritabanları) asla dokunulmaz.
struct DockerCard: View {
    let model: AppModel
    @State private var confirming = false

    var body: some View {
        Group {
            switch model.docker {
            case .unknown:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Docker'a soruluyor…").foregroundStyle(.secondary)
                }
            case .notInstalled:
                Label("Docker komutu bulunamadı.", systemImage: "questionmark.circle").foregroundStyle(.secondary)
            case .notRunning:
                HStack {
                    Label("Docker Desktop kapalı. İçindekileri görmek ve temizlemek için aç.", systemImage: "moon.zzz")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Docker'ı aç") { Docker.openDockerDesktop() }
                    Button("Tekrar dene") { model.refreshDocker() }
                }
            case .cleaning:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Kullanılmayan imajlar siliniyor…")
                }
            case .ready(let usage):
                ready(usage)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
        .onAppear { model.refreshDocker() }
        .confirmationDialog("Docker'da kullanılmayanları temizle", isPresented: $confirming, titleVisibility: .visible) {
            Button("Temizle", role: .destructive) { model.cleanDocker() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Hiçbir container'ın kullanmadığı imajlar ve derleme önbelleği silinecek. Çalışan ya da durmuş container'lara ve volume'lara (veritabanı gibi veriler) dokunulmaz. Silinen bir imaj gerekirse yeniden indirilir.")
        }
    }

    @ViewBuilder
    private func ready(_ usage: DockerUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                stat("Kullanılmayan imajlar", usage.unusedImages,
                     detail: usage.row("Images").map { "\($0.total) imajdan \($0.total - $0.active) tanesi" })
                stat("Derleme önbelleği", usage.buildCache, detail: nil)
                stat("Volume'lar", usage.volumes, detail: "dokunulmaz")
            }
            HStack {
                Text(usage.cleanable > 0
                     ? "Docker Desktop'ın disk görüntüsü, silinenlerin yerini birkaç dakika içinde Mac'e geri verir."
                     : "Temizlenecek kullanılmayan imaj ya da önbellek yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Kullanılmayanları temizle · \(ByteFormat.string(usage.cleanable))") { confirming = true }
                    .disabled(usage.cleanable == 0)
            }
        }
    }

    private func stat(_ title: String, _ bytes: Int64, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(ByteFormat.string(bytes)).font(.headline).monospacedDigit()
            if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary) }
        }
    }
}
