import Foundation
import TuckByteCore

let requestedMiB = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 64
let sizeMiB = max(1, requestedMiB)
let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("TuckByte-Benchmark-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: root) }
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

let source = root.appendingPathComponent("corpus", isDirectory: true)
try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
let textUnit = Data(String(repeating: "TuckByte benchmark text, JSON, CSV, and source code.\n", count: 4_096).utf8)
var text = Data()
while text.count < sizeMiB * 524_288 { text.append(textUnit) }
try text.prefix(sizeMiB * 524_288).write(to: source.appendingPathComponent("text.log"))

var state: UInt64 = 0x54_55_43_4B_42_59_54_45
var binary = Data(count: sizeMiB * 524_288)
binary.withUnsafeMutableBytes { rawBuffer in
    let bytes = rawBuffer.bindMemory(to: UInt8.self)
    for index in bytes.indices {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        bytes[index] = UInt8(truncatingIfNeeded: state)
    }
}
try binary.write(to: source.appendingPathComponent("binary.dat"))

let service = ShellArchiveService()
print("profile,input_bytes,archive_bytes,create_seconds,extract_seconds,create_mib_s,extract_mib_s")
for (name, level) in [("fast", 1), ("balanced", 6), ("maximum", 9)] {
    let archive = root.appendingPathComponent("\(name).tuck")
    let output = root.appendingPathComponent("\(name)-output", isDirectory: true)
    let createStart = Date()
    try service.createArchive(
        from: [source],
        destinationURL: archive,
        settings: CompressionSettings(outputFormat: .tuck, compressionLevel: level)
    )
    let createSeconds = Date().timeIntervalSince(createStart)
    let extractStart = Date()
    try service.extract(archiveURL: archive, destinationURL: output)
    let extractSeconds = Date().timeIntervalSince(extractStart)
    let inputBytes = text.prefix(sizeMiB * 524_288).count + binary.count
    let archiveBytes = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    let inputMiB = Double(inputBytes) / 1_048_576
    print(String(
        format: "%@,%d,%d,%.4f,%.4f,%.2f,%.2f",
        name,
        inputBytes,
        archiveBytes,
        createSeconds,
        extractSeconds,
        inputMiB / createSeconds,
        inputMiB / extractSeconds
    ))
}
