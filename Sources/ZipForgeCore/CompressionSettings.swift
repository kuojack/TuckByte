import Foundation

public struct CompressionSettings: Equatable {
    public var compressionLevel: Int
    public var filenameEncoding: ArchiveFilenameEncoding
    public var encryption: ArchiveEncryption

    public init(
        compressionLevel: Int = 6,
        filenameEncoding: ArchiveFilenameEncoding = .utf8,
        encryption: ArchiveEncryption = .none
    ) {
        self.compressionLevel = min(9, max(0, compressionLevel))
        self.filenameEncoding = filenameEncoding
        self.encryption = encryption
    }

    public static let standard = CompressionSettings()
}

public enum ArchiveFilenameEncoding: String, CaseIterable, Equatable {
    case utf8
    case systemDefault
    case traditionalChinese

    public var displayName: String {
        switch self {
        case .utf8:
            return "UTF-8"
        case .systemDefault:
            return "系統預設"
        case .traditionalChinese:
            return "繁體中文 Big5/CP950"
        }
    }
}

public enum ArchiveEncryption: Equatable {
    case none
    case zipCrypto(password: String)

    public var isEnabled: Bool {
        switch self {
        case .none:
            return false
        case .zipCrypto:
            return true
        }
    }
}
