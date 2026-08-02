import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import Vision

struct CornerSet: Equatable {
    enum Corner: CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    subscript(corner: Corner) -> CGPoint {
        get {
            switch corner {
            case .topLeft: return topLeft
            case .topRight: return topRight
            case .bottomRight: return bottomRight
            case .bottomLeft: return bottomLeft
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomLeft: bottomLeft = newValue
            }
        }
    }
}

enum CameraLens: String, CaseIterable, Identifiable, Hashable {
    case ultraWide
    case wide
    case telephoto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ultraWide: return "Ultra Wide"
        case .wide: return "Wide"
        case .telephoto: return "Telephoto"
        }
    }

    var shortTitle: String {
        switch self {
        case .ultraWide: return "0.5×"
        case .wide: return "1×"
        case .telephoto: return "Tele"
        }
    }

    fileprivate var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideAngleCamera
        case .wide: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
}

final class CameraProcessor: NSObject, ObservableObject {
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var corners: CornerSet?
    @Published private(set) var isRunning = false
    @Published private(set) var isLocked = false
    @Published private(set) var isSharing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var availableLenses: [CameraLens] = []
    @Published private(set) var selectedLens: CameraLens = .wide

    private let frameHandlerLock = NSLock()
    private let lifecycleLock = NSLock()
    private var storedFrameHandler: ((H264AccessUnit) -> Void)?
    private var runRequested = false

    var frameHandler: ((H264AccessUnit) -> Void)? {
        get {
            frameHandlerLock.lock()
            defer { frameHandlerLock.unlock() }
            return storedFrameHandler
        }
        set {
            frameHandlerLock.lock()
            storedFrameHandler = newValue
            frameHandlerLock.unlock()
        }
    }

