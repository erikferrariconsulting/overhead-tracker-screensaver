import SwiftUI
import OverheadTrackerScreensaverCore

@main
struct OverheadTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 1024, minHeight: 768)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
