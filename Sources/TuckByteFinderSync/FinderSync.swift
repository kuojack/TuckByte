import AppKit
import FinderSync
import OSLog
import TuckByteIntegration

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    private let logger = Logger(
        subsystem: "com.kuojack.TuckByte.FinderSync",
        category: "FinderSync"
    )

    override init() {
        super.init()
        let monitoredDirectories = Self.monitoredDirectories()
        controller.directoryURLs = monitoredDirectories
        logger.notice(
            "Monitoring \(monitoredDirectories.count, privacy: .public) Finder roots"
        )
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }

        let selectedURLs = currentSelectedURLs()
        logger.notice(
            "Context menu requested for \(selectedURLs.count, privacy: .public) items"
        )
        guard FinderMenuPolicy.canAddToArchive(selectedURLs) else { return nil }

        let menu = NSMenu(title: "TuckByte")
        menu.addItem(
            withTitle: "TuckByte：加入壓縮並開啟介面",
            action: #selector(addToArchiveWithInterface),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "TuckByte：加入壓縮",
            action: #selector(compressHere),
            keyEquivalent: ""
        )

        if FinderMenuPolicy.canExtractHere(selectedURLs) {
            menu.addItem(
                withTitle: "TuckByte：解壓縮至此",
                action: #selector(extractHere),
                keyEquivalent: ""
            )
        }
        return menu
    }

    @objc private func addToArchiveWithInterface() {
        dispatch(operation: .addToArchive, activatesApp: true)
    }

    @objc private func compressHere() {
        dispatch(operation: .compressHere, activatesApp: false)
    }

    @objc private func extractHere() {
        dispatch(operation: .extractHere, activatesApp: false)
    }

    private func dispatch(
        operation: FinderActionRequest.Operation,
        activatesApp: Bool
    ) {
        let selectedURLs = currentSelectedURLs()
        let request = FinderActionRequest(
            operation: operation,
            selectedURLs: selectedURLs
        )
        guard let requestURL = request.url else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activatesApp
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(
            requestURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    private func currentSelectedURLs() -> [URL] {
        if let selectedURLs = controller.selectedItemURLs(), !selectedURLs.isEmpty {
            return selectedURLs
        }
        if let targetedURL = controller.targetedURL() {
            return [targetedURL]
        }
        return []
    }

    private static func monitoredDirectories() -> Set<URL> {
        let paths = [
            "/Applications",
            "/Library",
            "/System",
            "/Users",
            "/Volumes",
            "/opt",
            "/private",
            "/usr"
        ]

        return Set(paths.compactMap { path in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        })
    }
}
