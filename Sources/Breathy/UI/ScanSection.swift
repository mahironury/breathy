import SwiftUI

private let turkish = Locale(identifier: "tr_TR")

/// Tarama düğmesi, tarama sırasında ilerleme + iptal, bitince kategori özeti.
struct ScanSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress = model.scanProgress {
                ScanProgressCard(progress: progress) { model.cancelScan() }
            } else {
                startButton
                if let result = model.lastScan {
                    ScanSummaryView(result: result) { model.openDetails($0) }
                    QuickCleanSection(model: model)
                    Button { model.openDetails(nil) } label: {
                        PanelRow(icon: "list.bullet.rectangle", title: "Detaylar ve temizlik…",
                                 trailing: result.cleanableBytes > 0 ? ByteFormat.string(result.cleanableBytes) : nil)
                    }
                    .buttonStyle(PanelButtonStyle())
                }
            }
        }
    }

    private var startButton: some View {
        let needsPermission = model.trash == .needsPermission
        let trailing: String? = needsPermission
            ? "önce izin ver"
            : model.lastScan.map { $0.date.formatted(.relative(presentation: .named).locale(turkish)) }
        return Button { model.startScan() } label: {
            PanelRow(
                icon: "magnifyingglass",
                title: model.lastScan == nil ? "Taramayı Başlat" : "Yeniden Tara",
                trailing: trailing
            )
        }
        .buttonStyle(PanelButtonStyle())
        .disabled(needsPermission || model.trash == .unknown)
    }
}

struct ScanProgressCard: View {
    let progress: ScanProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress.phase).fontWeight(.medium)
                Spacer()
                Button("İptal", action: cancel).controlSize(.small)
            }
            Text("\(progress.filesVisited.formatted(.number.locale(turkish))) dosya · \(progress.currentFolder)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Şimdiye kadar \(ByteFormat.string(progress.foundBytes)) temizlenebilir")
                .font(.caption)
                .monospacedDigit()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }
}

/// Son taramanın özeti: büyük toplam + kategoriler + bilgi satırı.
struct ScanSummaryView: View {
    let result: ScanResult
    var openDetails: (ScanCategory?) -> Void = { _ in }
    /// Büyüyenler kutusu görünürken panel uzamasın diye daha az kategori satırı.
    private var maxRows: Int { result.growth?.isEmpty == false ? 4 : 6 }

    var body: some View {
        let summaries = result.summaries()
        let actionable = summaries.filter { $0.risk != .info }
        let info = summaries.filter { $0.risk == .info }

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ByteFormat.string(result.cleanableBytes))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                Text("temizlenebilir").foregroundStyle(.secondary)
            }

            if let since = result.growthSince {
                GrowthList(items: result.growth ?? [], since: since)
            }

            ForEach(actionable.prefix(maxRows)) { summary in
                Button { openDetails(summary.category) } label: { CategoryRow(summary: summary) }
                    .buttonStyle(.plain)
                    .help("Detaylarda göster")
            }

            if actionable.count > maxRows {
                Text("+ \(actionable.count - maxRows) kategori daha")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !info.isEmpty {
                Text("Bilgi: " + info.prefix(3)
                    .map { "\($0.category.shortTitle) \(ByteFormat.string($0.bytes))" }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "Geçen taramadan beri ne büyüdü?" — en çok büyüyen üç klasör.
struct GrowthList: View {
    let items: [GrowthItem]
    let since: Date

    var body: some View {
        let when = since.formatted(.relative(presentation: .named).locale(turkish))
        VStack(alignment: .leading, spacing: 3) {
            if items.isEmpty {
                Text("\(when) yapılan taramadan beri belirgin bir büyüme yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(when) yapılan taramadan beri büyüyenler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(items.prefix(3)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                        Text(item.title).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text("+\(ByteFormat.string(item.delta))")
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                    .help("\(item.title): şimdi \(ByteFormat.string(item.bytes))")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(items.isEmpty ? 0.0 : 0.07)))
    }
}

/// Panelden tek tıkla temizlik: sadece kendiliğinden yeniden oluşanlar (önbellek, log, node_modules…).
/// Kişisel dosyalar bu düğmeyle asla silinmez; onlar için Detaylar penceresi var.
struct QuickCleanSection: View {
    let model: AppModel
    @State private var confirming = false

    var body: some View {
        if let progress = model.cleanProgress {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Button("Durdur") { model.cancelCleaning() }.controlSize(.small)
                }
                Text("Temizleniyor \(progress.done)/\(progress.total) · \(progress.current)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.green.opacity(0.08)))
        } else {
            let items = model.safeCleanable
            let bytes = items.reduce(0) { $0 + $1.bytes }
            if bytes > 0 {
                if confirming {
                    confirmCard(count: items.count, bytes: bytes)
                } else {
                    Button { confirming = true } label: {
                        PanelRow(icon: "sparkles", title: "Güvenli olanları temizle", trailing: ByteFormat.string(bytes))
                    }
                    .buttonStyle(PanelButtonStyle(tint: .green))
                    .disabled(model.isScanning)
                    .help("Sadece önbellek, log ve node_modules gibi kendiliğinden geri gelenler")
                }
            }
        }
    }

    private func confirmCard(count: Int, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Önbellek, log ve node_modules gibi kendiliğinden geri gelen \(count) öğe (\(ByteFormat.string(bytes))) **kalıcı olarak** silinecek.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Senin dosyalarına dokunulmaz; onları Detaylar'dan seçebilirsin.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Vazgeç") { confirming = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Temizle") {
                    confirming = false
                    model.cleanSafe()
                }
                .keyboardShortcut(.defaultAction)
                .tint(.green)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.green.opacity(0.08)))
    }
}

private struct CategoryRow: View {
    let summary: CategorySummary

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(summary.risk.color).frame(width: 7, height: 7)
            Image(systemName: summary.category.icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(summary.category.title).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if summary.cleanableBytes > 0 {
                Text(ByteFormat.string(summary.cleanableBytes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text("\(ByteFormat.string(summary.bytes)) · incele")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
    }
}

extension Risk {
    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .info: .gray
        }
    }
}
