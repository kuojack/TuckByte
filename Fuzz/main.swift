import Foundation
import TuckByteCore

private func exercise(_ data: Data) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("TuckByte-Fuzz-\(UUID().uuidString)", isDirectory: true)
    let archive = root.appendingPathComponent("input.tuck")
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: archive)
        _ = try? ShellArchiveService().inspect(archiveURL: archive)
    } catch {
        // Invalid data is the expected input class. A crash, trap, or hang is not.
    }
    try? FileManager.default.removeItem(at: root)
}

#if FUZZING
@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ bytes: UnsafePointer<UInt8>, _ count: Int) -> Int32 {
    exercise(Data(bytes: bytes, count: count))
    return 0
}
#else
let arguments = Array(CommandLine.arguments.dropFirst())
guard let path = arguments.first else {
    FileHandle.standardError.write(Data("usage: tuck-parser-fuzz <seed.tuck> [iterations]\n".utf8))
    exit(2)
}
let seed = try Data(contentsOf: URL(fileURLWithPath: path))
let iterations = arguments.count > 1 ? (Int(arguments[1]) ?? 1_000) : 1_000
for iteration in 0..<max(1, iterations) {
    var input = seed
    if !input.isEmpty {
        let offset = (iteration &* 1_103_515_245 &+ 12_345) % input.count
        input[offset] ^= UInt8(truncatingIfNeeded: iteration &* 31 &+ 1)
    }
    exercise(input)
}
print("completed \(max(1, iterations)) deterministic parser mutations")
#endif
