import Foundation

/// Bounded random-access reader over one `.tuck` file or consecutive volumes.
/// Split reads cross volume boundaries directly and never assemble a full temp file.
final class TuckArchiveDataSource {
    let size: UInt64

    private struct Volume {
        let start: UInt64
        let size: UInt64
        let handle: FileHandle
    }

    private let volumes: [Volume]

    init(archiveURL: URL, fileManager: FileManager = .default) throws {
        let urls: [URL]
        if SplitTuckArchive.isVolumeURL(archiveURL) {
            urls = try SplitTuckArchive.volumeURLs(
                startingAt: archiveURL,
                fileManager: fileManager
            )
        } else {
            guard fileManager.fileExists(atPath: archiveURL.path) else {
                throw ArchiveServiceError.fileDoesNotExist(archiveURL)
            }
            urls = [archiveURL]
        }

        var created: [Volume] = []
        var offset: UInt64 = 0
        do {
            for url in urls {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                guard let sizeNumber = attributes[.size] as? NSNumber else {
                    throw ArchiveServiceError.tuckArchiveCorrupt("missing volume size")
                }
                let volumeSize = sizeNumber.uint64Value
                guard volumeSize > 0, offset <= UInt64.max - volumeSize else {
                    throw ArchiveServiceError.tuckArchiveCorrupt("invalid volume size")
                }
                created.append(Volume(
                    start: offset,
                    size: volumeSize,
                    handle: try FileHandle(forReadingFrom: url)
                ))
                offset += volumeSize
            }
        } catch {
            created.forEach { $0.handle.closeFile() }
            throw error
        }
        guard !created.isEmpty else {
            throw ArchiveServiceError.tuckArchiveCorrupt("archive has no volumes")
        }
        volumes = created
        size = offset
    }

    deinit {
        volumes.forEach { $0.handle.closeFile() }
    }

    func read(offset: UInt64, count: Int) throws -> Data {
        guard count >= 0,
              offset <= size,
              UInt64(count) <= size - offset else {
            throw ArchiveServiceError.tuckArchiveCorrupt("record exceeds archive bounds")
        }
        if count == 0 { return Data() }

        var result = Data()
        result.reserveCapacity(count)
        var logicalOffset = offset
        var remaining = count
        for volume in volumes {
            guard remaining > 0 else { break }
            let volumeEnd = volume.start + volume.size
            guard logicalOffset < volumeEnd else { continue }
            guard logicalOffset >= volume.start else { continue }
            let localOffset = logicalOffset - volume.start
            let available = volume.size - localOffset
            let readCount = Int(min(UInt64(remaining), available))
            try volume.handle.seek(toOffset: localOffset)
            let data = volume.handle.readData(ofLength: readCount)
            guard data.count == readCount else {
                throw ArchiveServiceError.tuckArchiveCorrupt("unexpected end of volume")
            }
            result.append(data)
            logicalOffset += UInt64(readCount)
            remaining -= readCount
        }
        guard remaining == 0 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("missing split volume data")
        }
        return result
    }
}
