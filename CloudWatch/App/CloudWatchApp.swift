import SwiftUI
@main struct CloudWatchApp: App {
    @StateObject private var store = MusicStore()
    @StateObject private var player = AudioPlayer()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(player).tint(.pink)
        }
    }
}
