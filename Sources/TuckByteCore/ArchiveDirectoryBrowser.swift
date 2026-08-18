import Foundation

public struct ArchiveBreadcrumb: Identifiable, Equatable {
    public let name: String
    public let path: String

    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum ArchiveDirectoryBrowser {
    public static func entries(
        in directoryPath: String,
        from allEntries: [ArchiveEntry]
    ) -> [ArchiveEntry] {
        guard let currentPath = canonicalDirectoryPath(directoryPath) else {
            return []
        }

        var children: [String: (entry: ArchiveEntry, isExplicit: Bool)] = [:]

        for entry in allEntries {
            guard let normalizedPath = normalizedEntryPath(
                entry.path,
                isDirectory: entry.isDirectory
            ), normalizedPath.hasPrefix(currentPath), normalizedPath != currentPath else {
                continue
            }

            let remainder = String(normalizedPath.dropFirst(currentPath.count))
            let components = remainder.split(separator: "/", omittingEmptySubsequences: true)
            guard let firstComponent = components.first else { continue }

            if components.count > 1 {
                let name = String(firstComponent)
                let path = currentPath + name + "/"
                let synthesized = ArchiveEntry(
                    name: name,
                    path: path,
                    size: nil,
                    isDirectory: true,
                    modifiedAt: entry.modifiedAt
                )
                if children[path] == nil {
                    children[path] = (synthesized, false)
                }
                continue
            }

            let name = String(firstComponent)
            let path = currentPath + name + (entry.isDirectory ? "/" : "")
            let normalizedEntry = ArchiveEntry(
                name: name,
                path: path,
                size: entry.size,
                isDirectory: entry.isDirectory,
                modifiedAt: entry.modifiedAt
            )
            let existing = children[path]
            if existing == nil || existing?.isExplicit == false {
                children[path] = (normalizedEntry, true)
            }
        }

        return children.values
            .map(\.entry)
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }
    }

    public static func parentPath(of directoryPath: String) -> String {
        guard let canonicalPath = canonicalDirectoryPath(directoryPath),
              !canonicalPath.isEmpty else {
            return ""
        }

        var components = canonicalPath.split(separator: "/", omittingEmptySubsequences: true)
        components.removeLast()
        return components.isEmpty ? "" : components.joined(separator: "/") + "/"
    }

    public static func breadcrumbs(for directoryPath: String) -> [ArchiveBreadcrumb] {
        guard let canonicalPath = canonicalDirectoryPath(directoryPath) else {
            return [ArchiveBreadcrumb(name: "根目錄", path: "")]
        }

        var result = [ArchiveBreadcrumb(name: "根目錄", path: "")]
        var accumulatedPath = ""
        for component in canonicalPath.split(separator: "/", omittingEmptySubsequences: true) {
            accumulatedPath += String(component) + "/"
            result.append(
                ArchiveBreadcrumb(name: String(component), path: accumulatedPath)
            )
        }
        return result
    }

    public static func canonicalDirectoryPath(_ path: String) -> String? {
        if path.isEmpty {
            return ""
        }
        guard let components = safeComponents(of: path) else {
            return nil
        }
        return components.isEmpty ? "" : components.joined(separator: "/") + "/"
    }

    private static func normalizedEntryPath(
        _ path: String,
        isDirectory: Bool
    ) -> String? {
        guard let components = safeComponents(of: path), !components.isEmpty else {
            return nil
        }
        return components.joined(separator: "/") + (isDirectory ? "/" : "")
    }

    private static func safeComponents(of path: String) -> [String]? {
        guard !path.hasPrefix("/") else { return nil }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: true
        ).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components
    }
}
