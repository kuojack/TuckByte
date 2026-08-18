import Foundation

final class TuckArchiveReader {
    private let fileManager: FileManager
    private let compression = TuckArchiveCompression()
    private let crypto = TuckArchiveCrypto()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func encryptionMethod(for archiveURL: URL) throws -> ArchiveEncryptionMethod {
        let archive = try openArchive(at: archiveURL, password: nil, readIndex: false)
        return archive.header.isEncrypted ? .aes256 : .none
    }

    func inspect(archiveURL: URL, password: String?) throws -> [ArchiveEntry] {
        let archive = try openArchive(at: archiveURL, password: password, readIndex: true)
        return archive.entries.map { record in
            let cleanPath = record.path.hasSuffix("/") ? String(record.path.dropLast()) : record.path
            return ArchiveEntry(
                name: URL(fileURLWithPath: cleanPath).lastPathComponent,
                path: record.path,
                size: record.isDirectory ? nil : Int64(record.size),
                isDirectory: record.isDirectory,
                modifiedAt: Date(timeIntervalSince1970:
                    TimeInterval(record.modifiedNanoseconds) / 1_000_000_000)
            )
        }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String?,
        operation: ArchiveOperation? = nil
    ) throws {
        try operation?.checkCancellation()
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        operation?.update(phase: .readingIndex, completedBytes: 0, totalBytes: 0)
        let archive = try openArchive(at: archiveURL, password: password, readIndex: true)
        try verifyAvailableCapacity(for: archive.totalExtractedSize, near: destinationURL)
        do {
            try fileManager.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try extractRecords(
                archive.entries,
                from: archive,
                archiveURL: archiveURL,
                destinationRoot: destinationURL,
                strippingPrefix: "",
                totalBytes: archive.totalExtractedSize,
                operation: operation
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    func extractEntry(
        archiveURL: URL,
        path: String,
        destinationURL: URL,
        password: String?
    ) throws {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        let archive = try openArchive(at: archiveURL, password: password, readIndex: true)
        guard let selected = archive.entries.first(where: { $0.path == path }) else {
            throw ArchiveServiceError.archiveEntryNotFound(path)
        }
        if !selected.isDirectory {
            try verifyAvailableCapacity(for: selected.size, near: destinationURL)
            try extractFile(selected, from: archive, archiveURL: archiveURL, destinationURL: destinationURL)
            return
        }

        let prefix = selected.path.hasSuffix("/") ? selected.path : selected.path + "/"
        let records = archive.entries.filter { $0.path == selected.path || $0.path.hasPrefix(prefix) }
        let total = records.reduce(UInt64(0)) { $0 + ($1.isDirectory ? 0 : $1.size) }
        try verifyAvailableCapacity(for: total, near: destinationURL)
        do {
            try fileManager.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try extractRecords(
                records.filter { $0.path != selected.path },
                from: archive,
                archiveURL: archiveURL,
                destinationRoot: destinationURL,
                strippingPrefix: prefix
            )
            try applyMetadata(selected, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    func changePassword(archiveURL: URL, oldPassword: String, newPassword: String) throws {
        guard !newPassword.isEmpty else {
            throw ArchiveServiceError.encryptionPasswordRequired
        }
        let archive = try openArchive(at: archiveURL, password: oldPassword, readIndex: false)
        guard archive.header.isEncrypted, let dataEncryptionKey = archive.dataEncryptionKey else {
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature(
                "password change requires an encrypted archive"
            )
        }
        let newSalt = try crypto.randomBytes(count: 16)
        let newWrapNonce = try crypto.randomBytes(count: 12)
        let newHeaderData = TuckArchiveWriter.encodeHeader(
            flags: archive.header.flags,
            archiveID: archive.header.archiveID,
            salt: newSalt,
            noncePrefix: archive.header.noncePrefix,
            wrapNonce: newWrapNonce,
            wrappedKeyLength: 48
        )
        let passwordKey = try crypto.derivePasswordKey(
            password: newPassword,
            salt: newSalt,
            memoryKiB: TuckArchiveFormat.defaultArgonMemoryKiB,
            iterations: TuckArchiveFormat.defaultArgonIterations,
            parallelism: TuckArchiveFormat.defaultArgonParallelism
        )
        let wrappedKey = try crypto.seal(
            dataEncryptionKey,
            using: passwordKey,
            nonceData: newWrapNonce,
            authenticating: newHeaderData
        )
        guard wrappedKey.count == 48 else {
            throw ArchiveServiceError.tuckArchiveCryptoFailed("wrapped key length")
        }
        let handle = try FileHandle(forUpdating: archiveURL)
        defer { handle.closeFile() }
        try handle.seek(toOffset: 0)
        handle.write(newHeaderData)
        handle.write(wrappedKey)
        try handle.synchronize()
    }

    private func openArchive(at archiveURL: URL, password: String?, readIndex: Bool) throws -> OpenArchive {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw ArchiveServiceError.fileDoesNotExist(archiveURL)
        }
        let source = try TuckArchiveDataSource(
            archiveURL: archiveURL,
            fileManager: fileManager
        )
        let fileSize = source.size
        guard fileSize >= UInt64(TuckArchiveFormat.headerSize + TuckArchiveFormat.footerSize) else {
            throw ArchiveServiceError.tuckArchiveCorrupt("file is too short")
        }

        let headerData = try readExactly(
            source: source,
            offset: 0,
            count: TuckArchiveFormat.headerSize
        )
        let header = try parseHeader(headerData)
        let footerOffset = fileSize - UInt64(TuckArchiveFormat.footerSize)
        let footerData = try readExactly(
            source: source,
            offset: footerOffset,
            count: TuckArchiveFormat.footerSize
        )
        let footer = try parseFooter(footerData)
        guard footer.flags == header.flags else {
            throw ArchiveServiceError.tuckArchiveCorrupt("header/footer flags mismatch")
        }

        let contentStart = UInt64(TuckArchiveFormat.headerSize) + UInt64(header.wrappedKeyLength)
        guard footer.indexStoredLength <= UInt64(TuckArchiveLimits.maximumIndexSize + 16),
              footer.indexPlainLength <= UInt64(TuckArchiveLimits.maximumIndexSize),
              footer.indexOffset >= contentStart,
              footer.indexOffset <= footerOffset,
              footer.indexStoredLength <= footerOffset - footer.indexOffset,
              footer.indexOffset + footer.indexStoredLength == footerOffset else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid index bounds")
        }

        var dataEncryptionKey: Data?
        var keys: TuckArchiveCrypto.Keys?
        if header.isEncrypted {
            guard let password = password, !password.isEmpty else {
                if readIndex { throw ArchiveServiceError.archivePasswordRequired }
                return OpenArchive(
                    header: header,
                    footer: footer,
                    source: source,
                    entries: [],
                    totalExtractedSize: 0,
                    dataEncryptionKey: nil,
                    keys: nil
                )
            }
            let wrappedKey = try readExactly(
                source: source,
                offset: UInt64(TuckArchiveFormat.headerSize),
                count: Int(header.wrappedKeyLength)
            )
            let passwordKey = try crypto.derivePasswordKey(
                password: password,
                salt: header.salt,
                memoryKiB: header.argonMemoryKiB,
                iterations: header.argonIterations,
                parallelism: header.argonParallelism
            )
            let dek = try crypto.open(
                wrappedKey,
                using: passwordKey,
                nonceData: header.wrapNonce,
                authenticating: header.encoded
            )
            guard dek.count == 32 else {
                throw ArchiveServiceError.tuckArchiveCorrupt("invalid data key length")
            }
            dataEncryptionKey = dek
            keys = crypto.deriveArchiveKeys(dataEncryptionKey: dek, archiveID: header.archiveID)
        }
        guard readIndex else {
            return OpenArchive(
                header: header,
                footer: footer,
                source: source,
                entries: [],
                totalExtractedSize: 0,
                dataEncryptionKey: dataEncryptionKey,
                keys: keys
            )
        }

        let storedIndex = try readExactly(
            source: source,
            offset: footer.indexOffset,
            count: try checkedInt(footer.indexStoredLength, label: "index length")
        )
        guard crypto.sha256(storedIndex).tuckConstantTimeEquals(footer.indexDigest) else {
            throw ArchiveServiceError.tuckArchiveCorrupt("index digest mismatch")
        }
        let plainIndex: Data
        if let keys = keys {
            var aad = TuckArchiveFormat.contentAuthenticationData(
                flags: header.flags,
                chunkSize: header.chunkSize,
                archiveID: header.archiveID,
                noncePrefix: header.noncePrefix
            )
            aad.append(contentsOf: "TUCKBYTE-INDEX-v1".utf8)
            plainIndex = try crypto.open(
                storedIndex,
                using: keys.indexKey,
                nonceData: footer.indexNonce,
                authenticating: aad,
                authenticationFailure: .tuckArchiveCorrupt("index authentication failed")
            )
        } else {
            plainIndex = storedIndex
        }
        guard UInt64(plainIndex.count) == footer.indexPlainLength else {
            throw ArchiveServiceError.tuckArchiveCorrupt("index length mismatch")
        }
        let parsed = try parseAndValidateIndex(
            plainIndex,
            header: header,
            indexOffset: footer.indexOffset,
            contentStart: contentStart,
            source: source
        )
        return OpenArchive(
            header: header,
            footer: footer,
            source: source,
            entries: parsed.entries,
            totalExtractedSize: parsed.totalSize,
            dataEncryptionKey: dataEncryptionKey,
            keys: keys
        )
    }

    private func parseHeader(_ data: Data) throws -> TuckArchiveHeader {
        var reader = TuckBinaryReader(data: data)
        guard try reader.readBytes(count: 8) == TuckArchiveFormat.magic else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid magic")
        }
        let major = try reader.readUInt16()
        let minor = try reader.readUInt16()
        guard major == TuckArchiveFormat.majorVersion else {
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature("format version \(major).\(minor)")
        }
        guard minor <= TuckArchiveFormat.minorVersion,
              try reader.readUInt32() == UInt32(TuckArchiveFormat.headerSize) else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid header version or size")
        }
        let flags = try reader.readUInt32()
        let knownFlags = TuckArchiveFormat.encryptedFlag | TuckArchiveFormat.experimentalFlag
        guard flags & ~knownFlags == 0 else {
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature("header flags")
        }
        let defaultCodec = try reader.readUInt16()
        let encryption = try reader.readUInt16()
        let kdf = try reader.readUInt16()
        let minimumReaderVersion = try reader.readUInt16()
        guard minimumReaderVersion > 0,
              minimumReaderVersion <= TuckArchiveFormat.majorVersion else {
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature(
                "minimum reader version \(minimumReaderVersion)"
            )
        }
        let chunkSize = try reader.readUInt32()
        let archiveID = try reader.readBytes(count: 16)
        let salt = try reader.readBytes(count: 16)
        let memory = try reader.readUInt32()
        let iterations = try reader.readUInt32()
        let parallelism = try reader.readUInt32()
        let noncePrefix = try reader.readBytes(count: 8)
        let wrapNonce = try reader.readBytes(count: 12)
        let wrappedLength = try reader.readUInt32()
        let reserved = try reader.readBytes(count: reader.remainingCount)

        guard defaultCodec == UInt16(TuckArchiveFormat.zstdCodec),
              chunkSize > 0,
              chunkSize <= UInt32(TuckArchiveLimits.maximumChunkSize),
              reserved.allSatisfy({ $0 == 0 }) else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid header fields")
        }
        let encrypted = flags & TuckArchiveFormat.encryptedFlag != 0
        if encrypted {
            guard encryption == TuckArchiveFormat.aes256GCM,
                  kdf == TuckArchiveFormat.argon2id,
                  wrappedLength == 48,
                  memory >= 8 * parallelism,
                  memory <= TuckArchiveLimits.maximumArgonMemoryKiB,
                  iterations > 0,
                  iterations <= TuckArchiveLimits.maximumArgonIterations,
                  parallelism > 0,
                  parallelism <= TuckArchiveLimits.maximumArgonParallelism else {
                throw ArchiveServiceError.tuckArchiveCorrupt("invalid encryption parameters")
            }
        } else {
            guard encryption == 0, kdf == 0, wrappedLength == 0,
                  memory == 0, iterations == 0, parallelism == 0,
                  salt.allSatisfy({ $0 == 0 }),
                  wrapNonce.allSatisfy({ $0 == 0 }) else {
                throw ArchiveServiceError.tuckArchiveCorrupt("inconsistent encryption fields")
            }
        }
        return TuckArchiveHeader(
            flags: flags,
            chunkSize: chunkSize,
            archiveID: archiveID,
            salt: salt,
            argonMemoryKiB: memory,
            argonIterations: iterations,
            argonParallelism: parallelism,
            noncePrefix: noncePrefix,
            wrapNonce: wrapNonce,
            wrappedKeyLength: wrappedLength,
            encoded: data
        )
    }

    private func parseFooter(_ data: Data) throws -> TuckArchiveFooter {
        var reader = TuckBinaryReader(data: data)
        guard try reader.readBytes(count: 8) == TuckArchiveFormat.footerMagic else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid footer magic")
        }
        let major = try reader.readUInt16()
        let minor = try reader.readUInt16()
        guard major == TuckArchiveFormat.majorVersion,
              minor <= TuckArchiveFormat.minorVersion,
              try reader.readUInt32() == UInt32(TuckArchiveFormat.footerSize) else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid footer version or size")
        }
        let flags = try reader.readUInt32()
        guard try reader.readUInt32() == 0 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("non-zero footer reserved field")
        }
        let indexOffset = try reader.readUInt64()
        let storedLength = try reader.readUInt64()
        let plainLength = try reader.readUInt64()
        let nonce = try reader.readBytes(count: 12)
        let digest = try reader.readBytes(count: 32)
        guard try reader.readUInt32() == 0, reader.remainingCount == 0 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid footer tail")
        }
        return TuckArchiveFooter(
            flags: flags,
            indexOffset: indexOffset,
            indexStoredLength: storedLength,
            indexPlainLength: plainLength,
            indexNonce: nonce,
            indexDigest: digest
        )
    }

    private func parseAndValidateIndex(
        _ data: Data,
        header: TuckArchiveHeader,
        indexOffset: UInt64,
        contentStart: UInt64,
        source: TuckArchiveDataSource
    ) throws -> (entries: [TuckEntryRecord], totalSize: UInt64) {
        var reader = TuckBinaryReader(data: data)
        guard try reader.readBytes(count: 4) == TuckArchiveFormat.indexMagic,
              try reader.readUInt16() == TuckArchiveFormat.majorVersion,
              try reader.readUInt16() == 0 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid index header")
        }
        let entryCount = Int(try reader.readUInt32())
        guard entryCount <= TuckArchiveLimits.maximumEntryCount else {
            throw ArchiveServiceError.tuckArchiveLimitExceeded("entry count")
        }

        var entries: [TuckEntryRecord] = []
        entries.reserveCapacity(entryCount)
        var usedPaths = Set<String>()
        var filePaths = Set<String>()
        var usedSequences = Set<UInt32>()
        var ranges: [(start: UInt64, end: UInt64)] = []
        var totalChunks = 0
        var totalSize: UInt64 = 0

        for _ in 0..<entryCount {
            let kind = try reader.readUInt8()
            guard kind <= 1, try reader.readBytes(count: 3).allSatisfy({ $0 == 0 }) else {
                throw ArchiveServiceError.tuckArchiveCorrupt("invalid index entry flags")
            }
            let path = try reader.readUTF8()
            let isDirectory = kind == 1
            try validatePath(path, isDirectory: isDirectory)
            let collisionKey = path.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            guard usedPaths.insert(collisionKey).inserted else {
                throw ArchiveServiceError.tuckArchiveCorrupt("duplicate path: \(path)")
            }
            let size = try reader.readUInt64()
            let modified = try reader.readInt64()
            let permissions = try reader.readUInt32()
            let chunkCount = Int(try reader.readUInt32())
            guard size <= TuckArchiveLimits.maximumEntrySize,
                  permissions & ~UInt32(0o777) == 0,
                  chunkCount <= TuckArchiveLimits.maximumChunkCount - totalChunks else {
                throw ArchiveServiceError.tuckArchiveLimitExceeded("entry metadata")
            }
            totalChunks += chunkCount
            if isDirectory {
                guard size == 0, chunkCount == 0 else {
                    throw ArchiveServiceError.tuckArchiveCorrupt("directory contains file data")
                }
            } else {
                guard totalSize <= TuckArchiveLimits.maximumTotalExtractedSize - size else {
                    throw ArchiveServiceError.tuckArchiveLimitExceeded("total extracted size")
                }
                totalSize += size
                filePaths.insert(collisionKey)
            }

            var chunks: [TuckChunkRecord] = []
            chunks.reserveCapacity(chunkCount)
            var entryChunkSize: UInt64 = 0
            for _ in 0..<chunkCount {
                let sequence = try reader.readUInt32()
                let codec = try reader.readUInt8()
                guard try reader.readBytes(count: 3).allSatisfy({ $0 == 0 }) else {
                    throw ArchiveServiceError.tuckArchiveCorrupt("invalid chunk index reserved field")
                }
                let recordOffset = try reader.readUInt64()
                let storedLength = try reader.readUInt32()
                let originalLength = try reader.readUInt32()
                let digest = try reader.readBytes(count: 32)
                guard sequence > 0, sequence < UInt32.max,
                      usedSequences.insert(sequence).inserted,
                      codec == TuckArchiveFormat.storeCodec || codec == TuckArchiveFormat.zstdCodec,
                      originalLength > 0,
                      originalLength <= header.chunkSize,
                      storedLength > 0,
                      recordOffset >= contentStart,
                      recordOffset < indexOffset else {
                    throw ArchiveServiceError.tuckArchiveCorrupt("invalid chunk index record")
                }
                let effectiveStoredLength = header.isEncrypted
                    ? UInt64(storedLength > 16 ? storedLength - 16 : 0)
                    : UInt64(storedLength)
                guard effectiveStoredLength > 0,
                      UInt64(originalLength) <= effectiveStoredLength
                        * TuckArchiveLimits.maximumCompressionRatio else {
                    throw ArchiveServiceError.tuckArchiveLimitExceeded("compression ratio")
                }
                let fullLength = UInt64(TuckArchiveFormat.chunkHeaderSize) + UInt64(storedLength)
                guard fullLength <= indexOffset - recordOffset else {
                    throw ArchiveServiceError.tuckArchiveCorrupt("chunk exceeds content bounds")
                }
                ranges.append((recordOffset, recordOffset + fullLength))
                entryChunkSize += UInt64(originalLength)
                chunks.append(TuckChunkRecord(
                    sequence: sequence,
                    codec: codec,
                    recordOffset: recordOffset,
                    storedLength: storedLength,
                    originalLength: originalLength,
                    digest: digest
                ))
            }
            guard isDirectory || entryChunkSize == size else {
                throw ArchiveServiceError.tuckArchiveCorrupt("entry size does not match chunks")
            }
            entries.append(TuckEntryRecord(
                path: path,
                isDirectory: isDirectory,
                size: size,
                modifiedNanoseconds: modified,
                permissions: permissions,
                chunks: chunks
            ))
        }
        guard reader.remainingCount == 0 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("trailing index bytes")
        }

        let sortedRanges = ranges.sorted { $0.start < $1.start }
        for index in 1..<sortedRanges.count {
            guard sortedRanges[index - 1].end <= sortedRanges[index].start else {
                throw ArchiveServiceError.tuckArchiveCorrupt("overlapping chunk records")
            }
        }
        for filePath in filePaths {
            let components = filePath.split(separator: "/")
            guard components.count > 1 else { continue }
            for count in 1..<components.count {
                guard !filePaths.contains(components.prefix(count).joined(separator: "/")) else {
                    throw ArchiveServiceError.tuckArchiveCorrupt("file used as directory")
                }
            }
        }
        for entry in entries {
            for chunk in entry.chunks {
                try validateChunkHeader(chunk, header: header, source: source)
            }
        }
        return (entries, totalSize)
    }

    private func validateChunkHeader(
        _ record: TuckChunkRecord,
        header: TuckArchiveHeader,
        source: TuckArchiveDataSource
    ) throws {
        let data = try readExactly(
            source: source,
            offset: record.recordOffset,
            count: TuckArchiveFormat.chunkHeaderSize
        )
        var reader = TuckBinaryReader(data: data)
        guard try reader.readBytes(count: 4) == TuckArchiveFormat.chunkMagic,
              try reader.readUInt16() == TuckArchiveFormat.majorVersion,
              try reader.readUInt8() == record.codec,
              try reader.readUInt8() == (header.isEncrypted ? 1 : 0),
              try reader.readUInt32() == record.sequence,
              try reader.readUInt32() == record.originalLength,
              try reader.readUInt32() == record.storedLength,
              try reader.readUInt32() == 0,
              reader.remainingCount == 0 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("chunk header/index mismatch")
        }
    }

    private func extractRecords(
        _ records: [TuckEntryRecord],
        from archive: OpenArchive,
        archiveURL: URL,
        destinationRoot: URL,
        strippingPrefix prefix: String,
        totalBytes: UInt64 = 0,
        operation: ArchiveOperation? = nil
    ) throws {
        var completedBytes: UInt64 = 0
        let directories = records.filter(\.isDirectory).sorted {
            pathDepth($0.path) < pathDepth($1.path)
        }
        for record in directories {
            try operation?.checkCancellation()
            let relative = try strippedPath(record.path, prefix: prefix)
            guard !relative.isEmpty else { continue }
            try fileManager.createDirectory(
                at: safeDestination(root: destinationRoot, relativePath: relative),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        for record in records where !record.isDirectory {
            try operation?.checkCancellation()
            let relative = try strippedPath(record.path, prefix: prefix)
            let url = safeDestination(root: destinationRoot, relativePath: relative)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try extractFile(
                record,
                from: archive,
                archiveURL: archiveURL,
                destinationURL: url,
                operation: operation
            )
            completedBytes += record.size
            operation?.update(
                phase: .extracting,
                completedBytes: completedBytes,
                totalBytes: totalBytes
            )
        }
        for record in directories.sorted(by: { pathDepth($0.path) > pathDepth($1.path) }) {
            let relative = try strippedPath(record.path, prefix: prefix)
            guard !relative.isEmpty else { continue }
            try applyMetadata(record, to: safeDestination(root: destinationRoot, relativePath: relative))
        }
    }

    private func extractFile(
        _ record: TuckEntryRecord,
        from archive: OpenArchive,
        archiveURL: URL,
        destinationURL: URL,
        operation: ArchiveOperation? = nil
    ) throws {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).partial-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: temporaryURL)
            defer { output.closeFile() }
            var written: UInt64 = 0
            let contentAAD = TuckArchiveFormat.contentAuthenticationData(
                flags: archive.header.flags,
                chunkSize: archive.header.chunkSize,
                archiveID: archive.header.archiveID,
                noncePrefix: archive.header.noncePrefix
            )
            for chunk in record.chunks {
                try operation?.checkCancellation()
                let chunkHeader = try readExactly(
                    source: archive.source,
                    offset: chunk.recordOffset,
                    count: TuckArchiveFormat.chunkHeaderSize
                )
                var stored = try readExactly(
                    source: archive.source,
                    offset: chunk.recordOffset + UInt64(TuckArchiveFormat.chunkHeaderSize),
                    count: Int(chunk.storedLength)
                )
                if let keys = archive.keys {
                    let nonce = try crypto.nonce(prefix: archive.header.noncePrefix, counter: chunk.sequence)
                    var aad = contentAAD
                    aad.append(chunkHeader)
                    stored = try crypto.open(
                        stored,
                        using: keys.dataKey,
                        nonceData: nonce,
                        authenticating: aad,
                        authenticationFailure: .tuckArchiveCorrupt("chunk authentication failed")
                    )
                }
                let raw = try compression.decompress(
                    stored,
                    codec: chunk.codec,
                    originalSize: Int(chunk.originalLength)
                )
                guard crypto.sha256(raw).tuckConstantTimeEquals(chunk.digest) else {
                    throw ArchiveServiceError.tuckArchiveCorrupt("chunk digest mismatch")
                }
                output.write(raw)
                written += UInt64(raw.count)
            }
            guard written == record.size else {
                throw ArchiveServiceError.tuckArchiveCorrupt("extracted size mismatch")
            }
            try output.synchronize()
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            try applyMetadata(record, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func validatePath(_ path: String, isDirectory: Bool) throws {
        let validation = path.hasSuffix("/") ? String(path.dropLast()) : path
        let components = validation.split(separator: "/", omittingEmptySubsequences: false)
        guard path == path.precomposedStringWithCanonicalMapping,
              !validation.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: { $0.value == 0 }),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              isDirectory == path.hasSuffix("/"),
              path.utf8.count <= TuckArchiveLimits.maximumPathBytes else {
            throw ArchiveServiceError.unsafeArchiveEntry(path)
        }
    }

    private func strippedPath(_ path: String, prefix: String) throws -> String {
        guard prefix.isEmpty || path.hasPrefix(prefix) else {
            throw ArchiveServiceError.unsafeArchiveEntry(path)
        }
        return String(path.dropFirst(prefix.count)).trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
    }

    private func safeDestination(root: URL, relativePath: String) -> URL {
        relativePath.split(separator: "/").reduce(root) {
            $0.appendingPathComponent(String($1), isDirectory: false)
        }
    }

    private func pathDepth(_ path: String) -> Int {
        path.split(separator: "/").count
    }

    private func applyMetadata(_ record: TuckEntryRecord, to url: URL) throws {
        let date = Date(timeIntervalSince1970:
            TimeInterval(record.modifiedNanoseconds) / 1_000_000_000)
        try fileManager.setAttributes([
            .posixPermissions: NSNumber(value: record.permissions),
            .modificationDate: date
        ], ofItemAtPath: url.path)
    }

    private func verifyAvailableCapacity(for size: UInt64, near destinationURL: URL) throws {
        let parent = destinationURL.deletingLastPathComponent()
        let values = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage,
           available >= 0,
           size > UInt64(available) {
            throw ArchiveServiceError.tuckArchiveLimitExceeded("insufficient disk capacity")
        }
    }

    private func readExactly(
        source: TuckArchiveDataSource,
        offset: UInt64,
        count: Int
    ) throws -> Data {
        let data = try source.read(offset: offset, count: count)
        guard data.count == count else {
            throw ArchiveServiceError.tuckArchiveCorrupt("unexpected end of file")
        }
        return data
    }

    private func checkedInt(_ value: UInt64, label: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw ArchiveServiceError.tuckArchiveLimitExceeded(label)
        }
        return Int(value)
    }
}

private struct OpenArchive {
    let header: TuckArchiveHeader
    let footer: TuckArchiveFooter
    let source: TuckArchiveDataSource
    let entries: [TuckEntryRecord]
    let totalExtractedSize: UInt64
    let dataEncryptionKey: Data?
    let keys: TuckArchiveCrypto.Keys?
}
