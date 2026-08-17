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
    case sevenZip
    case rar
    case tar

    public var displayName: String {
        switch self {
        case .zip:
            return "ZIP"
        case .sevenZip:
            return "7z"
        case .rar:
            return "RAR"
        case .tar:
            return "TAR"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip:
            return "zip"
        case .sevenZip:
            return "7z"
        case .rar:
            return "rar"
        case .tar:
            return "tar"
        }
    }

    public var isSupportedForCreation: Bool {
        switch self {
        case .zip:
            return true
        case .sevenZip, .rar, .tar:
            return false
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
