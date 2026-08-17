import AppKit
import Foundation
import TuckByteCore
import UniformTypeIdentifiers

final class ArchiveViewModel: ObservableObject {
    @Published var workspaceMode: WorkspaceMode = .compress
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
    @Published var isSplitArchiveEnabled = false
    @Published var splitVolumeSizePreset: SplitVolumeSizePreset = .hundredMB
    @Published var customSplitVolumeSizeMB = "100"
    @Published var encryptionMethod: ArchiveEncryptionMethod = .none
    @Published var encryptionPassword = ""
    @Published var encryptionPasswordConfirmation = ""
    @Published var archiveEncryptionMethod: ArchiveEncryptionMethod = .none
    @Published var archivePassword = ""
    @Published var statusMessage = "拖放 ZIP 或 7z 檔，或使用工具列開始。"
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

    var archiveIsEncrypted: Bool {
        archiveEncryptionMethod != .none
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

    func openArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["zip", "001", "7z"]
        if panel.runModal() == .OK, let url = panel.url {
            loadArchive(url)
        }
    }

    func loadArchive(_ url: URL) {
        perform("正在讀取 \(url.lastPathComponent)...") {
            let encryptionMethod = try self.archiveService.encryptionMethod(
                archiveURL: url
            )
            let loadedEntries = try self.archiveService.inspect(archiveURL: url)
            DispatchQueue.main.async {
                self.workspaceMode = .extract
                self.archiveURL = url
                self.entries = loadedEntries
                self.currentArchiveDirectoryPath = ""
                self.archiveEncryptionMethod = encryptionMethod
                self.archivePassword = ""
                self.statusMessage = encryptionMethod == .none
                    ? "已讀取 \(loadedEntries.count) 個項目。"
                    : "已讀取 \(loadedEntries.count) 個項目，解壓時需要密碼。"
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
        guard ArchiveFormat(fileURL: url).isSupportedForReading else {
            errorMessage = "目前只能瀏覽 ZIP、分割 ZIP 或 7z 壓縮檔。"
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
            errorMessage = "請先開啟 ZIP 或 7z 壓縮檔。"
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
        let destinationURL = folderURL.appendingPathComponent(
            archiveBaseName(for: archiveURL),
            isDirectory: true
        )
        guard extractionPasswordIsValid else { return }
        let password = archiveIsEncrypted ? archivePassword : nil
        perform("正在解壓到 \(destinationURL.lastPathComponent)...") {
            try self.archiveService.extract(
                archiveURL: archiveURL,
                destinationURL: destinationURL,
                password: password
            )
            DispatchQueue.main.async {
                self.statusMessage = "解壓完成：\(destinationURL.path)"
            }
        }
    }

    func extractEntry(_ entry: ArchiveEntry) {
        guard let archiveURL = archiveURL else {
            errorMessage = "請先開啟 ZIP 或 7z 壓縮檔。"
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
        guard extractionPasswordIsValid else { return }
        let password = archiveIsEncrypted ? archivePassword : nil
        perform("正在解壓 \(entry.name)...") {
            try self.archiveService.extractEntry(
                archiveURL: archiveURL,
                entry: entry,
                destinationURL: destinationURL,
                password: password
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
            let password = self.archiveIsEncrypted ? self.archivePassword : nil
            if self.archiveIsEncrypted && self.archivePassword.isEmpty {
                completion(nil, false, ArchiveServiceError.archivePasswordRequired)
                DispatchQueue.main.async {
                    self.errorMessage = ArchiveServiceError.archivePasswordRequired.errorDescription
                    self.statusMessage = self.errorMessage ?? "無法拖出壓縮項目。"
                }
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
                        destinationURL: destinationURL,
                        password: password
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
        workspaceMode = .compress
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
        workspaceMode = .compress
        archiveURL = nil
        entries = []
        currentArchiveDirectoryPath = ""
        archiveEncryptionMethod = .none
        archivePassword = ""
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
        statusMessage = "正在背景解壓 \(count) 個壓縮檔..."
    }

    func completeFinderExtraction(_ results: [ArchiveExtractionResult]) {
        isWorking = false
        let succeededResults = results.filter(\.succeeded)
        let failedResults = results.filter { !$0.succeeded }

        if failedResults.isEmpty {
            if succeededResults.count == 1, let destinationURL = succeededResults.first?.destinationURL {
                statusMessage = "解壓完成：\(destinationURL.path)"
            } else {
                statusMessage = "已完成 \(succeededResults.count) 個壓縮檔的解壓。"
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
        configureSavePanel(savePanel, baseName: "Archive")
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return }

        perform("正在以目前設定建立 \(destinationURL.lastPathComponent)...") {
            try self.createZip(from: self.pendingItems.map { $0.url }, destinationURL: destinationURL)
        }
    }

    func handleDrop(urls: [URL]) {
        guard !urls.isEmpty else { return }
        switch workspaceMode {
        case .compress:
            addPendingItems(urls)
        case .extract:
            guard urls.count == 1,
                  ArchiveFormat(fileURL: urls[0]).isSupportedForReading else {
                errorMessage = "解壓縮模式只能拖入一個 ZIP、分割 ZIP 或 7z 壓縮檔。"
                statusMessage = errorMessage ?? "操作失敗。"
                return
            }
            loadArchive(urls[0])
        }
    }

    private func createZip(from sourceURLs: [URL], destinationURL: URL) throws {
        let settings = currentCompressionSettings
        try self.archiveService.createZip(
            from: sourceURLs,
            destinationURL: destinationURL,
            settings: settings
        )
        DispatchQueue.main.async {
            self.statusMessage = settings.volumeSizeBytes != nil
                ? "已建立分割 ZIP：\(destinationURL.path)"
                : "已建立 ZIP：\(destinationURL.path)"
        }
    }

    private var currentCompressionSettings: CompressionSettings {
        let encryption: ArchiveEncryption
        switch encryptionMethod {
        case .none:
            encryption = .none
        case .aes256:
            encryption = .aes256(password: encryptionPassword)
        case .zipCrypto:
            encryption = .zipCrypto(password: encryptionPassword)
        }

        return CompressionSettings(
            outputFormat: outputFormat,
            compressionLevel: Int(compressionLevel.rounded()),
            encryption: encryption,
            volumeSizeBytes: splitVolumeSizeBytes
        )
    }

    private var splitVolumeSizeBytes: Int64? {
        guard isSplitArchiveEnabled else { return nil }
        if let presetBytes = splitVolumeSizePreset.volumeSizeBytes {
            return presetBytes
        }
        guard let megabytes = Int64(customSplitVolumeSizeMB), megabytes > 0 else {
            return nil
        }
        return megabytes.multipliedReportingOverflow(by: 1_048_576).overflow
            ? nil
            : megabytes * 1_048_576
    }

    private var encryptionInputsAreValid: Bool {
        encryptionMethod == .none
            || (!encryptionPassword.isEmpty
                && encryptionPassword == encryptionPasswordConfirmation)
    }

    private var extractionPasswordIsValid: Bool {
        guard archiveIsEncrypted && archivePassword.isEmpty else { return true }
        errorMessage = ArchiveServiceError.archivePasswordRequired.errorDescription
        statusMessage = errorMessage ?? "操作失敗。"
        return false
    }

    private var compressionOptionsAreValid: Bool {
        guard encryptionInputsAreValid else {
            errorMessage = encryptionPassword.isEmpty
                ? "請輸入加密密碼。"
                : "兩次輸入的密碼不一致。"
            statusMessage = errorMessage ?? "操作失敗。"
            return false
        }
        if isSplitArchiveEnabled {
            guard outputFormat == .zip else {
                errorMessage = "分割壓縮檔目前只支援 ZIP 格式。"
                statusMessage = errorMessage ?? "操作失敗。"
                return false
            }
            guard let volumeSizeBytes = splitVolumeSizeBytes,
                  volumeSizeBytes >= 1_048_576 else {
                errorMessage = "自訂分卷大小必須是大於或等於 1 的整數 MB。"
                statusMessage = errorMessage ?? "操作失敗。"
                return false
            }
        }
        return true
    }

    private func configureSavePanel(
        _ savePanel: NSSavePanel,
        baseName: String
    ) {
        let suffix = isSplitArchiveEnabled
            ? "zip.001"
            : outputFormat.fileExtension
        savePanel.allowedFileTypes = [isSplitArchiveEnabled ? "001" : suffix]
        savePanel.nameFieldStringValue = "\(baseName).\(suffix)"
        savePanel.isExtensionHidden = false
    }

    private func archiveBaseName(for archiveURL: URL) -> String {
        let logicalURL = SplitZipArchive.logicalArchiveURL(for: archiveURL)
            ?? archiveURL
        let baseName = logicalURL.deletingPathExtension().lastPathComponent
        return baseName.isEmpty ? "Archive" : baseName
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

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case compress
    case extract

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compress:
            return "壓縮"
        case .extract:
            return "解壓縮"
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

enum SplitVolumeSizePreset: String, CaseIterable, Identifiable {
    case tenMB
    case hundredMB
    case oneGB
    case fourGB
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tenMB:
            return "10 MB"
        case .hundredMB:
            return "100 MB"
        case .oneGB:
            return "1 GB"
        case .fourGB:
            return "4 GB"
        case .custom:
            return "自訂"
        }
    }

    var volumeSizeBytes: Int64? {
        switch self {
        case .tenMB:
            return 10 * 1_048_576
        case .hundredMB:
            return 100 * 1_048_576
        case .oneGB:
            return 1_024 * 1_048_576
        case .fourGB:
            return 4_096 * 1_048_576
        case .custom:
            return nil
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
