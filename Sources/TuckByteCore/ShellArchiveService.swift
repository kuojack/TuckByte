import Foundation

public final class ShellArchiveService: ArchiveService {
    private let fileManager: FileManager
    private let zipPath = "/usr/bin/zip"
    private let zipInfoPath = "/usr/bin/zipinfo"
    private let tarPath = "/usr/bin/tar"
    private let dittoPath = "/usr/bin/ditto"
    private let minizipEngine = MinizipArchiveEngine()
    private let tuckEngine: TuckArchiveEngine

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.tuckEngine = TuckArchiveEngine(fileManager: fileManager)
    }

    public func inspect(archiveURL: URL) throws -> [ArchiveEntry] {
        try inspect(archiveURL: archiveURL, password: nil)
    }

    public func inspect(archiveURL: URL, password: String?) throws -> [ArchiveEntry] {
        let preparedArchive = try prepareReadableArchive(archiveURL)
        defer { preparedArchive.removeTemporaryFiles(fileManager: fileManager) }
        let format = ArchiveFormat(fileURL: archiveURL)

        switch format {
        case .zip, .splitZip:
            return try inspectZip(
                readableURL: preparedArchive.url,
                originalURL: archiveURL,
                isSplitArchive: format == .splitZip
            )
        case .tuck, .splitTuck:
            return try tuckEngine.inspect(
                archiveURL: preparedArchive.url,
                password: password
            )
        case .sevenZip:
            return try inspectSevenZip(archiveURL: preparedArchive.url)
        case .unsupported:
            throw ArchiveServiceError.unsupportedFormat(format)
        }
    }

    private func inspectZip(
        readableURL: URL,
        originalURL: URL,
        isSplitArchive: Bool
    ) throws -> [ArchiveEntry] {

        let zipInfoResult: CommandResult
        do {
            zipInfoResult = try runExecutable(
                zipInfoPath,
                arguments: ["-l", "-T", readableURL.path],
                currentDirectoryURL: nil
            )
        } catch {
            if isSplitArchive {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    originalURL
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
            if isSplitArchive {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    originalURL
                )
            }
            throw error
        }
        let paths = pathResult.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        guard metadataLines.count == paths.count else {
            if isSplitArchive {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    originalURL
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
            if isSplitArchive {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    originalURL
                )
            }
            throw ArchiveServiceError.couldNotParseArchive
        }
        return entries
    }

    private func inspectSevenZip(archiveURL: URL) throws -> [ArchiveEntry] {
        let pathResult = try runExecutable(
            tarPath,
            arguments: ["-tf", archiveURL.path],
            currentDirectoryURL: nil
        )
        let metadataResult = try runExecutable(
            tarPath,
            arguments: ["-tvf", archiveURL.path],
            currentDirectoryURL: nil
        )
        let paths = pathResult.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let metadataLines = metadataResult.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        guard paths.count == metadataLines.count else {
            throw ArchiveServiceError.couldNotParseArchive
        }

        let entries = zip(metadataLines, paths)
            .compactMap { metadataLine, path in
                Self.parseTarListLine(metadataLine, archivePath: path)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }

        guard !entries.isEmpty else {
            throw ArchiveServiceError.couldNotParseArchive
        }
        return entries
    }

    public func encryptionMethod(
        archiveURL: URL
    ) throws -> ArchiveEncryptionMethod {
        let format = ArchiveFormat(fileURL: archiveURL)
        if format == .tuck || format == .splitTuck {
            let preparedArchive = try prepareReadableArchive(archiveURL)
            defer { preparedArchive.removeTemporaryFiles(fileManager: fileManager) }
            return try tuckEngine.encryptionMethod(for: preparedArchive.url)
        }
        guard format == .zip || format == .splitZip else {
            return .none
        }
        let preparedArchive = try prepareReadableArchive(archiveURL)
        defer { preparedArchive.removeTemporaryFiles(fileManager: fileManager) }
        return try minizipEngine.encryptionMethod(for: preparedArchive.url)
    }

    public func extract(archiveURL: URL, destinationURL: URL) throws {
        try extract(
            archiveURL: archiveURL,
            destinationURL: destinationURL,
            password: nil
        )
    }

    public func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String?
    ) throws {
        try extract(
            archiveURL: archiveURL,
            destinationURL: destinationURL,
            password: password,
            operation: nil
        )
    }

    public func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String?,
        operation: ArchiveOperation?
    ) throws {
        let preparedArchive = try prepareReadableArchive(archiveURL)
        defer { preparedArchive.removeTemporaryFiles(fileManager: fileManager) }
        let format = ArchiveFormat(fileURL: archiveURL)
        if format == .tuck || format == .splitTuck {
            try tuckEngine.extract(
                archiveURL: preparedArchive.url,
                destinationURL: destinationURL,
                password: password,
                operation: operation
            )
            return
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        do {
            switch format {
            case .zip, .splitZip:
                let encryption = try minizipEngine.encryptionMethod(
                    for: preparedArchive.url
                )
                if encryption == .none {
                    _ = try runExecutable(
                        dittoPath,
                        arguments: ["-x", "-k", preparedArchive.url.path, destinationURL.path],
                        currentDirectoryURL: nil
                    )
                } else {
                    guard let password = password, !password.isEmpty else {
                        throw ArchiveServiceError.archivePasswordRequired
                    }
                    try minizipEngine.extract(
                        archiveURL: preparedArchive.url,
                        destinationURL: destinationURL,
                        password: password
                    )
                }
            case .sevenZip:
                _ = try runExecutable(
                    tarPath,
                    arguments: ["-xf", preparedArchive.url.path, "-C", destinationURL.path],
                    currentDirectoryURL: nil
                )
            case .tuck, .splitTuck:
                assertionFailure("TuckByte archives are handled before this switch")
            case .unsupported:
                throw ArchiveServiceError.unsupportedFormat(format)
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if format == .splitZip {
                throw ArchiveServiceError.splitArchiveIncompleteOrCorrupt(
                    archiveURL
                )
            }
            throw error
        }
    }

    public func extractEntry(
        archiveURL: URL,
        entry: ArchiveEntry,
        destinationURL: URL,
        password: String?
    ) throws {
        let format = ArchiveFormat(fileURL: archiveURL)
        guard format == .tuck || format == .splitTuck else {
            try extractEntryUsingWholeArchive(
                archiveURL: archiveURL,
                entry: entry,
                destinationURL: destinationURL,
                password: password
            )
            return
        }
        let preparedArchive = try prepareReadableArchive(archiveURL)
        defer { preparedArchive.removeTemporaryFiles(fileManager: fileManager) }
        try tuckEngine.extractEntry(
            archiveURL: preparedArchive.url,
            path: entry.path,
            destinationURL: destinationURL,
            password: password
        )
    }

    private func extractEntryUsingWholeArchive(
        archiveURL: URL,
        entry: ArchiveEntry,
        destinationURL: URL,
        password: String?
    ) throws {
        let components = entry.path.split(separator: "/").map(String.init)
        guard !entry.path.hasPrefix("/"),
              !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw ArchiveServiceError.unsafeArchiveEntry(entry.path)
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ArchiveServiceError.destinationAlreadyExists(destinationURL)
        }
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("TuckByte-Entry-\(UUID().uuidString)", isDirectory: true)
        let extractedRoot = stagingRoot.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }
        try extract(archiveURL: archiveURL, destinationURL: extractedRoot, password: password)
        let extractedURL = components.reduce(extractedRoot) { $0.appendingPathComponent($1) }
        let rootPath = extractedRoot.standardizedFileURL.path + "/"
        guard extractedURL.standardizedFileURL.path.hasPrefix(rootPath),
              fileManager.fileExists(atPath: extractedURL.path) else {
            throw ArchiveServiceError.archiveEntryNotFound(entry.path)
        }
        try fileManager.copyItem(at: extractedURL, to: destinationURL)
    }

    public func extractEntry(
        archiveURL: URL,
        entry: ArchiveEntry,
        destinationURL: URL
    ) throws {
        try extractEntry(
            archiveURL: archiveURL,
            entry: entry,
            destinationURL: destinationURL,
            password: nil
        )
    }

    public func createZip(from sourceURLs: [URL], destinationURL: URL, settings: CompressionSettings = .standard) throws {
        try createArchive(from: sourceURLs, destinationURL: destinationURL, settings: settings)
    }

    public func createArchive(
        from sourceURLs: [URL],
        destinationURL: URL,
        settings: CompressionSettings = .standard
    ) throws {
        try createArchive(
            from: sourceURLs,
            destinationURL: destinationURL,
            settings: settings,
            operation: nil
        )
    }

    public func createArchive(
        from sourceURLs: [URL],
        destinationURL: URL,
        settings: CompressionSettings,
        operation: ArchiveOperation?
    ) throws {
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
        if settings.outputFormat == .tuck {
            try createTuckArchive(
                from: sourceURLs,
                destinationURL: destinationURL,
                settings: settings,
                operation: operation
            )
            return
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

        let generatedArchiveURL = createsSplitArchive
            ? stagingDirectory.appendingPathComponent("Generated.zip")
            : destinationURL
        switch settings.encryption {
        case .none:
            let arguments = [
                "-r",
                "-\(settings.compressionLevel)",
                generatedArchiveURL.path
            ] + stagedNames
            _ = try runExecutable(
                zipPath,
                arguments: arguments,
                currentDirectoryURL: stagingDirectory
            )
        case .zipCrypto, .aes256:
            try minizipEngine.createEncryptedZip(
                archiveURL: generatedArchiveURL,
                stagingDirectoryURL: stagingDirectory,
                compressionLevel: settings.compressionLevel,
                encryption: settings.encryption
            )
        }

        if let volumeSizeBytes = settings.volumeSizeBytes {
            try SplitZipArchive.split(
                archiveURL: generatedArchiveURL,
                firstVolumeURL: destinationURL,
                volumeSizeBytes: volumeSizeBytes,
                fileManager: fileManager
            )
        }
    }

    public func changePassword(
        archiveURL: URL,
        oldPassword: String,
        newPassword: String
    ) throws {
        guard ArchiveFormat(fileURL: archiveURL) == .tuck else {
            throw ArchiveServiceError.tuckArchiveUnsupportedFeature(
                "password change is available for a single .tuck file"
            )
        }
        try tuckEngine.changePassword(
            archiveURL: archiveURL,
            oldPassword: oldPassword,
            newPassword: newPassword
        )
    }

    private func createTuckArchive(
        from sourceURLs: [URL],
        destinationURL: URL,
        settings: CompressionSettings,
        operation: ArchiveOperation?
    ) throws {
        try tuckEngine.create(
            from: sourceURLs,
            destinationURL: destinationURL,
            settings: settings,
            operation: operation
        )
    }

    private func prepareReadableArchive(_ archiveURL: URL) throws -> PreparedArchive {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw ArchiveServiceError.fileDoesNotExist(archiveURL)
        }
        let format = ArchiveFormat(fileURL: archiveURL)
        guard format.isSupportedForReading else {
            throw ArchiveServiceError.unsupportedFormat(format)
        }

        // Native `.tuck` reads consecutive volumes directly through its
        // random-access source, so only legacy split ZIP needs assembly.
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

    private static func parseTarListLine(
        _ line: String,
        archivePath: String
    ) -> ArchiveEntry? {
        let parts = line.split(
            separator: " ",
            maxSplits: 8,
            omittingEmptySubsequences: true
        )
        guard parts.count >= 8,
              let size = Int64(parts[4]) else {
            return nil
        }

        let path = archivePath
        let isDirectory = parts[0].first == "d" || path.hasSuffix("/")
        let name = URL(fileURLWithPath: path).lastPathComponent
        let dateText = "\(parts[5]) \(parts[6]) \(parts[7])"

        return ArchiveEntry(
            name: name.isEmpty
                ? path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : name,
            path: path,
            size: isDirectory ? nil : size,
            isDirectory: isDirectory,
            modifiedAt: tarListDate(from: dateText)
        )
    }

    private static func tarListDate(from text: String) -> Date? {
        if text.contains(":") {
            let currentYear = Calendar.current.component(.year, from: Date())
            return tarListTimeFormatter.date(from: "\(text) \(currentYear)")
        }
        return tarListYearFormatter.date(from: text)
    }

    private static let zipInfoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd.HHmmss"
        return formatter
    }()

    private static let tarListTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm yyyy"
        return formatter
    }()

    private static let tarListYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d yyyy"
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
