import Foundation

/// Sequential transactional output for one archive or numbered `.tuck` volumes.
/// Split mode keeps only the active volume open and never materializes a full archive.
final class TuckArchiveOutputSink {
    private let fileManager: FileManager
    private let destinationURL: URL
    private let volumeSize: Int64?
    private let transactionID = UUID().uuidString

    private var handle: FileHandle?
    private var currentVolumeBytes: Int64 = 0
    private var temporaryURLs: [URL] = []
    private var finalURLs: [URL] = []
    private var committed = false

    private(set) var offset: UInt64 = 0

    init(
        destinationURL: URL,
        volumeSizeBytes: Int64?,
        fileManager: FileManager = .default
    ) throws {
        self.destinationURL = destinationURL
        self.volumeSize = volumeSizeBytes
        self.fileManager = fileManager

        if let volumeSizeBytes = volumeSizeBytes {
            guard volumeSizeBytes > 0 else {
                throw ArchiveServiceError.invalidSplitVolumeSize
            }
            guard SplitTuckArchive.firstVolumeURL(for: destinationURL)?.standardizedFileURL
                    == destinationURL.standardizedFileURL else {
                throw ArchiveServiceError.invalidSplitArchiveName(destinationURL)
            }
            try rejectExistingVolumes()
        } else if fileManager.fileExists(atPath: destinationURL.path) {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
    }

    deinit {
        if !committed { abort() }
    }

    func write(_ data: Data) throws {
        var dataOffset = 0
        while dataOffset < data.count {
            if handle == nil { try openNextOutput() }
            let capacity: Int
            if let volumeSize = volumeSize {
                capacity = Int(min(
                    Int64(data.count - dataOffset),
                    volumeSize - currentVolumeBytes
                ))
            } else {
                capacity = data.count - dataOffset
            }
            guard capacity > 0 else {
                try closeCurrentOutput()
                continue
            }
            handle?.write(data.subdata(in: dataOffset..<(dataOffset + capacity)))
            dataOffset += capacity
            currentVolumeBytes += Int64(capacity)
            guard offset <= UInt64.max - UInt64(capacity) else {
                throw ArchiveServiceError.tuckArchiveLimitExceeded("archive output size")
            }
            offset += UInt64(capacity)
            if let volumeSize = volumeSize, currentVolumeBytes == volumeSize {
                try closeCurrentOutput()
            }
        }
    }

    func finish() throws {
        try closeCurrentOutput()
        guard !temporaryURLs.isEmpty else {
            throw ArchiveServiceError.tuckArchiveCorrupt("empty archive output")
        }
        var movedURLs: [URL] = []
        do {
            for (temporaryURL, finalURL) in zip(temporaryURLs, finalURLs) {
                try fileManager.moveItem(at: temporaryURL, to: finalURL)
                movedURLs.append(finalURL)
            }
            committed = true
            temporaryURLs.removeAll()
        } catch {
            movedURLs.forEach { try? fileManager.removeItem(at: $0) }
            abort()
            throw error
        }
    }

    func abort() {
        handle?.closeFile()
        handle = nil
        temporaryURLs.forEach { try? fileManager.removeItem(at: $0) }
        temporaryURLs.removeAll()
    }

    private func openNextOutput() throws {
        let finalURL: URL
        if volumeSize != nil {
            let number = finalURLs.count + 1
            guard number <= 999 else {
                throw ArchiveServiceError.tooManySplitVolumes
            }
            guard let logicalURL = SplitTuckArchive.logicalArchiveURL(for: destinationURL) else {
                throw ArchiveServiceError.invalidSplitArchiveName(destinationURL)
            }
            finalURL = logicalURL.appendingPathExtension(String(format: "%03d", number))
        } else {
            guard finalURLs.isEmpty else {
                throw ArchiveServiceError.tuckArchiveCorrupt("unexpected extra output file")
            }
            finalURL = destinationURL
        }

        let temporaryURL = finalURL.deletingLastPathComponent().appendingPathComponent(
            ".\(finalURL.lastPathComponent).partial-\(transactionID)"
        )
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            handle = try FileHandle(forWritingTo: temporaryURL)
            temporaryURLs.append(temporaryURL)
            finalURLs.append(finalURL)
            currentVolumeBytes = 0
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func closeCurrentOutput() throws {
        guard let handle = handle else { return }
        try handle.synchronize()
        handle.closeFile()
        self.handle = nil
        currentVolumeBytes = 0
    }

    private func rejectExistingVolumes() throws {
        guard let logicalURL = SplitTuckArchive.logicalArchiveURL(for: destinationURL) else {
            throw ArchiveServiceError.invalidSplitArchiveName(destinationURL)
        }
        let siblings = try fileManager.contentsOfDirectory(
            at: logicalURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if let existing = siblings.first(where: { candidate in
            guard SplitTuckArchive.isVolumeURL(candidate),
                  let candidateLogical = SplitTuckArchive.logicalArchiveURL(for: candidate) else {
                return false
            }
            return candidateLogical.lastPathComponent.caseInsensitiveCompare(
                logicalURL.lastPathComponent
            ) == .orderedSame
        }) {
            throw ArchiveServiceError.destinationAlreadyExists(existing)
        }
    }
}
