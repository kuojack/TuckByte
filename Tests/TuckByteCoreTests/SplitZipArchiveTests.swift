import XCTest
@testable import TuckByteCore

final class SplitZipArchiveTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TuckByteSplitTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testSplitAndAssemblePreserveExactBytes() throws {
        let originalData = Data((0..<1_025).map { UInt8($0 % 251) })
        let archiveURL = tempDirectory.appendingPathComponent("Original.zip")
        try originalData.write(to: archiveURL)
        let firstVolumeURL = tempDirectory
            .appendingPathComponent("中文壓縮.zip.001")

        let volumeURLs = try SplitZipArchive.split(
            archiveURL: archiveURL,
            firstVolumeURL: firstVolumeURL,
            volumeSizeBytes: 256
        )

        XCTAssertEqual(volumeURLs.map(\.lastPathComponent), [
            "中文壓縮.zip.001",
            "中文壓縮.zip.002",
            "中文壓縮.zip.003",
            "中文壓縮.zip.004",
            "中文壓縮.zip.005"
        ])
        XCTAssertEqual(
            try Data(contentsOf: volumeURLs[0]).count,
            256
        )

        let assembledURL = tempDirectory.appendingPathComponent("Assembled.zip")
        try SplitZipArchive.assemble(
            startingAt: volumeURLs[2],
            destinationURL: assembledURL
        )
        XCTAssertEqual(try Data(contentsOf: assembledURL), originalData)
    }

    func testMissingIntermediateVolumeReturnsFriendlyError() throws {
        let firstURL = tempDirectory.appendingPathComponent("Archive.zip.001")
        let thirdURL = tempDirectory.appendingPathComponent("Archive.zip.003")
        try Data([1]).write(to: firstURL)
        try Data([3]).write(to: thirdURL)

        XCTAssertThrowsError(
            try SplitZipArchive.volumeURLs(startingAt: thirdURL)
        ) { error in
            XCTAssertEqual(
                error as? ArchiveServiceError,
                .splitArchiveMissingVolume(
                    self.tempDirectory.appendingPathComponent("Archive.zip.002")
                )
            )
        }
    }

    func testRequiresZipDotThreeDigitVolumeName() throws {
        let invalidURL = tempDirectory.appendingPathComponent("Archive.001")
        try Data().write(to: invalidURL)

        XCTAssertFalse(SplitZipArchive.isVolumeURL(invalidURL))
        XCTAssertThrowsError(
            try SplitZipArchive.assemble(
                startingAt: invalidURL,
                destinationURL: tempDirectory.appendingPathComponent("Output.zip")
            )
        ) { error in
            XCTAssertEqual(
                error as? ArchiveServiceError,
                .invalidSplitArchiveName(invalidURL)
            )
        }
    }
}
