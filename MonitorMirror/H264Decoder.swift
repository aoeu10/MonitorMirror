import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import UIKit
import VideoToolbox

final class H264Decoder {
    typealias OutputHandler = (Result<UIImage, Error>) -> Void

    private let outputHandler: OutputHandler
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private var currentSPS: Data?
    private var currentPPS: Data?
    private var frameIndex: Int64 = 0

    init(outputHandler: @escaping OutputHandler) {
        self.outputHandler = outputHandler
    }

    deinit {
        invalidate()
    }

    func decode(_ accessUnit: H264AccessUnit) throws {
        guard accessUnit.isKeyFrame || decompressionSession != nil else {
            throw H264DecoderError.configurationRequired
        }

        if accessUnit.isKeyFrame {
            guard let sps = accessUnit.sps, let pps = accessUnit.pps else {
                throw H264DecoderError.configurationRequired
            }
            if decompressionSession == nil || sps != currentSPS || pps != currentPPS {
                try configure(sps: sps, pps: pps)
            }
        }

        guard let decompressionSession, let formatDescription else {
            throw H264DecoderError.configurationRequired
        }
        let blockBuffer = try makeBlockBuffer(from: accessUnit.sampleData)
        let sampleBuffer = try makeSampleBuffer(
            blockBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleSize: accessUnit.sampleData.count
        )

        var infoFlags = VTDecodeInfoFlags()
        let decodeFlags: VTDecodeFrameFlags = [
            ._EnableAsynchronousDecompression,
            ._1xRealTimePlayback
        ]
        let status = VTDecompressionSessionDecodeFrame(
            decompressionSession,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )
        guard status == noErr else {
            throw H264DecoderError.decodeFailed(status)
        }
        frameIndex &+= 1
    }

    func invalidate() {
        guard let decompressionSession else {
            formatDescription = nil
            currentSPS = nil
            currentPPS = nil
            return
        }
        self.decompressionSession = nil
        VTDecompressionSessionWaitForAsynchronousFrames(decompressionSession)
        VTDecompressionSessionInvalidate(decompressionSession)
        formatDescription = nil
        currentSPS = nil
        currentPPS = nil
    }

    private func configure(sps: Data, pps: Data) throws {
        invalidate()

        var createdFormat: CMFormatDescription?
        let formatStatus = try sps.withUnsafeBytes { spsBytes -> OSStatus in
            try pps.withUnsafeBytes { ppsBytes -> OSStatus in
                guard let spsBase = spsBytes.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBase = ppsBytes.bindMemory(to: UInt8.self).baseAddress else {
                    throw H264DecoderError.invalidParameterSets
                }
                var pointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                var sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &createdFormat
                )
            }
        }
        guard formatStatus == noErr, let videoFormat = createdFormat else {
            throw H264DecoderError.formatCreationFailed(formatStatus)
        }

        let destinationAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: Self.decompressionOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        var createdSession: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: videoFormat,
            decoderSpecification: nil,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &createdSession
        )
        guard sessionStatus == noErr, let createdSession else {
            throw H264DecoderError.decoderCreationFailed(sessionStatus)
        }

        formatDescription = videoFormat
        decompressionSession = createdSession
        currentSPS = sps
        currentPPS = pps
    }

    private func makeBlockBuffer(from data: Data) throws -> CMBlockBuffer {
        var optionalBlockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &optionalBlockBuffer
        )
        guard createStatus == kCMBlockBufferNoErr, let blockBuffer = optionalBlockBuffer else {
            throw H264DecoderError.blockBufferCreationFailed(createStatus)
        }
        let replaceStatus = data.withUnsafeBytes { bytes -> OSStatus in
            guard let source = bytes.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: source,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else {
            throw H264DecoderError.blockBufferCopyFailed(replaceStatus)
        }
        return blockBuffer
    }

    private func makeSampleBuffer(
        blockBuffer: CMBlockBuffer,
        formatDescription: CMVideoFormatDescription,
        sampleSize: Int
    ) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: H264Encoder.framesPerSecond),
            presentationTimeStamp: CMTime(
                value: frameIndex,
                timescale: H264Encoder.framesPerSecond
            ),
            decodeTimeStamp: .invalid
        )
        var size = sampleSize
        var optionalSampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &optionalSampleBuffer
        )
        guard status == noErr, let sampleBuffer = optionalSampleBuffer else {
            throw H264DecoderError.sampleBufferCreationFailed(status)
        }
        return sampleBuffer
    }

    private static let decompressionOutputCallback: VTDecompressionOutputCallback = {
        decompressionOutputRefCon,
        _,
        status,
        _,
        imageBuffer,
        _,
        _
        in
        guard let decompressionOutputRefCon else { return }
        let decoder = Unmanaged<H264Decoder>
            .fromOpaque(decompressionOutputRefCon)
            .takeUnretainedValue()
        guard status == noErr, let imageBuffer else {
            decoder.outputHandler(.failure(H264DecoderError.decodeFailed(status)))
            return
        }

        let image = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = decoder.ciContext.createCGImage(image, from: image.extent) else {
            decoder.outputHandler(.failure(H264DecoderError.imageCreationFailed))
            return
        }
        decoder.outputHandler(.success(UIImage(cgImage: cgImage)))
    }
}

enum H264DecoderError: LocalizedError {
    case configurationRequired
    case invalidParameterSets
    case formatCreationFailed(OSStatus)
    case decoderCreationFailed(OSStatus)
    case blockBufferCreationFailed(OSStatus)
    case blockBufferCopyFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
    case decodeFailed(OSStatus)
    case imageCreationFailed

    var errorDescription: String? {
        "H.264 video reception failed."
    }
}
