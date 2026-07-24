import Foundation

public struct ArchiveEntry: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let size: Int64?
    public let isDirectory: Bool
    public let modifiedAt: Date?

    public init(name: String, path: String, size: Int64?, isDirectory: Bool, modifiedAt: Date?) {
        self.id = path
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.modifiedAt = modifiedAt
    }
}
