import SwiftUI

/// Menü çubuğu simgesine basınca açılan panel.
struct MenuPanel: View {
    let model: AppModel

    var body: some View {
        if model.isPrimaryInstance {
            content
        } else {
            Text("Breathy başlıyor…")
                .padding(16)
                .frame(width: 320)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let disk = model.disk {
                DiskGauge(disk: disk)
            } else {
                Text("Disk bilgisi okunamadı.").foregroundStyle(.secondary)
            }

            if let celebration = model.celebration {
                FreedBanner(celebration: celebration)
                    .id(celebration.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                                            removal: .opacity))
            }

            if let swap = model.swap, swap.shouldWarn {
                SwapRow(swap: swap)
            }

            Divider()

            TrashSection(model: model)

            ScanSection(model: model)

            ICloudCard(
                status: model.iCloud,
                summary: model.lastScan?.iCloud,
                screenshotFolder: model.screenshotFolder,
                screenshotsGoToICloud: model.screenshotsGoToICloud,
                moveScreenshots: { model.moveScreenshotsOutOfICloud() }
            )

            if let flash = model.flash {
                Text(flash)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            ForEach(model.oldCopies) { copy in
                OldCopyRow(copy: copy) { model.trashOldCopy(copy) }
            }

            if let update = model.update {
                UpdateRow(version: update.version, isUpdating: model.isUpdating,
                          install: { model.installUpdate() },
                          showNotes: { NSWorkspace.shared.open(update.pageURL) })
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .animation(.easeInOut(duration: 0.2), value: model.flash)
        .animation(.spring(duration: 0.45, bounce: 0.3), value: model.celebration)
        .onAppear { model.panelOpened() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "wind").foregroundStyle(.tint)
            Text("Breathy").font(.headline)
            Spacer()
            Button {
                model.refreshDisk()
                model.refreshTrash(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Yenile")
        }
    }

    private var footer: some View {
        HStack {
            Button("v\(Updater.currentVersion)") { model.checkForUpdates(manual: true) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("Güncellemeleri denetle")
            Button { model.showHistory() } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Temizlik geçmişi")
            loginToggle
            Spacer()
            Button("Çık") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var loginToggle: some View {
        switch model.loginItem {
        case .unavailable:
            EmptyView()
        case .needsApproval:
            Button("Açılışta başlatmayı onayla…") { LoginItem.openSystemSettings() }
                .buttonStyle(.link)
                .font(.caption)
                .help("Sistem Ayarları → Genel → Oturum Açma Öğeleri")
        case .enabled, .disabled:
            Toggle("Açılışta başlat", isOn: Binding(
                get: { model.loginItem == .enabled },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// GitHub'da yeni sürüm varsa: "Yeni sürüm 0.3.0 · Güncelle".
struct UpdateRow: View {
    let version: String
    let isUpdating: Bool
    let install: () -> Void
    let showNotes: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Yeni sürüm: \(version)").fontWeight(.medium)
                Button("Neler yeni?", action: showNotes)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer()
            if isUpdating {
                ProgressView().controlSize(.small)
                Text("Güncelleniyor…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Güncelle", action: install)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }
}

/// Başka bir yerde eski Breathy kopyası varsa: "Eski Breathy kopyası (0.2.0) · Çöp'e taşı".
struct OldCopyRow: View {
    let copy: OldCopy
    let trash: () -> Void

    private var shortPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folder = (copy.path as NSString).deletingLastPathComponent
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.on.square.dashed")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Eski Breathy kopyası").fontWeight(.medium).lineLimit(1)
                Text("\(copy.version) · \(shortPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Çöp'e taşı", action: trash)
                .controlSize(.small)
                .help("Bu kopya çalışıyorsa önce kapatılır, sonra Çöp'e taşınır")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.08)))
    }
}
