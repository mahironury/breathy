import SwiftUI

/// Alt çubuk: seçim özeti + temizlik düğmeleri; temizlik sürerken ilerleme; bitince rapor.
/// Seçim bütün kategorileri kapsar; "Sadece bu kategori" yalnızca açık kategoridekileri temizler.
struct CleanBar: View {
    let model: AppModel
    /// Detaylar'da açık olan kategori.
    var category: ScanCategory? = nil
    /// Doluysa onay penceresi açık: neyin temizleneceği.
    @State private var scope: CleanScope?
    @State private var confirmingTrash = false

    enum CleanScope: Equatable {
        case all
        case only(ScanCategory)

        var category: ScanCategory? {
            if case .only(let category) = self { return category }
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let progress = model.cleanProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: 200)
                Text("Temizleniyor \(progress.done)/\(progress.total) · \(progress.current)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Durdur") { model.cancelCleaning() }
            } else if let report = model.lastCleanReport {
                reportView(report)
            } else {
                selectionView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .confirmationDialog(
            scope.flatMap(\.category).map { "\($0.title): seçilenleri temizle" } ?? "Seçilenleri temizle",
            isPresented: Binding(get: { scope != nil }, set: { if !$0 { scope = nil } }),
            titleVisibility: .visible,
            presenting: scope
        ) { scope in
            Button("Temizle", role: .destructive) { model.cleanSelected(in: scope.category) }
            Button("Vazgeç", role: .cancel) {}
        } message: { scope in
            Text(confirmationText(scope))
        }
        .confirmationDialog("Çöp'ü boşalt", isPresented: $confirmingTrash, titleVisibility: .visible) {
            Button("Boşalt", role: .destructive) { model.emptyTrash() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Çöp'teki her şey kalıcı olarak silinecek. Geri alınamaz.")
        }
    }

    // MARK: - Seçim

    private func split(_ scope: CleanScope = .all) -> (deleteCount: Int, deleteBytes: Int64, trashCount: Int, trashBytes: Int64) {
        let selected = model.selectedFindings(in: scope.category)
        let delete = selected.filter { $0.risk == .safe }
        let trash = selected.filter { $0.risk == .review }
        return (delete.count, delete.reduce(0) { $0 + $1.bytes }, trash.count, trash.reduce(0) { $0 + $1.bytes })
    }

    private var selectionView: some View {
        let s = split()
        let total = s.deleteBytes + s.trashBytes
        let here = category.map { model.selectedBytes(in: $0) } ?? 0
        // Seçim açık kategorinin dışına da taşıyor mu? O zaman iki düğme, adları da kapsamı söylesin.
        let spansOthers = here < total
        return Group {
            VStack(alignment: .leading, spacing: 2) {
                Text("Seçili: \(s.deleteCount + s.trashCount) öğe · \(ByteFormat.string(total))")
                    .font(.headline)
                    .monospacedDigit()
                // Dar pencerede yan yana sığmazsa alt alta (satır ortasından bölünmesin).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { splitLabels(s) }
                    VStack(alignment: .leading, spacing: 1) { splitLabels(s) }
                }
                .labelStyle(DotLabelStyle())
                .font(.caption)
            }
            Spacer()
            Button("Önerilenlere dön") { model.resetSelection() }
                .help("Seçimi Breathy'nin önerdiklerine geri al")
            if let category, here > 0, spansOthers {
                Button("Sadece bu kategori · \(ByteFormat.string(here))") { scope = .only(category) }
                    .controlSize(.large)
                    .help("Sadece \(category.title) içindeki seçilenleri temizle; diğer kategorilerdeki seçimin kalır")
            }
            Button {
                scope = .all
            } label: {
                Label(spansOthers && here > 0 ? "Tüm seçilenleri temizle" : "Seçilenleri temizle", systemImage: "sparkles")
            }
            .help("Bütün kategorilerde seçili olanları temizler")
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(total == 0 || model.isScanning)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func splitLabels(_ s: (deleteCount: Int, deleteBytes: Int64, trashCount: Int, trashBytes: Int64)) -> some View {
        Label("\(ByteFormat.string(s.deleteBytes)) doğrudan silinecek", systemImage: "circle.fill")
            .foregroundStyle(.green)
            .fixedSize()
        Label("\(ByteFormat.string(s.trashBytes)) Çöp'e gidecek", systemImage: "circle.fill")
            .foregroundStyle(.orange)
            .fixedSize()
    }

    private func confirmationText(_ scope: CleanScope) -> String {
        let s = split(scope)
        var lines: [String] = []
        switch scope {
        case .only(let category):
            lines.append("Sadece \"\(category.title)\" temizlenecek. Diğer kategorilerdeki seçimin olduğu gibi kalır.")
        case .all:
            let count = Set(model.selectedFindings.map(\.category)).count
            if count > 1 { lines.append("\(count) kategorideki bütün seçilenler temizlenecek.") }
        }
        if s.deleteCount > 0 {
            lines.append("\(s.deleteCount) öğe (\(ByteFormat.string(s.deleteBytes))) kalıcı olarak silinecek. Bunlar önbellek, log, node_modules gibi kendiliğinden yeniden oluşan dosyalar.")
        }
        if s.trashCount > 0 {
            lines.append("\(s.trashCount) öğe (\(ByteFormat.string(s.trashBytes))) Çöp'e taşınacak. İstersen Çöp'ten geri alabilirsin.")
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Rapor

    @ViewBuilder
    private func reportView(_ report: CleanReport) -> some View {
        Image(systemName: report.wasCancelled ? "pause.circle.fill" : "checkmark.circle.fill")
            .font(.title2)
            .foregroundStyle(report.wasCancelled ? .orange : .green)
        VStack(alignment: .leading, spacing: 2) {
            reportHeadline(report)
            if report.trashedBytes > 0 {
                Text("Çöp'e taşınanlar, Çöp boşaltılınca yer açar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if !report.issues.isEmpty {
            Menu("\(report.issues.count) öğe atlandı") {
                ForEach(report.issues.prefix(30), id: \.self) { issue in
                    Text("\(issue.name): \(issue.reason)")
                }
            }
            .fixedSize()
        }
        Spacer()
        if report.trashedBytes > 0, case .ready(let trash) = model.trash, !trash.isEmpty {
            Button("Çöp'ü de boşalt (\(ByteFormat.string(trash.diskBytes)))") { confirmingTrash = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        Button("Tamam") { model.dismissCleanReport() }
    }

    /// "2,3 GB silindi · 120 MB Çöp'e taşındı"; silinen miktar sıfırdan sayarak yükselir.
    private func reportHeadline(_ report: CleanReport) -> some View {
        HStack(spacing: 0) {
            if report.wasCancelled { Text("Durduruldu: ") }
            if report.deletedBytes > 0 {
                AnimatedBytes(bytes: report.deletedBytes, suffix: " silindi")
                    .foregroundStyle(.green)
                if report.trashedBytes > 0 { Text(" · ") }
            }
            if report.trashedBytes > 0 { Text("\(ByteFormat.string(report.trashedBytes)) Çöp'e taşındı") }
            if report.deletedBytes == 0, report.trashedBytes == 0 { Text("Hiçbir şey temizlenmedi") }
        }
        .font(.headline)
        .monospacedDigit()
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title.foregroundStyle(.secondary)
        }
    }
}
