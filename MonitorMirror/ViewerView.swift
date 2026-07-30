import SwiftUI
import UIKit

struct ViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var peer: PeerSession

    var body: some View {
        VStack(spacing: 18) {
            if peer.isConnected {
                receivedVideo
            } else {
                pairingPanel
            }

            if case .failed(let message) = peer.state {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)

                Button("Create a New Pairing Code") {
                    peer.startViewerSession()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label(peer.state.message, systemImage: peer.isConnected ? "lock.fill" : "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(peer.isConnected ? .green : .secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .navigationTitle("iPad Viewer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            peer.startViewerSession()
        }
        .onChange(of: peer.sessionEndSequence) { _, _ in
            dismiss()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            peer.stop()
        }
    }

    private var pairingPanel: some View {
        VStack(spacing: 18) {
            Text("Scan with the iPhone")
                .font(.title2.bold())

            if let payload = peer.pairingPayload,
               let encoded = try? payload.encoded() {
                QRCodeView(value: encoded)
                    .frame(width: 280, height: 280)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22))

                Text("Open Monitor Mirror on the iPhone, choose **Share Monitor**, and scan this one-time code.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 500)

                Text("For direct peer-to-peer use, keep Wi-Fi and Bluetooth turned on on both devices. Joining a Wi-Fi network is not required.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 500)

                Text("Expires in two minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Generate New Code", systemImage: "arrow.clockwise") {
                    peer.regenerateViewerCode()
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView("Creating private session…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var receivedVideo: some View {
        ZStack {
            Color.black

            if let frame = peer.receivedFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connected. Waiting for the iPhone to lock and share the monitor.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
