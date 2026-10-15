import AVFoundation
import Combine
import CoreImage
import ImageIO
import UIKit
import XCTest
@testable import MonitorMirror

final class CameraSetupTests: XCTestCase {
    private let context = CIContext()

    @MainActor
    func testDetectionHoldsFirstCandidateUntilRedetectAndPreservesManualEdits() async throws {
        let camera = CameraProcessor()
        let first = monitorImage(rect: CGRect(x: 70, y: 100, width: 400, height: 260))
        let second = monitorImage(rect: CGRect(x: 190, y: 60, width: 360, height: 300))
        try await observe(camera.$corners, when: { $0 != nil }) {
            try feed(first, to: camera, count: 12)
        }
        let held = try XCTUnwrap(camera.corners)
        try feed(second, to: camera, count: 36)
        await flushMainQueue()
        XCTAssertEqual(camera.corners, held, "A later rectangle must not replace the first candidate")

        await observe(camera.$corners, when: { $0 == nil }) { camera.redetect() }
        try await observe(camera.$corners, when: { $0 != nil }) {
            try feed(second, to: camera, count: 12)
        }
        XCTAssertNotEqual(camera.corners, held, "Re-detect must accept a new candidate")

        let adjusted = CGPoint(x: 0.18, y: 0.84)
        await observe(camera.$corners, when: { $0?.topLeft == adjusted }) {
            camera.updateCorner(.topLeft, to: adjusted)
        }
        await observe(camera.$isLocked, when: { $0 }) { camera.setCalibrationLocked(true) }
        await observe(camera.$isLocked, when: { !$0 }) { camera.setCalibrationLocked(false) }
        try feed(first, to: camera, count: 36)
        await flushMainQueue()
        XCTAssertEqual(camera.corners?.topLeft, adjusted, "Unlocking must not restart detection")
    }

    func testCornerIdentitiesSurviveEveryQuarterTurnAndRoundTrip() {
        let corners = CornerSet(
            topLeft: CGPoint(x: 0.15, y: 0.88), topRight: CGPoint(x: 0.81, y: 0.79),
            bottomRight: CGPoint(x: 0.9, y: 0.14), bottomLeft: CGPoint(x: 0.08, y: 0.21)
        )
        let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        let reference = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        for old in orientations {
            for new in orientations {
                let converted = corners.reoriented(from: old, to: new)
                let oldImage = reference.oriented(old)
                let newImage = reference.oriented(new)
                let transform = reference.orientationTransform(for: old).inverted()
                    .concatenating(reference.orientationTransform(for: new))
                for corner in CornerSet.Corner.allCases {
                    let point = corners[corner]
                    let oldPixel = CGPoint(
                        x: oldImage.extent.minX + point.x * oldImage.extent.width,
                        y: oldImage.extent.minY + point.y * oldImage.extent.height
                    )
                    let expectedPixel = oldPixel.applying(transform)
                    let actual = converted[corner]
                    XCTAssertEqual(actual.x, (expectedPixel.x - newImage.extent.minX) / newImage.extent.width, accuracy: 0.000001)
                    XCTAssertEqual(actual.y, (expectedPixel.y - newImage.extent.minY) / newImage.extent.height, accuracy: 0.000001)
                    let roundTrip = converted.reoriented(from: new, to: old)[corner]
                    XCTAssertEqual(roundTrip.x, point.x, accuracy: 0.000001)
                    XCTAssertEqual(roundTrip.y, point.y, accuracy: 0.000001)
                }
            }
        }
    }

