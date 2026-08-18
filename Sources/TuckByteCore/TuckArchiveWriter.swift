import Foundation
import CryptoKit

final class TuckArchiveWriter {
    private let fileManager: FileManager
    private let compression = TuckArchiveCompression()
    private let crypto = TuckArchiveCrypto()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func create(
        from sourceURLs: [URL],
        destinationURL: URL,
        settings: CompressionSettings,
        operation: ArchiveOperation? = nil
    ) throws {
        try operation?.checkCancellation()
        operation?.update(phase: .scanning, completedBytes: 0, totalBytes: 0)
        guard !sourceURLs.isEmpty else {
            throw ArchiveServiceError.emptySelection
        }
        let sources = try collectSources(sourceURLs)
        guard sources.count <= TuckArchiveLimits.maximumEntryCount else {
            throw ArchiveServiceError.tuckArchiveLimitExceeded("entry count")
        }
        var pathKeys = Set<String>()
        var totalSize: UInt64 = 0
        for source in sources {
            let key = source.archivePath.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            guard pathKeys.insert(key).inserted else {
                throw ArchiveServiceError.tuckArchiveCorrupt(
                    "case-insensitive path collision: \(source.archivePath)"
                )
            }
            guard totalSize <= TuckArchiveLimits.maximumTotalExtractedSize - source.size else {
                throw ArchiveServiceError.tuckArchiveLimitExceeded("total source size")
            }
            totalSize += source.size
        }

        let output = try TuckArchiveOutputSink(
            destinationURL: destinationURL,
            volumeSizeBytes: settings.volumeSizeBytes,
            fileManager: fileManager
        )
        do {
            try write(
                sources: sources,
                to: output,
                settings: settings,
                totalSourceSize: totalSize,
                operation: operation
            )
            try operation?.checkCancellation()
            operation?.update(
                phase: .finalizing,
                completedBytes: totalSize,
                totalBytes: totalSize
            )
            try output.finish()
        } catch {
            output.abort()
            throw error
        }
    }

