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
            .disabled(viewModel.archiveURL == nil || viewModel.isWorking)
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
                List(viewModel.entries) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder" : "doc")
                            .foregroundColor(entry.isDirectory ? .accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .lineLimit(1)
                            Text(entry.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
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
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }
                    DispatchQueue.main.async {
                        viewModel.handleDrop(urls: [url])
                    }
                }
                return true
            }
        }
        return false
    }
}

private struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}
