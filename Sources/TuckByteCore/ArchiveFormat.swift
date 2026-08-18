import Foundation

public enum ArchiveFormat: String, Equatable {
    case zip
    case splitZip
    case tuck
    case splitTuck
    case sevenZip
    case unsupported

    public init(fileURL: URL) {
        let name = fileURL.lastPathComponent.lowercased()
        if SplitZipArchive.isVolumeURL(fileURL) {
            self = .splitZip
        } else if SplitTuckArchive.isVolumeURL(fileURL) {
            self = .splitTuck
        } else if name.hasSuffix(".zip") {
            self = .zip
        } else if name.hasSuffix(".tuck") {
            self = .tuck
        } else if name.hasSuffix(".7z") {
            self = .sevenZip
        } else {
            self = .unsupported
        }
    }

    public var displayName: String {
        switch self {
        case .zip:
            return "ZIP"
        case .splitZip:
            return "分割 ZIP"
        case .tuck:
            return "TuckByte (.tuck)"
        case .splitTuck:
            return "分割 TuckByte"
        case .sevenZip:
            return "7z"
        case .unsupported:
            return "Unsupported"
        }
    }

    public var isSupportedForReading: Bool {
        self == .zip || self == .splitZip || self == .tuck
            || self == .splitTuck || self == .sevenZip
    }
}