    private func write(
        sources: [SourceEntry],
        to output: TuckArchiveOutputSink,
        settings: CompressionSettings,
        totalSourceSize: UInt64,
        operation: ArchiveOperation?
    ) throws {
        try operation?.checkCancellation()
        let encryptionPassword: String?
        switch settings.encryption {
        case .none:
            encryptionPassword = nil
        case .aes256(let password):
            guard !password.isEmpty else {
                throw ArchiveServiceError.encryptionPasswordRequired
            }
            encryptionPassword = password
        case .zipCrypto:
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature("ZipCrypto")
        }

        let archiveID = try crypto.randomBytes(count: 16)
        let salt = encryptionPassword == nil
            ? Data(repeating: 0, count: 16)
            : try crypto.randomBytes(count: 16)
        let noncePrefix = try crypto.randomBytes(count: 8)
        let wrapNonce = encryptionPassword == nil
            ? Data(repeating: 0, count: 12)
            : try crypto.randomBytes(count: 12)
        let flags = TuckArchiveFormat.experimentalFlag
            | (encryptionPassword == nil ? 0 : TuckArchiveFormat.encryptedFlag)
        let headerData = Self.encodeHeader(
            flags: flags,
            archiveID: archiveID,
            salt: salt,
            noncePrefix: noncePrefix,
            wrapNonce: wrapNonce,
            wrappedKeyLength: encryptionPassword == nil ? 0 : 48
        )
        let contentAAD = TuckArchiveFormat.contentAuthenticationData(
            flags: flags,
            chunkSize: UInt32(TuckArchiveFormat.defaultChunkSize),
            archiveID: archiveID,
            noncePrefix: noncePrefix
        )

        var archiveKeys: TuckArchiveCrypto.Keys?
        var wrappedKey = Data()
        if let password = encryptionPassword {
            var dataEncryptionKey = try crypto.randomBytes(count: 32)
            defer {
                dataEncryptionKey.resetBytes(in: 0..<dataEncryptionKey.count)
            }
            let passwordKey = try crypto.derivePasswordKey(
                password: password,
                salt: salt,
                memoryKiB: TuckArchiveFormat.defaultArgonMemoryKiB,
                iterations: TuckArchiveFormat.defaultArgonIterations,
                parallelism: TuckArchiveFormat.defaultArgonParallelism
            )
            wrappedKey = try crypto.seal(
                dataEncryptionKey,
                using: passwordKey,
                nonceData: wrapNonce,
                authenticating: headerData
            )
            guard wrappedKey.count == 48 else {
                throw ArchiveServiceError.tuckArchiveCryptoFailed("wrapped key length")
            }
            archiveKeys = crypto.deriveArchiveKeys(
                dataEncryptionKey: dataEncryptionKey,
                archiveID: archiveID
            )
        }

        try output.write(headerData)
        try output.write(wrappedKey)

        let profile = TuckCompressionProfile.fromLegacyLevel(settings.compressionLevel)
        var entryRecords: [TuckEntryRecord] = []
        entryRecords.reserveCapacity(sources.count)
        var nextSequence: UInt32 = 1
        var completedBytes: UInt64 = 0
        let workerCount = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 8))

        for source in sources {
            try operation?.checkCancellation()
            if source.isDirectory {
                entryRecords.append(TuckEntryRecord(
                    path: source.archivePath,
                    isDirectory: true,
                    size: 0,
                    modifiedNanoseconds: source.modifiedNanoseconds,
                    permissions: source.permissions,
                    chunks: []
                ))
                continue
            }

            let input = try FileHandle(forReadingFrom: source.url)
            var chunks: [TuckChunkRecord] = []
            var bytesRead: UInt64 = 0
            do {
                defer { input.closeFile() }
                while true {
                    try operation?.checkCancellation()
                    var batch: [PendingChunk] = []
                    batch.reserveCapacity(workerCount * 2)
                    while batch.count < workerCount * 2 {
                        let raw = input.readData(ofLength: TuckArchiveFormat.defaultChunkSize)
                        if raw.isEmpty { break }
                        guard nextSequence < UInt32.max else {
                            throw ArchiveServiceError.tuckArchiveLimitExceeded("chunk sequence")
                        }
                        batch.append(PendingChunk(sequence: nextSequence, raw: raw))
                        nextSequence += 1
                    }
                    if batch.isEmpty { break }
                    let prepared = try prepareChunks(
                        batch,
                        profile: profile,
                        archiveKeys: archiveKeys,
                        noncePrefix: noncePrefix,
                        contentAAD: contentAAD,
                        workerCount: workerCount,
                        operation: operation
                    )
                    for chunk in prepared {
                        try operation?.checkCancellation()
                        let recordOffset = output.offset
                        try output.write(chunk.header)
                        try output.write(chunk.stored)
                        chunks.append(TuckChunkRecord(
                            sequence: chunk.sequence,
                            codec: chunk.codec,
                            recordOffset: recordOffset,
                            storedLength: UInt32(chunk.stored.count),
                            originalLength: chunk.originalLength,
                            digest: chunk.digest
                        ))
                        let count = UInt64(chunk.originalLength)
                        bytesRead += count
                        completedBytes += count
                        operation?.update(
                            phase: .compressing,
                            completedBytes: completedBytes,
                            totalBytes: totalSourceSize
                        )
                    }
                }
            }

            guard bytesRead == source.size else {
                throw ArchiveServiceError.tuckArchiveCorrupt(
                    "source file changed while archiving: \(source.archivePath)"
                )
            }
            entryRecords.append(TuckEntryRecord(
                path: source.archivePath,
                isDirectory: false,
                size: source.size,
                modifiedNanoseconds: source.modifiedNanoseconds,
                permissions: source.permissions,
                chunks: chunks
            ))
        }

        try operation?.checkCancellation()
        operation?.update(
            phase: .writingIndex,
            completedBytes: completedBytes,
            totalBytes: totalSourceSize
        )
        let plainIndex = try encodeIndex(entryRecords)
        guard plainIndex.count <= TuckArchiveLimits.maximumIndexSize else {
            throw ArchiveServiceError.tuckArchiveLimitExceeded("index size")
        }
        let indexOffset = output.offset
        let indexNonce = try crypto.nonce(prefix: noncePrefix, counter: UInt32.max)
        let storedIndex: Data
        if let keys = archiveKeys {
            var aad = contentAAD
            aad.append(contentsOf: "TUCKBYTE-INDEX-v1".utf8)
            storedIndex = try crypto.seal(
                plainIndex,
                using: keys.indexKey,
                nonceData: indexNonce,
                authenticating: aad
            )
        } else {
            storedIndex = plainIndex
        }
        try output.write(storedIndex)
        let footer = encodeFooter(
            flags: flags,
            indexOffset: indexOffset,
            indexStoredLength: UInt64(storedIndex.count),
            indexPlainLength: UInt64(plainIndex.count),
            indexNonce: indexNonce,
            indexDigest: crypto.sha256(storedIndex)
        )
        try output.write(footer)
    }

    private func prepareChunks(
        _ pending: [PendingChunk],
        profile: TuckCompressionProfile,
        archiveKeys: TuckArchiveCrypto.Keys?,
        noncePrefix: Data,
        contentAAD: Data,
        workerCount: Int,
        operation: ArchiveOperation?
    ) throws -> [PreparedChunk] {
        var results = Array<PreparedChunk?>(repeating: nil, count: pending.count)
        var firstError: Error?
        let lock = NSLock()
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: workerCount)

        for index in pending.indices {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                semaphore.wait()
                defer {
                    semaphore.signal()
                    group.leave()
                }
                do {
                    try operation?.checkCancellation()
                    let item = pending[index]
                    let compressed = try self.compression.compress(item.raw, profile: profile)
                    let storedLength = compressed.data.count + (archiveKeys == nil ? 0 : 16)
                    guard storedLength <= Int(UInt32.max) else {
                        throw ArchiveServiceError.tuckArchiveLimitExceeded("stored chunk length")
                    }
                    let header = self.encodeChunkHeader(
                        sequence: item.sequence,
                        codec: compressed.codec,
                        encrypted: archiveKeys != nil,
                        originalLength: UInt32(item.raw.count),
                        storedLength: UInt32(storedLength)
                    )
                    let stored: Data
                    if let keys = archiveKeys {
                        let nonce = try self.crypto.nonce(
                            prefix: noncePrefix,
                            counter: item.sequence
                        )
                        var aad = contentAAD
                        aad.append(header)
                        stored = try self.crypto.seal(
                            compressed.data,
                            using: keys.dataKey,
                            nonceData: nonce,
                            authenticating: aad
                        )
                    } else {
                        stored = compressed.data
                    }
                    let result = PreparedChunk(
                        sequence: item.sequence,
                        codec: compressed.codec,
                        originalLength: UInt32(item.raw.count),
                        header: header,
                        stored: stored,
                        digest: self.crypto.sha256(item.raw)
                    )
                    lock.lock()
                    results[index] = result
                    lock.unlock()
                } catch {
                    lock.lock()
                    if firstError == nil { firstError = error }
                    lock.unlock()
                }
            }
        }
        group.wait()
        if let firstError = firstError { throw firstError }
        return try results.map { result in
            guard let result = result else {
                throw ArchiveServiceError.tuckArchiveCodecFailed("parallel chunk pipeline")
            }
            return result
        }
    }

    private func collectSources(_ sourceURLs: [URL]) throws -> [SourceEntry] {
        var result: [SourceEntry] = []
        var usedRootNames = Set<String>()

        for sourceURL in sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ArchiveServiceError.fileDoesNotExist(sourceURL)
            }
            let rootKeys: Set<URLResourceKey> = [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                .fileSizeKey, .contentModificationDateKey
            ]
            let selectedRootValues = try sourceURL.resourceValues(forKeys: rootKeys)
            try rejectUnsupportedType(selectedRootValues, path: sourceURL.path)
            // FileManager enumeration may canonicalize `/var` to `/private/var`.
            // Resolve the non-symlink root once so relative paths never depend on textual aliases.
            let physicalSourceURL = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            let rootName = uniqueName(
                sourceURL.lastPathComponent.isEmpty ? "Item" : sourceURL.lastPathComponent,
                usedNames: usedRootNames
            )
            usedRootNames.insert(rootName)
            let rootValues = try physicalSourceURL.resourceValues(forKeys: rootKeys)
            try rejectUnsupportedType(rootValues, path: physicalSourceURL.path)
            let rootPath = try normalizedArchivePath(
                rootName + (rootValues.isDirectory == true ? "/" : "")
            )
            result.append(try sourceEntry(
                url: physicalSourceURL,
                archivePath: rootPath,
                values: rootValues
            ))

            guard rootValues.isDirectory == true else { continue }
            let keys: [URLResourceKey] = [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                .fileSizeKey, .contentModificationDateKey
            ]
            var enumerationError: Error?
            guard let enumerator = fileManager.enumerator(
                at: physicalSourceURL,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            ) else {
                throw CocoaError(.fileReadUnknown)
            }
            let sourcePrefix = physicalSourceURL.path.hasSuffix("/")
                ? physicalSourceURL.path
                : physicalSourceURL.path + "/"
            while let childURL = enumerator.nextObject() as? URL {
                let physicalChildURL = childURL.standardizedFileURL
                let values = try physicalChildURL.resourceValues(forKeys: Set(keys))
                try rejectUnsupportedType(values, path: physicalChildURL.path)
                guard physicalChildURL.path.hasPrefix(sourcePrefix) else {
                    throw ArchiveServiceError.unsafeArchiveEntry(physicalChildURL.path)
                }
                let relativePath = String(physicalChildURL.path.dropFirst(sourcePrefix.count))
                let archivePath = try normalizedArchivePath(
                    rootName + "/" + relativePath
                        + (values.isDirectory == true ? "/" : "")
                )
                result.append(try sourceEntry(
                    url: physicalChildURL,
                    archivePath: archivePath,
                    values: values
                ))
                guard result.count <= TuckArchiveLimits.maximumEntryCount else {
                    throw ArchiveServiceError.tuckArchiveLimitExceeded("entry count")
                }
            }
            if let enumerationError = enumerationError {
                throw enumerationError
            }
        }
        return result
    }

    private func sourceEntry(
        url: URL,
        archivePath: String,
        values: URLResourceValues
    ) throws -> SourceEntry {
        let isDirectory = values.isDirectory == true
        let signedSize = values.fileSize ?? 0
        guard signedSize >= 0 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("negative source size")
        }
        let size = isDirectory ? 0 : UInt64(signedSize)
        guard size <= TuckArchiveLimits.maximumEntrySize else {
            throw ArchiveServiceError.tuckArchiveLimitExceeded("entry size")
        }
        let modified = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        let nanoseconds = Int64(modified.timeIntervalSince1970 * 1_000_000_000)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint32Value ?? 0o644
        return SourceEntry(
            url: url,
            archivePath: archivePath,
            isDirectory: isDirectory,
            size: size,
            modifiedNanoseconds: nanoseconds,
            permissions: permissions & 0o777
        )
    }

    private func rejectUnsupportedType(_ values: URLResourceValues, path: String) throws {
        if values.isSymbolicLink == true {
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature("symbolic link: \(path)")
        }
        guard values.isDirectory == true || values.isRegularFile == true else {
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature("special file: \(path)")
        }
    }

    private func normalizedArchivePath(_ path: String) throws -> String {
        let normalized = path.precomposedStringWithCanonicalMapping
        let validationPath = normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
        let components = validationPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !validationPath.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\\"),
              !normalized.unicodeScalars.contains(where: { $0.value == 0 }),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              normalized.utf8.count <= TuckArchiveLimits.maximumPathBytes else {
            throw ArchiveServiceError.unsafeArchiveEntry(path)
        }
        return normalized
    }

    private func uniqueName(_ baseName: String, usedNames: Set<String>) -> String {
        let contains: (String) -> Bool = { candidate in
            usedNames.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
        guard !contains(baseName) else {
            let name = (baseName as NSString).deletingPathExtension
            let ext = (baseName as NSString).pathExtension
            var index = 2
            while true {
                let candidate = ext.isEmpty ? "\(name)-\(index)" : "\(name)-\(index).\(ext)"
                if !contains(candidate) { return candidate }
                index += 1
            }
        }
        return baseName
    }

    static func encodeHeader(
        flags: UInt32,
        archiveID: Data,
        salt: Data,
        noncePrefix: Data,
        wrapNonce: Data,
        wrappedKeyLength: UInt32
    ) -> Data {
        var writer = TuckBinaryWriter()
        writer.append(bytes: TuckArchiveFormat.magic)
        writer.append(TuckArchiveFormat.majorVersion)
        writer.append(TuckArchiveFormat.minorVersion)
        writer.append(UInt32(TuckArchiveFormat.headerSize))
        writer.append(flags)
        writer.append(UInt16(TuckArchiveFormat.zstdCodec))
        writer.append(wrappedKeyLength == 0 ? 0 : TuckArchiveFormat.aes256GCM)
        writer.append(wrappedKeyLength == 0 ? 0 : TuckArchiveFormat.argon2id)
        writer.append(TuckArchiveFormat.majorVersion)
        writer.append(UInt32(TuckArchiveFormat.defaultChunkSize))
        writer.append(bytes: archiveID)
        writer.append(bytes: salt)
        writer.append(wrappedKeyLength == 0 ? 0 : TuckArchiveFormat.defaultArgonMemoryKiB)
        writer.append(wrappedKeyLength == 0 ? 0 : TuckArchiveFormat.defaultArgonIterations)
        writer.append(wrappedKeyLength == 0 ? 0 : TuckArchiveFormat.defaultArgonParallelism)
        writer.append(bytes: noncePrefix)
        writer.append(bytes: wrapNonce)
        writer.append(wrappedKeyLength)
        writer.appendZeroes(count: TuckArchiveFormat.headerSize - writer.data.count)
        return writer.data
    }

    private func encodeChunkHeader(
        sequence: UInt32,
        codec: UInt8,
        encrypted: Bool,
        originalLength: UInt32,
        storedLength: UInt32
    ) -> Data {
        var writer = TuckBinaryWriter()
        writer.append(bytes: TuckArchiveFormat.chunkMagic)
        writer.append(TuckArchiveFormat.majorVersion)
        writer.append(codec)
        writer.append(UInt8(encrypted ? 1 : 0))
        writer.append(sequence)
        writer.append(originalLength)
        writer.append(storedLength)
        writer.append(UInt32(0))
        return writer.data
    }

    private func encodeIndex(_ entries: [TuckEntryRecord]) throws -> Data {
        var writer = TuckBinaryWriter()
        writer.append(bytes: TuckArchiveFormat.indexMagic)
        writer.append(TuckArchiveFormat.majorVersion)
        writer.append(UInt16(0))
        writer.append(UInt32(entries.count))
        for entry in entries {
            writer.append(UInt8(entry.isDirectory ? 1 : 0))
            writer.appendZeroes(count: 3)
            try writer.appendUTF8(entry.path)
            writer.append(entry.size)
            writer.append(entry.modifiedNanoseconds)
            writer.append(entry.permissions)
            writer.append(UInt32(entry.chunks.count))
            for chunk in entry.chunks {
                writer.append(chunk.sequence)
                writer.append(chunk.codec)
                writer.appendZeroes(count: 3)
                writer.append(chunk.recordOffset)
                writer.append(chunk.storedLength)
                writer.append(chunk.originalLength)
                writer.append(bytes: chunk.digest)
            }
        }
        return writer.data
    }

    private func encodeFooter(
        flags: UInt32,
        indexOffset: UInt64,
        indexStoredLength: UInt64,
        indexPlainLength: UInt64,
        indexNonce: Data,
        indexDigest: Data
    ) -> Data {
        var writer = TuckBinaryWriter()
        writer.append(bytes: TuckArchiveFormat.footerMagic)
        writer.append(TuckArchiveFormat.majorVersion)
        writer.append(TuckArchiveFormat.minorVersion)
        writer.append(UInt32(TuckArchiveFormat.footerSize))
        writer.append(flags)
        writer.append(UInt32(0))
        writer.append(indexOffset)
        writer.append(indexStoredLength)
        writer.append(indexPlainLength)
        writer.append(bytes: indexNonce)
        writer.append(bytes: indexDigest)
        writer.append(UInt32(0))
        return writer.data
    }
}

private struct SourceEntry {
    let url: URL
    let archivePath: String
    let isDirectory: Bool
    let size: UInt64
    let modifiedNanoseconds: Int64
    let permissions: UInt32
}

private struct PendingChunk {
    let sequence: UInt32
    let raw: Data
}

private struct PreparedChunk {
    let sequence: UInt32
    let codec: UInt8
    let originalLength: UInt32
    let header: Data
    let stored: Data
    let digest: Data
}
