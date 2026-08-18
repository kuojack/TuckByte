import XCTest
@testable import TuckByteCore

final class ArchiveFormatTests: XCTestCase {
    func testDetectsKnownFormats() {
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.zip")), .zip)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.zip.001")), .splitZip)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.ZIP.025")), .splitZip)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.tuck")), .tuck)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.TUCK.025")), .splitTuck)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.7z")), .sevenZip)
        XCTAssertTrue(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.7z")).isSupportedForReading)
    }

    func testMarksUnknownFormatUnsupported() {
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "notes.txt")), .unsupported)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.001")), .unsupported)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.rar")), .unsupported)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.tar")), .unsupported)
    }

    func testZipAndTuckCanBeCreated() {
        XCTAssertEqual(ArchiveOutputFormat.allCases, [.zip, .tuck])
    }
}
