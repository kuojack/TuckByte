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
        archiveURLs.map { archiveURL in
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
        let baseName = archiveURL.deletingPathExtension().lastPathComponent
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
}
