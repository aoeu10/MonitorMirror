import Foundation

struct H264AccessUnit: Equatable, Sendable {
    static let maximumPayloadBytes = 4 * 1_024 * 1_024
    static let headerBytes = 9
    static let maximumSampleBytes = maximumPayloadBytes - headerBytes

    private static let keyFrameFlag: UInt8 = 1 << 0
    private static let supportedFlags = keyFrameFlag

    let sampleData: Data
    let isKeyFrame: Bool
    let sps: Data?
    let pps: Data?

    init(sampleData: Data, isKeyFrame: Bool, sps: Data? = nil, pps: Data? = nil) throws {
        self.sampleData = sampleData
        self.isKeyFrame = isKeyFrame
        self.sps = sps
        self.pps = pps
        try validate()
    }

    init(payload: Data) throws {
        guard payload.count >= Self.headerBytes else { throw H264AccessUnitError.invalidPayload }

        let flags = payload.byte(at: 0)
        guard flags & ~Self.supportedFlags == 0 else { throw H264AccessUnitError.invalidPayload }

        let spsLength = Int(payload.uint16(at: 1))
        let ppsLength = Int(payload.uint16(at: 3))
        let sampleLength = Int(payload.uint32(at: 5))
        guard sampleLength > 0 else { throw H264AccessUnitError.invalidPayload }
        guard sampleLength <= Self.maximumSampleBytes else { throw H264AccessUnitError.invalidPayload }
        guard payload.count == Self.headerBytes + spsLength + ppsLength + sampleLength else {
            throw H264AccessUnitError.invalidPayload
        }

        var offset = Self.headerBytes
        let parsedSPS = spsLength > 0 ? payload.subdata(in: offset..<(offset + spsLength)) : nil
        offset += spsLength
        let parsedPPS = ppsLength > 0 ? payload.subdata(in: offset..<(offset + ppsLength)) : nil
        offset += ppsLength

        sampleData = payload.subdata(in: offset..<(offset + sampleLength))
        isKeyFrame = flags & Self.keyFrameFlag != 0
        sps = parsedSPS
        pps = parsedPPS
        try validate()
    }

    func encodedPayload() throws -> Data {
        try validate()
        let spsData = sps ?? Data()
        let ppsData = pps ?? Data()
        guard spsData.count <= Int(UInt16.max), ppsData.count <= Int(UInt16.max) else {
            throw H264AccessUnitError.parameterSetTooLarge
        }

        var payload = Data([isKeyFrame ? Self.keyFrameFlag : 0])
        payload.appendBigEndian(UInt16(spsData.count))
        payload.appendBigEndian(UInt16(ppsData.count))
        payload.appendBigEndian(UInt32(sampleData.count))
        payload.append(spsData)
        payload.append(ppsData)
        payload.append(sampleData)
        guard payload.count <= Self.maximumPayloadBytes else {
            throw H264AccessUnitError.payloadTooLarge
        }
        return payload
    }

    private func validate() throws {
        guard !sampleData.isEmpty, sampleData.count <= Self.maximumSampleBytes else {
            throw H264AccessUnitError.invalidSample
        }
        guard !isKeyFrame || (sps != nil && pps != nil) else {
            throw H264AccessUnitError.missingParameterSets
        }
        guard isKeyFrame || (sps == nil && pps == nil) else {
            throw H264AccessUnitError.unexpectedParameterSets
        }
        if let sps, sps.isEmpty { throw H264AccessUnitError.invalidParameterSets }
        if let pps, pps.isEmpty { throw H264AccessUnitError.invalidParameterSets }
        let total = Self.headerBytes + (sps?.count ?? 0) + (pps?.count ?? 0) + sampleData.count
        guard total <= Self.maximumPayloadBytes else { throw H264AccessUnitError.payloadTooLarge }
    }
}

enum H264AccessUnitError: LocalizedError {
    case invalidPayload
    case invalidSample
    case invalidParameterSets
    case missingParameterSets
    case unexpectedParameterSets
    case parameterSetTooLarge
    case payloadTooLarge

    var errorDescription: String? {
        "The other device sent invalid H.264 video data."
    }
}

private extension Data {
    func byte(at offset: Int) -> UInt8 {
        self[index(startIndex, offsetBy: offset)]
    }

    func uint16(at offset: Int) -> UInt16 {
        (UInt16(byte(at: offset)) << 8) | UInt16(byte(at: offset + 1))
    }

    func uint32(at offset: Int) -> UInt32 {
        (UInt32(byte(at: offset)) << 24) |
            (UInt32(byte(at: offset + 1)) << 16) |
            (UInt32(byte(at: offset + 2)) << 8) |
            UInt32(byte(at: offset + 3))
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
}
