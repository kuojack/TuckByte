import XCTest
import CryptoKit
@testable import TuckByteCore

final class TuckArchiveTests: XCTestCase {
    private var root: URL!
    private var service: ShellArchiveService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TuckArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        service = ShellArchiveService()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testUnencryptedRoundTripBrowseAndDirectEntryExtraction() throws {
        let source = root.appendingPathComponent("來源 資料", isDirectory: true)
        let nested = source.appendingPathComponent("子目錄", isDirectory: true)
        let empty = source.appendingPathComponent("空目錄", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let text = "TuckByte 自有格式 🚀"
        try Data(text.utf8).write(to: nested.appendingPathComponent("內容.txt"))
        let binary = Data((0..<100_000).map { UInt8($0 % 251) })
        try binary.write(to: source.appendingPathComponent("payload.bin"))

        let archive = root.appendingPathComponent("測試.tuck")
        try service.createArchive(
            from: [source],
            destinationURL: archive,
            settings: CompressionSettings(outputFormat: .tuck, compressionLevel: 6)
        )
        XCTAssertEqual(try service.encryptionMethod(archiveURL: archive), .none)
        let entries = try service.inspect(archiveURL: archive)
        XCTAssertTrue(
            entries.contains { $0.path == "來源 資料/空目錄/" && $0.isDirectory },
            "entries: \(entries.map(\.path))"
        )
        let textEntry = try XCTUnwrap(entries.first { $0.path == "來源 資料/子目錄/內容.txt" })

        let extracted = root.appendingPathComponent("完整解壓", isDirectory: true)
        try service.extract(archiveURL: archive, destinationURL: extracted)
        XCTAssertEqual(
            try String(contentsOf: extracted.appendingPathComponent("來源 資料/子目錄/內容.txt")),
            text
        )
        XCTAssertEqual(
            try Data(contentsOf: extracted.appendingPathComponent("來源 資料/payload.bin")),
            binary
        )

        let oneFile = root.appendingPathComponent("單項.txt")
        try service.extractEntry(
            archiveURL: archive,
            entry: textEntry,
            destinationURL: oneFile
        )
        XCTAssertEqual(try String(contentsOf: oneFile), text)

        let directoryEntry = try XCTUnwrap(entries.first { $0.path == "來源 資料/子目錄/" })
        let oneDirectory = root.appendingPathComponent("單項資料夾", isDirectory: true)
        try service.extractEntry(
            archiveURL: archive,
            entry: directoryEntry,
            destinationURL: oneDirectory
        )
        XCTAssertEqual(try String(contentsOf: oneDirectory.appendingPathComponent("內容.txt")), text)
    }

    func testAllCompressionProfilesRoundTrip() throws {
        let source = root.appendingPathComponent("repeat.txt")
        let content = Data(String(repeating: "abcdef0123456789", count: 20_000).utf8)
        try content.write(to: source)
        for level in [1, 6, 9] {
            let archive = root.appendingPathComponent("profile-\(level).tuck")
            try service.createArchive(
                from: [source],
                destinationURL: archive,
                settings: CompressionSettings(
                    outputFormat: .tuck,
                    compressionLevel: level,
                    encryption: .none
                )
            )
            let destination = root.appendingPathComponent("profile-\(level)", isDirectory: true)
            try service.extract(archiveURL: archive, destinationURL: destination)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("repeat.txt")), content)
        }
    }

    func testAES256PasswordChangeRewrapsOnlyKeyMaterial() throws {
        let source = root.appendingPathComponent("secret.txt")
        try Data("classified".utf8).write(to: source)
        let archive = root.appendingPathComponent("secret.tuck")
        try service.createArchive(
            from: [source],
            destinationURL: archive,
            settings: CompressionSettings(
                outputFormat: .tuck,
                compressionLevel: 6,
                encryption: .aes256(password: "old-password")
            )
        )
        XCTAssertEqual(try service.encryptionMethod(archiveURL: archive), .aes256)
        XCTAssertThrowsError(try service.inspect(archiveURL: archive)) { error in
            XCTAssertEqual(error as? ArchiveServiceError, .archivePasswordRequired)
        }
        XCTAssertThrowsError(try service.inspect(archiveURL: archive, password: "wrong")) { error in
            XCTAssertEqual(error as? ArchiveServiceError, .incorrectArchivePassword)
        }
        XCTAssertEqual(
            try service.inspect(archiveURL: archive, password: "old-password").first?.path,
            "secret.txt"
        )

        let before = try Data(contentsOf: archive)
        try service.changePassword(
            archiveURL: archive,
            oldPassword: "old-password",
            newPassword: "new-password"
        )
        let after = try Data(contentsOf: archive)
        XCTAssertEqual(before.count, after.count)
        XCTAssertEqual(before.dropFirst(176), after.dropFirst(176))
        XCTAssertThrowsError(try service.inspect(archiveURL: archive, password: "old-password"))
        XCTAssertEqual(
            try service.inspect(archiveURL: archive, password: "new-password").first?.path,
            "secret.txt"
        )
        let extracted = root.appendingPathComponent("decrypted", isDirectory: true)
        try service.extract(
            archiveURL: archive,
            destinationURL: extracted,
            password: "new-password"
        )
        XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("secret.txt")), "classified")
    }

    func testIndexAndChunkTamperingAreRejected() throws {
        let source = root.appendingPathComponent("payload.txt")
        try Data(String(repeating: "payload", count: 10_000).utf8).write(to: source)
        let original = root.appendingPathComponent("original.tuck")
        try service.createArchive(
            from: [source],
            destinationURL: original,
            settings: CompressionSettings(outputFormat: .tuck)
        )

        var indexTampered = try Data(contentsOf: original)
        let footerOffset = indexTampered.count - TuckArchiveFormat.footerSize
        let indexOffset = Int(readUInt64LE(indexTampered, at: footerOffset + 24))
        indexTampered[indexOffset] ^= 0x01
        let indexURL = root.appendingPathComponent("index-tampered.tuck")
        try indexTampered.write(to: indexURL)
        XCTAssertThrowsError(try service.inspect(archiveURL: indexURL)) { error in
            guard case .tuckArchiveCorrupt = error as? ArchiveServiceError else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        var chunkTampered = try Data(contentsOf: original)
        chunkTampered[TuckArchiveFormat.headerSize + TuckArchiveFormat.chunkHeaderSize] ^= 0x80
        let chunkURL = root.appendingPathComponent("chunk-tampered.tuck")
        try chunkTampered.write(to: chunkURL)
        let destination = root.appendingPathComponent("tampered-output", isDirectory: true)
        XCTAssertThrowsError(try service.extract(archiveURL: chunkURL, destinationURL: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testSplitTuckRoundTripFromAnyVolume() throws {
        let source = root.appendingPathComponent("split.bin")
        var state: UInt64 = 0x54_55_43_4B_42_59_54_45
        let payload = Data((0..<100_000).map { _ in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return UInt8(truncatingIfNeeded: state)
        })
        try payload.write(to: source)
        let firstVolume = root.appendingPathComponent("archive.tuck.001")
        try service.createArchive(
            from: [source],
            destinationURL: firstVolume,
            settings: CompressionSettings(
                outputFormat: .tuck,
                compressionLevel: 1,
                encryption: .none,
                volumeSizeBytes: 4_096
            )
        )
        let volumes = try SplitTuckArchive.volumeURLs(startingAt: firstVolume)
        XCTAssertGreaterThan(volumes.count, 1)
        XCTAssertEqual(try service.inspect(archiveURL: volumes.last!).first?.path, "split.bin")
        let extracted = root.appendingPathComponent("split-output", isDirectory: true)
        try service.extract(archiveURL: volumes[1], destinationURL: extracted)
        XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("split.bin")), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("archive.tuck").path))

        try FileManager.default.removeItem(at: volumes[1])
        XCTAssertThrowsError(try service.inspect(archiveURL: volumes.last!)) { error in
            guard case .splitArchiveMissingVolume = error as? ArchiveServiceError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testEncryptedHeaderCiphertextTagNonceAndIndexTamperingFailClosed() throws {
        let source = root.appendingPathComponent("secure.bin")
        try Data(String(repeating: "authenticated payload ", count: 300_000).utf8).write(to: source)
        let originalURL = root.appendingPathComponent("secure.tuck")
        try service.createArchive(
            from: [source],
            destinationURL: originalURL,
            settings: CompressionSettings(
                outputFormat: .tuck,
                encryption: .aes256(password: "correct-password")
            )
        )
        let original = try Data(contentsOf: originalURL)
        let footerOffset = original.count - TuckArchiveFormat.footerSize
        let indexOffset = Int(readUInt64LE(original, at: footerOffset + 24))
        let firstChunkPayloadOffset = TuckArchiveFormat.headerSize + 48
            + TuckArchiveFormat.chunkHeaderSize
        let mutations: [(String, Int)] = [
            ("header", 32),
            ("wrapped-key-tag", TuckArchiveFormat.headerSize + 47),
            ("chunk-header", TuckArchiveFormat.headerSize + 48 + 8),
            ("chunk-ciphertext", firstChunkPayloadOffset),
            ("index-ciphertext", indexOffset),
            ("index-nonce", footerOffset + 48)
        ]

        for (name, offset) in mutations {
            var changed = original
            changed[offset] ^= 0x40
            let changedURL = root.appendingPathComponent("tampered-\(name).tuck")
            try changed.write(to: changedURL)
            let destination = root.appendingPathComponent("output-\(name)", isDirectory: true)
            XCTAssertThrowsError(
                try service.extract(
                    archiveURL: changedURL,
                    destinationURL: destination,
                    password: "correct-password"
                ),
                "mutation should fail: \(name)"
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: destination.path),
                "partial plaintext remained after: \(name)"
            )
        }
    }

    func testEncryptedNoncesAreUniqueAndIndexUsesReservedCounter() throws {
        let source = root.appendingPathComponent("multi.bin")
        try Data(repeating: 0xA5, count: TuckArchiveFormat.defaultChunkSize * 2 + 123).write(to: source)
        let archiveURL = root.appendingPathComponent("nonces.tuck")
        try service.createArchive(
            from: [source],
            destinationURL: archiveURL,
            settings: CompressionSettings(
                outputFormat: .tuck,
                encryption: .aes256(password: "nonce-password")
            )
        )
        let data = try Data(contentsOf: archiveURL)
        let prefix = data.subdata(in: 76..<84)
        let footerOffset = data.count - TuckArchiveFormat.footerSize
        let indexOffset = Int(readUInt64LE(data, at: footerOffset + 24))
        var recordOffset = TuckArchiveFormat.headerSize + 48
        var nonces = Set<Data>()
        while recordOffset < indexOffset {
            XCTAssertEqual(data.subdata(in: recordOffset..<(recordOffset + 4)), TuckArchiveFormat.chunkMagic)
            let sequence = readUInt32LE(data, at: recordOffset + 8)
            var nonce = prefix
            nonce.append(contentsOf: withUnsafeBytes(of: sequence.littleEndian, Array.init))
            XCTAssertTrue(nonces.insert(nonce).inserted)
            let storedLength = Int(readUInt32LE(data, at: recordOffset + 16))
            recordOffset += TuckArchiveFormat.chunkHeaderSize + storedLength
        }
        XCTAssertEqual(recordOffset, indexOffset)
        let indexNonce = data.subdata(in: (footerOffset + 48)..<(footerOffset + 60))
        var expectedIndexNonce = prefix
        expectedIndexNonce.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(indexNonce, expectedIndexNonce)
        XCTAssertTrue(nonces.insert(indexNonce).inserted)
    }

    func testExcessiveArgonMemoryIsRejectedBeforeKeyDerivation() throws {
        let source = root.appendingPathComponent("argon.txt")
        try Data("argon".utf8).write(to: source)
        let archiveURL = root.appendingPathComponent("argon.tuck")
        try service.createArchive(
            from: [source],
            destinationURL: archiveURL,
            settings: CompressionSettings(
                outputFormat: .tuck,
                encryption: .aes256(password: "password")
            )
        )
        var data = try Data(contentsOf: archiveURL)
        data.replaceSubrange(64..<68, with: [0x01, 0x00, 0x04, 0x00]) // 256 MiB + 1 KiB
        try data.write(to: archiveURL, options: .atomic)
        XCTAssertThrowsError(
            try service.inspect(archiveURL: archiveURL, password: "password")
        ) { error in
            guard case .tuckArchiveCorrupt = error as? ArchiveServiceError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testUnsafeIndexPathIsRejectedEvenWithMatchingIndexDigest() throws {
        let source = root.appendingPathComponent("safe.txt")
        try Data("safe".utf8).write(to: source)
        let archiveURL = root.appendingPathComponent("unsafe-index.tuck")
        try service.createArchive(
            from: [source],
            destinationURL: archiveURL,
            settings: CompressionSettings(outputFormat: .tuck)
        )
        var data = try Data(contentsOf: archiveURL)
        let footerOffset = data.count - TuckArchiveFormat.footerSize
        let indexOffset = Int(readUInt64LE(data, at: footerOffset + 24))
        let safeName = Data("safe.txt".utf8)
        let unsafeName = Data("../a.txt".utf8)
        let indexRange = indexOffset..<footerOffset
        let pathRange = try XCTUnwrap(data.range(of: safeName, options: [], in: indexRange))
        data.replaceSubrange(pathRange, with: unsafeName)
        let digest = Data(SHA256.hash(data: data.subdata(in: indexRange)))
        data.replaceSubrange((footerOffset + 60)..<(footerOffset + 92), with: digest)
        try data.write(to: archiveURL, options: .atomic)
        XCTAssertThrowsError(try service.inspect(archiveURL: archiveURL)) { error in
            guard case .unsafeArchiveEntry = error as? ArchiveServiceError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testCancellationRemovesPartialSingleAndSplitOutputs() throws {
        let source = root.appendingPathComponent("large.bin")
        try Data(repeating: 0x5A, count: TuckArchiveFormat.defaultChunkSize * 3).write(to: source)

        for destination in [
            root.appendingPathComponent("cancel.tuck"),
            root.appendingPathComponent("cancel-split.tuck.001")
        ] {
            var operation: ArchiveOperation!
            operation = ArchiveOperation { snapshot in
                if snapshot.phase == .compressing && snapshot.completedBytes > 0 {
                    operation.cancel()
                }
            }
            let settings = CompressionSettings(
                outputFormat: .tuck,
                volumeSizeBytes: destination.pathExtension == "001" ? 1_024 : nil
            )
            XCTAssertThrowsError(
                try service.createArchive(
                    from: [source],
                    destinationURL: destination,
                    settings: settings,
                    operation: operation
                )
            ) { error in
                XCTAssertEqual(error as? ArchiveServiceError, .operationCancelled)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.contains("partial-") }
            XCTAssertTrue(leftovers.isEmpty, "partial outputs: \(leftovers)")
        }
    }

    func testSymbolicLinksAreRejected() throws {
        let target = root.appendingPathComponent("target.txt")
        try Data("target".utf8).write(to: target)
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(
            try service.createArchive(
                from: [link],
                destinationURL: root.appendingPathComponent("link.tuck"),
                settings: CompressionSettings(outputFormat: .tuck)
            )
        ) { error in
            guard case .tuckArchiveUnsupportedFeature = error as? ArchiveServiceError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testGoldenV1StoreArchive() throws {
        let sourceFixtureURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tuck-v1-store-golden.tuck")
        if ProcessInfo.processInfo.environment["TUCKBYTE_GENERATE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: sourceFixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let source = root.appendingPathComponent("golden.txt")
            try Data("TuckByte v1 golden vector\n".utf8).write(to: source)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
                 .posixPermissions: 0o640],
                ofItemAtPath: source.path
            )
            try service.createArchive(
                from: [source],
                destinationURL: sourceFixtureURL,
                settings: CompressionSettings(outputFormat: .tuck, compressionLevel: 1)
            )
        }
        let fixtureURL = ProcessInfo.processInfo.environment["TUCKBYTE_GENERATE_GOLDEN"] == "1"
            ? sourceFixtureURL
            : try XCTUnwrap(Bundle.module.url(
                forResource: "tuck-v1-store-golden",
                withExtension: "tuck",
                subdirectory: "Fixtures"
            ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))
        XCTAssertEqual(try Data(contentsOf: fixtureURL).prefix(8), TuckArchiveFormat.magic)
        let entry = try XCTUnwrap(try service.inspect(archiveURL: fixtureURL).first)
        XCTAssertEqual(entry.path, "golden.txt")
        XCTAssertEqual(entry.size, 26)
        let destination = root.appendingPathComponent("golden-output", isDirectory: true)
        try service.extract(archiveURL: fixtureURL, destinationURL: destination)
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("golden.txt")),
            "TuckByte v1 golden vector\n"
        )
    }

    private func readUInt64LE(_ data: Data, at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { value, index in
            value | (UInt64(data[offset + index]) << UInt64(index * 8))
        }
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { value, index in
            value | (UInt32(data[offset + index]) << UInt32(index * 8))
        }
    }
}