    private lazy var session = AVCaptureSession()
    private lazy var output = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "MonitorMirror.camera", qos: .userInitiated)
    private lazy var ciContext = CIContext(options: [.cacheIntermediates: false])

    private var activeCorners: CornerSet?
    private var autoDetectionEnabled = true
    private var locked = false
    private var sharing = false
    private var frameNumber = 0
    private var lastSentAt = CFAbsoluteTimeGetCurrent()
    private var configured = false
    private var h264Encoder: H264Encoder?
    private var encoderDimensions: CGSize?
    private var captureOrientation: CGImagePropertyOrientation = .right
    private var cameraInput: AVCaptureDeviceInput?
    private var activeLens: CameraLens = .wide

    override init() {
        super.init()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        updateCaptureOrientation(UIDevice.current.orientation)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func start() {
        setRunRequested(true)
        updateCaptureOrientation(UIDevice.current.orientation)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    self.setRunRequested(false)
                    self.publishError("Camera permission is required to capture the monitor.")
                    return
                }
                guard self.isRunRequested else { return }
                self.configureAndStart()
            }
        default:
            setRunRequested(false)
            publishError("Enable camera access in Settings to capture the monitor.")
        }
    }

    func stop() {
        setRunRequested(false)
        captureQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.sharing = false
            self.stopEncoder()
            DispatchQueue.main.async {
                self.isRunning = false
                self.isSharing = false
            }
        }
    }

    func redetect() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.sharing = false
            self.stopEncoder()
            self.locked = false
            self.autoDetectionEnabled = true
            self.activeCorners = nil
            DispatchQueue.main.async {
                self.isSharing = false
                self.isLocked = false
                self.corners = nil
            }
        }
    }

    func setCalibrationLocked(_ value: Bool) {
        captureQueue.async { [weak self] in
            self?.locked = value
            DispatchQueue.main.async { self?.isLocked = value }
        }
    }

    func setSharing(_ value: Bool) {
        captureQueue.async { [weak self] in
            guard let self else { return }
            if value, self.activeCorners != nil {
                self.sharing = true
            } else {
                self.sharing = false
                self.stopEncoder()
            }
            DispatchQueue.main.async { self.isSharing = self.sharing }
        }
    }

    func selectLens(_ lens: CameraLens) {
        captureQueue.async { [weak self] in
            guard let self, self.configured, lens != self.activeLens else { return }
            do {
                guard let device = self.availableRearDevices().first(where: {
                    $0.deviceType == lens.deviceType
                }) else {
                    throw CameraError.lensUnavailable
                }

                let newInput = try AVCaptureDeviceInput(device: device)
                let previousInput = self.cameraInput
                self.session.beginConfiguration()
                if let previousInput {
                    self.session.removeInput(previousInput)
                }
                guard self.session.canAddInput(newInput) else {
                    let restoredPreviousInput: Bool
                    if let previousInput, self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                        restoredPreviousInput = true
                    } else {
                        restoredPreviousInput = false
                        if self.session.outputs.contains(where: { $0 === self.output }) {
                            self.session.removeOutput(self.output)
                        }
                        self.cameraInput = nil
                        self.configured = false
                    }
                    self.session.commitConfiguration()
                    guard restoredPreviousInput else {
                        self.setRunRequested(false)
                        if self.session.isRunning { self.session.stopRunning() }
                        self.sharing = false
                        self.stopEncoder()
                        self.locked = false
                        self.autoDetectionEnabled = true
                        self.activeCorners = nil
                        DispatchQueue.main.async {
                            self.isRunning = false
                            self.isSharing = false
                            self.isLocked = false
                            self.corners = nil
                            self.previewImage = nil
                            self.availableLenses = []
                        }
                        throw CameraError.lensRollbackFailed
                    }
                    throw CameraError.inputUnavailable
                }
                self.session.addInput(newInput)
                self.session.commitConfiguration()

                self.cameraInput = newInput
                self.activeLens = lens
                self.sharing = false
                self.stopEncoder()
                self.locked = false
                self.autoDetectionEnabled = true
                self.activeCorners = nil
                self.frameNumber = 0
                DispatchQueue.main.async {
                    self.selectedLens = lens
                    self.isSharing = false
                    self.isLocked = false
                    self.corners = nil
                    self.previewImage = nil
                    self.errorMessage = nil
                }
            } catch {
                self.publishError("Camera lens change failed: \(error.localizedDescription)")
            }
        }
    }

    func requestKeyFrame() {
        captureQueue.async { [weak self] in
            self?.h264Encoder?.requestKeyFrame()
        }
    }

    func updateCorner(_ corner: CornerSet.Corner, to point: CGPoint) {
        let clamped = CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
        captureQueue.async { [weak self] in
            guard let self, var updated = self.activeCorners else { return }
            self.autoDetectionEnabled = false
            updated[corner] = clamped
            self.activeCorners = updated
            DispatchQueue.main.async { self.corners = updated }
        }
    }

    private var isRunRequested: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return runRequested
    }

    private func setRunRequested(_ value: Bool) {
        lifecycleLock.lock()
        runRequested = value
        lifecycleLock.unlock()
    }

    @objc private func deviceOrientationDidChange() {
        updateCaptureOrientation(UIDevice.current.orientation)
    }

    private func updateCaptureOrientation(_ deviceOrientation: UIDeviceOrientation) {
        let orientation: CGImagePropertyOrientation
        switch deviceOrientation {
        case .portrait:
            orientation = .right
        case .portraitUpsideDown:
            orientation = .left
        case .landscapeLeft:
            orientation = .up
        case .landscapeRight:
            orientation = .down
        default:
            return
        }

        captureQueue.async { [weak self] in
            self?.captureOrientation = orientation
        }
    }

    private func configureAndStart() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.configured { try self.configureSession() }
                guard self.isRunRequested, !self.session.isRunning else { return }
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.errorMessage = nil
                }
            } catch {
                self.publishError("Camera setup failed: \(error.localizedDescription)")
            }
        }
    }

    private func configureSession() throws {
        let devices = availableRearDevices()
        let lenses = CameraLens.allCases.filter { lens in
            devices.contains { $0.deviceType == lens.deviceType }
        }
        let initialLens: CameraLens?
        if lenses.contains(.wide) {
            initialLens = .wide
        } else {
            initialLens = lenses.first
        }
        guard let initialLens,
              let camera = devices.first(where: { $0.deviceType == initialLens.deviceType }) else {
            throw CameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.inputUnavailable
        }
        session.addInput(input)
        cameraInput = input
        activeLens = initialLens

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.outputUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
        DispatchQueue.main.async {
            self.availableLenses = lenses
            self.selectedLens = initialLens
        }
    }

    private func availableRearDevices() -> [AVCaptureDevice] {
        let deviceTypes = CameraLens.allCases.map { $0.deviceType }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        ).devices
    }

    private func detectMonitor(in image: CIImage) {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 4
        request.minimumConfidence = 0.62
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.18
        request.quadratureTolerance = 35

        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        do {
            try handler.perform([request])
            guard let observation = request.results?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            }) else { return }

            let detected = CornerSet(
                topLeft: observation.topLeft,
                topRight: observation.topRight,
                bottomRight: observation.bottomRight,
                bottomLeft: observation.bottomLeft
            )
            activeCorners = detected
            DispatchQueue.main.async { [weak self] in self?.corners = detected }
        } catch {
            publishError("Monitor detection failed: \(error.localizedDescription)")
        }
    }

    private func correctedImage(from image: CIImage, corners: CornerSet) -> CIImage? {
        let extent = image.extent
        func imagePoint(_ normalized: CGPoint) -> CGPoint {
            CGPoint(
                x: extent.minX + normalized.x * extent.width,
                y: extent.minY + normalized.y * extent.height
            )
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = imagePoint(corners.topLeft)
        filter.topRight = imagePoint(corners.topRight)
        filter.bottomRight = imagePoint(corners.bottomRight)
        filter.bottomLeft = imagePoint(corners.bottomLeft)
        guard var outputImage = filter.outputImage, !outputImage.extent.isEmpty else { return nil }

        let outputExtent = outputImage.extent
        outputImage = outputImage.transformed(
            by: CGAffineTransform(translationX: -outputExtent.minX, y: -outputExtent.minY)
        )

        let maximumWidth: CGFloat = 960
        if outputImage.extent.width > maximumWidth {
            let scale = maximumWidth / outputImage.extent.width
            outputImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return outputImage
    }

    private func makePreview(from image: CIImage) -> UIImage? {
        let maximumWidth: CGFloat = 720
        var preview = image
        if image.extent.width > maximumWidth {
            let scale = maximumWidth / image.extent.width
            preview = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cgImage = ciContext.createCGImage(preview, from: preview.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func ensureEncoder(for image: CIImage) throws {
        let dimensions = H264Encoder.dimensions(for: image.extent)
        if encoderDimensions != dimensions {
            stopEncoder()
        }
        guard h264Encoder == nil else { return }

        let encoder = try H264Encoder(
            width: Int(dimensions.width),
            height: Int(dimensions.height),
            ciContext: ciContext
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let accessUnit):
                let handler = self.frameHandler
                handler?(accessUnit)
            case .failure(let error):
                self.reportH264Error(error)
            }
        }
        h264Encoder = encoder
        encoderDimensions = dimensions
    }

    private func stopEncoder() {
        h264Encoder?.invalidate()
        h264Encoder = nil
        encoderDimensions = nil
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = message }
    }

    private func reportH264Error(_ error: Error) {
        guard let codecError = error as? H264CodecError else {
            LaunchDiagnostics.mark("h264.encoder.unknown.failed")
            publishError("H.264 video processing failed at an unknown stage.")
            return
        }
        LaunchDiagnostics.mark(codecError.diagnosticEvent)
        publishError(codecError.localizedDescription)
    }
}

extension CameraProcessor: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Rear-camera buffers arrive in sensor orientation. Apply the current physical-device
        // orientation before detection, calibration, correction, and encoding.
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(captureOrientation)
        frameNumber += 1

        if autoDetectionEnabled && !locked && frameNumber % 12 == 0 {
            detectMonitor(in: image)
        }

        if frameNumber % 3 == 0, let preview = makePreview(from: image) {
            DispatchQueue.main.async { [weak self] in self?.previewImage = preview }
        }

        guard sharing,
              let activeCorners,
              CFAbsoluteTimeGetCurrent() - lastSentAt >= (1.0 / Double(H264Encoder.framesPerSecond)),
              let corrected = correctedImage(from: image, corners: activeCorners) else {
            return
        }

        lastSentAt = CFAbsoluteTimeGetCurrent()
        do {
            try ensureEncoder(for: corrected)
        } catch {
            sharing = false
            stopEncoder()
            DispatchQueue.main.async { [weak self] in self?.isSharing = false }
            reportH264Error(error)
            return
        }

        do {
            try h264Encoder?.encode(corrected)
        } catch {
            reportH264Error(error)
        }
    }
}

private enum CameraError: LocalizedError {
    case cameraUnavailable
    case lensUnavailable
    case lensRollbackFailed
    case inputUnavailable
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "The rear camera is unavailable."
        case .lensUnavailable: return "The selected rear camera lens is unavailable."
        case .lensRollbackFailed: return "The previous camera could not be restored. Reconnect to restart capture."
        case .inputUnavailable: return "The rear camera could not be added to the capture session."
        case .outputUnavailable: return "Video frame output is unavailable."
        }
    }
}
