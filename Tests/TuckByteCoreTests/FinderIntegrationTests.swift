import XCTest
@testable import TuckByteCore
@testable import TuckByteIntegration

final class FinderIntegrationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TuckByteFinderTests-\(UUID().uuidString)", isDirectory: true)
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

    func testFinderActionURLRoundTripPreservesUnicodeSpacesAndMultiplePaths() throws {
        let firstURL = tempDirectory.appendingPathComponent("中文 檔案.txt")
        let secondURL = tempDirectory.appendingPathComponent("外接磁碟資料夾", isDirectory: true)
        try Data().write(to: firstURL)
        try FileManager.default.createDirectory(
            at: secondURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let request = FinderActionRequest(
            operation: .addToArchive,
            selectedURLs: [firstURL, secondURL]
        )
        let encodedURL = try XCTUnwrap(request.url)
        let decodedRequest = try XCTUnwrap(FinderActionRequest(url: encodedURL))

        XCTAssertEqual(decodedRequest, request)
    }

    func testFinderActionRejectsUnknownOperationAndMissingFiles() throws {
        let unknownOperationURL = try XCTUnwrap(
            URL(string: "tuckbyte://finder?operation=unknown&path=/tmp/file.zip")
        )
        XCTAssertNil(FinderActionRequest(url: unknownOperationURL, fileExists: { _ in true }))

        let missingFileURL = try XCTUnwrap(
            URL(string: "tuckbyte://finder?operation=extractHere&path=/tmp/missing.zip")
        )
        XCTAssertNil(FinderActionRequest(url: missingFileURL, fileExists: { _ in false }))
    }

    func testFinderMenuPolicyRequiresAllSelectedFilesToBeZipForExtraction() {
        let firstZip = URL(fileURLWithPath: "/tmp/One.zip")
        let secondZip = URL(fileURLWithPath: "/Volumes/External/Two.ZIP")
        let textFile = URL(fileURLWithPath: "/tmp/Notes.txt")

        XCTAssertTrue(FinderMenuPolicy.canAddToArchive([textFile]))
        XCTAssertTrue(
            FinderMenuPolicy.canExtractHere([firstZip, secondZip], isRegularFile: { _ in true })
        )
        XCTAssertFalse(
            FinderMenuPolicy.canExtractHere([firstZip, textFile], isRegularFile: { _ in true })
        )
        XCTAssertFalse(FinderMenuPolicy.canExtractHere([]))
    }

    func testBatchExtractionUsesNumberedDestinationAndContinuesAfterFailure() throws {
        let service = ShellArchiveService()
        let sourceFileURL = tempDirectory.appendingPathComponent("payload.txt")
        try "Finder extraction".data(using: .utf8)!.write(to: sourceFileURL)

        let validArchiveURL = tempDirectory.appendingPathComponent("Archive.zip")
        try service.createZip(from: [sourceFileURL], destinationURL: validArchiveURL)
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Archive", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let corruptArchiveURL = tempDirectory.appendingPathComponent("Corrupt.zip")
        try "not a zip".data(using: .utf8)!.write(to: corruptArchiveURL)

        let extractor = ArchiveBatchExtractor(archiveService: service)
        let results = extractor.extractHere([corruptArchiveURL, validArchiveURL])

        XCTAssertEqual(results.count, 2)
        XCTAssertFalse(results[0].succeeded)
        XCTAssertTrue(results[1].succeeded)
        XCTAssertEqual(results[1].destinationURL?.lastPathComponent, "Archive 2")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempDirectory
                    .appendingPathComponent("Archive 2/payload.txt")
                    .path
            )
        )
    }
}
