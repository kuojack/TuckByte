import Foundation

public enum ArchiveFormat: String, Equatable {
    case zip
    case splitZip
    case tar
    case gzip
    case sevenZip
    case rar
    case unsupported

    public init(fileURL: URL) {
        let name = fileURL.lastPathComponent.lowercased()
        if SplitZipArchive.isVolumeURL(fileURL) {
            self = .splitZip
        } else if name.hasSuffix(".zip") {
            self = .zip
        } else if name.hasSuffix(".tar") {
            self = .tar
        } else if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") || name.hasSuffix(".gz") {
            self = .gzip
        } else if name.hasSuffix(".7z") {
            self = .sevenZip
        } else if name.hasSuffix(".rar") {
            self = .rar
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
        case .tar:
            return "TAR"
        case .gzip:
            return "GZip"
        case .sevenZip:
            return "7z"
        case .rar:
            return "RAR"
        case .unsupported:
            return "Unsupported"
        }
    }

    public var isSupportedInFirstVersion: Bool {
        self == .zip || self == .splitZip
    }
}
