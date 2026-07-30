import CryptoKit
import Foundation
import Security

struct PairingPayload: Codable, Equatable {
    // Version 3 selects H.264 media over the Network.framework TLS-PSK
    // transport. Versions 1 (Multipeer) and 2 (JPEG) are incompatible.
    static let currentVersion = 3

    let version: Int
    let token: String
    let viewerPeerName: String
    let expiresAt: Date

    var tokenHash: String {
        SHA256.hash(data: Data(token.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var isValid: Bool {
        version == Self.currentVersion && expiresAt > Date()
    }

    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self).base64URLEncodedString()
    }

    static func decode(_ value: String) throws -> PairingPayload {
        guard let data = Data(base64URLEncoded: value) else {
            throw PairingError.invalidCode
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payload: PairingPayload
        do {
            payload = try decoder.decode(PairingPayload.self, from: data)
        } catch {
            throw PairingError.invalidCode
        }
        guard payload.version == currentVersion else {
            throw PairingError.unsupportedVersion
        }
        guard payload.expiresAt > Date() else {
            throw PairingError.expiredCode
        }
        return payload
    }

    static func make(viewerPeerName: String, lifetime: TimeInterval = 120) -> PairingPayload {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Secure random generation failed")
        return PairingPayload(
            version: currentVersion,
            token: Data(bytes).base64URLEncodedString(),
            viewerPeerName: viewerPeerName,
            expiresAt: Date().addingTimeInterval(lifetime)
        )
    }
}

enum PairingError: LocalizedError {
    case invalidCode
    case unsupportedVersion
    case expiredCode

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "This is not a valid Monitor Mirror pairing code."
        case .unsupportedVersion:
            return "These devices have incompatible Monitor Mirror versions. Update Monitor Mirror on both devices and create a new pairing code."
        case .expiredCode:
            return "This pairing code has expired. Create a new session on the iPad."
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
