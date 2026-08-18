import Foundation

enum TuckArchiveFormat {
    static let magic = Data("TUCKBYTE".utf8)
    static let footerMagic = Data("TUCKEND!".utf8)
    static let chunkMagic = Data("CHNK".utf8)
    static let indexMagic = Data("TIDX".utf8)

    static let majorVersion: UInt16 = 1
    static let minorVersion: UInt16 = 0
    static let headerSize = 128
    static let chunkHeaderSize = 24
    static let footerSize = 96

    static let encryptedFlag: UInt32 = 1 << 0
    static let experimentalFlag: UInt32 = 1 << 31

    static let storeCodec: UInt8 = 0
    static let zstdCodec: UInt8 = 1
    static let aes256GCM: UInt16 = 1
    static let argon2id: UInt16 = 1

    static let defaultChunkSize = 4 * 1_024 * 1_024
    static let defaultArgonMemoryKiB: UInt32 = 64 * 1_024
    static let defaultArgonIterations: UInt32 = 3
    static let defaultArgonParallelism: UInt32 = 4

    /// Authentication data that binds encrypted payloads to immutable archive
    /// identity and format fields. Password/KDF fields are deliberately not
    /// included so a password can be changed by re-wrapping only the DEK.
    static func contentAuthenticationData(
        flags: UInt32,
        chunkSize: UInt32,
        archiveID: Data,
        noncePrefix: Data
    ) -> Data {
        var writer = TuckBinaryWriter()
        writer.append(bytes: magic)
        writer.append(majorVersion)
        writer.append(minorVersion)
        writer.append(flags)
        writer.append(chunkSize)
        writer.append(bytes: archiveID)
        writer.append(bytes: noncePrefix)
        writer.append(UInt16(zstdCodec))
        writer.append(aes256GCM)
        return writer.data
    }
}

public enum TuckCompressionProfile: String, CaseIterable, Equatable {
    case fast
    case balanced
    case maximum

    public var displayName: String {
        switch self {
        case .fast: return "快速"
        case .balanced: return "平衡"
        case .maximum: return "最大壓縮率"
        }
    }

    var zstdLevel: Int32 {
        switch self {
        case .fast: return 1
        case .balanced: return 6
        case .maximum: return 19
        }
    }

    static func fromLegacyLevel(_ level: Int) -> TuckCompressionProfile {
        switch level {
        case ...2: return .fast
        case 8...: return .maximum
        default: return .balanced
        }
    }
}

public enum TuckArchiveLimits {
    public static let maximumPathBytes = 16_384
    public static let maximumEntryCount = 1_000_000
    public static let maximumChunkCount = 4_000_000
    public static let maximumChunkSize = 64 * 1_024 * 1_024
    public static let maximumCompressionRatio: UInt64 = 1_000_000
    public static let maximumIndexSize = 512 * 1_024 * 1_024
    public static let maximumEntrySize: UInt64 = 8 * 1_024 * 1_024 * 1_024 * 1_024
    public static let maximumTotalExtractedSize: UInt64 = 16 * 1_024 * 1_024 * 1_024 * 1_024
    public static let maximumArgonMemoryKiB: UInt32 = 256 * 1_024
    public static let maximumArgonIterations: UInt32 = 20
    public static let maximumArgonParallelism: UInt32 = 64
}

struct TuckArchiveHeader {
    let flags: UInt32
    let chunkSize: UInt32
    let archiveID: Data
    let salt: Data
    let argonMemoryKiB: UInt32
    let argonIterations: UInt32
    let argonParallelism: UInt32
    let noncePrefix: Data
    let wrapNonce: Data
    let wrappedKeyLength: UInt32
    let encoded: Data

    var isEncrypted: Bool {
        flags & TuckArchiveFormat.encryptedFlag != 0
    }
}

struct TuckChunkRecord {
    let sequence: UInt32
    let codec: UInt8
    let recordOffset: UInt64
    let storedLength: UInt32
    let originalLength: UInt32
    let digest: Data
}

struct TuckEntryRecord {
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modifiedNanoseconds: Int64
    let permissions: UInt32
    let chunks: [TuckChunkRecord]
}

struct TuckArchiveFooter {
    let flags: UInt32
    let indexOffset: UInt64
    let indexStoredLength: UInt64
    let indexPlainLength: UInt64
    let indexNonce: Data
    let indexDigest: Data
}
