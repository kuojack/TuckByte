import AppKit
import Foundation
import ZipForgeCore

final class ArchiveViewModel: ObservableObject {
    @Published var archiveURL: URL?
    @Published var entries: [ArchiveEntry] = []
    @Published var statusMessage = "拖放 ZIP 檔或使用工具列開始。"
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let archiveService: ArchiveService

    init(archiveService: ArchiveService = ShellArchiveService()) {
        self.archiveService = archiveService
    }

    var archiveName: String {
        archiveURL?.lastPathComponent ?? "尚未選擇壓縮檔"
    }

    var selectedFormatDescription: String {
        guard let archiveURL = archiveURL else { return "ZIP 初版" }
        return ArchiveFormat(fileURL: archiveURL).displayName
    }

    func openArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["zip", "7z", "rar", "tar", "gz", "tgz"]
        if panel.runModal() == .OK, let url = panel.url {
            loadArchive(url)
        }
    }

    func loadArchive(_ url: URL) {
        perform("正在讀取 \(url.lastPathComponent)...") {
            let loadedEntries = try self.archiveService.inspect(archiveURL: url)
            DispatchQueue.main.async {
                self.archiveURL = url
                self.entries = loadedEntries
                self.statusMessage = "已讀取 \(loadedEntries.count) 個項目。"
            }
        }
    }

    func extractSelectedArchive() {
        guard let archiveURL = archiveURL else {
            errorMessage = "請先開啟一個 ZIP 壓縮檔。"
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選擇"
        if panel.runModal() != .OK {
            return
        }
        guard let folderURL = panel.url else { return }
        let destinationURL = folderURL.appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        perform("正在解壓到 \(destinationURL.lastPathComponent)...") {
            try self.archiveService.extract(archiveURL: archiveURL, destinationURL: destinationURL)
            DispatchQueue.main.async {
                self.statusMessage = "解壓完成：\(destinationURL.path)"
            }
        }
    }

    func createZipPanel() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.prompt = "選擇"
        guard openPanel.runModal() == .OK else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = ["zip"]
        savePanel.nameFieldStringValue = "Archive.zip"
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return }

        perform("正在建立 \(destinationURL.lastPathComponent)...") {
            try self.archiveService.createZip(from: openPanel.urls, destinationURL: destinationURL)
            let loadedEntries = try self.archiveService.inspect(archiveURL: destinationURL)
            DispatchQueue.main.async {
                self.archiveURL = destinationURL
                self.entries = loadedEntries
                self.statusMessage = "已建立 ZIP：\(destinationURL.path)"
            }
        }
    }

    func handleDrop(urls: [URL]) {
        guard let firstURL = urls.first else { return }
        loadArchive(firstURL)
    }

    private func perform(_ message: String, work: @escaping () throws -> Void) {
        errorMessage = nil
        statusMessage = message
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try work()
                DispatchQueue.main.async {
                    self.isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.statusMessage = "操作失敗。"
                }
            }
        }
    }
}
