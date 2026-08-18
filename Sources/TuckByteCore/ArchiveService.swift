import Foundation

public protocol ArchiveService {
    func inspect(archiveURL: URL) throws -> [ArchiveEntry]
    func inspect(archiveURL: URL, password: String?) throws -> [ArchiveEntry]
    func extract(archiveURL: URL, destinationURL: URL) throws
    func extractEntry(
        archiveURL: URL,
        entry: ArchiveEntry,
        destinationURL: URL
    ) throws
    func createZip(from sourceURLs: [URL], destinationURL: URL, settings: CompressionSettings) throws
    func createArchive(from sourceURLs: [URL], destinationURL: URL, settings: CompressionSettings) throws
    func createArchive(
        from sourceURLs: [URL],
        destinationURL: URL,
        settings: CompressionSettings,
        operation: ArchiveOperation?
    ) throws
    func encryptionMethod(archiveURL: URL) throws -> ArchiveEncryptionMethod
    func extract(archiveURL: URL, destinationURL: URL, password: String?) throws
    func extractEntry(
        archiveURL: URL,
        entry: ArchiveEntry,
        destinationURL: URL,
        password: String?
    ) throws
    func changePassword(archiveURL: URL, oldPassword: String, newPassword: String) throws
    func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String?,
        operation: ArchiveOperation?
    ) throws
}

public extension ArchiveService {
    func inspect(archiveURL: URL, password: String?) throws -> [ArchiveEntry] {
        try inspect(archiveURL: archiveURL)
    }

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

    func createArchive(
        from sourceURLs: [URL],
        destinationURL: URL,
        settings: CompressionSettings
    ) throws {
        try createZip(from: sourceURLs, destinationURL: destinationURL, settings: settings)
    }

    func createArchive(
        from sourceURLs: [URL],
        destinationURL: URL,
        settings: CompressionSettings,
        operation: ArchiveOperation?
    ) throws {
        try createArchive(from: sourceURLs, destinationURL: destinationURL, settings: settings)
    }

    func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String?,
        operation: ArchiveOperation?
    ) throws {
        try extract(
            archiveURL: archiveURL,
            destinationURL: destinationURL,
            password: password
        )
    }

    func changePassword(archiveURL: URL, oldPassword: String, newPassword: String) throws {
        throw ArchiveServiceError.tuckArchiveUnsupportedFeature("password change")
    }

    func encryptionMethod(archiveURL: URL) throws -> ArchiveEncryptionMethod {
        .none
    }

    func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String?
    ) throws {
        try extract(archiveURL: archiveURL, destinationURL: destinationURL)
    }

    func extractEntry(
        archiveURL: URL,
        entry: ArchiveEntry,
        destinationURL: URL,
        password: String?
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
            .appendingPathComponent("TuckByte-Entry-\(UUID().uuidString)", isDirectory: true)
        let extractedRoot = stagingRoot.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try extract(
            archiveURL: archiveURL,
            destinationURL: extractedRoot,
            password: password
        )
        let extractedURL = pathComponents.reduce(extractedRoot) {
            $0.appendingPathComponent($1)
        }
        let standardizedRootPath = extractedRoot.standardizedFileURL.path + "/"
        let standardizedExtractedURL = extractedURL.standardizedFileURL
        guard standardizedExtractedURL.path.hasPrefix(standardizedRootPath) else {
            throw ArchiveServiceError.unsafeArchiveEntry(entry.path)
        }
        guard fileManager.fileExists(atPath: standardizedExtractedURL.path) else {
            throw ArchiveServiceError.archiveEntryNotFound(entry.path)
        }
        try fileManager.copyItem(at: standardizedExtractedURL, to: destinationURL)
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
    case archivePasswordRequired
    case incorrectArchivePassword
    case operationCancelled
    case archiveEngineFailed(operation: String, code: Int32)
    case tuckArchiveCorrupt(String)
    case tuckArchiveUnsupportedFeature(String)
    case tuckArchiveLimitExceeded(String)
    case tuckArchiveCodecFailed(String)
    case tuckArchiveCryptoFailed(String)
    case invalidSplitArchiveName(URL)
    case splitArchiveMissingFirstVolume(URL)
    case splitArchiveMissingVolume(URL)
    case splitArchiveIncompleteOrCorrupt(URL)
    case invalidSplitVolumeSize
    case tooManySplitVolumes
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
        case .archivePasswordRequired:
            return "這個壓縮檔已加密，請先輸入密碼。"
        case .incorrectArchivePassword:
            return "密碼不正確，或加密壓縮檔已損壞。"
        case .operationCancelled:
            return "操作已取消。"
        case .archiveEngineFailed(let operation, let code):
            return "\(operation)失敗（錯誤碼 \(code)）。"
        case .tuckArchiveCorrupt(let reason):
            return "TuckByte 壓縮檔已損壞或格式無效：\(reason)。"
        case .tuckArchiveUnsupportedFeature(let feature):
            return "這個 TuckByte 壓縮檔使用尚未支援的功能：\(feature)。"
        case .tuckArchiveLimitExceeded(let limit):
            return "TuckByte 壓縮檔超過安全限制：\(limit)。"
        case .tuckArchiveCodecFailed(let reason):
            return "TuckByte 壓縮引擎失敗：\(reason)。"
        case .tuckArchiveCryptoFailed(let reason):
            return "TuckByte 加密引擎失敗：\(reason)。"
        case .invalidSplitArchiveName(let url):
            return "分割壓縮檔名稱必須為名稱.zip.001 或名稱.tuck.001：\(url.lastPathComponent)"
        case .splitArchiveMissingFirstVolume(let url):
            return "找不到分割壓縮檔的第一卷：\(url.lastPathComponent)"
        case .splitArchiveMissingVolume(let url):
            return "分割壓縮檔缺少分卷：\(url.lastPathComponent)"
        case .splitArchiveIncompleteOrCorrupt(let url):
            return "無法讀取分割壓縮檔，可能缺少最後一卷或檔案已損壞：\(url.lastPathComponent)"
        case .invalidSplitVolumeSize:
            return "分卷大小必須大於 0。"
        case .tooManySplitVolumes:
            return "分割壓縮檔超過 999 卷，請選擇較大的分卷大小。"
        case .commandFailed(let command, let status, let output):
            return "\(command) 執行失敗（狀態碼 \(status)）：\(output)"
        case .couldNotParseArchive:
            return "無法讀取壓縮檔內容。"
        }
    }
}
