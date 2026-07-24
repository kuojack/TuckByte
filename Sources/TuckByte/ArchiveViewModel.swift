import AppKit
import Foundation
import TuckByteCore
import UniformTypeIdentifiers

final class ArchiveViewModel: ObservableObject {
    @Published var archiveURL: URL?
    @Published var entries: [ArchiveEntry] = []
    @Published var currentArchiveDirectoryPath = ""
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

    var visibleEntries: [ArchiveEntry] {
        ArchiveDirectoryBrowser.entries(
            in: currentArchiveDirectoryPath,
            from: entries
        )
    }

    var archiveBreadcrumbs: [ArchiveBreadcrumb] {
        ArchiveDirectoryBrowser.breadcrumbs(for: currentArchiveDirectoryPath)
    }

    var canNavigateUpArchiveDirectory: Bool {
        !currentArchiveDirectoryPath.isEmpty
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
                self.currentArchiveDirectoryPath = ""
                self.statusMessage = "已讀取 \(loadedEntries.count) 個項目。"
            }
        }
    }

    func openArchiveDirectory(_ entry: ArchiveEntry) {
        guard entry.isDirectory,
              let directoryPath = ArchiveDirectoryBrowser.canonicalDirectoryPath(entry.path) else {
            return
        }
        currentArchiveDirectoryPath = directoryPath
        statusMessage = "正在瀏覽：\(directoryPath)"
    }

    func navigateToArchiveDirectory(_ directoryPath: String) {
        guard let canonicalPath = ArchiveDirectoryBrowser.canonicalDirectoryPath(directoryPath) else {
            return
        }
        currentArchiveDirectoryPath = canonicalPath
        statusMessage = canonicalPath.isEmpty ? "正在瀏覽壓縮檔根目錄。" : "正在瀏覽：\(canonicalPath)"
    }

    func navigateUpArchiveDirectory() {
        navigateToArchiveDirectory(
            ArchiveDirectoryBrowser.parentPath(of: currentArchiveDirectoryPath)
        )
    }

    func openDocumentURL(_ url: URL) {
        guard url.isFileURL else { return }
        guard ArchiveFormat(fileURL: url) == .zip else {
            errorMessage = "目前只能瀏覽 ZIP 壓縮檔。"
            statusMessage = errorMessage ?? "操作失敗。"
            return
        }
        loadArchive(url)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .first(where: { $0.canBecomeKey })?
            .makeKeyAndOrderFront(nil)
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

    func extractEntry(_ entry: ArchiveEntry) {
        guard let archiveURL = archiveURL else {
            errorMessage = "請先開啟一個 ZIP 壓縮檔。"
            return
        }

        let destinationURL: URL?
        if entry.isDirectory {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "解壓至此"
            guard panel.runModal() == .OK, let folderURL = panel.url else {
                return
            }
            destinationURL = folderURL.appendingPathComponent(
                entry.name,
                isDirectory: true
            )
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = entry.name
            panel.prompt = "解壓"
            guard panel.runModal() == .OK else { return }
            destinationURL = panel.url
        }

        guard let destinationURL = destinationURL else { return }
        perform("正在解壓 \(entry.name)...") {
            try self.archiveService.extractEntry(
                archiveURL: archiveURL,
                entry: entry,
                destinationURL: destinationURL
            )
            DispatchQueue.main.async {
                self.statusMessage = "已解壓：\(destinationURL.path)"
            }
        }
    }

    func dragItemProvider(for entry: ArchiveEntry) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = entry.name
        guard let archiveURL = archiveURL else { return provider }

        let typeIdentifier: String
        if entry.isDirectory {
            typeIdentifier = UTType.folder.identifier
        } else {
            typeIdentifier =
                UTType(filenameExtension:
                    URL(fileURLWithPath: entry.name).pathExtension
                )?.identifier
                ?? UTType.data.identifier
        }

        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: [],
            visibility: .all
        ) { [weak self] completion in
            let progress = Progress(totalUnitCount: 100)
            guard let self = self else {
                completion(nil, false, CocoaError(.fileNoSuchFile))
                return progress
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let temporaryRoot = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "TuckByte-Drag-\(UUID().uuidString)",
                        isDirectory: true
                    )
                let destinationURL = temporaryRoot.appendingPathComponent(
                    entry.name,
                    isDirectory: entry.isDirectory
                )

                do {
                    try FileManager.default.createDirectory(
                        at: temporaryRoot,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    try self.archiveService.extractEntry(
                        archiveURL: archiveURL,
                        entry: entry,
                        destinationURL: destinationURL
                    )
                    progress.completedUnitCount = 100
                    completion(destinationURL, false, nil)
                    DispatchQueue.main.async {
                        self.statusMessage = "已準備拖出：\(entry.name)"
                    }
                    Self.removeDragTemporaryDirectoryLater(temporaryRoot)
                } catch {
                    try? FileManager.default.removeItem(at: temporaryRoot)
                    completion(nil, false, error)
                    DispatchQueue.main.async {
                        self.errorMessage =
                            (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                        self.statusMessage =
                            self.errorMessage ?? "無法拖出壓縮項目。"
                    }
                }
            }
            return progress
        }
        return provider
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

    func replacePendingItems(
        _ urls: [URL],
        statusMessage customStatusMessage: String? = nil
    ) {
        archiveURL = nil
        entries = []
        currentArchiveDirectoryPath = ""
        pendingItems = urls.map { PendingArchiveItem(url: $0) }
        errorMessage = nil
        statusMessage = customStatusMessage
            ?? "已從 Finder 加入 \(pendingItems.count) 個項目。"
    }

    func beginFinderCompression(count: Int) {
        errorMessage = nil
        isWorking = true
        statusMessage = "正在背景壓縮 \(count) 個項目..."
    }

    func completeFinderCompression(_ result: ArchiveCompressionResult) {
        isWorking = false
        if let destinationURL = result.destinationURL, result.succeeded {
            errorMessage = nil
            statusMessage = "壓縮完成：\(destinationURL.path)"
            return
        }

        let message = result.errorDescription ?? "無法建立 ZIP。"
        errorMessage = message
        statusMessage = message
    }

    func beginFinderExtraction(count: Int) {
        errorMessage = nil
        isWorking = true
        statusMessage = "正在背景解壓 \(count) 個 ZIP..."
    }

    func completeFinderExtraction(_ results: [ArchiveExtractionResult]) {
        isWorking = false
        let succeededResults = results.filter(\.succeeded)
        let failedResults = results.filter { !$0.succeeded }

        if failedResults.isEmpty {
            if succeededResults.count == 1, let destinationURL = succeededResults.first?.destinationURL {
                statusMessage = "解壓完成：\(destinationURL.path)"
            } else {
                statusMessage = "已完成 \(succeededResults.count) 個 ZIP 的解壓。"
            }
            return
        }

        let failureDetails = failedResults.map {
            "\($0.archiveURL.lastPathComponent)：\($0.errorDescription ?? "未知錯誤")"
        }.joined(separator: "\n")
        errorMessage = "完成 \(succeededResults.count) 個，失敗 \(failedResults.count) 個。\n\(failureDetails)"
        statusMessage = "背景解壓有 \(failedResults.count) 個項目失敗。"
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
            self.currentArchiveDirectoryPath = ""
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

    private static func removeDragTemporaryDirectoryLater(_ url: URL) {
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 600
        ) {
            try? FileManager.default.removeItem(at: url)
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
