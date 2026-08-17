import XCTest
@testable import TuckByteCore

final class ArchiveFormatTests: XCTestCase {
    func testDetectsKnownFormats() {
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.zip")), .zip)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.zip.001")), .splitZip)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.ZIP.025")), .splitZip)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.7z")), .sevenZip)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.rar")), .rar)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.tar")), .tar)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.tar.gz")), .gzip)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.tgz")), .gzip)
    }

    func testMarksUnknownFormatUnsupported() {
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "notes.txt")), .unsupported)
        XCTAssertEqual(ArchiveFormat(fileURL: URL(fileURLWithPath: "sample.001")), .unsupported)
    }
}
