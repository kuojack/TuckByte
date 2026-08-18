import Foundation
#if SWIFT_PACKAGE
import CZstd
#endif

struct TuckArchiveCompression {
    struct Result {
        let codec: UInt8
        let data: Data
    }

    func compress(_ input: Data, profile: TuckCompressionProfile) throws -> Result {
        guard !input.isEmpty else {
            return Result(codec: TuckArchiveFormat.storeCodec, data: input)
        }

        let bound = ZSTD_compressBound(input.count)
        var output = Data(count: Int(bound))
        let written: Int = input.withUnsafeBytes { sourceBuffer in
            output.withUnsafeMutableBytes { destinationBuffer in
                ZSTD_compress(
                    destinationBuffer.baseAddress,
                    destinationBuffer.count,
                    sourceBuffer.baseAddress,
                    sourceBuffer.count,
                    profile.zstdLevel
                )
            }
        }
        guard ZSTD_isError(written) == 0 else {
            throw ArchiveServiceError.tuckArchiveCodecFailed(
                String(cString: ZSTD_getErrorName(written))
            )
        }

        output.count = written
        // Keep at least a small margin so incompressible data does not grow.
        guard written + 16 < input.count else {
            return Result(codec: TuckArchiveFormat.storeCodec, data: input)
        }
        return Result(codec: TuckArchiveFormat.zstdCodec, data: output)
    }

    func decompress(_ input: Data, codec: UInt8, originalSize: Int) throws -> Data {
        guard originalSize >= 0,
              originalSize <= TuckArchiveLimits.maximumChunkSize else {
            throw ArchiveServiceError.tuckArchiveLimitExceeded("chunk size")
        }
        switch codec {
        case TuckArchiveFormat.storeCodec:
            guard input.count == originalSize else {
                throw ArchiveServiceError.tuckArchiveCorrupt("stored chunk length mismatch")
            }
            return input
        case TuckArchiveFormat.zstdCodec:
            var output = Data(count: originalSize)
            let written: Int = input.withUnsafeBytes { sourceBuffer in
                output.withUnsafeMutableBytes { destinationBuffer in
                    ZSTD_decompress(
                        destinationBuffer.baseAddress,
                        destinationBuffer.count,
                        sourceBuffer.baseAddress,
                        sourceBuffer.count
                    )
                }
            }
            guard ZSTD_isError(written) == 0 else {
                throw ArchiveServiceError.tuckArchiveCodecFailed(
                    String(cString: ZSTD_getErrorName(written))
                )
            }
            guard written == originalSize else {
                throw ArchiveServiceError.tuckArchiveCorrupt("decompressed chunk length mismatch")
            }
            return output
        default:
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature("codec \(codec)")
        }
    }
}
