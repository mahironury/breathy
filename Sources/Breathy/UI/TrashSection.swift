import SwiftUI

/// "Çöpü Boşalt" düğmesi: ölçüm, iki adımlı onay, izin rehberi.
struct TrashSection: View {
    let model: AppModel
    @State private var confirming = false

    var body: some View {
        switch model.trash {
        case .unknown:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Çöp ölçülüyor…").foregroundStyle(.secondary)
            }
        case .needsPermission:
            PermissionCard()
        case .ready(let summary):
            ready(summary)
        }
    }

    @ViewBuilder
    private func ready(_ summary: TrashSummary) -> some View {
        if model.isEmptyingTrash {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Çöp boşaltılıyor…")
            }
            .padding(.vertical, 6)
        } else if confirming {
            VStack(alignment: .leading, spacing: 8) {
                Text("Çöp'teki \(summary.items) öğe (\(ByteFormat.string(summary.diskBytes))) **kalıcı olarak** silinecek. Geri alınamaz.")
                    .fixedSize(horizontal: false, vertical: true)
                if summary.iCloudItems > 0 {
                    Text("\(summary.iCloudItems) tanesi iCloud Drive'dan; bütün cihazlarından da silinir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Vazgeç") { confirming = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Boşalt", role: .destructive) {
                        confirming = false
                        model.emptyTrash()
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.08)))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button { confirming = true } label: {
                    PanelRow(
                        icon: summary.isEmpty ? "trash" : "trash.fill",
                        title: summary.isEmpty ? "Çöp boş" : "Çöpü Boşalt",
                        trailing: summary.isEmpty ? nil : ByteFormat.string(summary.diskBytes)
                    )
                }
                .buttonStyle(PanelButtonStyle(tint: .red))
                .disabled(summary.isEmpty)

                if summary.iCloudItems > 0 {
                    Text("iCloud Drive çöpü: \(summary.iCloudItems) öğe · \(ByteFormat.string(summary.iCloudBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
    }
}

/// Tam Disk Erişimi verilmemişse gösterilen kısa rehber.
private struct PermissionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Çöp'ü görebilmem için izin gerekiyor", systemImage: "lock.fill")
                .font(.callout.weight(.semibold))
            Text("Sistem Ayarları → Gizlilik ve Güvenlik → **Tam Disk Erişimi**'nde Breathy'yi aç. Listede yoksa \"Breathy'yi Göster\"e bas ve uygulamayı listeye sürükle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Ayarları Aç") { SystemLinks.openFullDiskAccess() }
                Button("Breathy'yi Göster") { SystemLinks.revealApp() }
                Spacer()
            }
            .controlSize(.small)
            HStack(spacing: 4) {
                Text("İzni verdin mi?").font(.caption).foregroundStyle(.secondary)
                Button("Yeniden başlat") { SystemLinks.relaunch() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.10)))
    }
}
