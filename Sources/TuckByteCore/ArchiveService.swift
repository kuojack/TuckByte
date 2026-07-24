import Foundation

public protocol ArchiveService {
    func inspect(archiveURL: URL) throws -> [ArchiveEntry]
    func extract(archiveURL: URL, destinationURL: URL) throws
    func extractEntry(
        archiveURL: URL,
        entry: ArchiveEntry,
        destinationURL: URL
    ) throws
    func createZip(from sourceURLs: [URL], destinationURL: URL, settings: CompressionSettings) throws
}

public extension ArchiveService {
    func extractEntry(
        archiveURL: URL,
        entry: ArchiveEntry,
        destinationURL: URL
    ) throws {
        let pathComponents = entry.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !entry.path.hasPrefix("/"),
              !pathComponents.isEmpty,
              pathComponents.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw ArchiveServiceError.unsafeArchiveEntry(entry.path)
        }

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "TuckByte-Entry-\(UUID().uuidString)",
                isDirectory: true
            )
        let extractedRoot = stagingRoot
            .appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true,
            attributes: nil
        )
        defer {
            try? fileManager.removeItem(at: stagingRoot)
        }

        try extract(archiveURL: archiveURL, destinationURL: extractedRoot)
        let extractedURL = pathComponents.reduce(extractedRoot) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        let standardizedRootPath = extractedRoot.standardizedFileURL.path + "/"
        let standardizedExtractedURL = extractedURL.standardizedFileURL
        guard standardizedExtractedURL.path.hasPrefix(standardizedRootPath) else {
            throw ArchiveServiceError.unsafeArchiveEntry(entry.path)
        }
        guard fileManager.fileExists(atPath: standardizedExtractedURL.path) else {
            throw ArchiveServiceError.archiveEntryNotFound(entry.path)
        }

        try fileManager.copyItem(
            at: standardizedExtractedURL,
            to: destinationURL
        )
    }

    func createZip(from sourceURLs: [URL], destinationURL: URL) throws {
        try createZip(from: sourceURLs, destinationURL: destinationURL, settings: .standard)
    }
}

public enum ArchiveServiceError: Error, LocalizedError, Equatable {
    case fileDoesNotExist(URL)
    case destinationAlreadyExists(URL)
    case unsupportedFormat(ArchiveFormat)
    case unsupportedCreationFormat(ArchiveOutputFormat)
    case emptySelection
    case selectionSpansMultipleDirectories
    case unsafeArchiveEntry(String)
    case archiveEntryNotFound(String)
    case encryptionPasswordRequired
    case commandFailed(command: String, status: Int32, output: String)
    case couldNotParseArchive

    public var errorDescription: String? {
        switch self {
        case .fileDoesNotExist(let url):
            return "找不到檔案：\(url.path)"
        case .destinationAlreadyExists(let url):
            return "目的地已經存在，請換一個檔名或位置：\(url.path)"
        case .unsupportedFormat(let format):
            return "\(format.displayName) 格式初版尚未支援。"
        case .unsupportedCreationFormat(let format):
            return "\(format.displayName) 建立功能目前尚未支援。"
        case .emptySelection:
            return "請先選擇要壓縮的檔案或資料夾。"
        case .selectionSpansMultipleDirectories:
            return "選取項目位於不同資料夾，請開啟介面選擇輸出位置。"
        case .unsafeArchiveEntry(let path):
            return "壓縮檔包含不安全的項目路徑：\(path)"
        case .archiveEntryNotFound(let path):
            return "在壓縮檔中找不到項目：\(path)"
        case .encryptionPasswordRequired:
            return "已啟用加密，請輸入密碼。"
        case .commandFailed(let command, let status, let output):
            return "\(command) 執行失敗（狀態碼 \(status)）：\(output)"
        case .couldNotParseArchive:
            return "無法讀取壓縮檔內容。"
        }
    }
}
