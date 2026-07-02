import SwiftUI
import ZipForgeCore

struct ContentView: View {
    @ObservedObject var viewModel: ArchiveViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                dropZone
                    .frame(width: 300)
                Divider()
                entryList
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
            Button(action: viewModel.createZipPanel) {
                Label("建立 ZIP", systemImage: "archivebox")
            }
            .disabled(viewModel.isWorking)
            Spacer()
            if viewModel.isWorking {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(12)
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.accentColor)
            Text(viewModel.archiveName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(viewModel.selectedFormatDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("拖放 ZIP 檔到這裡")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("拖入檔案或資料夾可建立 ZIP")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            loadDroppedURLs(providers: providers)
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
                VStack(spacing: 0) {
                    entryHeader
                    Divider()
                    List(viewModel.entries) { entry in
                        entryRow(entry)
                            .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var entryHeader: some View {
        HStack(spacing: 12) {
            Text("類型")
                .frame(width: 56, alignment: .leading)
            Text("名稱")
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text("大小")
                .frame(width: 90, alignment: .trailing)
            Text("修改時間")
                .frame(width: 150, alignment: .leading)
            Text("路徑")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func entryRow(_ entry: ArchiveEntry) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: entry.isDirectory ? "folder" : "doc")
                    .foregroundColor(entry.isDirectory ? .accentColor : .secondary)
                Text(entry.typeDescription)
            }
            .frame(width: 56, alignment: .leading)
            Text(entry.name)
                .lineLimit(1)
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text(entry.formattedSize)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(entry.formattedModifiedAt)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(entry.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
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
