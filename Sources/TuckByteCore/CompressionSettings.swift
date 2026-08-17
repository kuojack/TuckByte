import Foundation

public struct CompressionSettings: Equatable {
    public var outputFormat: ArchiveOutputFormat
    public var compressionLevel: Int
    public var encryption: ArchiveEncryption
    public var volumeSizeBytes: Int64?

    public init(
        outputFormat: ArchiveOutputFormat = .zip,
        compressionLevel: Int = 6,
        encryption: ArchiveEncryption = .none,
        volumeSizeBytes: Int64? = nil
    ) {
        self.outputFormat = outputFormat
        self.compressionLevel = min(9, max(0, compressionLevel))
        self.encryption = encryption
        self.volumeSizeBytes = volumeSizeBytes
    }

    public static let standard = CompressionSettings()
}

public enum ArchiveOutputFormat: String, CaseIterable, Equatable {
    case zip

    public var displayName: String {
        "ZIP"
    }

    public var fileExtension: String {
        "zip"
    }

    public var isSupportedForCreation: Bool {
        true
    }
}

public enum ArchiveEncryption: Equatable {
    case none
    case zipCrypto(password: String)
    case aes256(password: String)

    public var isEnabled: Bool {
        switch self {
        case .none:
            return false
        case .zipCrypto, .aes256:
            return true
        }
    }
}

public enum ArchiveEncryptionMethod: String, CaseIterable, Equatable {
    case none
    case aes256
    case zipCrypto

    public var displayName: String {
        switch self {
        case .none:
            return "無加密"
        case .aes256:
            return "AES-256（推薦）"
        case .zipCrypto:
            return "ZipCrypto（相容模式）"
        }
    }
}
