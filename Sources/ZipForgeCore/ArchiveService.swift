import Foundation

public protocol ArchiveService {
    func inspect(archiveURL: URL) throws -> [ArchiveEntry]
    func extract(archiveURL: URL, destinationURL: URL) throws
    func createZip(from sourceURLs: [URL], destinationURL: URL, settings: CompressionSettings) throws
}

public extension ArchiveService {
    func createZip(from sourceURLs: [URL], destinationURL: URL) throws {
        try createZip(from: sourceURLs, destinationURL: destinationURL, settings: .standard)
    }
}

public enum ArchiveServiceError: Error, LocalizedError, Equatable {
    case fileDoesNotExist(URL)
    case destinationAlreadyExists(URL)
    case unsupportedFormat(ArchiveFormat)
    case emptySelection
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
        case .emptySelection:
            return "請先選擇要壓縮的檔案或資料夾。"
        case .encryptionPasswordRequired:
            return "已啟用加密，請輸入密碼。"
        case .commandFailed(let command, let status, let output):
            return "\(command) 執行失敗（狀態碼 \(status)）：\(output)"
        case .couldNotParseArchive:
            return "無法讀取壓縮檔內容。"
        }
    }
}
