import Foundation

public final class ShellArchiveService: ArchiveService {
    private let fileManager: FileManager
    private let zipPath = "/usr/bin/zip"
    private let zipInfoPath = "/usr/bin/zipinfo"
    private let dittoPath = "/usr/bin/ditto"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(archiveURL: URL) throws -> [ArchiveEntry] {
        try validateReadableArchive(archiveURL)
        let result = try runExecutable(zipInfoPath, arguments: ["-1", archiveURL.path], currentDirectoryURL: nil)
        let entries = result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { path -> ArchiveEntry in
                let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = URL(fileURLWithPath: trimmedPath).lastPathComponent
                return ArchiveEntry(
                    name: name.isEmpty ? trimmedPath : name,
                    path: trimmedPath,
                    size: nil,
                    isDirectory: trimmedPath.hasSuffix("/"),
                    modifiedAt: nil
                )
            }

        if entries.isEmpty {
            throw ArchiveServiceError.couldNotParseArchive
        }
        return entries
    }

    public func extract(archiveURL: URL, destinationURL: URL) throws {
        try validateReadableArchive(archiveURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        _ = try runExecutable(dittoPath, arguments: ["-x", "-k", archiveURL.path, destinationURL.path], currentDirectoryURL: nil)
    }

    public func createZip(from sourceURLs: [URL], destinationURL: URL) throws {
        if sourceURLs.isEmpty {
            throw ArchiveServiceError.emptySelection
        }
        for sourceURL in sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ArchiveServiceError.fileDoesNotExist(sourceURL)
            }
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }

        let workingDirectory = sourceURLs[0].deletingLastPathComponent()
        let names = sourceURLs.map { $0.lastPathComponent }
        _ = try runExecutable(zipPath, arguments: ["-r", destinationURL.path] + names, currentDirectoryURL: workingDirectory)
    }

    private func validateReadableArchive(_ archiveURL: URL) throws {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw ArchiveServiceError.fileDoesNotExist(archiveURL)
        }
        let format = ArchiveFormat(fileURL: archiveURL)
        guard format.isSupportedInFirstVersion else {
            throw ArchiveServiceError.unsupportedFormat(format)
        }
    }

    private func runExecutable(_ executablePath: String, arguments: [String], currentDirectoryURL: URL?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ArchiveServiceError.commandFailed(
                command: URL(fileURLWithPath: executablePath).lastPathComponent,
                status: process.terminationStatus,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return CommandResult(output: output, status: process.terminationStatus)
    }
}

private struct CommandResult {
    let output: String
    let status: Int32
}
