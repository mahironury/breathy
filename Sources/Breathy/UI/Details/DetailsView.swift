import QuickLook
import SwiftUI

/// Solda kategoriler, sağda dosyalar, altta temizlik çubuğu.
struct DetailsView: View {
    let model: AppModel
    @State private var category: ScanCategory?
    @State private var search = ""
    @State private var previewURL: URL?

    var body: some View {
        Group {
            if let progress = model.scanProgress {
                VStack {
                    Spacer()
                    ScanProgressCard(progress: progress) { model.cancelScan() }.frame(width: 360)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let result = model.lastScan, !result.findings.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        CategorySidebar(model: model, result: result, category: $category)
                            .frame(width: 300)
                        Divider()
                        if let category {
                            FindingList(model: model, category: category, search: $search, previewURL: $previewURL)
                        } else {
                            ContentUnavailableView("Soldan bir kategori seç", systemImage: "sidebar.left")
                        }
                    }
                    Divider()
                    CleanBar(model: model, category: category)
                }
            } else {
                ContentUnavailableView {
                    Label("Henüz tarama sonucu yok", systemImage: "wind")
                } description: {
                    Text("Breathy diskini tarar, gereksizleri burada listeler. Sen seçmeden hiçbir şey silinmez.")
                } actions: {
                    Button("Taramayı Başlat") { model.startScan() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.trash == .needsPermission)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 480)
        .quickLookPreview($previewURL)
        .onAppear { pickInitialCategory() }
        .onChange(of: model.detailsCategory) { _, new in if let new { category = new } }
        .onChange(of: model.lastScan?.date) { _, _ in pickInitialCategory() }
    }

    private func pickInitialCategory() {
        guard let result = model.lastScan else { return }
        let available = Set(result.findings.map(\.category))
        if let wanted = model.detailsCategory, available.contains(wanted) {
            category = wanted
        } else if category == nil || !available.contains(category!) {
            category = result.summaries().first?.category
        }
    }
}

/// Kategori listesi: temizlenebilirler üstte, sadece bilgi olanlar altta.
private struct CategorySidebar: View {
    let model: AppModel
    let result: ScanResult
    @Binding var category: ScanCategory?

    @State private var showingIgnored = false

    var body: some View {
        let summaries = result.summaries()
        VStack(spacing: 0) {
            list(summaries)
            if !model.ignored.isEmpty {
                Divider()
                Button { showingIgnored = true } label: {
                    Label("Önerilmeyenler (\(model.ignored.paths.count))", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .sheet(isPresented: $showingIgnored) { IgnoredSheet(model: model) }
    }

    private func list(_ summaries: [CategorySummary]) -> some View {
        List(selection: $category) {
            Section("Temizlenebilir") {
                ForEach(summaries.filter { $0.risk != .info }) { summary in
                    row(summary).tag(summary.category as ScanCategory?)
                }
            }
            let info = summaries.filter { $0.risk == .info }
            if !info.isEmpty {
                Section("Sadece bilgi") {
                    ForEach(info) { summary in
                        row(summary).tag(summary.category as ScanCategory?)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ summary: CategorySummary) -> some View {
        let selected = model.selectedBytes(in: summary.category)
        return HStack(spacing: 8) {
            Image(systemName: summary.category.icon)
                .frame(width: 18)
                .foregroundStyle(summary.risk.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.category.title).lineLimit(1)
                Text(summary.risk == .info
                     ? "\(summary.count) öğe"
                     : "\(ByteFormat.string(selected)) seçili")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(ByteFormat.string(summary.bytes))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// "Bunu bir daha önerme" denilenler. Geri alınan öğe bir sonraki taramada yeniden görünür.
private struct IgnoredSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Önerilmeyenler").font(.title3.weight(.semibold))
            Text("Bunlar ve içlerindekiler taramada önerilmez. Geri aldığın öğe bir sonraki taramada yeniden görünür.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(model.ignored.paths, id: \.self) { path in
                    HStack {
                        Text(path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Geri al") { model.unignore(path) }
                    }
                }
            }
            .frame(minHeight: 180)
            HStack {
                Spacer()
                Button("Kapat") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
    }
}
