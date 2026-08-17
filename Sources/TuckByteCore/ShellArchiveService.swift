import Foundation

public final class ShellArchiveService: ArchiveService {
    private let fileManager: FileManager
    private let zipPath = "/usr/bin/zip"
    private let zipInfoPath = "/usr/bin/zipinfo"
    private let tarPath = "/usr/bin/tar"
    private let dittoPath = "/usr/bin/ditto"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(archiveURL: URL) throws -> [ArchiveEntry] {
        let preparedArchive = try prepareReadableArchive(archiveURL)
        defer { preparedArchive.removeTemporaryFiles(fileManager: fileManager) }
        let readableURL = preparedArchive.url

        let zipInfoResult: CommandResult
        do {
            zipInfoResult = try runExecutable(
                zipInfoPath,
                arguments: ["-l", "-T", readableURL.path],
                currentDirectoryURL: nil
            )
        } catch {
            if ArchiveFormat(fileURL: archiveURL) == .splitZip {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    archiveURL
                )
            }
            throw error
        }
        let metadataLines = zipInfoResult.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter(Self.isZipInfoEntryLine)
        let pathResult: CommandResult
        do {
            pathResult = try runExecutable(
                tarPath,
                arguments: ["-tf", readableURL.path],
                currentDirectoryURL: nil
            )
        } catch {
            if ArchiveFormat(fileURL: archiveURL) == .splitZip {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    archiveURL
                )
            }
            throw error
        }
        let paths = pathResult.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        guard metadataLines.count == paths.count else {
            if ArchiveFormat(fileURL: archiveURL) == .splitZip {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    archiveURL
                )
            }
            throw ArchiveServiceError.couldNotParseArchive
        }

        let entries = zip(metadataLines, paths)
            .compactMap { metadataLine, path in
                Self.parseZipInfoLine(metadataLine, archivePath: path)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }

        if entries.isEmpty {
            if ArchiveFormat(fileURL: archiveURL) == .splitZip {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    archiveURL
                )
            }
            throw ArchiveServiceError.couldNotParseArchive
        }
        return entries
    }

    public func extract(archiveURL: URL, destinationURL: URL) throws {
        let preparedArchive = try prepareReadableArchive(archiveURL)
        defer { preparedArchive.removeTemporaryFiles(fileManager: fileManager) }
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        do {
            _ = try runExecutable(
                dittoPath,
                arguments: ["-x", "-k", preparedArchive.url.path, destinationURL.path],
                currentDirectoryURL: nil
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if ArchiveFormat(fileURL: archiveURL) == .splitZip {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    archiveURL
                )
            }
            throw error
        }
    }

    public func createZip(from sourceURLs: [URL], destinationURL: URL, settings: CompressionSettings = .standard) throws {
        guard settings.outputFormat.isSupportedForCreation else {
            throw ArchiveServiceError.unsupportedCreationFormat(settings.outputFormat)
        }
        if sourceURLs.isEmpty {
            throw ArchiveServiceError.emptySelection
        }
        for sourceURL in sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ArchiveServiceError.fileDoesNotExist(sourceURL)
            }
        }
        let createsSplitArchive = settings.volumeSizeBytes != nil
        if !createsSplitArchive && fileManager.fileExists(atPath: destinationURL.path) {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        if createsSplitArchive {
            guard let volumeSizeBytes = settings.volumeSizeBytes,
                  volumeSizeBytes > 0 else {
                throw ArchiveServiceError.invalidSplitVolumeSize
            }
            guard SplitZipArchive.firstVolumeURL(for: destinationURL)?.standardizedFileURL
                    == destinationURL.standardizedFileURL else {
                throw ArchiveServiceError.invalidSplitArchiveName(destinationURL)
            }
        }

        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TuckByte-\(UUID().uuidString)", isDirectory: true)
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
        let generatedArchiveURL = createsSplitArchive
            ? stagingDirectory.appendingPathComponent("Generated.zip")
            : destinationURL
        arguments += [generatedArchiveURL.path] + stagedNames
        _ = try runExecutable(zipPath, arguments: arguments, currentDirectoryURL: stagingDirectory)

        if let volumeSizeBytes = settings.volumeSizeBytes {
            try SplitZipArchive.split(
                archiveURL: generatedArchiveURL,
                firstVolumeURL: destinationURL,
                volumeSizeBytes: volumeSizeBytes,
                fileManager: fileManager
            )
        }
    }

    private func prepareReadableArchive(_ archiveURL: URL) throws -> PreparedArchive {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw ArchiveServiceError.fileDoesNotExist(archiveURL)
        }
        let format = ArchiveFormat(fileURL: archiveURL)
        guard format.isSupportedInFirstVersion else {
            throw ArchiveServiceError.unsupportedFormat(format)
        }

        guard format == .splitZip else {
            return PreparedArchive(url: archiveURL, temporaryRootURL: nil)
        }

        let temporaryRootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "TuckByte-Split-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: temporaryRootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        do {
            let logicalName = SplitZipArchive.logicalArchiveURL(for: archiveURL)?
                .lastPathComponent ?? "Archive.zip"
            let assembledURL = temporaryRootURL.appendingPathComponent(logicalName)
            try SplitZipArchive.assemble(
                startingAt: archiveURL,
                destinationURL: assembledURL,
                fileManager: fileManager
            )
            return PreparedArchive(
                url: assembledURL,
                temporaryRootURL: temporaryRootURL
            )
        } catch {
            try? fileManager.removeItem(at: temporaryRootURL)
            throw error
        }
    }

    private func runExecutable(_ executablePath: String, arguments: [String], currentDirectoryURL: URL?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8"
        ]) { _, utf8Locale in
            utf8Locale
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ArchiveServiceError.commandFailed(
                command: URL(fileURLWithPath: executablePath).lastPathComponent,
                status: process.terminationStatus,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return CommandResult(output: output, status: process.terminationStatus)
    }

    private static func isZipInfoEntryLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("d")
    }

    private static func parseZipInfoLine(_ line: String, archivePath: String) -> ArchiveEntry? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isZipInfoEntryLine(trimmedLine) else {
            return nil
        }

        let parts = trimmedLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 9,
              let size = Int64(parts[3]) else {
            return nil
        }

        let dateText = String(parts[7])
        let path = archivePath
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

private struct PreparedArchive {
    let url: URL
    let temporaryRootURL: URL?

    func removeTemporaryFiles(fileManager: FileManager) {
        guard let temporaryRootURL = temporaryRootURL else { return }
        try? fileManager.removeItem(at: temporaryRootURL)
    }
}
