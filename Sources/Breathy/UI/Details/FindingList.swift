import AppKit
import SwiftUI

private let turkish = Locale(identifier: "tr_TR")

/// Bir kategorideki dosyalar: kutucuk, simge, ad, konum, son kullanım, boyut.
/// Boşluk tuşu Quick Look, sağ tık menüsü Finder'da göster.
struct FindingList: View {
    let model: AppModel
    let category: ScanCategory
    @Binding var search: String
    @Binding var previewURL: URL?
    @State private var focused: Finding.ID?

    var body: some View {
        let all = model.findings(in: category)
        let items = filtered(all)
        let selectable = all.contains(where: AppModel.isSelectable)

        VStack(alignment: .leading, spacing: 0) {
            header(all: all, selectable: selectable)
                .padding(16)
            Divider()

            List(selection: $focused) {
                if category == .duplicates {
                    ForEach(duplicateGroups(items), id: \.id) { group in
                        Section {
                            ForEach(group.items) { row($0) }
                        } header: {
                            Text("\(group.items.count) kopya · her biri \(ByteFormat.string(group.size))")
                        }
                    }
                } else {
                    ForEach(items) { row($0) }
                }
            }
            .listStyle(.inset)
            .onKeyPress(.space) {
                guard let focused else { return .ignored }
                previewURL = URL(fileURLWithPath: focused)
                return .handled
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    // MARK: - Başlık

    private func header(all: [Finding], selectable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: category.icon).font(.title2)
                Text(category.title).font(.title2.weight(.semibold))
                Spacer()
                TextField("Ada veya konuma göre ara", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            Text(explanation(all))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if category == .docker {
                DockerCard(model: model)
            }
            HStack {
                if selectable {
                    Button("Tümünü seç") { model.setSelection(true, in: category) }
                    Button("Seçimi kaldır") { model.setSelection(false, in: category) }
                }
                Spacer()
                Text("\(all.count) öğe · \(ByteFormat.string(all.reduce(0) { $0 + $1.bytes }))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .controlSize(.small)
        }
    }

    private func explanation(_ items: [Finding]) -> String {
        var text: String
        if items.allSatisfy({ $0.risk == .info }) {
            text = "Sadece bilgi: Breathy bunları silmez. İlgili uygulamanın kendi ayarlarından temizleyebilirsin."
        } else if items.allSatisfy({ $0.risk == .safe }) {
            text = "Kendiliğinden yeniden oluşur → doğrudan silinir."
        } else if items.allSatisfy({ $0.risk == .review }) {
            text = "Senin dosyaların → Çöp'e taşınır, geri alınabilir. Yer, Çöp'ü boşaltınca açılır."
        } else {
            text = "Yeşil etiketliler doğrudan silinir, turuncular Çöp'e taşınır."
        }
        if items.contains(where: { $0.risk != .info }) {
            text += " İstemediğin bir öğeye sağ tıklayıp \"Bunu bir daha önerme\" diyebilirsin."
        }
        switch category {
        case .duplicates: text += " Her grupta bir kopya mutlaka korunur."
        case .largeFiles: text += " 6 aydır açılmayanlar işaretlendi."
        case .screenCaptures: text += " 30 günden eskiler işaretlendi."
        case .nodeModules, .buildOutputs, .pythonEnvs: text += " Sadece 90 gündür dokunulmamış projeler."
        case .docker:
            text = "Docker'ın disk görüntüsü. Aşağıdaki karttan hiçbir container'ın kullanmadığı imajları ve derleme önbelleğini temizleyebilirsin; container'lara ve volume'lara (veritabanı gibi veriler) dokunulmaz."
        case .games:
            text = "Oyunların önbellekleri yeniden oluşur ve doğrudan silinir. Kurulu oyunlar sadece bilgi: gerekmiyorsa Steam'den kaldır. Kayıtlı oyunlarına dokunulmaz."
        case .devTools:
            text = "Kodlama ve yapay zekâ araçlarının (VS Code, Cursor, Antigravity…) yeniden oluşan önbellekleri ve eski ekran kayıtları. Sohbet geçmişi, planlar ve dosyaların yerel geçmişi asla önerilmez. Araç açıksa önce kapat."
        case .hiddenFolders:
            text = "Gizli klasörler uygulamaların verisidir; klasörün kendisi sadece bilgi. İçinde 3 aydır hiçbir dosyası değişmemiş büyük alt klasörler (ör. eski kopyalar) seçilebilir, hiçbiri otomatik işaretlenmez. Seçersen Çöp'e taşınır; önce ilgili uygulamayı kapat."
        case .unusedApps: text += " 6 aydır açılmamış uygulamalar."
        default: break
        }
        return text
    }

    // MARK: - Satır

    private func row(_ finding: Finding) -> some View {
        FindingRow(
            finding: finding,
            isSelected: model.isSelected(finding),
            toggle: { model.toggle(finding) },
            preview: { previewURL = finding.url },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) },
            ignore: { model.ignore(finding) }
        )
        .tag(finding.id)
    }

    // MARK: - Filtre ve gruplar

    private func filtered(_ items: [Finding]) -> [Finding] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    private struct DuplicateGroup {
        let id: String
        let items: [Finding]
        let size: Int64
    }

    private func duplicateGroups(_ items: [Finding]) -> [DuplicateGroup] {
        Dictionary(grouping: items) { $0.groupID ?? $0.path }
            .map { id, members in
                // Korunacak kopya en üstte.
                let sorted = members.sorted { !$0.suggested && $1.suggested }
                return DuplicateGroup(id: id, items: sorted, size: members.map(\.bytes).max() ?? 0)
            }
            .sorted { $0.size * Int64($0.items.count) > $1.size * Int64($1.items.count) }
    }
}

private struct FindingRow: View {
    let finding: Finding
    let isSelected: Bool
    let toggle: () -> Void
    let preview: () -> Void
    let reveal: () -> Void
    let ignore: () -> Void

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    var body: some View {
        HStack(spacing: 10) {
            if finding.risk != .info {
                Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!AppModel.isSelectable(finding))
            }

            Image(nsImage: NSWorkspace.shared.icon(forFile: finding.path))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(finding.name).lineLimit(1).truncationMode(.middle)
                    badge
                }
                Text(shortPath(finding.url.deletingLastPathComponent().path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let owner = finding.inUseBy {
                    Text("\(owner) açık — kapatıp yeniden tara")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let note = finding.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let used = finding.lastUsed {
                Text(used.formatted(.relative(presentation: .named).locale(turkish)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
            }
            Text(ByteFormat.string(finding.bytes))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)

            Button(action: preview) { Image(systemName: "eye") }
                .buttonStyle(.borderless)
                .help("Önizle (boşluk tuşu)")
            Button(action: reveal) { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .help("Finder'da göster")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Önizle", action: preview)
            Button("Finder'da göster", action: reveal)
            if AppModel.isSelectable(finding) {
                Button(isSelected ? "Seçimi kaldır" : "Seç", action: toggle)
            }
            Divider()
            Button("Bunu bir daha önerme", action: ignore)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch finding.risk {
        case .safe: tag("silinir", .green)
        case .review: tag(finding.groupID != nil && !finding.suggested ? "korunacak" : "Çöp'e", .orange)
        case .info: tag("bilgi", .gray)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func shortPath(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
