import SwiftUI

/// Alt çubuk: seçim özeti + "Seçilenleri temizle"; temizlik sürerken ilerleme; bitince rapor.
struct CleanBar: View {
    let model: AppModel
    @State private var confirmingClean = false
    @State private var confirmingTrash = false

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
        .confirmationDialog("Seçilenleri temizle", isPresented: $confirmingClean, titleVisibility: .visible) {
            Button("Temizle", role: .destructive) { model.cleanSelected() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(confirmationText)
        }
        .confirmationDialog("Çöp'ü boşalt", isPresented: $confirmingTrash, titleVisibility: .visible) {
            Button("Boşalt", role: .destructive) { model.emptyTrash() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Çöp'teki her şey kalıcı olarak silinecek. Geri alınamaz.")
        }
    }

    // MARK: - Seçim

    private var split: (deleteCount: Int, deleteBytes: Int64, trashCount: Int, trashBytes: Int64) {
        let selected = model.selectedFindings
        let delete = selected.filter { $0.risk == .safe }
        let trash = selected.filter { $0.risk == .review }
        return (delete.count, delete.reduce(0) { $0 + $1.bytes }, trash.count, trash.reduce(0) { $0 + $1.bytes })
    }

    private var selectionView: some View {
        let s = split
        let total = s.deleteBytes + s.trashBytes
        return Group {
            VStack(alignment: .leading, spacing: 2) {
                Text("Seçili: \(s.deleteCount + s.trashCount) öğe · \(ByteFormat.string(total))")
                    .font(.headline)
                    .monospacedDigit()
                HStack(spacing: 12) {
                    Label("\(ByteFormat.string(s.deleteBytes)) doğrudan silinecek", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                    Label("\(ByteFormat.string(s.trashBytes)) Çöp'e gidecek", systemImage: "circle.fill")
                        .foregroundStyle(.orange)
                }
                .labelStyle(DotLabelStyle())
                .font(.caption)
            }
            Spacer()
            Button("Önerilenlere dön") { model.resetSelection() }
                .help("Seçimi Breathy'nin önerdiklerine geri al")
            Button {
                confirmingClean = true
            } label: {
                Label("Seçilenleri temizle", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(total == 0 || model.isScanning)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var confirmationText: String {
        let s = split
        var lines: [String] = []
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
