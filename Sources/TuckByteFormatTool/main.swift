import Foundation
import TuckByteCore

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else {
    fail("usage: tuck-inspect <archive.tuck|archive.tuck.001> [--password-stdin]")
}

let archiveURL = URL(fileURLWithPath: arguments[0])
var password: String?
if arguments.count > 1 {
    guard arguments.count == 2, arguments[1] == "--password-stdin" else {
        fail("usage: tuck-inspect <archive.tuck|archive.tuck.001> [--password-stdin]")
    }
    let input = FileHandle.standardInput.readData(ofLength: 4_096)
    password = String(decoding: input, as: UTF8.self)
        .trimmingCharacters(in: .newlines)
    guard password?.isEmpty == false else { fail("password input is empty") }
}

do {
    let service = ShellArchiveService()
    let encryption = try service.encryptionMethod(archiveURL: archiveURL)
    let entries = try service.inspect(archiveURL: archiveURL, password: password)
    let totalSize = entries.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
    print("format: \(ArchiveFormat(fileURL: archiveURL).displayName)")
    print("encryption: \(encryption.displayName)")
    print("entries: \(entries.count)")
    print("declared-size: \(totalSize)")
    for entry in entries {
        print("\(entry.isDirectory ? "d" : "f")\t\(entry.size ?? 0)\t\(entry.path)")
    }
} catch {
    fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
}
