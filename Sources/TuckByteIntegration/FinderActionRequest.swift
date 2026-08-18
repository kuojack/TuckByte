import Foundation

public struct FinderActionRequest: Equatable {
    public enum Operation: String, Equatable {
        case addToArchive
        case compressHere
        case extractHere
    }

    public static let scheme = "tuckbyte"
    public static let host = "finder"

    public let operation: Operation
    public let selectedURLs: [URL]

    public init(operation: Operation, selectedURLs: [URL]) {
        self.operation = operation
        self.selectedURLs = selectedURLs
    }

    public var url: URL? {
        guard !selectedURLs.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "operation", value: operation.rawValue)
        ] + selectedURLs.map {
            URLQueryItem(name: "path", value: $0.standardizedFileURL.path)
        }
        return components.url
    }

    public init?(
        url: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        guard url.scheme?.lowercased() == Self.scheme,
              url.host?.lowercased() == Self.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let operationValue = components.queryItems?.first(where: { $0.name == "operation" })?.value,
              let operation = Operation(rawValue: operationValue) else {
            return nil
        }

        let selectedURLs = (components.queryItems ?? [])
            .filter { $0.name == "path" }
            .compactMap(\.value)
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { fileExists($0.path) }

        guard !selectedURLs.isEmpty else { return nil }
        self.operation = operation
        self.selectedURLs = selectedURLs
    }
}

public enum FinderMenuPolicy {
    public static func canAddToArchive(_ selectedURLs: [URL]) -> Bool {
        !selectedURLs.isEmpty
    }

    public static func canExtractHere(
        _ selectedURLs: [URL],
        isRegularFile: (URL) -> Bool = { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }
    ) -> Bool {
        !selectedURLs.isEmpty && selectedURLs.allSatisfy {
            isRegularFile($0) && isExtractableArchiveURL($0)
        }
    }

    public static func isExtractableArchiveURL(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "zip" || fileExtension == "tuck" || fileExtension == "7z" {
            return true
        }
        let volumeExtension = fileExtension
        return volumeExtension.count == 3
            && volumeExtension.allSatisfy(\.isNumber)
            && (Int(volumeExtension) ?? 0) > 0
            && ["zip", "tuck"].contains(
                url.deletingPathExtension().pathExtension.lowercased()
            )
    }
}
