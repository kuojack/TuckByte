import Foundation

/// Native `.tuck` facade. It deliberately contains no shell/process calls.
final class TuckArchiveEngine {
    private let writer: TuckArchiveWriter
    private let reader: TuckArchiveReader

    init(fileManager: FileManager = .default) {
        writer = TuckArchiveWriter(fileManager: fileManager)
        reader = TuckArchiveReader(fileManager: fileManager)
    }

    func create(
        from sources: [URL],
        destinationURL: URL,
        settings: CompressionSettings,
        operation: ArchiveOperation? = nil
    ) throws {
        try writer.create(
            from: sources,
            destinationURL: destinationURL,
            settings: settings,
            operation: operation
        )
    }

    func inspect(archiveURL: URL, password: String?) throws -> [ArchiveEntry] {
        try reader.inspect(archiveURL: archiveURL, password: password)
    }

    func encryptionMethod(for archiveURL: URL) throws -> ArchiveEncryptionMethod {
        try reader.encryptionMethod(for: archiveURL)
    }

    func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String?,
        operation: ArchiveOperation? = nil
    ) throws {
        try reader.extract(
            archiveURL: archiveURL,
            destinationURL: destinationURL,
            password: password,
            operation: operation
        )
    }

    func extractEntry(
        archiveURL: URL,
        path: String,
        destinationURL: URL,
        password: String?
    ) throws {
        try reader.extractEntry(
            archiveURL: archiveURL,
            path: path,
            destinationURL: destinationURL,
            password: password
        )
    }

    func changePassword(archiveURL: URL, oldPassword: String, newPassword: String) throws {
        try reader.changePassword(
            archiveURL: archiveURL,
            oldPassword: oldPassword,
            newPassword: newPassword
        )
    }
}
