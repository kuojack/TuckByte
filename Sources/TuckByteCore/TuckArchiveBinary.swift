import Foundation

struct TuckBinaryWriter {
    private(set) var data = Data()

    mutating func append(_ value: UInt8) {
        data.append(value)
    }

    mutating func append(_ value: UInt16) {
        appendLittleEndian(UInt64(value), byteCount: 2)
    }

    mutating func append(_ value: UInt32) {
        appendLittleEndian(UInt64(value), byteCount: 4)
    }

    mutating func append(_ value: UInt64) {
        appendLittleEndian(value, byteCount: 8)
    }

    mutating func append(_ value: Int64) {
        append(UInt64(bitPattern: value))
    }

    mutating func append(bytes: Data) {
        data.append(bytes)
    }

    mutating func append(bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    mutating func appendUTF8(_ value: String) throws {
        guard let encoded = value.data(using: .utf8),
              encoded.count <= TuckArchiveLimits.maximumPathBytes else {
            throw ArchiveServiceError.tuckArchiveLimitExceeded("path length")
        }
        append(UInt32(encoded.count))
        append(bytes: encoded)
    }

    mutating func appendZeroes(count: Int) {
        guard count > 0 else { return }
        data.append(Data(repeating: 0, count: count))
    }

    private mutating func appendLittleEndian(_ value: UInt64, byteCount: Int) {
        for index in 0..<byteCount {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(index * 8)))
        }
    }
}

struct TuckBinaryReader {
    let data: Data
    private(set) var offset = 0

    var remainingCount: Int { data.count - offset }

    mutating func readUInt8() throws -> UInt8 {
        let bytes = try readBytes(count: 1)
        return bytes[bytes.startIndex]
    }

    mutating func readUInt16() throws -> UInt16 {
        UInt16(try readLittleEndian(byteCount: 2))
    }

    mutating func readUInt32() throws -> UInt32 {
        UInt32(try readLittleEndian(byteCount: 4))
    }

    mutating func readUInt64() throws -> UInt64 {
        try readLittleEndian(byteCount: 8)
    }

    mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0,
              offset <= data.count,
              count <= data.count - offset else {
            throw ArchiveServiceError.tuckArchiveCorrupt("record exceeds file bounds")
        }
        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    mutating func readUTF8() throws -> String {
        let length = Int(try readUInt32())
        guard length <= TuckArchiveLimits.maximumPathBytes else {
            throw ArchiveServiceError.tuckArchiveLimitExceeded("path length")
        }
        let bytes = try readBytes(count: length)
        guard let value = String(data: bytes, encoding: .utf8),
              value.data(using: .utf8) == bytes else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid UTF-8 path")
        }
        return value
    }

    mutating func skip(count: Int) throws {
        _ = try readBytes(count: count)
    }

    private mutating func readLittleEndian(byteCount: Int) throws -> UInt64 {
        let bytes = try readBytes(count: byteCount)
        var value: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt64(byte) << UInt64(index * 8)
        }
        return value
    }
}

extension Data {
    func tuckConstantTimeEquals(_ other: Data) -> Bool {
        guard count == other.count else { return false }
        var difference: UInt8 = 0
        for index in indices {
            difference |= self[index] ^ other[index]
        }
        return difference == 0
    }
}
