import SwiftUI

@main
struct MonitorMirrorApp: App {
    @StateObject private var peerSession = PeerSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(peerSession)
        }
    }
}
