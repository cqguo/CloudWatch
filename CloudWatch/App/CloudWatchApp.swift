import SwiftUI
@main struct CloudWatchApp: App {
    @StateObject private var store = MusicStore()
    @StateObject private var player = AudioPlayer()
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            RootView().modifier(DebugScreenModifier()).environmentObject(store).environmentObject(player).tint(.pink)
            #else
            RootView().environmentObject(store).environmentObject(player).tint(.pink)
            #endif
        }
    }
}
