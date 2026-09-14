import SwiftUI

@main
struct CloudWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack { EmbeddedBrowserView() }
                .tint(.red)
        }
    }
}
