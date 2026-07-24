import Foundation
import XCTest
@testable import TuckByteCore

final class ArchiveDirectoryBrowserTests: XCTestCase {
    func testRootShowsDirectChildrenAndSynthesizesMissingFolderEntries() {
        let entries = [
            makeEntry(path: "readme.txt"),
            makeEntry(path: "Documents/report.txt"),
            makeEntry(path: "Documents/Images/photo.jpg")
        ]

        XCTAssertEqual(
            ArchiveDirectoryBrowser.entries(in: "", from: entries),
            [
                makeEntry(path: "Documents/", isDirectory: true),
                makeEntry(path: "readme.txt")
            ]
        )
    }

    func testNestedDirectoryShowsOnlyItsDirectChildren() {
        let entries = [
            makeEntry(path: "Documents/report.txt"),
            makeEntry(path: "Documents/Images/photo.jpg"),
            makeEntry(path: "unrelated.txt")
        ]

        XCTAssertEqual(
            ArchiveDirectoryBrowser.entries(in: "Documents/", from: entries),
            [
                makeEntry(path: "Documents/Images/", isDirectory: true),
                makeEntry(path: "Documents/report.txt")
            ]
        )
    }

    func testExplicitDirectoryEntryReplacesSynthesizedEntry() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            makeEntry(path: "Folder/file.txt"),
            ArchiveEntry(
                name: "Folder",
                path: "Folder/",
                size: 0,
                isDirectory: true,
                modifiedAt: date
            )
        ]

        let result = ArchiveDirectoryBrowser.entries(in: "", from: entries)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "Folder/")
        XCTAssertEqual(result[0].size, 0)
        XCTAssertEqual(result[0].modifiedAt, date)
    }

    func testBreadcrumbsAndParentPaths() {
        XCTAssertEqual(
            ArchiveDirectoryBrowser.breadcrumbs(for: "One/Two/"),
            [
                ArchiveBreadcrumb(name: "根目錄", path: ""),
                ArchiveBreadcrumb(name: "One", path: "One/"),
                ArchiveBreadcrumb(name: "Two", path: "One/Two/")
            ]
        )
        XCTAssertEqual(
            ArchiveDirectoryBrowser.parentPath(of: "One/Two/"),
            "One/"
        )
        XCTAssertEqual(ArchiveDirectoryBrowser.parentPath(of: "One/"), "")
        XCTAssertEqual(ArchiveDirectoryBrowser.parentPath(of: ""), "")
    }

    func testUnsafePathsAreIgnored() {
        let entries = [
            makeEntry(path: "../secret.txt"),
            makeEntry(path: "/absolute.txt"),
            makeEntry(path: "safe/file.txt")
        ]

        XCTAssertEqual(
            ArchiveDirectoryBrowser.entries(in: "", from: entries),
            [makeEntry(path: "safe/", isDirectory: true)]
        )
        XCTAssertNil(ArchiveDirectoryBrowser.canonicalDirectoryPath("../"))
    }

    private func makeEntry(
        path: String,
        isDirectory: Bool = false
    ) -> ArchiveEntry {
        let trimmedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        return ArchiveEntry(
            name: URL(fileURLWithPath: trimmedPath).lastPathComponent,
            path: path,
            size: nil,
            isDirectory: isDirectory,
            modifiedAt: nil
        )
    }
}
