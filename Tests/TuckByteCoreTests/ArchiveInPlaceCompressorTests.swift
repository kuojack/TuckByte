import XCTest
@testable import TuckByteCore

final class ArchiveInPlaceCompressorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TuckByteInPlaceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testDestinationNamesSingleFileFolderAndExistingZip() throws {
        let compressor = ArchiveInPlaceCompressor()

        let fileURL = tempDirectory.appendingPathComponent("報告.txt")
        try Data().write(to: fileURL)
        XCTAssertEqual(
            try compressor.availableDestination(for: [fileURL]).lastPathComponent,
            "報告.zip"
        )

        let folderURL = tempDirectory
            .appendingPathComponent("專案.v1", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        XCTAssertEqual(
            try compressor.availableDestination(for: [folderURL]).lastPathComponent,
            "專案.v1.zip"
        )

        let archiveURL = tempDirectory.appendingPathComponent("Report.zip")
        try Data().write(to: archiveURL)
        XCTAssertEqual(
            try compressor.availableDestination(for: [archiveURL]).lastPathComponent,
            "Report-外層.zip"
        )
    }

    func testMultipleItemsUseParentFolderNameAndRootFallsBackToArchive() throws {
        let compressor = ArchiveInPlaceCompressor()
        let firstURL = tempDirectory.appendingPathComponent("One.txt")
        let secondURL = tempDirectory.appendingPathComponent("Two.txt")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        XCTAssertEqual(
            try compressor
                .availableDestination(for: [firstURL, secondURL])
                .lastPathComponent,
            "\(tempDirectory.lastPathComponent).zip"
        )

        let rootDestination = try compressor.availableDestination(
            for: [
                URL(fileURLWithPath: "/One.txt"),
                URL(fileURLWithPath: "/Two.txt")
            ]
        )
        XCTAssertEqual(rootDestination.path, "/Archive.zip")
    }

    func testExistingDestinationUsesNextAvailableSequenceNumber() throws {
        let compressor = ArchiveInPlaceCompressor()
        let sourceURL = tempDirectory.appendingPathComponent("報告.txt")
        try Data().write(to: sourceURL)
        try Data().write(
            to: tempDirectory.appendingPathComponent("報告.zip")
        )
        try Data().write(
            to: tempDirectory.appendingPathComponent("報告 2.zip")
        )

        XCTAssertEqual(
            try compressor.availableDestination(for: [sourceURL]).lastPathComponent,
            "報告 3.zip"
        )
    }

    func testSelectionAcrossDirectoriesRequiresInterface() throws {
        let compressor = ArchiveInPlaceCompressor()
        let otherDirectory = tempDirectory
            .appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(
            at: otherDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let firstURL = tempDirectory.appendingPathComponent("One.txt")
        let secondURL = otherDirectory.appendingPathComponent("Two.txt")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        XCTAssertThrowsError(
            try compressor.availableDestination(for: [firstURL, secondURL])
        ) { error in
            XCTAssertEqual(
                error as? ArchiveServiceError,
                .selectionSpansMultipleDirectories
            )
        }
    }

    func testCompressHereUsesStandardSettingsAndPreservesUnicodeContent() throws {
        let service = RecordingArchiveService()
        let compressor = ArchiveInPlaceCompressor(archiveService: service)
        let sourceURL = tempDirectory.appendingPathComponent("中文 檔案.txt")
        try "TuckByte 原地壓縮".data(using: .utf8)!.write(to: sourceURL)

        let recordedResult = compressor.compressHere([sourceURL])
        XCTAssertTrue(recordedResult.succeeded)
        XCTAssertEqual(service.settings, .standard)
        XCTAssertEqual(service.sourceURLs, [sourceURL])

        let realCompressor = ArchiveInPlaceCompressor()
        let realResult = realCompressor.compressHere([sourceURL])
        let archiveURL = try XCTUnwrap(realResult.destinationURL)
        XCTAssertTrue(realResult.succeeded)

        let extractionURL = tempDirectory
            .appendingPathComponent("Extracted", isDirectory: true)
        try ShellArchiveService().extract(
            archiveURL: archiveURL,
            destinationURL: extractionURL
        )
        let extractedText = try String(
            contentsOf: extractionURL.appendingPathComponent("中文 檔案.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(extractedText, "TuckByte 原地壓縮")
    }
}

private final class RecordingArchiveService: ArchiveService {
    private(set) var sourceURLs: [URL]?
    private(set) var destinationURL: URL?
    private(set) var settings: CompressionSettings?

    func inspect(archiveURL: URL) throws -> [ArchiveEntry] {
        []
    }

    func extract(archiveURL: URL, destinationURL: URL) throws {
    }

    func createZip(
        from sourceURLs: [URL],
        destinationURL: URL,
        settings: CompressionSettings
    ) throws {
        self.sourceURLs = sourceURLs
        self.destinationURL = destinationURL
        self.settings = settings
        try Data().write(to: destinationURL)
    }
}
