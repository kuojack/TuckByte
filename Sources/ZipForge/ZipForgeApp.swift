import SwiftUI

struct ZipForgeApp: App {
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
                    minWidth: 960,
                    idealWidth: 1280,
                    minHeight: 600,
                    idealHeight: 720
                )
                .onOpenURL(perform: finderActionRouter.handle)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            FinderIntegrationSettingsView()
        }
    }
}
