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

final class CameraProcessor: NSObject, ObservableObject {
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var corners: CornerSet?
    @Published private(set) var isRunning = false
    @Published private(set) var isLocked = false
    @Published private(set) var isSharing = false
    @Published private(set) var errorMessage: String?

    private let frameHandlerLock = NSLock()
    private let lifecycleLock = NSLock()
    private var storedFrameHandler: ((Data) -> Void)?
    private var runRequested = false

    var frameHandler: ((Data) -> Void)? {
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
    private var locked = false
    private var sharing = false
    private var frameNumber = 0
    private var lastSentAt = CFAbsoluteTimeGetCurrent()
    private var configured = false

    func start() {
        setRunRequested(true)
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
            DispatchQueue.main.async {
                self.isRunning = false
                self.isSharing = false
            }
        }
    }

    func redetect() {
        captureQueue.async { [weak self] in
            self?.locked = false
            self?.activeCorners = nil
            DispatchQueue.main.async {
                self?.isLocked = false
                self?.corners = nil
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
            self.sharing = value && self.activeCorners != nil
            DispatchQueue.main.async { self.isSharing = self.sharing }
        }
    }

    func updateCorner(_ corner: CornerSet.Corner, to point: CGPoint) {
        let clamped = CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
        captureQueue.async { [weak self] in
            guard let self, var updated = self.activeCorners else { return }
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
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
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

    private func makeJPEG(from image: CIImage) -> Data? {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.68)
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = message }
    }
}

extension CameraProcessor: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Rear-camera buffers arrive in the sensor's landscape orientation. The sender UI is portrait.
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        frameNumber += 1

        if !locked && frameNumber % 12 == 0 {
            detectMonitor(in: image)
        }

        if frameNumber % 3 == 0, let preview = makePreview(from: image) {
            DispatchQueue.main.async { [weak self] in self?.previewImage = preview }
        }

        guard sharing,
              let activeCorners,
              CFAbsoluteTimeGetCurrent() - lastSentAt >= 0.10,
              let corrected = correctedImage(from: image, corners: activeCorners),
              let jpeg = makeJPEG(from: corrected) else {
            return
        }

        lastSentAt = CFAbsoluteTimeGetCurrent()
        let handler = frameHandler
        handler?(jpeg)
    }
}

private enum CameraError: LocalizedError {
    case cameraUnavailable
    case inputUnavailable
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "The rear camera is unavailable."
        case .inputUnavailable: return "The rear camera could not be added to the capture session."
        case .outputUnavailable: return "Video frame output is unavailable."
        }
    }
}
