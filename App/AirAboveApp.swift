import SwiftUI
import AirAboveScreensaverCore

@main
struct AirAboveApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 1024, minHeight: 768)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
