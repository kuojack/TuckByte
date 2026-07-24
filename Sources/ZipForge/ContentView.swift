import SwiftUI
import ZipForgeCore

struct ContentView: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @AppStorage("hasShownFinderIntegrationOnboarding")
    private var hasShownFinderIntegrationOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                compressionBrowser
                    .frame(width: 300)
                    .layoutPriority(2)
                Divider()
                entryList
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .layoutPriority(1)
                Divider()
                compressionOptions
                    .frame(width: 270)
                    .layoutPriority(2)
            }
            Divider()
            statusBar
        }
        .alert(item: Binding<AlertMessage?>(
            get: {
                guard let message = viewModel.errorMessage else { return nil }
                return AlertMessage(message: message)
            },
            set: { _ in viewModel.errorMessage = nil }
        )) { alert in
            Alert(title: Text("ZipForge"), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .sheet(
            isPresented: Binding(
                get: { !hasShownFinderIntegrationOnboarding },
                set: { isPresented in
                    if !isPresented {
                        hasShownFinderIntegrationOnboarding = true
                    }
                }
            )
        ) {
            FinderIntegrationOnboardingView {
                hasShownFinderIntegrationOnboarding = true
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: viewModel.openArchivePanel) {
                Label("開啟", systemImage: "folder")
            }
            Button(action: viewModel.extractSelectedArchive) {
                Label("解壓", systemImage: "arrow.down.doc")
            }
            .disabled(!viewModel.hasArchiveLoaded || viewModel.isWorking)
            Button(action: viewModel.wrapSelectedArchive) {
                Label("再壓縮一層", systemImage: "archivebox.fill")
            }
            .disabled(!viewModel.canWrapArchive)
            Button(action: viewModel.createZipPanel) {
                Label("建立 ZIP", systemImage: "archivebox")
            }
            .disabled(viewModel.isWorking)
            Button(action: viewModel.createZipFromPendingItems) {
                Label("壓縮清單", systemImage: "tray.and.arrow.down")
            }
            .disabled(!viewModel.canCreatePendingZip)
            Spacer()
            if viewModel.isWorking {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(12)
    }

    private var compressionBrowser: some View {
        VStack(spacing: 0) {
            HStack {
                Text("待壓縮")
                    .font(.headline)
                Spacer()
                Button(action: viewModel.addPendingItemsPanel) {
                    Image(systemName: "plus")
                }
                .buttonStyle(PlainButtonStyle())
                Button(action: viewModel.clearPendingItems) {
                    Image(systemName: "trash")
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.pendingItems.isEmpty)
            }
            .padding(12)
            Divider()
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundColor(.accentColor)
                Text("把檔案或資料夾拖進來")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("拖入 ZIP 後可解壓或再壓縮一層")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color(NSColor.controlBackgroundColor))
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                loadDroppedURLs(providers: providers)
            }
            Divider()
            if viewModel.pendingItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("清單目前是空的")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.pendingItems) { item in
                        pendingItemRow(item)
                    }
                    .onDelete(perform: viewModel.removePendingItems)
                }
            }
        }
    }

    private func pendingItemRow(_ item: PendingArchiveItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundColor(item.isDirectory ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.typeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(item.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("內容")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.entries.count) 個項目")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            Divider()
            if viewModel.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("尚無內容可顯示")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    let visibility = EntryColumnVisibility(availableWidth: geometry.size.width)

                    VStack(spacing: 0) {
                        entryHeader(visibility: visibility)
                        Divider()
                        List(viewModel.entries) { entry in
                            entryRow(entry, visibility: visibility)
                                .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func entryHeader(visibility: EntryColumnVisibility) -> some View {
        HStack(spacing: 12) {
            Text("類型")
                .frame(width: 56, alignment: .leading)
            Text("名稱")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("大小")
                .frame(width: 76, alignment: .trailing)
            if visibility.showsModifiedAt {
                Text("修改時間")
                    .frame(width: 132, alignment: .leading)
            }
            if visibility.showsPath {
                Text("路徑")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func entryRow(_ entry: ArchiveEntry, visibility: EntryColumnVisibility) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: entry.isDirectory ? "folder" : "doc")
                    .foregroundColor(entry.isDirectory ? .accentColor : .secondary)
                Text(entry.typeDescription)
            }
            .frame(width: 56, alignment: .leading)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.formattedSize)
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .trailing)
            if visibility.showsModifiedAt {
                Text(entry.formattedModifiedAt)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 132, alignment: .leading)
            }
            if visibility.showsPath {
                Text(entry.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 13))
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(viewModel.errorMessage == nil ? .secondary : .red)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var compressionOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("壓縮設定")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("速度")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $viewModel.compressionSpeed) {
                    ForEach(CompressionSpeed.allCases) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("壓縮率")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.compressionLevel.rounded())) / 9")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $viewModel.compressionLevel, in: 0...9, step: 1)
                Text("0 最快但較大，9 最小但較慢。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("格式")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $viewModel.outputFormat) {
                    ForEach(ArchiveOutputFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                Text(viewModel.outputFormat.isSupportedForCreation ? "目前可建立 ZIP。" : "這個格式下一版接 7z/libarchive 後支援。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("啟用傳統 ZIP 加密", isOn: $viewModel.isEncryptionEnabled)
                SecureField("密碼", text: $viewModel.encryptionPassword)
                    .disabled(!viewModel.isEncryptionEnabled)
                SecureField("再次輸入密碼", text: $viewModel.encryptionPasswordConfirmation)
                    .disabled(!viewModel.isEncryptionEnabled)
                Text("初版使用系統 zip 的傳統密碼保護，不是 AES。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: viewModel.createArchiveFromCurrentContext) {
                Label(viewModel.currentContextActionTitle, systemImage: "archivebox.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.canCreateFromCurrentContext)
            .controlSize(.large)
        }
        .padding(14)
    }

    private func loadDroppedURLs(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !fileProviders.isEmpty else { return false }

        var urls: [URL] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            viewModel.handleDrop(urls: urls)
        }
        return true
    }
}

private struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}

private struct EntryColumnVisibility {
    let showsModifiedAt: Bool
    let showsPath: Bool

    init(availableWidth: CGFloat) {
        showsModifiedAt = availableWidth >= 560
        showsPath = availableWidth >= 780
    }
}
