import AppKit
import Foundation
import ZipForgeCore

final class ArchiveViewModel: ObservableObject {
    @Published var archiveURL: URL?
    @Published var entries: [ArchiveEntry] = []
    @Published var pendingItems: [PendingArchiveItem] = []
    @Published var compressionLevel: Double = 6
    @Published var compressionSpeed: CompressionSpeed = .balanced {
        didSet {
            compressionLevel = Double(compressionSpeed.defaultCompressionLevel)
        }
    }
    @Published var outputFormat: ArchiveOutputFormat = .zip
    @Published var isEncryptionEnabled = false
    @Published var encryptionPassword = ""
    @Published var encryptionPasswordConfirmation = ""
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

    var canCreatePendingZip: Bool {
        !pendingItems.isEmpty && !isWorking
    }

    var canWrapArchive: Bool {
        hasArchiveLoaded && !isWorking
    }

    var canCreateFromCurrentContext: Bool {
        canCreatePendingZip || canWrapArchive
    }

    var currentContextActionTitle: String {
        pendingItems.isEmpty && hasArchiveLoaded ? "再壓縮一層" : "建立壓縮檔"
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

    func addPendingItemsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "加入"
        if panel.runModal() == .OK {
            addPendingItems(panel.urls)
        }
    }

    func addPendingItems(_ urls: [URL]) {
        let newItems = urls
            .filter { url in
                !pendingItems.contains { $0.url == url }
            }
            .map { PendingArchiveItem(url: $0) }

        guard !newItems.isEmpty else {
            statusMessage = "檔案已在待壓縮清單中。"
            return
        }
        pendingItems.append(contentsOf: newItems)
        statusMessage = "已加入 \(newItems.count) 個項目到待壓縮清單。"
    }

    func removePendingItems(at offsets: IndexSet) {
        pendingItems.remove(atOffsets: offsets)
        statusMessage = pendingItems.isEmpty ? "待壓縮清單已清空。" : "已移除項目。"
    }

    func clearPendingItems() {
        pendingItems.removeAll()
        statusMessage = "待壓縮清單已清空。"
    }

    func createZipFromPendingItems() {
        guard !pendingItems.isEmpty else {
            errorMessage = "請先把檔案或資料夾拖進待壓縮清單。"
            return
        }
        guard compressionOptionsAreValid else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = [outputFormat.fileExtension]
        savePanel.nameFieldStringValue = "Archive.\(outputFormat.fileExtension)"
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return }

        perform("正在以目前設定建立 \(destinationURL.lastPathComponent)...") {
            try self.createZip(from: self.pendingItems.map { $0.url }, destinationURL: destinationURL)
        }
    }

    func createArchiveFromCurrentContext() {
        if !pendingItems.isEmpty {
            createZipFromPendingItems()
        } else {
            wrapSelectedArchive()
        }
    }

    func wrapSelectedArchive() {
        guard let sourceArchiveURL = archiveURL else {
            errorMessage = "請先開啟要再壓縮一層的 ZIP。"
            statusMessage = errorMessage ?? "操作失敗。"
            return
        }
        guard compressionOptionsAreValid else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = [outputFormat.fileExtension]
        savePanel.nameFieldStringValue = "\(sourceArchiveURL.deletingPathExtension().lastPathComponent)-外層.\(outputFormat.fileExtension)"
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return }

        perform("正在把 \(sourceArchiveURL.lastPathComponent) 再壓縮一層...") {
            try self.createZip(from: [sourceArchiveURL], destinationURL: destinationURL)
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
                addPendingItems(urls)
            }
        } else {
            addPendingItems(urls)
        }
    }

    private func createZip(from sourceURLs: [URL], destinationURL: URL) throws {
        try self.archiveService.createZip(from: sourceURLs, destinationURL: destinationURL, settings: currentCompressionSettings)
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

    private var currentCompressionSettings: CompressionSettings {
        let encryption: ArchiveEncryption
        if isEncryptionEnabled {
            encryption = .zipCrypto(password: encryptionPassword)
        } else {
            encryption = .none
        }

        return CompressionSettings(
            outputFormat: outputFormat,
            compressionLevel: Int(compressionLevel.rounded()),
            encryption: encryption
        )
    }

    private var encryptionInputsAreValid: Bool {
        !isEncryptionEnabled || encryptionPassword == encryptionPasswordConfirmation
    }

    private var compressionOptionsAreValid: Bool {
        guard outputFormat.isSupportedForCreation else {
            errorMessage = "\(outputFormat.displayName) 建立功能下一版才會支援，目前請先選 ZIP。"
            statusMessage = errorMessage ?? "操作失敗。"
            return false
        }
        guard encryptionInputsAreValid else {
            errorMessage = "兩次輸入的密碼不一致。"
            statusMessage = errorMessage ?? "操作失敗。"
            return false
        }
        return true
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

struct PendingArchiveItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    var name: String {
        url.lastPathComponent
    }

    var path: String {
        url.path
    }

    var isDirectory: Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    var typeDescription: String {
        isDirectory ? "資料夾" : "檔案"
    }
}

enum CompressionSpeed: String, CaseIterable, Identifiable {
    case fastest
    case balanced
    case smallest

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .fastest:
            return "最快速度"
        case .balanced:
            return "平衡"
        case .smallest:
            return "最小檔案"
        }
    }

    var defaultCompressionLevel: Int {
        switch self {
        case .fastest:
            return 1
        case .balanced:
            return 6
        case .smallest:
            return 9
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
