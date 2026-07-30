import Foundation
import OSLog
import SwiftUI

enum LaunchDiagnostics {
    private static let startedAt = ProcessInfo.processInfo.systemUptime
    private static let logger = Logger(subsystem: "MonitorMirror", category: "lifecycle")

    static func mark(_ event: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let formatted = String(format: "%.3f", elapsed)
        logger.notice("MM_DIAG \(event, privacy: .public) +\(formatted, privacy: .public)s")
    }
}

@main
struct MonitorMirrorApp: App {
    @StateObject private var peerSession = PeerSession()

    init() {
        LaunchDiagnostics.mark("app.init")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(peerSession)
                .onAppear {
                    LaunchDiagnostics.mark("root.appeared")
                }
        }
    }
}
