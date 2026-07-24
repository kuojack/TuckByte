import AppKit
import Foundation
import TuckByteCore
import TuckByteIntegration

final class FinderActionRouter: ObservableObject {
    private let viewModel: ArchiveViewModel
    private let batchExtractor: ArchiveBatchExtractor
    private let inPlaceCompressor: ArchiveInPlaceCompressor
    private let notificationService: FinderNotificationService
    private let workQueue = DispatchQueue(
        label: "com.kuojack.TuckByte.finder-work",
        qos: .userInitiated
    )

    init(
        viewModel: ArchiveViewModel,
        batchExtractor: ArchiveBatchExtractor = ArchiveBatchExtractor(),
        inPlaceCompressor: ArchiveInPlaceCompressor = ArchiveInPlaceCompressor(),
        notificationService: FinderNotificationService = FinderNotificationService()
    ) {
        self.viewModel = viewModel
        self.batchExtractor = batchExtractor
        self.inPlaceCompressor = inPlaceCompressor
        self.notificationService = notificationService
    }

    func handle(url: URL) {
        guard let request = FinderActionRequest(url: url) else { return }

        switch request.operation {
        case .addToArchive:
            handleAddToArchive(request.selectedURLs)
        case .compressHere:
            handleCompressHere(request.selectedURLs)
        case .extractHere:
            handleExtractHere(request.selectedURLs)
        }
    }

    private func handleAddToArchive(_ selectedURLs: [URL]) {
        viewModel.replacePendingItems(selectedURLs)
        activateApp()
    }

    private func handleCompressHere(_ selectedURLs: [URL]) {
        do {
            _ = try inPlaceCompressor.availableDestination(for: selectedURLs)
        } catch ArchiveServiceError.selectionSpansMultipleDirectories {
            viewModel.replacePendingItems(
                selectedURLs,
                statusMessage: "選取項目位於不同資料夾，請確認設定與輸出位置。"
            )
            activateApp()
            return
        } catch {
            viewModel.completeFinderCompression(
                ArchiveCompressionResult(
                    sourceURLs: selectedURLs,
                    destinationURL: nil,
                    errorDescription: (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                )
            )
            activateApp()
            return
        }

        let appWasActive = NSApplication.shared.isActive
        viewModel.beginFinderCompression(count: selectedURLs.count)
        if !appWasActive {
            NSApplication.shared.hide(nil)
        }

        workQueue.async { [weak self] in
            guard let self = self else { return }
            let result = self.inPlaceCompressor.compressHere(selectedURLs)

            DispatchQueue.main.async {
                self.viewModel.completeFinderCompression(result)
                guard result.succeeded else {
                    self.activateApp()
                    return
                }

                self.notificationService.deliverCompressionSuccess(result: result) { delivered in
                    guard !delivered else { return }
                    DispatchQueue.main.async {
                        self.activateApp()
                    }
                }
            }
        }
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
