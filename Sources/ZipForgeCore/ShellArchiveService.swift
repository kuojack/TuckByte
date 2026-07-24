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
        let result = try runExecutable(zipInfoPath, arguments: ["-l", "-T", archiveURL.path], currentDirectoryURL: nil)
        let entries = result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { Self.parseZipInfoLine($0) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
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

    public func createZip(from sourceURLs: [URL], destinationURL: URL, settings: CompressionSettings = .standard) throws {
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

        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ZipForge-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true, attributes: nil)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        var stagedNames: [String] = []
        for sourceURL in sourceURLs {
            let stagedName = uniqueStagedName(for: sourceURL, existingNames: Set(stagedNames))
            let stagedURL = stagingDirectory.appendingPathComponent(stagedName)
            try fileManager.copyItem(at: sourceURL, to: stagedURL)
            stagedNames.append(stagedName)
        }

        var arguments = ["-r", "-\(settings.compressionLevel)"]
        switch settings.encryption {
        case .none:
            break
        case .zipCrypto(let password):
            guard !password.isEmpty else {
                throw ArchiveServiceError.encryptionPasswordRequired
            }
            arguments += ["-P", password]
        }
        arguments += [destinationURL.path] + stagedNames
        _ = try runExecutable(zipPath, arguments: arguments, currentDirectoryURL: stagingDirectory)
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

    private static func parseZipInfoLine(_ line: String) -> ArchiveEntry? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("d") else {
            return nil
        }

        let parts = trimmedLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 9,
              let size = Int64(parts[3]) else {
            return nil
        }

        let dateText = String(parts[7])
        let path = parts[8...].joined(separator: " ")
        let isDirectory = trimmedLine.hasPrefix("d") || path.hasSuffix("/")
        let name = URL(fileURLWithPath: path).lastPathComponent

        return ArchiveEntry(
            name: name.isEmpty ? path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : name,
            path: path,
            size: isDirectory ? nil : size,
            isDirectory: isDirectory,
            modifiedAt: zipInfoDateFormatter.date(from: dateText)
        )
    }

    private static let zipInfoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd.HHmmss"
        return formatter
    }()

    private func uniqueStagedName(for sourceURL: URL, existingNames: Set<String>) -> String {
        let baseName = sourceURL.lastPathComponent.isEmpty ? "Item" : sourceURL.lastPathComponent
        guard existingNames.contains(baseName) else {
            return baseName
        }

        let name = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(name)-\(index)" : "\(name)-\(index).\(ext)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }
}

private struct CommandResult {
    let output: String
    let status: Int32
}
