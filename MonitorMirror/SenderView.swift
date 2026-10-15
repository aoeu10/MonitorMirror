import SwiftUI
import UIKit

struct SenderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var peer: PeerSession
    @StateObject private var camera = CameraProcessor()

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
        .background(CameraOrientationReader(onChange: camera.updateInterfaceOrientation))
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            let activePeer = peer
            let activeCamera = camera
            camera.frameHandler = { [weak activePeer] accessUnit in
                Task { @MainActor in activePeer?.sendEncodedFrame(accessUnit) }
            }
            activePeer.keyFrameRequestHandler = { [weak activeCamera] in
                activeCamera?.requestKeyFrame()
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
            peer.keyFrameRequestHandler = nil
            peer.stop()
        }
    }

    private var pairingView: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                landscapePairingView(in: geometry.size)
            } else {
                portraitPairingView
            }
        }
        .padding()
    }

    private var portraitPairingView: some View {
        VStack(spacing: 16) {
            pairingInstructions
            pairingScanner
            pairingStatus
        }
    }

    private func landscapePairingView(in size: CGSize) -> some View {
        HStack(spacing: 16) {
            pairingScanner
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 12) {
                pairingInstructions
                Spacer(minLength: 0)
                pairingStatus
            }
            .frame(width: min(360, max(280, size.width * 0.36)))
        }
    }

    private var pairingInstructions: some View {
        VStack(spacing: 12) {
            Text("Scan the iPad")
                .font(.title2.bold())

            Text("On the iPad, choose **View Monitor**, then point this camera at its pairing code.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Wi-Fi and Bluetooth must be turned on on both devices. They do not need to be connected to a Wi-Fi network.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pairingScanner: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView(peer.state.message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var pairingStatus: some View {
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

    private var calibrationView: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                landscapeCalibrationView(in: geometry.size)
            } else {
                portraitCalibrationView
            }
        }
        .padding()
    }

    private var portraitCalibrationView: some View {
        VStack(spacing: 12) {
            calibrationControls
                .fixedSize(horizontal: false, vertical: true)
            calibrationPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func landscapeCalibrationView(in size: CGSize) -> some View {
        HStack(spacing: 12) {
            calibrationPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 10) {
                calibrationActions(stacked: true)
                ScrollView {
                    calibrationDetails
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: min(340, max(280, size.width * 0.31)), alignment: .top)
        }
    }

    @ViewBuilder
    private var calibrationPreview: some View {
        if let image = camera.previewImage {
            CalibrationCanvas(
                image: image,
                corners: camera.corners,
                isLocked: camera.isLocked,
                onCornerChanged: camera.updateCorner
            )
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            ZStack {
                Color.black
                ProgressView("Starting rear camera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var calibrationControls: some View {
        VStack(spacing: 10) {
            calibrationActions()
            calibrationDetails
        }
    }

    private func calibrationActions(stacked: Bool = false) -> some View {
        VStack(spacing: 10) {
            if stacked {
                VStack(spacing: 10) { cornerControls }
            } else {
                HStack(spacing: 10) { cornerControls }
            }

            Button {
                if camera.isSharing {
                    endSharingSession()
                } else {
                    camera.setSharing(true)
                }
            } label: {
                Label(camera.isSharing ? "Stop Sharing" : "Share", systemImage: camera.isSharing ? "stop.fill" : "video.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(camera.isSharing ? .red : .blue)
            .disabled(!camera.isLocked || camera.corners == nil)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var cornerControls: some View {
        Button {
            camera.setSharing(false)
            camera.redetect()
        } label: {
            Label("Re-detect", systemImage: "viewfinder")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
            if camera.isLocked {
                camera.setSharing(false)
                camera.setCalibrationLocked(false)
            } else {
                camera.setCalibrationLocked(true)
            }
        } label: {
            Label(camera.isLocked ? "Unlock" : "Lock Corners", systemImage: camera.isLocked ? "lock.open" : "lock")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(camera.corners == nil)
    }

    private var calibrationDetails: some View {
        VStack(spacing: 10) {
            if camera.previewImage != nil {
                Text(camera.corners == nil ? "Detecting monitor…" : (camera.isLocked ? "Calibration locked" : "Corners held — drag to adjust or Re-detect"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if camera.availableLenses.count > 1 {
                Picker("Camera Lens", selection: Binding(
                    get: { camera.selectedLens },
                    set: { camera.selectLens($0) }
                )) {
                    ForEach(camera.availableLenses) { lens in
                        Text(lens.shortTitle)
                            .tag(lens)
                            .accessibilityLabel(lens.title)
                    }
                }
                .pickerStyle(.segmented)

                Text("Changing lens stops sharing and resets calibration.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = camera.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Label(peer.state.message, systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        }
        .controlSize(.large)
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

private struct CameraOrientationReader: UIViewControllerRepresentable {
    let onChange: (UIInterfaceOrientation) -> Void

    func makeUIViewController(context: Context) -> OrientationController {
        let controller = OrientationController()
        controller.onChange = onChange
        return controller
    }

    func updateUIViewController(_ controller: OrientationController, context: Context) {
        controller.onChange = onChange
        controller.reportOrientation()
    }

    final class OrientationController: UIViewController {
        var onChange: ((UIInterfaceOrientation) -> Void)?
        private var lastOrientation: UIInterfaceOrientation?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            reportOrientation()
        }

        override func viewWillTransition(
            to size: CGSize,
            with coordinator: UIViewControllerTransitionCoordinator
        ) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.reportOrientation()
            }
        }

        func reportOrientation() {
            guard let orientation = view.window?.windowScene?.interfaceOrientation,
                  orientation != .unknown,
                  orientation != lastOrientation else { return }
            lastOrientation = orientation
            onChange?(orientation)
        }
    }
}
