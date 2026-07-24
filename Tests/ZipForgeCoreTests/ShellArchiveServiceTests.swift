import XCTest
@testable import ZipForgeCore

final class ShellArchiveServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var service: ShellArchiveService!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZipForgeTests-\(UUID().uuidString)", isDirectory: true)
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
        try "Hello ZipForge".data(using: .utf8)!.write(to: fileURL)

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
        XCTAssertEqual(extractedText, "Hello ZipForge")
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
        let settings = CompressionSettings(compressionLevel: 1, filenameEncoding: .utf8, encryption: .none)
        try service.createZip(from: [sourceURL], destinationURL: zipURL, settings: settings)

        let entries = try service.inspect(archiveURL: zipURL)
        XCTAssertTrue(entries.contains { $0.path == "fast.txt" })
    }

    func testEncryptedZipRequiresPassword() throws {
        let sourceURL = tempDirectory.appendingPathComponent("secret.txt")
        try "Secret".data(using: .utf8)!.write(to: sourceURL)

        let zipURL = tempDirectory.appendingPathComponent("Secret.zip")
        let settings = CompressionSettings(compressionLevel: 6, filenameEncoding: .utf8, encryption: .zipCrypto(password: ""))

        XCTAssertThrowsError(try service.createZip(from: [sourceURL], destinationURL: zipURL, settings: settings)) { error in
            XCTAssertEqual(error as? ArchiveServiceError, .encryptionPasswordRequired)
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
