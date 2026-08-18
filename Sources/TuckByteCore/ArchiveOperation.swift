import Foundation

public final class ArchiveOperation {
    public enum Phase: String, Equatable {
        case scanning
        case compressing
        case writingIndex
        case readingIndex
        case extracting
        case finalizing
    }

    public struct Snapshot: Equatable {
        public let phase: Phase
        public let completedBytes: UInt64
        public let totalBytes: UInt64

        public var fractionCompleted: Double {
            guard totalBytes > 0 else { return 0 }
            return min(1, Double(completedBytes) / Double(totalBytes))
        }
    }

    public var updateHandler: ((Snapshot) -> Void)?

    private let lock = NSLock()
    private var cancelled = false

    public init(updateHandler: ((Snapshot) -> Void)? = nil) {
        self.updateHandler = updateHandler
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func checkCancellation() throws {
        if isCancelled { throw ArchiveServiceError.operationCancelled }
    }

    func update(phase: Phase, completedBytes: UInt64, totalBytes: UInt64) {
        let snapshot = Snapshot(
            phase: phase,
            completedBytes: completedBytes,
            totalBytes: totalBytes
        )
        updateHandler?(snapshot)
    }
}
