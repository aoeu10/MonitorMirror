import SwiftUI
import UIKit

struct SenderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var peer: PeerSession
    @EnvironmentObject private var camera: CameraProcessor

    @State private var pairingAccepted = false
    @State private var scanError: String?
    @State private var scannerID = UUID()

    var body: some View {
        Group {
            if peer.isConnected {
                calibrationView
            } else {
                pairingView
            }
        }
        .navigationTitle("iPhone Camera")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            let activePeer = peer
            camera.frameHandler = { [weak activePeer] jpeg in
                Task { @MainActor in activePeer?.sendCorrectedFrame(jpeg) }
            }
        }
        .onChange(of: peer.isConnected) { _, connected in
            if connected {
                camera.start()
            } else {
                camera.setSharing(false)
                camera.stop()
            }
        }
        .onChange(of: peer.sessionEndSequence) { _, _ in
            dismiss()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            camera.setSharing(false)
            camera.stop()
            camera.frameHandler = nil
            peer.stop()
        }
    }

    private var pairingView: some View {
        VStack(spacing: 16) {
            Text("Scan the iPad")
                .font(.title2.bold())

            Text("On the iPad, choose **View Monitor**, then point this camera at its pairing code.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Text("Wi-Fi and Bluetooth must be turned on on both devices. They do not need to be connected to a Wi-Fi network.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if !pairingAccepted {
                QRScannerView(
                    onCode: handlePairingCode,
                    onError: { scanError = $0 }
                )
                .id(scannerID)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.blue, lineWidth: 3)
                        .padding(42)
                }
                .frame(maxWidth: 520, maxHeight: 520)
            } else {
                Spacer()
                ProgressView(peer.state.message)
                Spacer()
            }

            if case .failed(let message) = peer.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)

                Button("Try Pairing Again") {
                    resetPairing()
                }
                .buttonStyle(.borderedProminent)
            } else if let scanError {
                Text(scanError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)

                Button("Scan Again") {
                    resetPairing()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label(peer.state.message, systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var calibrationView: some View {
        VStack(spacing: 12) {
            if let image = camera.previewImage {
                CalibrationCanvas(
                    image: image,
                    corners: camera.corners,
                    isLocked: camera.isLocked,
                    onCornerChanged: camera.updateCorner
                )
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .top) {
                    Text(camera.corners == nil ? "Detecting monitor…" : (camera.isLocked ? "Calibration locked" : "Drag corners to adjust"))
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            } else {
                ZStack {
                    Color.black
                    ProgressView("Starting rear camera…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let error = camera.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button("Re-detect", systemImage: "viewfinder") {
                    camera.setSharing(false)
                    camera.redetect()
                }
                .buttonStyle(.bordered)

                Button(camera.isLocked ? "Unlock" : "Lock Corners", systemImage: camera.isLocked ? "lock.open" : "lock") {
                    if camera.isLocked {
                        camera.setSharing(false)
                        camera.setCalibrationLocked(false)
                    } else {
                        camera.setCalibrationLocked(true)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(camera.corners == nil)

                Button(camera.isSharing ? "Stop Sharing" : "Share", systemImage: camera.isSharing ? "stop.fill" : "video.fill") {
                    if camera.isSharing {
                        endSharingSession()
                    } else {
                        camera.setSharing(true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(camera.isSharing ? .red : .blue)
                .disabled(!camera.isLocked || camera.corners == nil)
            }
            .controlSize(.large)

            Label(peer.state.message, systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        }
        .padding()
    }

    private func endSharingSession() {
        camera.setSharing(false)
        camera.stop()
        peer.endSession()
    }

    private func resetPairing() {
        camera.setSharing(false)
        camera.stop()
        peer.stop()
        pairingAccepted = false
        scanError = nil
        scannerID = UUID()
    }

    private func handlePairingCode(_ code: String) {
        do {
            try peer.joinViewer(using: code)
            pairingAccepted = true
            scanError = nil
        } catch {
            scanError = error.localizedDescription
            pairingAccepted = false
            scannerID = UUID()
        }
    }
}

private struct CalibrationCanvas: View {
    let image: UIImage
    let corners: CornerSet?
    let isLocked: Bool
    let onCornerChanged: (CornerSet.Corner, CGPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            let imageRect = aspectFitRect(imageSize: image.size, in: geometry.size)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let corners {
                    Path { path in
                        let points = [
                            displayPoint(corners.topLeft, in: imageRect),
                            displayPoint(corners.topRight, in: imageRect),
                            displayPoint(corners.bottomRight, in: imageRect),
                            displayPoint(corners.bottomLeft, in: imageRect)
                        ]
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                        path.closeSubpath()
                    }
                    .stroke(isLocked ? .green : .yellow, style: StrokeStyle(lineWidth: 3, dash: isLocked ? [] : [7, 5]))

                    if !isLocked {
                        ForEach(CornerSet.Corner.allCases, id: \.self) { corner in
                            Circle()
                                .fill(.yellow)
                                .overlay {
                                    Circle().stroke(.black, lineWidth: 2)
                                }
                                .frame(width: 30, height: 30)
                                .position(displayPoint(corners[corner], in: imageRect))
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            onCornerChanged(corner, normalizedPoint(value.location, in: imageRect))
                                        }
                                )
                        }
                    }
                }
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
    }

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func displayPoint(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: rect.minY + (1 - normalized.y) * rect.height
        )
    }

    private func normalizedPoint(_ display: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((display.x - rect.minX) / rect.width, 0), 1),
            y: min(max(1 - (display.y - rect.minY) / rect.height, 0), 1)
        )
    }
}
