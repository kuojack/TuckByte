import AppKit
import FinderSync
import ZipForgeIntegration

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()

    override init() {
        super.init()
        controller.directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }

        let selectedURLs = currentSelectedURLs()
        guard FinderMenuPolicy.canAddToArchive(selectedURLs) else { return nil }

        let menu = NSMenu(title: "ZipForge")
        menu.addItem(
            withTitle: "加入壓縮檔",
            action: #selector(addToArchive),
            keyEquivalent: ""
        )

        if FinderMenuPolicy.canExtractHere(selectedURLs) {
            menu.addItem(
                withTitle: "解壓縮至此",
                action: #selector(extractHere),
                keyEquivalent: ""
            )
        }
        return menu
    }

    @objc private func addToArchive() {
        dispatch(operation: .addToArchive, activatesApp: true)
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
}
