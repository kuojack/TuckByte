import SwiftUI

struct ZipForgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: ArchiveViewModel())
                .frame(
                    minWidth: 960,
                    idealWidth: 1280,
                    minHeight: 600,
                    idealHeight: 720
                )
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
