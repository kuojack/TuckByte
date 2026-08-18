import Foundation

public enum SplitZipArchive {
    public static func isVolumeURL(_ url: URL) -> Bool {
        volumeDescriptor(for: url) != nil
    }

    public static func firstVolumeURL(for url: URL) -> URL? {
        guard let descriptor = volumeDescriptor(for: url) else { return nil }
        return descriptor.logicalArchiveURL.appendingPathExtension("001")
    }

    public static func logicalArchiveURL(for url: URL) -> URL? {
        volumeDescriptor(for: url)?.logicalArchiveURL
    }

    public static func volumeURLs(
        startingAt selectedURL: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard let descriptor = volumeDescriptor(for: selectedURL) else {
            throw ArchiveServiceError.invalidSplitArchiveName(selectedURL)
        }

        let parentURL = selectedURL.deletingLastPathComponent()
        let siblingURLs = try fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var volumesByNumber: [Int: URL] = [:]
        for siblingURL in siblingURLs {
            guard let siblingDescriptor = volumeDescriptor(for: siblingURL),
                  siblingDescriptor.logicalArchiveURL.lastPathComponent
                    .caseInsensitiveCompare(
                        descriptor.logicalArchiveURL.lastPathComponent
                    ) == .orderedSame else {
                continue
            }
            volumesByNumber[siblingDescriptor.number] = siblingURL
        }

        guard let firstVolumeURL = volumesByNumber[1] else {
            throw ArchiveServiceError.splitArchiveMissingFirstVolume(
                descriptor.logicalArchiveURL.appendingPathExtension("001")
            )
        }
        guard let highestNumber = volumesByNumber.keys.max() else {
            throw ArchiveServiceError.splitArchiveMissingFirstVolume(firstVolumeURL)
        }

        return try (1...highestNumber).map { number in
            guard let volumeURL = volumesByNumber[number] else {
                throw ArchiveServiceError.splitArchiveMissingVolume(
                    descriptor.logicalArchiveURL.appendingPathExtension(
                        String(format: "%03d", number)
                    )
                )
            }
            return volumeURL
        }
    }

    public static func assemble(
        startingAt selectedURL: URL,
        destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        let volumeURLs = try volumeURLs(
            startingAt: selectedURL,
            fileManager: fileManager
        )

        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: nil,
            attributes: nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let outputHandle = try FileHandle(forWritingTo: destinationURL)
            defer { outputHandle.closeFile() }

            for volumeURL in volumeURLs {
                let inputHandle = try FileHandle(forReadingFrom: volumeURL)
                while true {
                    let data = inputHandle.readData(ofLength: bufferSize)
                    if data.isEmpty { break }
                    outputHandle.write(data)
                }
                inputHandle.closeFile()
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    @discardableResult
    public static func split(
        archiveURL: URL,
        firstVolumeURL: URL,
        volumeSizeBytes: Int64,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard volumeSizeBytes > 0 else {
            throw ArchiveServiceError.invalidSplitVolumeSize
        }
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw ArchiveServiceError.fileDoesNotExist(archiveURL)
        }
        guard let descriptor = volumeDescriptor(for: firstVolumeURL),
              descriptor.number == 1 else {
            throw ArchiveServiceError.invalidSplitArchiveName(firstVolumeURL)
        }

        let existingVolumes = try matchingVolumeURLs(
            for: descriptor.logicalArchiveURL,
            fileManager: fileManager
        )
        if let existingURL = existingVolumes.first {
            throw ArchiveServiceError.destinationAlreadyExists(existingURL)
        }

        let inputHandle = try FileHandle(forReadingFrom: archiveURL)
        defer { inputHandle.closeFile() }

        var createdURLs: [URL] = []
        var outputHandle: FileHandle?
        var currentVolumeSize: Int64 = 0

        func closeOutput() {
            outputHandle?.closeFile()
            outputHandle = nil
            currentVolumeSize = 0
        }

        do {
            while true {
                let data = inputHandle.readData(ofLength: bufferSize)
                if data.isEmpty { break }

                var offset = 0
                while offset < data.count {
                    if outputHandle == nil {
                        let number = createdURLs.count + 1
                        guard number <= 999 else {
                            throw ArchiveServiceError.tooManySplitVolumes
                        }
                        let volumeURL = descriptor.logicalArchiveURL
                            .appendingPathExtension(
                                String(format: "%03d", number)
                            )
                        guard fileManager.createFile(
                            atPath: volumeURL.path,
                            contents: nil,
                            attributes: nil
                        ) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        createdURLs.append(volumeURL)
                        outputHandle = try FileHandle(forWritingTo: volumeURL)
                    }

                    let remainingCapacity = volumeSizeBytes - currentVolumeSize
                    let writeCount = min(
                        data.count - offset,
                        Int(min(remainingCapacity, Int64(Int.max)))
                    )
                    outputHandle?.write(
                        data.subdata(in: offset..<(offset + writeCount))
                    )
                    offset += writeCount
                    currentVolumeSize += Int64(writeCount)

                    if currentVolumeSize == volumeSizeBytes {
                        closeOutput()
                    }
                }
            }
            closeOutput()
            return createdURLs
        } catch {
            closeOutput()
            for createdURL in createdURLs {
                try? fileManager.removeItem(at: createdURL)
            }
            throw error
        }
    }

    private static let bufferSize = 1_048_576

    private struct VolumeDescriptor {
        let logicalArchiveURL: URL
        let number: Int
    }

    private static func volumeDescriptor(for url: URL) -> VolumeDescriptor? {
        let numberText = url.pathExtension
        guard numberText.count == 3,
              numberText.allSatisfy(\.isNumber),
              let number = Int(numberText),
              number > 0 else {
            return nil
        }

        let logicalArchiveURL = url.deletingPathExtension()
        guard logicalArchiveURL.pathExtension.lowercased() == "zip" else {
            return nil
        }
        return VolumeDescriptor(
            logicalArchiveURL: logicalArchiveURL,
            number: number
        )
    }

    private static func matchingVolumeURLs(
        for logicalArchiveURL: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        let parentURL = logicalArchiveURL.deletingLastPathComponent()
        let siblingURLs = try fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return siblingURLs.filter { siblingURL in
            guard let descriptor = volumeDescriptor(for: siblingURL) else {
                return false
            }
            return descriptor.logicalArchiveURL.lastPathComponent
                .caseInsensitiveCompare(logicalArchiveURL.lastPathComponent)
                == .orderedSame
        }
    }
}
