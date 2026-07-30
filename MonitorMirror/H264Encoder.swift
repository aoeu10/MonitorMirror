import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class H264Encoder {
    static let width = 960
    static let height = 540
    static let framesPerSecond: Int32 = 15

    typealias OutputHandler = (Result<H264AccessUnit, Error>) -> Void

    private let ciContext: CIContext
    private let outputHandler: OutputHandler
    private let targetRect = CGRect(
        x: 0,
        y: 0,
        width: CGFloat(H264Encoder.width),
        height: CGFloat(H264Encoder.height)
    )
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var compressionSession: VTCompressionSession?
    private var frameIndex: Int64 = 0
    private var needsKeyFrame = true

    init(ciContext: CIContext, outputHandler: @escaping OutputHandler) throws {
        self.ciContext = ciContext
        self.outputHandler = outputHandler
        try createSession()
    }

    deinit {
        invalidate()
    }

    func encode(_ image: CIImage) throws {
        guard let compressionSession,
              let pool = VTCompressionSessionGetPixelBufferPool(compressionSession) else {
            throw H264CodecError.encoderUnavailable
        }

        var optionalPixelBuffer: CVPixelBuffer?
        let pixelStatus = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pool,
            &optionalPixelBuffer
        )
        guard pixelStatus == kCVReturnSuccess, let pixelBuffer = optionalPixelBuffer else {
            throw H264CodecError.pixelBufferCreationFailed(pixelStatus)
        }

        let canvas = CIImage(color: .black).cropped(to: targetRect)
        let source = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)
        )
        let scale = min(
            targetRect.width / source.extent.width,
            targetRect.height / source.extent.height
        )
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.transformed(
            by: CGAffineTransform(
                translationX: (targetRect.width - scaled.extent.width) / 2,
                y: (targetRect.height - scaled.extent.height) / 2
            )
        )
        ciContext.render(
            centered.composited(over: canvas),
            to: pixelBuffer,
            bounds: targetRect,
            colorSpace: colorSpace
        )

        let presentationTime = CMTime(value: frameIndex, timescale: Self.framesPerSecond)
        frameIndex &+= 1
        let frameProperties: CFDictionary? = needsKeyFrame
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            : nil
        let status = VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: CMTime(value: 1, timescale: Self.framesPerSecond),
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        guard status == noErr else { throw H264CodecError.encodeFailed(status) }
        needsKeyFrame = false
    }

    func requestKeyFrame() {
        needsKeyFrame = true
    }

    func invalidate() {
        guard let compressionSession else { return }
        self.compressionSession = nil
        VTCompressionSessionCompleteFrames(
            compressionSession,
            untilPresentationTimeStamp: .invalid
        )
        VTCompressionSessionInvalidate(compressionSession)
    }

    private func createSession() throws {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Self.width,
            kCVPixelBufferHeightKey: Self.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var createdSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(Self.width),
            height: Int32(Self.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: Self.compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &createdSession
        )
        guard status == noErr, let createdSession else {
            throw H264CodecError.encoderCreationFailed(status)
        }
        compressionSession = createdSession

        try set(kVTCompressionPropertyKey_RealTime, to: kCFBooleanTrue, on: createdSession)
        try set(
            kVTCompressionPropertyKey_ProfileLevel,
            to: kVTProfileLevel_H264_Baseline_AutoLevel,
            on: createdSession
        )
        try set(kVTCompressionPropertyKey_AllowFrameReordering, to: kCFBooleanFalse, on: createdSession)
        try set(
            kVTCompressionPropertyKey_MaxFrameDelayCount,
            to: NSNumber(value: 1),
            on: createdSession
        )
        try set(
            kVTCompressionPropertyKey_ExpectedFrameRate,
            to: NSNumber(value: Self.framesPerSecond),
            on: createdSession
        )
        try set(
            kVTCompressionPropertyKey_AverageBitRate,
            to: NSNumber(value: 1_500_000),
            on: createdSession
        )
        try set(
            kVTCompressionPropertyKey_MaxKeyFrameInterval,
            to: NSNumber(value: Self.framesPerSecond * 2),
            on: createdSession
        )
        try set(
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
            to: NSNumber(value: 2),
            on: createdSession
        )

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(createdSession)
        guard prepareStatus == noErr else {
            invalidate()
            throw H264CodecError.encoderPreparationFailed(prepareStatus)
        }
    }

    private func set(_ key: CFString, to value: CFTypeRef, on session: VTCompressionSession) throws {
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else { throw H264CodecError.encoderConfigurationFailed(status) }
    }

    private static let compressionOutputCallback: VTCompressionOutputCallback = {
        outputCallbackRefCon,
        _,
        status,
        _,
        sampleBuffer
        in
        guard let outputCallbackRefCon else { return }
        let encoder = Unmanaged<H264Encoder>
            .fromOpaque(outputCallbackRefCon)
            .takeUnretainedValue()
        guard status == noErr,
              let sampleBuffer,
              CMSampleBufferDataIsReady(sampleBuffer) else {
            encoder.outputHandler(.failure(H264CodecError.encodeFailed(status)))
            return
        }

        do {
            encoder.outputHandler(.success(try makeAccessUnit(from: sampleBuffer)))
        } catch {
            encoder.outputHandler(.failure(error))
        }
    }

    private static func makeAccessUnit(from sampleBuffer: CMSampleBuffer) throws -> H264AccessUnit {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw H264CodecError.missingEncodedData
        }
        let sampleLength = CMBlockBufferGetDataLength(blockBuffer)
        guard sampleLength > 0, sampleLength <= H264AccessUnit.maximumSampleBytes else {
            throw H264CodecError.invalidEncodedData
        }
        var sampleData = Data(count: sampleLength)
        let copyStatus = sampleData.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let destination = bytes.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: sampleLength,
                destination: destination
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else {
            throw H264CodecError.encodedDataCopyFailed(copyStatus)
        }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[CFString: Any]]
        var isKeyFrame = true
        if let firstAttachment = attachments?.first,
           let notSync = firstAttachment[kCMSampleAttachmentKey_NotSync] as? Bool {
            isKeyFrame = !notSync
        }

        var sps: Data?
        var pps: Data?
        if isKeyFrame {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                throw H264CodecError.missingFormatDescription
            }
            sps = try parameterSet(at: 0, from: format)
            pps = try parameterSet(at: 1, from: format)
        }
        return try H264AccessUnit(
            sampleData: sampleData,
            isKeyFrame: isKeyFrame,
            sps: sps,
            pps: pps
        )
    }

    private static func parameterSet(
        at index: Int,
        from format: CMFormatDescription
    ) throws -> Data {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        var count = 0
        var headerLength: Int32 = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: index,
            parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size,
            parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: &headerLength
        )
        guard status == noErr,
              headerLength == 4,
              count >= 2,
              size > 0,
              let pointer else {
            throw H264CodecError.invalidParameterSets
        }
        return Data(bytes: pointer, count: size)
    }
}

enum H264CodecError: LocalizedError {
    case encoderUnavailable
    case encoderCreationFailed(OSStatus)
    case encoderConfigurationFailed(OSStatus)
    case encoderPreparationFailed(OSStatus)
    case pixelBufferCreationFailed(CVReturn)
    case encodeFailed(OSStatus)
    case missingEncodedData
    case invalidEncodedData
    case encodedDataCopyFailed(OSStatus)
    case missingFormatDescription
    case invalidParameterSets

    var errorDescription: String? {
        "H.264 video processing failed."
    }
}
