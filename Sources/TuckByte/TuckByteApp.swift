import SwiftUI

struct TuckByteApp: App {
    @StateObject private var viewModel: ArchiveViewModel
    @StateObject private var finderActionRouter: FinderActionRouter

    init() {
        let viewModel = ArchiveViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        _finderActionRouter = StateObject(
            wrappedValue: FinderActionRouter(viewModel: viewModel)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(
                    minWidth: 780,
                    idealWidth: 1080,
                    minHeight: 520,
                    idealHeight: 680
                )
                .onOpenURL { url in
                    if url.isFileURL {
                        viewModel.openDocumentURL(url)
                    } else {
                        finderActionRouter.handle(url: url)
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            FinderIntegrationSettingsView()
        }
    }
}