    @MainActor
    func testEncodedViewerPixelsStayUprightWhenPhoneRotatesAfterCalibration() async throws {
        let camera = CameraProcessor()
        // Four different quadrants expose quarter-turn and upside-down errors after H.264 decoding.
        let upright = quadrantImage()
        try await observe(camera.$corners, when: { $0 != nil }) {
            try feed(monitorImage(rect: CGRect(x: 70, y: 100, width: 400, height: 260)), to: camera, count: 12)
        }
        let full = CornerSet(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1),
                             bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 0))
        for corner in CornerSet.Corner.allCases {
            await observe(camera.$corners, when: { $0?[corner] == full[corner] }) {
                camera.updateCorner(corner, to: full[corner])
            }
        }
        await observe(camera.$isLocked, when: { $0 }) { camera.setCalibrationLocked(true) }
        await observe(camera.$isSharing, when: { $0 }) { camera.setSharing(true) }
        // Portrait calibration uses .right on sensor pixels. Keep the physical fixture constant.
        let raw = upright.oriented(.left)
        let orientations: [UIInterfaceOrientation] = [.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown]
        for orientation in orientations {
            if orientation != .portrait {
                let previous = camera.corners
                await observe(camera.$corners, when: { $0 != previous }) {
                    camera.updateInterfaceOrientation(orientation)
                }
            }
            // Respect the production 15 FPS rate limit before submitting the next synthetic frame.
            try await Task.sleep(for: .milliseconds(100))
            let decoded = expectation(description: "Decoded frame for \(orientation.rawValue)")
            let result = FrameResult()
            let decoder = H264Decoder { frame in
                result.store(frame)
                decoded.fulfill()
            }
            camera.frameHandler = { unit in
                do { try decoder.decode(unit) }
                catch { result.store(.failure(error)); decoded.fulfill() }
            }
            try feedRaw(raw, to: camera, count: 1)
            await fulfillment(of: [decoded], timeout: 10)
            camera.frameHandler = nil
            let frame = try result.image()
            XCTAssertGreaterThan(frame.size.width, frame.size.height)
            assertColor(frame, x: 0.25, y: 0.75, red: true, green: false, blue: false)
            assertColor(frame, x: 0.75, y: 0.75, red: false, green: true, blue: false)
            assertColor(frame, x: 0.25, y: 0.25, red: false, green: false, blue: true)
            assertColor(frame, x: 0.75, y: 0.25, red: true, green: true, blue: false)
            decoder.invalidate()
        }
        await observe(camera.$isSharing, when: { !$0 }) { camera.setSharing(false) }
    }

    @MainActor
    private func observe<T>(
        _ publisher: Published<T>.Publisher, when predicate: @escaping (T) -> Bool,
        action: () throws -> Void
    ) async rethrows {
        let changed = expectation(description: "Camera state transition")
        let subscription = publisher.filter(predicate).prefix(1).sink { _ in changed.fulfill() }
        try action()
        await fulfillment(of: [changed], timeout: 5)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    private func flushMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func monitorImage(rect: CGRect) -> CIImage {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 480)
        return CIImage(color: .white).cropped(to: rect)
            .composited(over: CIImage(color: .black).cropped(to: bounds))
    }

    private func quadrantImage() -> CIImage {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 480)
        var image = CIImage(color: .black).cropped(to: bounds)
        let patches: [(CIColor, CGRect)] = [
            (.red, CGRect(x: 0, y: 240, width: 320, height: 240)),
            (.green, CGRect(x: 320, y: 240, width: 320, height: 240)),
            (.blue, CGRect(x: 0, y: 0, width: 320, height: 240)),
            (CIColor(red: 1, green: 1, blue: 0), CGRect(x: 320, y: 0, width: 320, height: 240))
        ]
        for (color, rect) in patches {
            image = CIImage(color: color).cropped(to: rect).composited(over: image)
        }
        return image
    }

    private func feed(_ upright: CIImage, to camera: CameraProcessor, count: Int) throws {
        try feedRaw(upright.oriented(.left), to: camera, count: count)
    }

    private func feedRaw(_ raw: CIImage, to camera: CameraProcessor, count: Int) throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, Int(raw.extent.width), Int(raw.extent.height),
            kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        let normalized = raw.transformed(by: CGAffineTransform(translationX: -raw.extent.minX, y: -raw.extent.minY))
        context.render(normalized, to: pixels)
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixels, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        let sampleBuffer = try XCTUnwrap(sample)
        let output = AVCaptureVideoDataOutput()
        let connection = AVCaptureConnection(inputPorts: [], output: output)
        for _ in 0..<count { camera.captureOutput(output, didOutput: sampleBuffer, from: connection) }
    }

    private func assertColor(_ image: UIImage, x: CGFloat, y: CGFloat, red: Bool, green: Bool, blue: Bool) {
        let ciImage = CIImage(cgImage: image.cgImage!)
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(ciImage, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: ciImage.extent.width * x, y: ciImage.extent.height * y, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        for (value, high) in zip(pixel.prefix(3), [red, green, blue]) {
            if high { XCTAssertGreaterThan(value, 180) } else { XCTAssertLessThan(value, 65) }
        }
    }
}

private final class FrameResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<UIImage, Error>?
    func store(_ result: Result<UIImage, Error>) { lock.lock(); self.result = result; lock.unlock() }
    func image() throws -> UIImage {
        lock.lock(); defer { lock.unlock() }
        return try XCTUnwrap(result).get()
    }
}
