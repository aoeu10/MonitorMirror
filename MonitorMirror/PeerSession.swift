import CryptoKit
import Dispatch
import Foundation
import Network
import Security
import SwiftUI
import UIKit

@MainActor
final class PeerSession: ObservableObject {
    enum Role {
        case idle
        case viewer
        case sender
    }

    enum ConnectionState: Equatable {
        case idle
        case advertising
        case searching
        case connecting
        case connected(String)
        case failed(String)

        var message: String {
            switch self {
            case .idle: return "Not connected"
            case .advertising: return "Waiting for the iPhone to scan this code"
            case .searching: return "Looking for the iPad"
            case .connecting: return "Authenticating the devices"
            case .connected(let name): return "Securely connected to \(name)"
            case .failed(let message): return message
            }
        }
    }

    private nonisolated static let bonjourType = "_monmirror._tcp"
    private nonisolated static let framePacket: UInt8 = 1
    private nonisolated static let endSessionPacket: UInt8 = 2
    private nonisolated static let headerBytes = 5
    private nonisolated static let maximumFrameBytes = 4 * 1_024 * 1_024
    private nonisolated static let peerToPeerFailureMessage =
        "Unable to establish a peer-to-peer connection. Wi-Fi may be disabled. Open Settings on both devices and make sure Wi-Fi and Bluetooth are enabled. Neither device needs to join a Wi-Fi network. Move the devices closer and try again."
    private nonisolated static let localNetworkPermissionMessage =
        "Local Network permission is unavailable. Open Settings → Apps → Monitor Mirror → Local Network, enable access, then try pairing again."

    @Published private(set) var role: Role = .idle
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var pairingPayload: PairingPayload?
    @Published private(set) var receivedFrame: UIImage?
    @Published private(set) var sessionEndSequence = 0

    private let networkQueue = DispatchQueue(label: "MonitorMirror.network", qos: .userInitiated)
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var activeToken: String?
    private var expectedViewerName: String?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var endSessionTimeoutTask: Task<Void, Never>?
    private var pendingFrame: Data?
    private var sendInFlight = false
    private var endingSession = false
    private var endSessionPacketSent = false

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    func startViewerSession() {
        stop()
        role = .viewer

        let serviceName = Self.makeServiceName()
        let payload = PairingPayload.make(viewerPeerName: serviceName)
        pairingPayload = payload
        activeToken = payload.token
        state = .advertising
        prepareViewerListener(payload, serviceName: serviceName)
    }

    func regenerateViewerCode() {
        guard role == .viewer else { return }
        startViewerSession()
    }

    func joinViewer(using encodedPayload: String) throws {
        let payload = try PairingPayload.decode(encodedPayload)
        stop()
        role = .sender
        activeToken = payload.token
        expectedViewerName = payload.viewerPeerName
        pairingPayload = payload

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        parameters.serviceClass = .interactiveVideo

        let browser = NWBrowser(
            for: .bonjour(type: Self.bonjourType, domain: nil),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self, weak browser] newState in
            Task { @MainActor [weak self, weak browser] in
                guard let self, self.browser === browser else { return }
                self.handleBrowserState(newState)
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            Task { @MainActor [weak self, weak browser] in
                guard let self, self.browser === browser else { return }
                self.handleBrowseResults(results)
            }
        }
        self.browser = browser
        state = .searching
        beginConnectionTimeout()
        browser.start(queue: networkQueue)
    }

    func sendCorrectedFrame(_ jpegData: Data) {
        guard role == .sender,
              isConnected,
              !endingSession,
              !jpegData.isEmpty,
              jpegData.count <= Self.maximumFrameBytes else {
            return
        }

        pendingFrame = jpegData
        sendPendingFrameIfNeeded()
    }

    func endSession() {
        guard !endingSession else { return }
        guard isConnected, connection != nil else {
            finishSession()
            return
        }

        endingSession = true
        pendingFrame = nil
        if sendInFlight { return }
        sendEndSessionPacket()
    }

