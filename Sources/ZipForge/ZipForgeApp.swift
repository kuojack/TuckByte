import SwiftUI

@main
struct ZipForgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: ArchiveViewModel())
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
