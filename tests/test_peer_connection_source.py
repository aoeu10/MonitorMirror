from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PEER = (ROOT / "MonitorMirror/PeerSession.swift").read_text()
SENDER = (ROOT / "MonitorMirror/SenderView.swift").read_text()
VIEWER = (ROOT / "MonitorMirror/ViewerView.swift").read_text()
INFO = (ROOT / "MonitorMirror/Info.plist").read_text()
PAIRING = (ROOT / "MonitorMirror/PairingPayload.swift").read_text()


class NetworkPeerConnectionSourceTests(unittest.TestCase):
    def test_uses_network_framework_not_multipeer(self):
        self.assertIn("import Network", PEER)
        self.assertNotIn("import MultipeerConnectivity", PEER)
        self.assertNotIn("MCSession", PEER)

    def test_listener_browser_and_connection_enable_peer_to_peer(self):
        self.assertGreaterEqual(PEER.count("includePeerToPeer = true"), 2)
        self.assertIn("NWListener", PEER)
        self.assertIn("NWBrowser", PEER)
        self.assertIn("NWConnection", PEER)

    def test_transport_requires_tls_psk_without_plaintext_fallback(self):
        self.assertIn("sec_protocol_options_add_pre_shared_key", PEER)
        self.assertIn("sec_protocol_options_set_min_tls_protocol_version", PEER)
        self.assertIn("sec_protocol_options_set_max_tls_protocol_version", PEER)
        self.assertIn(".TLSv12", PEER)
        self.assertIn("NWParameters(tls: tlsOptions, tcp: tcpOptions)", PEER)
        self.assertNotIn("NWParameters.tcp", PEER)

    def test_tls_psk_uses_explicit_cipher_and_nonsecret_identity(self):
        self.assertIn("sec_protocol_options_append_tls_ciphersuite", PEER)
        self.assertIn(
            "tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!",
            PEER,
        )
        self.assertIn("Data(serviceIdentity.utf8)", PEER)
        self.assertNotIn("Data(tokenHash.utf8)", PEER)

    def test_psk_is_derived_from_existing_qr_token(self):
        self.assertIn("SHA256.hash(data: Data(token.utf8))", PEER)
        self.assertIn("serviceIdentity: expectedViewerName", PEER)

    def test_sender_matches_exact_qr_service_name(self):
        self.assertIn("expectedViewerName", PEER)
        self.assertIn("name == self.expectedViewerName", PEER)

    def test_listener_rejects_expired_or_additional_clients(self):
        self.assertIn("private func accept", PEER)
        listener_accept = PEER.split("private func accept", 1)[1].split("private func", 1)[0]
        self.assertIn("pairingPayload?.isValid == true", listener_accept)
        self.assertIn("connection == nil", listener_accept)

    def test_frame_protocol_is_bounded_and_length_prefixed(self):
        self.assertIn("maximumFrameBytes", PEER)
        self.assertIn("UInt32", PEER)
        self.assertIn("bigEndian", PEER)
        self.assertIn("receiveHeader", PEER)
        self.assertIn("receivePayload", PEER)

    def test_sender_coalesces_frames_instead_of_building_backlog(self):
        self.assertIn("pendingFrame", PEER)
        self.assertIn("sendInFlight", PEER)
        self.assertIn("pendingFrame = jpegData", PEER)

    def test_camera_frame_handler_is_synchronized_across_queues(self):
        camera = (ROOT / "MonitorMirror/CameraProcessor.swift").read_text()
        self.assertIn("frameHandlerLock", camera)
        self.assertIn("NSLock", camera)
        self.assertIn("let handler = frameHandler", camera)
        self.assertIn("handler?(jpeg)", camera)

    def test_pending_camera_permission_cannot_restart_after_disconnect(self):
        camera = (ROOT / "MonitorMirror/CameraProcessor.swift").read_text()
        start = camera.split("func start()", 1)[1].split("func stop()", 1)[0]
        stop = camera.split("func stop()", 1)[1].split("func redetect()", 1)[0]
        configure = camera.split("private func configureAndStart()", 1)[1].split("private func configureSession", 1)[0]
        self.assertIn("setRunRequested(true)", start)
        self.assertIn("isRunRequested", start)
        self.assertIn("setRunRequested(false)", stop)
        self.assertIn("guard self.isRunRequested", configure)

    def test_sender_stops_camera_on_disconnect_and_retry(self):
        disconnect = SENDER.split(".onChange(of: peer.isConnected)", 1)[1].split(".onDisappear", 1)[0]
        retry = SENDER.split("private func resetPairing()", 1)[1].split("private func", 1)[0]
        for section in (disconnect, retry):
            self.assertIn("camera.setSharing(false)", section)
            self.assertIn("camera.stop()", section)

    def test_discovery_and_authentication_both_have_deadlines(self):
        join = PEER.split("func joinViewer", 1)[1].split("func sendCorrectedFrame", 1)[0]
        timeout = PEER.split("private func beginConnectionTimeout", 1)[1].split("private func", 1)[0]
        self.assertIn("beginConnectionTimeout()", join)
        self.assertIn("self.state == .searching || self.state == .connecting", timeout)

    def test_local_network_permission_has_specific_guidance(self):
        self.assertIn("Local Network permission", PEER)
        self.assertIn(".EPERM", PEER)

    def test_timeout_and_retry_guidance_remain(self):
        self.assertIn("30_000_000_000", PEER)
        self.assertIn("Wi-Fi may be disabled", PEER)
        self.assertIn("Try Pairing Again", SENDER)
        self.assertIn("wifi.exclamationmark", VIEWER)

    def test_bonjour_declaration_matches_network_service(self):
        self.assertIn("_monmirror._tcp", PEER)
        self.assertIn("_monmirror._tcp", INFO)

    def test_qr_protocol_version_rejects_incompatible_multipeer_builds(self):
        self.assertIn("static let currentVersion = 2", PAIRING)
        self.assertIn("case unsupportedVersion", PAIRING)
        self.assertIn("payload.version == currentVersion", PAIRING)
        self.assertIn("payload.expiresAt > Date()", PAIRING)

    def test_stop_cancels_all_network_objects_and_sensitive_state(self):
        stop = PEER.split("func stop()", 1)[1].split("private func", 1)[0]
        for required in (
            "listener?.cancel()",
            "browser?.cancel()",
            "connection?.cancel()",
            "pairingPayload = nil",
            "activeToken = nil",
            "receivedFrame = nil",
            "pendingFrame = nil",
        ):
            self.assertIn(required, stop)


if __name__ == "__main__":
    unittest.main(verbosity=2)
