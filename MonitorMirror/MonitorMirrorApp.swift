import SwiftUI

@main
struct MonitorMirrorApp: App {
    @StateObject private var peerSession = PeerSession()
    @StateObject private var camera = CameraProcessor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(peerSession)
                .environmentObject(camera)
        }
    }
}
