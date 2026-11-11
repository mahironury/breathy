import AppKit
import SwiftUI

private let turkish = Locale(identifier: "tr_TR")

/// Temizlik geçmişi: ne, ne zaman silindi; ne kadar yer açıldı; hangileri Çöp'e gitti.
struct HistoryView: View {
    let model: AppModel
    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    var body: some View {
        let records = model.history
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Temizlik geçmişi").font(.title2.weight(.semibold))
                if records.isEmpty {
                    Text("Henüz temizlik yapılmadı.").foregroundStyle(.secondary)
                } else {
                    Text("Breathy şimdiye kadar \(ByteFormat.string(CleanHistory.totalFreed(records))) yer açtı · \(records.count) temizlik")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(20)
            Divider()
            if records.isEmpty {
                ContentUnavailableView("Kayıt yok", systemImage: "clock.arrow.circlepath",
                                       description: Text("Temizlediğin her şey burada tarihiyle görünür."))
            } else {
                List(records) { record in
                    if record.items.isEmpty {
                        RecordHeader(record: record)
                    } else {
                        DisclosureGroup {
                            ForEach(record.items, id: \.path) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: item.trashed ? "trash" : "xmark.bin")
                                        .foregroundStyle(item.trashed ? .orange : .green)
                                        .frame(width: 16)
                                    Text(shortPath(item.path)).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(item.trashed ? "Çöp'e" : "silindi").font(.caption).foregroundStyle(.secondary)
                                    Text(ByteFormat.string(item.bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
                                }
                                .font(.callout)
                            }
                            if record.itemCount > record.items.count {
                                Text("+ \(record.itemCount - record.items.count) öğe daha").font(.caption).foregroundStyle(.secondary)
                            }
                        } label: {
                            RecordHeader(record: record)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, minHeight: 380)
    }

    private func shortPath(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct RecordHeader: View {
    let record: CleanRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.kind.icon).foregroundStyle(.tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.kind.title).fontWeight(.medium)
                Text(record.date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(turkish))
                     + (record.itemCount > 0 ? " · \(record.itemCount) öğe" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if record.freedBytes > 0 {
                    Text("\(ByteFormat.string(record.freedBytes)) açıldı").foregroundStyle(.green)
                }
                if record.trashedBytes > 0 {
                    Text("\(ByteFormat.string(record.trashedBytes)) Çöp'e").font(.caption).foregroundStyle(.orange)
                }
            }
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HistoryView(model: model)))
            window.title = "Breathy — Temizlik geçmişi"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 620, height: 460))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
