import SwiftUI
import TuckByteCore

struct ContentView: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @AppStorage("hasShownFinderIntegrationOnboarding")
    private var hasShownFinderIntegrationOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            switch viewModel.workspaceMode {
            case .compress:
                compressionWorkspace
            case .extract:
                extractionWorkspace
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
            Alert(title: Text("TuckByte"), message: Text(alert.message), dismissButton: .default(Text("好")))
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
            Picker("模式", selection: $viewModel.workspaceMode) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 220)

            Divider()
                .frame(height: 22)

            if viewModel.workspaceMode == .compress {
                Button(action: viewModel.addPendingItemsPanel) {
                    Label("加入檔案", systemImage: "plus")
                }
                .disabled(viewModel.isWorking)
                Button(action: viewModel.clearPendingItems) {
                    Label("清除", systemImage: "trash")
                }
                .disabled(viewModel.pendingItems.isEmpty || viewModel.isWorking)
            } else {
                Button(action: viewModel.openArchivePanel) {
                    Label("開啟壓縮檔", systemImage: "folder")
                }
                .disabled(viewModel.isWorking)
                Button(action: viewModel.extractSelectedArchive) {
                    Label("全部解壓", systemImage: "arrow.down.doc")
                }
                .disabled(!viewModel.hasArchiveLoaded || viewModel.isWorking)
            }
            Spacer()
            if viewModel.isWorking {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(12)
    }

    private var compressionWorkspace: some View {
        HStack(spacing: 0) {
            compressionBrowser
                .frame(minWidth: 420, maxWidth: .infinity)
            Divider()
            compressionOptions
                .frame(width: 310)
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            loadDroppedURLs(providers: providers)
        }
    }

    private var extractionWorkspace: some View {
        Group {
            if viewModel.hasArchiveLoaded {
                entryList
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundColor(.accentColor)
                    Text("拖入 .tuck、ZIP 或 7z")
                        .font(.title3.weight(.semibold))
                    Text("也可以使用上方的「開啟壓縮檔」。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            loadDroppedURLs(providers: providers)
        }
    }

    private var compressionBrowser: some View {
        VStack(spacing: 0) {
            HStack {
                Text("待壓縮檔案")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.pendingItems.count) 個項目")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                Text("拖入壓縮檔時，會把它當成一般來源再封裝。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color(NSColor.controlBackgroundColor))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.archiveName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(viewModel.selectedFormatDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(viewModel.visibleEntries.count) 個項目")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            Divider()
            if viewModel.archiveIsEncrypted {
                HStack(spacing: 10) {
                    Label(
                        viewModel.archiveEncryptionMethod.displayName,
                        systemImage: "lock.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    SecureField("輸入解壓密碼", text: $viewModel.archivePassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 220)
                    if viewModel.archiveIndexRequiresUnlock {
                        Button("解鎖內容") {
                            viewModel.unlockArchiveIndex()
                        }
                        .disabled(viewModel.isWorking || viewModel.archivePassword.isEmpty)
                    }
                    Spacer()
                    Text(
                        viewModel.archiveIndexRequiresUnlock
                            ? "密碼也用於解密內容索引"
                            : "解壓全部、單一項目與拖出時使用"
                    )
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
            }
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
                        archiveNavigationBar
                        Divider()
                        entryHeader(visibility: visibility)
                        Divider()
                        if viewModel.visibleEntries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("此資料夾是空的")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(viewModel.visibleEntries) { entry in
                                entryRow(entry, visibility: visibility)
                                    .padding(.vertical, 3)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        viewModel.openArchiveDirectory(entry)
                                    }
                                    .onDrag {
                                        viewModel.dragItemProvider(for: entry)
                                    }
                                    .contextMenu {
                                        if entry.isDirectory {
                                            Button {
                                                viewModel.openArchiveDirectory(entry)
                                            } label: {
                                                Label("打開資料夾", systemImage: "folder")
                                            }
                                        }
                                        Button {
                                            viewModel.extractEntry(entry)
                                        } label: {
                                            Label(
                                                "解壓此項目...",
                                                systemImage: "arrow.down.doc"
                                            )
                                        }
                                        .disabled(viewModel.isWorking)
                                    }
                                    .help(
                                        entry.isDirectory
                                            ? "雙擊進入資料夾；拖到 Finder 可解壓"
                                            : "拖到 Finder 可解壓此項目"
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private var archiveNavigationBar: some View {
        HStack(spacing: 8) {
            Button(action: viewModel.navigateUpArchiveDirectory) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!viewModel.canNavigateUpArchiveDirectory)
            .help("上一層")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(viewModel.archiveBreadcrumbs.enumerated()), id: \.element.id) {
                        index,
                        breadcrumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Button {
                            viewModel.navigateToArchiveDirectory(breadcrumb.path)
                        } label: {
                            if index == 0 {
                                Image(systemName: "archivebox")
                            } else {
                                Text(breadcrumb.name)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(
                            breadcrumb.path == viewModel.currentArchiveDirectoryPath
                                ? .primary
                                : .accentColor
                        )
                        .help(index == 0 ? "壓縮檔根目錄" : breadcrumb.path)
                    }
                }
            }
        }
        .font(.system(size: 13))
        .frame(height: 34)
        .padding(.horizontal, 12)
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
            HStack(spacing: 6) {
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.isDirectory {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
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
        HStack(spacing: 10) {
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(viewModel.errorMessage == nil ? .secondary : .red)
                .lineLimit(1)
            Spacer()
            if let progress = viewModel.operationProgress {
                ProgressView(value: progress.fractionCompleted)
                    .frame(width: 140)
                Text("\(Int(progress.fractionCompleted * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Button("取消") {
                    viewModel.cancelCurrentOperation()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var compressionOptions: some View {
        VStack(spacing: 0) {
            ScrollView {
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
                        .pickerStyle(SegmentedPickerStyle())
                        Text(
                            viewModel.outputFormat == .tuck
                                ? "自有格式：Zstd、加密索引與 AES-256-GCM。"
                                : "通用 ZIP 格式，適合跨平台分享。"
                        )
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("分割壓縮檔", isOn: $viewModel.isSplitArchiveEnabled)
                        if viewModel.isSplitArchiveEnabled {
                            Picker("每卷大小", selection: $viewModel.splitVolumeSizePreset) {
                                ForEach(SplitVolumeSizePreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            if viewModel.splitVolumeSizePreset == .custom {
                                HStack(spacing: 8) {
                                    TextField(
                                        "大小",
                                        text: $viewModel.customSplitVolumeSizeMB
                                    )
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    Text("MB")
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text(
                                "輸出為 .\(viewModel.outputFormat.fileExtension).001、.002、.003 連續分卷。"
                            )
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("加密")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Picker("", selection: $viewModel.encryptionMethod) {
                            ForEach(viewModel.availableEncryptionMethods, id: \.self) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        .labelsHidden()
                        if viewModel.encryptionMethod != .none {
                            SecureField("密碼", text: $viewModel.encryptionPassword)
                            SecureField(
                                "再次輸入密碼",
                                text: $viewModel.encryptionPasswordConfirmation
                            )
                        }
                        Text(encryptionHelpText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
            }

            Divider()
            Button(action: viewModel.createZipFromPendingItems) {
                Label(
                    "建立 \(viewModel.outputFormat.displayName)",
                    systemImage: "archivebox.fill"
                )
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.canCreatePendingZip)
            .controlSize(.large)
            .padding(14)
        }
    }

    private var encryptionHelpText: String {
        switch viewModel.encryptionMethod {
        case .none:
            return "不使用密碼保護。"
        case .aes256:
            return viewModel.outputFormat == .tuck
                ? "Argon2id + AES-256-GCM；索引、內容與檔名都受到保護。"
                : "安全性較高；Windows 建議使用 7-Zip，macOS 可用 TuckByte 解壓。"
        case .zipCrypto:
            return "相容性較廣，但安全性較低，不適合敏感資料。"
        }
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
