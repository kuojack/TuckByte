import Foundation

public struct ArchiveExtractionResult: Equatable {
    public let archiveURL: URL
    public let destinationURL: URL?
    public let errorDescription: String?

    public var succeeded: Bool {
        destinationURL != nil && errorDescription == nil
    }

    public init(archiveURL: URL, destinationURL: URL?, errorDescription: String?) {
        self.archiveURL = archiveURL
        self.destinationURL = destinationURL
        self.errorDescription = errorDescription
    }
}

public final class ArchiveBatchExtractor {
    private let archiveService: ArchiveService
    private let fileManager: FileManager

    public init(
        archiveService: ArchiveService = ShellArchiveService(),
        fileManager: FileManager = .default
    ) {
        self.archiveService = archiveService
        self.fileManager = fileManager
    }

    public func extractHere(_ archiveURLs: [URL]) -> [ArchiveExtractionResult] {
        canonicalArchiveURLs(archiveURLs).map { archiveURL in
            let destinationURL = availableDestination(for: archiveURL)
            do {
                try archiveService.extract(
                    archiveURL: archiveURL,
                    destinationURL: destinationURL
                )
                return ArchiveExtractionResult(
                    archiveURL: archiveURL,
                    destinationURL: destinationURL,
                    errorDescription: nil
                )
            } catch {
                return ArchiveExtractionResult(
                    archiveURL: archiveURL,
                    destinationURL: nil,
                    errorDescription: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    public func availableDestination(for archiveURL: URL) -> URL {
        let parentURL = archiveURL.deletingLastPathComponent()
        let logicalArchiveURL = SplitZipArchive.logicalArchiveURL(for: archiveURL)
            ?? archiveURL
        let baseName = logicalArchiveURL.deletingPathExtension().lastPathComponent
        let initialURL = parentURL.appendingPathComponent(baseName, isDirectory: true)
        guard fileManager.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        var suffix = 2
        while true {
            let candidateURL = parentURL
                .appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }

    private func canonicalArchiveURLs(_ archiveURLs: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return archiveURLs.compactMap { archiveURL in
            let canonicalURL = SplitZipArchive.firstVolumeURL(for: archiveURL)
                ?? archiveURL
            let standardizedURL = canonicalURL.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                return nil
            }
            return standardizedURL
        }
    }
}
