import AppKit
import Foundation
import ZipForgeCore
import ZipForgeIntegration

final class FinderActionRouter: ObservableObject {
    private let viewModel: ArchiveViewModel
    private let batchExtractor: ArchiveBatchExtractor
    private let notificationService: FinderNotificationService
    private let workQueue = DispatchQueue(
        label: "com.zipforge.finder-extraction",
        qos: .userInitiated
    )

    init(
        viewModel: ArchiveViewModel,
        batchExtractor: ArchiveBatchExtractor = ArchiveBatchExtractor(),
        notificationService: FinderNotificationService = FinderNotificationService()
    ) {
        self.viewModel = viewModel
        self.batchExtractor = batchExtractor
        self.notificationService = notificationService
    }

    func handle(url: URL) {
        guard let request = FinderActionRequest(url: url) else { return }

        switch request.operation {
        case .addToArchive:
            handleAddToArchive(request.selectedURLs)
        case .extractHere:
            handleExtractHere(request.selectedURLs)
        }
    }

    private func handleAddToArchive(_ selectedURLs: [URL]) {
        viewModel.replacePendingItems(selectedURLs)
        activateApp()
    }

    private func handleExtractHere(_ selectedURLs: [URL]) {
        guard FinderMenuPolicy.canExtractHere(selectedURLs) else { return }

        let appWasActive = NSApplication.shared.isActive
        viewModel.beginFinderExtraction(count: selectedURLs.count)
        if !appWasActive {
            NSApplication.shared.hide(nil)
        }

        workQueue.async { [weak self] in
            guard let self = self else { return }
            let results = self.batchExtractor.extractHere(selectedURLs)
            let failedResults = results.filter { !$0.succeeded }

            DispatchQueue.main.async {
                self.viewModel.completeFinderExtraction(results)
                if !failedResults.isEmpty {
                    self.activateApp()
                    return
                }

                self.notificationService.deliverExtractionSuccess(results: results) { delivered in
                    guard !delivered else { return }
                    DispatchQueue.main.async {
                        self.activateApp()
                    }
                }
            }
        }
    }

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
    }
}
