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
        XCTAssertTrue(entries.contains { $0.path == "Source/hello.txt" || $0.path == "Source/hello.txt/" })

        let destinationURL = tempDirectory.appendingPathComponent("Extracted", isDirectory: true)
        try service.extract(archiveURL: zipURL, destinationURL: destinationURL)
        let extractedFileURL = destinationURL.appendingPathComponent("Source/hello.txt")
        let extractedText = try String(contentsOf: extractedFileURL)
        XCTAssertEqual(extractedText, "Hello ZipForge")
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
