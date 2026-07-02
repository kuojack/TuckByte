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

    var hasArchiveLoaded: Bool {
        archiveURL != nil
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
            try self.createZip(from: openPanel.urls, destinationURL: destinationURL)
        }
    }

    func createZipFromDroppedItems(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = ["zip"]
        savePanel.nameFieldStringValue = defaultArchiveName(for: urls)
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return }

        perform("正在建立 \(destinationURL.lastPathComponent)...") {
            try self.createZip(from: urls, destinationURL: destinationURL)
        }
    }

    func handleDrop(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count == 1, ArchiveFormat(fileURL: urls[0]).isSupportedInFirstVersion {
            loadArchive(urls[0])
        } else if urls.count == 1 {
            let format = ArchiveFormat(fileURL: urls[0])
            if format == .sevenZip || format == .rar || format == .tar || format == .gzip {
                loadArchive(urls[0])
            } else {
                createZipFromDroppedItems(urls)
            }
        } else {
            createZipFromDroppedItems(urls)
        }
    }

    private func createZip(from sourceURLs: [URL], destinationURL: URL) throws {
        try self.archiveService.createZip(from: sourceURLs, destinationURL: destinationURL)
        let loadedEntries = try self.archiveService.inspect(archiveURL: destinationURL)
        DispatchQueue.main.async {
            self.archiveURL = destinationURL
            self.entries = loadedEntries
            self.statusMessage = "已建立 ZIP：\(destinationURL.path)"
        }
    }

    private func defaultArchiveName(for urls: [URL]) -> String {
        if urls.count == 1 {
            return "\(urls[0].deletingPathExtension().lastPathComponent).zip"
        }
        return "Archive.zip"
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
                    self.statusMessage = self.errorMessage ?? "操作失敗。"
                }
            }
        }
    }
}

extension ArchiveEntry {
    var formattedSize: String {
        guard let size = size else {
            return isDirectory ? "--" : "未知"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedModifiedAt: String {
        guard let modifiedAt = modifiedAt else {
            return "--"
        }
        return ArchiveEntry.displayDateFormatter.string(from: modifiedAt)
    }

    var typeDescription: String {
        isDirectory ? "資料夾" : "檔案"
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
