import AppKit
import SwiftUI

/// "Sistem Verileri neden bu kadar büyük?" penceresi.
struct SystemDataView: View {
    let model: AppModel

    var body: some View {
        let rows = model.systemDataRows
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sistem Verileri neden bu kadar büyük?").font(.title2.weight(.semibold))
                Text("Sistem Ayarları → Depolama'daki \"Sistem Verileri\", başka bir yere sığmayan her şeyin toplamıdır ve macOS içini göstermez. Breathy'nin ölçebildiği parçalar:")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.lastScan?.folderSizes == nil {
                Label("Uygulama verileri, önbellekler ve gizli klasörler için önce bir tarama yap.", systemImage: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    SystemDataRowView(row: row) { category in
                        model.openDetails(category)
                    }
                    if row.id != rows.last?.id { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))

            HStack {
                Text("Ölçülebilen toplam: \(ByteFormat.string(rows.reduce(0) { $0 + $1.bytes }))")
                    .fontWeight(.medium)
                    .monospacedDigit()
                Spacer()
            }
            Text("macOS'un kendi dosyaları ve bazı sistem önbellekleri de Sistem Verileri'nde sayılır; bunlar ölçülemez ve silinmemelidir. Apple'ın gösterdiği sayı bu yüzden biraz farklı olabilir.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 600)
    }
}

private struct SystemDataRowView: View {
    let row: SystemDataRow
    let open: (ScanCategory) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.title).fontWeight(.medium)
                    Spacer(minLength: 8)
                    Text(ByteFormat.string(row.bytes)).monospacedDigit().fontWeight(.medium)
                }
                Text(row.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let category = row.category {
                    Button("Detaylarda göster") { open(category) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(12)
    }
}

@MainActor
final class SystemDataWindowController {
    static let shared = SystemDataWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        let view = SystemDataView(model: model)
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Breathy — Sistem Verileri"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
