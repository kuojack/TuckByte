import XCTest
@testable import TuckByteCore

final class ShellArchiveServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var service: ShellArchiveService!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TuckByteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        service = ShellArchiveService()
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testMissingArchiveReturnsFriendlyError() {
        let missingURL = tempDirectory.appendingPathComponent("missing.zip")
        XCTAssertThrowsError(try service.inspect(archiveURL: missingURL)) { error in
            XCTAssertEqual(error as? ArchiveServiceError, .fileDoesNotExist(missingURL))
        }
    }

    func testUnsupportedArchiveReturnsFriendlyError() throws {
        let rarURL = tempDirectory.appendingPathComponent("archive.rar")
        try Data().write(to: rarURL)
        XCTAssertThrowsError(try service.inspect(archiveURL: rarURL)) { error in
            XCTAssertEqual(error as? ArchiveServiceError, .unsupportedFormat(.rar))
        }
    }

    func testCreateInspectAndExtractZipRoundTrip() throws {
        let sourceDirectory = tempDirectory.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true, attributes: nil)
        let fileURL = sourceDirectory.appendingPathComponent("hello.txt")
        try "Hello TuckByte".data(using: .utf8)!.write(to: fileURL)

        let zipURL = tempDirectory.appendingPathComponent("Archive.zip")
        try service.createZip(from: [sourceDirectory], destinationURL: zipURL)

        let entries = try service.inspect(archiveURL: zipURL)
        let fileEntry = try XCTUnwrap(entries.first { $0.path == "Source/hello.txt" })
        XCTAssertEqual(fileEntry.name, "hello.txt")
        XCTAssertEqual(fileEntry.size, 14)
        XCTAssertFalse(fileEntry.isDirectory)
        XCTAssertNotNil(fileEntry.modifiedAt)

        let destinationURL = tempDirectory.appendingPathComponent("Extracted", isDirectory: true)
        try service.extract(archiveURL: zipURL, destinationURL: destinationURL)
        let extractedFileURL = destinationURL.appendingPathComponent("Source/hello.txt")
        let extractedText = try String(contentsOf: extractedFileURL)
        XCTAssertEqual(extractedText, "Hello TuckByte")
    }

    func testCreateZipFromMultipleParentDirectories() throws {
        let firstDirectory = tempDirectory.appendingPathComponent("First", isDirectory: true)
        let secondDirectory = tempDirectory.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true, attributes: nil)

        let firstFile = firstDirectory.appendingPathComponent("one.txt")
        let secondFile = secondDirectory.appendingPathComponent("two.txt")
        try "One".data(using: .utf8)!.write(to: firstFile)
        try "Two".data(using: .utf8)!.write(to: secondFile)

        let zipURL = tempDirectory.appendingPathComponent("MultiSource.zip")
        try service.createZip(from: [firstFile, secondFile], destinationURL: zipURL)

        let entries = try service.inspect(archiveURL: zipURL)
        XCTAssertTrue(entries.contains { $0.path == "one.txt" })
        XCTAssertTrue(entries.contains { $0.path == "two.txt" })

        let destinationURL = tempDirectory.appendingPathComponent("MultiExtracted", isDirectory: true)
        try service.extract(archiveURL: zipURL, destinationURL: destinationURL)
        XCTAssertEqual(try String(contentsOf: destinationURL.appendingPathComponent("one.txt")), "One")
        XCTAssertEqual(try String(contentsOf: destinationURL.appendingPathComponent("two.txt")), "Two")
    }

    func testCreateZipUsesCompressionSettings() throws {
        let sourceURL = tempDirectory.appendingPathComponent("fast.txt")
        try "Fast".data(using: .utf8)!.write(to: sourceURL)

        let zipURL = tempDirectory.appendingPathComponent("Fast.zip")
        let settings = CompressionSettings(outputFormat: .zip, compressionLevel: 1, encryption: .none)
        try service.createZip(from: [sourceURL], destinationURL: zipURL, settings: settings)

        let entries = try service.inspect(archiveURL: zipURL)
        XCTAssertTrue(entries.contains { $0.path == "fast.txt" })
    }

    func testPreservesUnicodeFilenameWhenCreatingInspectingAndExtracting() throws {
        let filename = "index 可框選區域.html"
        let sourceURL = tempDirectory.appendingPathComponent(filename)
        try "Unicode filename".data(using: .utf8)!.write(to: sourceURL)

        let zipURL = tempDirectory.appendingPathComponent("Unicode.zip")
        try service.createZip(from: [sourceURL], destinationURL: zipURL)

        let entries = try service.inspect(archiveURL: zipURL)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.name, filename)
        XCTAssertEqual(entry.path, filename)

        let destinationURL = tempDirectory.appendingPathComponent("UnicodeExtracted", isDirectory: true)
        try service.extract(archiveURL: zipURL, destinationURL: destinationURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent(filename).path))
    }

    func testWrapsExistingArchiveInAnotherZip() throws {
        let sourceFileURL = tempDirectory.appendingPathComponent("內容.txt")
        try "Nested by TuckByte".data(using: .utf8)!.write(to: sourceFileURL)

        let innerArchiveURL = tempDirectory.appendingPathComponent("Inner.zip")
        try service.createZip(from: [sourceFileURL], destinationURL: innerArchiveURL)

        let outerArchiveURL = tempDirectory.appendingPathComponent("Outer.zip")
        let settings = CompressionSettings(outputFormat: .zip, compressionLevel: 9, encryption: .none)
        try service.createZip(from: [innerArchiveURL], destinationURL: outerArchiveURL, settings: settings)

        let outerEntries = try service.inspect(archiveURL: outerArchiveURL)
        XCTAssertTrue(outerEntries.contains { $0.path == "Inner.zip" })
        XCTAssertFalse(outerEntries.contains { $0.path == "內容.txt" })

        let destinationURL = tempDirectory.appendingPathComponent("OuterExtracted", isDirectory: true)
        try service.extract(archiveURL: outerArchiveURL, destinationURL: destinationURL)
        let extractedInnerArchiveURL = destinationURL.appendingPathComponent("Inner.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedInnerArchiveURL.path))
        let innerEntries = try service.inspect(archiveURL: extractedInnerArchiveURL)
        XCTAssertTrue(innerEntries.contains { $0.path == "內容.txt" })
    }

    func testEncryptedZipRequiresPassword() throws {
        let sourceURL = tempDirectory.appendingPathComponent("secret.txt")
        try "Secret".data(using: .utf8)!.write(to: sourceURL)

        let zipURL = tempDirectory.appendingPathComponent("Secret.zip")
        let settings = CompressionSettings(outputFormat: .zip, compressionLevel: 6, encryption: .zipCrypto(password: ""))

        XCTAssertThrowsError(try service.createZip(from: [sourceURL], destinationURL: zipURL, settings: settings)) { error in
            XCTAssertEqual(error as? ArchiveServiceError, .encryptionPasswordRequired)
        }
    }

    func testUnsupportedCreationFormatReturnsFriendlyError() throws {
        let sourceURL = tempDirectory.appendingPathComponent("archive-me.txt")
        try "Format".data(using: .utf8)!.write(to: sourceURL)

        let destinationURL = tempDirectory.appendingPathComponent("Archive.7z")
        let settings = CompressionSettings(outputFormat: .sevenZip, compressionLevel: 6, encryption: .none)

        XCTAssertThrowsError(try service.createZip(from: [sourceURL], destinationURL: destinationURL, settings: settings)) { error in
            XCTAssertEqual(error as? ArchiveServiceError, .unsupportedCreationFormat(.sevenZip))
        }
    }

    func testRefusesToOverwriteExistingDestination() throws {
        let sourceURL = tempDirectory.appendingPathComponent("hello.txt")
        try "Hello".data(using: .utf8)!.write(to: sourceURL)
        let zipURL = tempDirectory.appendingPathComponent("Archive.zip")
        try service.createZip(from: [sourceURL], destinationURL: zipURL)

        XCTAssertThrowsError(try service.createZip(from: [sourceURL], destinationURL: zipURL)) { error in
            XCTAssertEqual(error as? ArchiveServiceError, .destinationAlreadyExists(zipURL))
        }
    }
}