    func stop() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        endSessionTimeoutTask?.cancel()
        endSessionTimeoutTask = nil

        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil

        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        pairingPayload = nil
        activeToken = nil
        expectedViewerName = nil
        receivedFrame = nil
        pendingFrame = nil
        sendInFlight = false
        endingSession = false
        endSessionPacketSent = false
        role = .idle
        state = .idle
    }

    private func prepareViewerListener(_ payload: PairingPayload, serviceName: String) {
        let token = payload.token
        networkQueue.async { [weak self] in
            do {
                let candidate = try NWListener(
                    using: Self.makeTransportParameters(
                        token: token,
                        serviceIdentity: serviceName
                    )
                )
                candidate.service = NWListener.Service(name: serviceName, type: Self.bonjourType)
                Task { @MainActor [weak self] in
                    self?.installViewerListener(
                        candidate,
                        token: token
                    )
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self,
                          self.role == .viewer,
                          self.pairingPayload?.token == token else {
                        return
                    }
                    self.state = .failed("Could not create the iPad listener: \(message)")
                }
            }
        }
    }

    private func installViewerListener(_ candidate: NWListener, token: String) {
        guard role == .viewer,
              pairingPayload?.token == token,
              listener == nil else {
            candidate.cancel()
            return
        }

        candidate.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.accept(connection)
            }
        }
        candidate.stateUpdateHandler = { [weak self, weak candidate] newState in
            Task { @MainActor [weak self, weak candidate] in
                guard let self, self.listener === candidate else { return }
                self.handleListenerState(newState)
            }
        }
        listener = candidate
        candidate.start(queue: networkQueue)
    }

    private func accept(_ candidate: NWConnection) {
        guard role == .viewer,
              state == .advertising,
              connection == nil,
              pairingPayload?.isValid == true else {
            candidate.cancel()
            return
        }

        connection = candidate
        state = .connecting
        beginConnectionTimeout()
        configure(candidate, displayName: "iPhone Camera")
        candidate.start(queue: networkQueue)
    }

    private func handleListenerState(_ newState: NWListener.State) {
        switch newState {
        case .ready:
            if state == .idle { state = .advertising }
        case .failed(let error):
            if Self.isLocalNetworkPermissionDenied(error) {
                state = .failed(Self.localNetworkPermissionMessage)
            } else {
                state = .failed("Could not advertise this iPad: \(error.localizedDescription)")
            }
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleBrowserState(_ newState: NWBrowser.State) {
        switch newState {
        case .waiting(let error):
            if Self.isLocalNetworkPermissionDenied(error) {
                state = .failed(Self.localNetworkPermissionMessage)
            }
        case .failed(let error):
            if Self.isLocalNetworkPermissionDenied(error) {
                state = .failed(Self.localNetworkPermissionMessage)
            } else {
                state = .failed("Could not search for the iPad: \(error.localizedDescription)")
            }
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard role == .sender,
              state == .searching,
              connection == nil,
              let payload = pairingPayload,
              payload.isValid,
              let expectedViewerName else {
            return
        }

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint,
                  name == self.expectedViewerName,
                  name == expectedViewerName else {
                continue
            }

            let connection = NWConnection(
                to: result.endpoint,
                using: Self.makeTransportParameters(
                    token: payload.token,
                    serviceIdentity: expectedViewerName
                )
            )
            self.connection = connection
            state = .connecting
            beginConnectionTimeout()
            configure(connection, displayName: expectedViewerName)
            connection.start(queue: networkQueue)
            return
        }
    }

    private func configure(_ candidate: NWConnection, displayName: String) {
        candidate.stateUpdateHandler = { [weak self, weak candidate] newState in
            Task { @MainActor [weak self, weak candidate] in
                guard let self,
                      let candidate,
                      self.connection === candidate else {
                    return
                }
                self.handleConnectionState(newState, connection: candidate, displayName: displayName)
            }
        }
    }

    private func handleConnectionState(
        _ newState: NWConnection.State,
        connection candidate: NWConnection,
        displayName: String
    ) {
        switch newState {
        case .ready:
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            state = .connected(displayName)
            if role == .viewer {
                receiveHeader(on: candidate)
            }
        case .waiting(let error):
            if Self.isLocalNetworkPermissionDenied(error) {
                state = .failed(Self.localNetworkPermissionMessage)
                candidate.cancel()
            } else if !isConnected {
                state = .connecting
            }
        case .failed(let error):
            handleConnectionEnded(candidate, error: error)
        case .cancelled:
            handleConnectionEnded(candidate, error: nil)
        default:
            break
        }
    }

    private func handleConnectionEnded(_ candidate: NWConnection, error: NWError?) {
        guard connection === candidate else { return }
        let wasConnected = isConnected
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        connection = nil
        pendingFrame = nil
        sendInFlight = false

        if endingSession {
            finishSession()
            return
        }

        if case .failed = state {
            return
        }

        if role == .viewer && !wasConnected {
            state = .advertising
            return
        }

        if wasConnected {
            state = .failed("The other device disconnected.")
        } else if let error {
            state = .failed("Secure peer-to-peer connection failed: \(error.localizedDescription). \(Self.peerToPeerFailureMessage)")
        } else if state != .idle {
            state = .failed(Self.peerToPeerFailureMessage)
        }
    }

    private func beginConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  self.state == .searching || self.state == .connecting else {
                return
            }

            self.state = .failed(Self.peerToPeerFailureMessage)
            self.connection?.cancel()
        }
    }

    private func sendEndSessionPacket() {
        guard endingSession,
              !endSessionPacketSent,
              !sendInFlight,
              let activeConnection = connection,
              isConnected else {
            return
        }

        endSessionPacketSent = true
        let packet = Self.makePacket(type: Self.endSessionPacket, payload: Data([0]))

        endSessionTimeoutTask?.cancel()
        endSessionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self, self.endingSession else { return }
            self.finishSession()
        }

        activeConnection.send(
            content: packet,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.endingSession else { return }
                    if error != nil {
                        self.finishSession()
                    }
                }
            }
        )
    }

    private func sendPendingFrameIfNeeded() {
        guard !sendInFlight,
              !endingSession,
              let frame = pendingFrame,
              let connection,
              isConnected else {
            return
        }

        pendingFrame = nil
        sendInFlight = true
        let packet = Self.makePacket(type: Self.framePacket, payload: frame)

        connection.send(content: packet, completion: .contentProcessed { [weak self, weak connection] error in
            Task { @MainActor [weak self, weak connection] in
                guard let self,
                      let connection,
                      self.connection === connection else {
                    return
                }

                self.sendInFlight = false
                if let error {
                    if self.endingSession {
                        self.finishSession()
                    } else {
                        self.state = .failed("Video transmission failed: \(error.localizedDescription)")
                        connection.cancel()
                    }
                    return
                }
                if self.endingSession {
                    self.sendEndSessionPacket()
                    return
                }
                self.sendPendingFrameIfNeeded()
            }
        })
    }

    private func receiveHeader(on candidate: NWConnection) {
        candidate.receive(
            minimumIncompleteLength: Self.headerBytes,
            maximumLength: Self.headerBytes
        ) { [weak self, weak candidate] data, _, _, error in
            guard let self, let candidate else { return }
            Task { @MainActor [weak self, weak candidate] in
                guard let self,
                      let candidate,
                      self.connection === candidate else {
                    return
                }

                if let error {
                    self.handleReceiveFailure(error, connection: candidate)
                    return
                }
                guard let data, data.count == Self.headerBytes else {
                    self.handleReceiveFailure(nil, connection: candidate)
                    return
                }

                let type = data[data.startIndex]
                var encodedLength: UInt32 = 0
                _ = withUnsafeMutableBytes(of: &encodedLength) { destination in
                    data.copyBytes(to: destination, from: 1..<Self.headerBytes)
                }
                let length = Int(UInt32(bigEndian: encodedLength))
                guard length > 0, length <= Self.maximumFrameBytes else {
                    self.state = .failed("The other device sent an invalid frame.")
                    candidate.cancel()
                    return
                }

                self.receivePayload(type: type, length: length, on: candidate)
            }
        }
    }

    private func receivePayload(type: UInt8, length: Int, on candidate: NWConnection) {
        candidate.receive(
            minimumIncompleteLength: length,
            maximumLength: length
        ) { [weak self, weak candidate] data, _, isComplete, error in
            guard let self, let candidate else { return }
            Task { @MainActor [weak self, weak candidate] in
                guard let self,
                      let candidate,
                      self.connection === candidate else {
                    return
                }

                if let error {
                    self.handleReceiveFailure(error, connection: candidate)
                    return
                }
                guard let data, data.count == length else {
                    self.handleReceiveFailure(nil, connection: candidate)
                    return
                }

                if type == Self.endSessionPacket {
                    guard data == Data([0]) else {
                        self.state = .failed("The other device sent an invalid session command.")
                        candidate.cancel()
                        return
                    }
                    self.finishSession()
                    return
                }

                guard type == Self.framePacket, let image = UIImage(data: data) else {
                    self.state = .failed("The other device sent an invalid frame.")
                    candidate.cancel()
                    return
                }
                self.receivedFrame = image

                if isComplete {
                    candidate.cancel()
                } else {
                    self.receiveHeader(on: candidate)
                }
            }
        }
    }

    private func finishSession() {
        guard role != .idle else { return }
        stop()
        sessionEndSequence &+= 1
    }

    private func handleReceiveFailure(_ error: NWError?, connection candidate: NWConnection) {
        guard connection === candidate else { return }
        if let error {
            state = .failed("Video reception failed: \(error.localizedDescription)")
        } else {
            state = .failed("The other device disconnected.")
        }
        candidate.cancel()
    }

    private nonisolated static func isLocalNetworkPermissionDenied(_ error: NWError) -> Bool {
        if case .posix(let code) = error {
            return code == .EPERM
        }
        return false
    }

    private nonisolated static func makePacket(type: UInt8, payload: Data) -> Data {
        var packet = Data([type])
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }

    private nonisolated static func makeTransportParameters(
        token: String,
        serviceIdentity: String
    ) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        let securityOptions = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(securityOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(
            securityOptions,
            tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!
        )

        let key = Data(SHA256.hash(data: Data(token.utf8)))
        // TLS 1.2 sends the PSK identity in cleartext. Use the random Bonjour
        // service name, which is public and independent of the secret key.
        let identity = Data(serviceIdentity.utf8)
        let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            securityOptions,
            keyData as dispatch_data_t,
            identityData as dispatch_data_t
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        parameters.serviceClass = .interactiveVideo
        return parameters
    }

    private nonisolated static func makeServiceName() -> String {
        "MonitorMirror-\(UUID().uuidString.prefix(8))"
    }
}
