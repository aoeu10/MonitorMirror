import Foundation
import SwiftUI

struct ContentView: View {
    @State private var isShowingAbout = false

    init() {
        LaunchDiagnostics.mark("root.init")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image("MonitorMirrorLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .blue.opacity(0.22), radius: 14, y: 8)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Monitor Mirror")
                        .font(.largeTitle.bold())
                    Text("Privately share a perspective-corrected view of an angled monitor between two nearby Apple devices.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 520)
                }

                VStack(spacing: 14) {
                    NavigationLink {
                        ViewerView()
                    } label: {
                        RoleCard(
                            title: "View Monitor",
                            subtitle: "Use this on the iPad. It creates the private pairing code.",
                            systemImage: "ipad.landscape"
                        )
                    }

                    NavigationLink {
                        SenderView()
                    } label: {
                        RoleCard(
                            title: "Share Monitor",
                            subtitle: "Use this on the iPhone mounted beside the monitor.",
                            systemImage: "iphone"
                        )
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 620)

                Spacer()

                Label("No cloud, accounts, recordings, or analytics", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Monitor Mirror")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAbout = true
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingAbout) {
                AboutView()
            }
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let websiteURL = URL(string: "https://monitor-mirror.com")!

    private var versionText: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.1.0"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image("MonitorMirrorLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .accessibilityHidden(true)

                        Text("Monitor Mirror")
                            .font(.title.bold())
                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Privately share a perspective-corrected view of an angled monitor between two nearby Apple devices.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Changelog")
                            .font(.title3.bold())
                        Text("1.1.0 — Added low-latency H.264 video streaming with bounded backpressure, keyframe recovery, and complete session teardown.")
                        Text("1.0.1 — Added secure one-scan QR pairing, encrypted nearby transport, perspective correction, and the current app identity.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Libraries")
                            .font(.title3.bold())
                        Text("No third-party libraries or external open-source packages are included. Monitor Mirror is built with Apple system frameworks including SwiftUI, AVFoundation, Vision, Core Image, VideoToolbox, Network.framework, CryptoKit, and Security.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Website")
                            .font(.title3.bold())
                        Link(destination: websiteURL) {
                            Label("monitor-mirror.com", systemImage: "safari")
                        }
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct RoleCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.blue)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}
