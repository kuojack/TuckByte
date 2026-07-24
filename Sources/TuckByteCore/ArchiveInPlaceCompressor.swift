import Foundation

public struct ArchiveCompressionResult: Equatable {
    public let sourceURLs: [URL]
    public let destinationURL: URL?
    public let errorDescription: String?

    public var succeeded: Bool {
        destinationURL != nil && errorDescription == nil
    }

    public init(
        sourceURLs: [URL],
        destinationURL: URL?,
        errorDescription: String?
    ) {
        self.sourceURLs = sourceURLs
        self.destinationURL = destinationURL
        self.errorDescription = errorDescription
    }
}

public final class ArchiveInPlaceCompressor {
    private let archiveService: ArchiveService
    private let fileManager: FileManager

    public init(
        archiveService: ArchiveService = ShellArchiveService(),
        fileManager: FileManager = .default
    ) {
        self.archiveService = archiveService
        self.fileManager = fileManager
    }

    public func compressHere(_ sourceURLs: [URL]) -> ArchiveCompressionResult {
        do {
            let destinationURL = try availableDestination(for: sourceURLs)
            try archiveService.createZip(
                from: sourceURLs,
                destinationURL: destinationURL,
                settings: .standard
            )
            return ArchiveCompressionResult(
                sourceURLs: sourceURLs,
                destinationURL: destinationURL,
                errorDescription: nil
            )
        } catch {
            return ArchiveCompressionResult(
                sourceURLs: sourceURLs,
                destinationURL: nil,
                errorDescription: (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            )
        }
    }

    public func availableDestination(for sourceURLs: [URL]) throws -> URL {
        guard !sourceURLs.isEmpty else {
            throw ArchiveServiceError.emptySelection
        }

        let standardizedURLs = sourceURLs.map(\.standardizedFileURL)
        let parentURLs = Set(
            standardizedURLs.map {
                $0.deletingLastPathComponent().standardizedFileURL
            }
        )
        guard parentURLs.count == 1, let parentURL = parentURLs.first else {
            throw ArchiveServiceError.selectionSpansMultipleDirectories
        }

        let baseName = destinationBaseName(
            for: standardizedURLs,
            parentURL: parentURL
        )
        return firstAvailableDestination(baseName: baseName, parentURL: parentURL)
    }

    private func destinationBaseName(
        for sourceURLs: [URL],
        parentURL: URL
    ) -> String {
        guard sourceURLs.count == 1, let sourceURL = sourceURLs.first else {
            let parentName = parentURL.lastPathComponent
            return parentURL.path == "/" || parentName.isEmpty
                ? "Archive"
                : parentName
        }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
            atPath: sourceURL.path,
            isDirectory: &isDirectory
        )
        if exists && isDirectory.boolValue {
            return sourceURL.lastPathComponent.isEmpty
                ? "Archive"
                : sourceURL.lastPathComponent
        }

        let nameWithoutExtension = sourceURL
            .deletingPathExtension()
            .lastPathComponent
        let baseName = nameWithoutExtension.isEmpty
            ? sourceURL.lastPathComponent
            : nameWithoutExtension
        if sourceURL.pathExtension.lowercased() == "zip" {
            return "\(baseName)-外層"
        }
        return baseName.isEmpty ? "Archive" : baseName
    }

    private func firstAvailableDestination(
        baseName: String,
        parentURL: URL
    ) -> URL {
        let initialURL = parentURL.appendingPathComponent("\(baseName).zip")
        guard fileManager.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        var suffix = 2
        while true {
            let candidateURL = parentURL
                .appendingPathComponent("\(baseName) \(suffix).zip")
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }
}
