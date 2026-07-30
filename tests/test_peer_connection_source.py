from pathlib import Path
import json
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
PEER = (ROOT / "MonitorMirror/PeerSession.swift").read_text()
SENDER = (ROOT / "MonitorMirror/SenderView.swift").read_text()
VIEWER = (ROOT / "MonitorMirror/ViewerView.swift").read_text()
INFO = (ROOT / "MonitorMirror/Info.plist").read_text()
PAIRING = (ROOT / "MonitorMirror/PairingPayload.swift").read_text()
APP = (ROOT / "MonitorMirror/MonitorMirrorApp.swift").read_text()
CONTENT = (ROOT / "MonitorMirror/ContentView.swift").read_text()
QR = (ROOT / "MonitorMirror/QRCodeView.swift").read_text()
CAMERA = (ROOT / "MonitorMirror/CameraProcessor.swift").read_text()


class NetworkPeerConnectionSourceTests(unittest.TestCase):
    def test_perspective_monitor_logo_is_used_in_app_and_home_screen(self):
        assets = ROOT / "MonitorMirror/Assets.xcassets"
        app_icon = assets / "AppIcon.appiconset/AppIcon-1024.png"
        logo_set = assets / "MonitorMirrorLogo.imageset"

        self.assertTrue(app_icon.is_file())
        self.assertEqual(self._png_metadata(app_icon), (1024, 1024, 2))
        app_contents = json.loads((app_icon.parent / "Contents.json").read_text())
        self.assertIn(
            {
                "filename": "AppIcon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            app_contents["images"],
        )

        expected_logos = {
            "MonitorMirrorLogo.png": (256, 256, 2),
            "MonitorMirrorLogo@2x.png": (512, 512, 2),
            "MonitorMirrorLogo@3x.png": (768, 768, 2),
        }
        for filename, metadata in expected_logos.items():
            self.assertEqual(self._png_metadata(logo_set / filename), metadata)

        logo_contents = json.loads((logo_set / "Contents.json").read_text())
        self.assertEqual({image["scale"] for image in logo_contents["images"]}, {"1x", "2x", "3x"})
        self.assertIn('Image("MonitorMirrorLogo")', CONTENT)
        self.assertNotIn('rectangle.inset.filled.and.person.filled', CONTENT)

        project = (ROOT / "MonitorMirror.xcodeproj/project.pbxproj").read_text()
        self.assertIn("Assets.xcassets in Resources", project)
        self.assertEqual(project.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"), 2)

    @staticmethod
    def _png_metadata(path):
        data = path.read_bytes()[:26]
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise AssertionError(f"Not a PNG: {path}")
        width, height = struct.unpack(">II", data[16:24])
        return width, height, data[25]

    def test_root_uses_backward_compatible_iphone_symbol(self):
        self.assertNotIn('systemImage: "iphone.gen3.camera"', CONTENT)
        self.assertIn('systemImage: "iphone"', CONTENT)

    def test_launch_diagnostics_cover_root_and_first_viewer_path_without_secrets(self):
        for marker in (
            'LaunchDiagnostics.mark("peer.init")',
            'LaunchDiagnostics.mark("app.init")',
            'LaunchDiagnostics.mark("root.init")',
            'LaunchDiagnostics.mark("root.appeared")',
            'LaunchDiagnostics.mark("viewer.init")',
            'LaunchDiagnostics.mark("viewer.appeared")',
            'LaunchDiagnostics.mark("viewer.session.begin")',
            'LaunchDiagnostics.mark("viewer.listener.begin")',
            'LaunchDiagnostics.mark("viewer.listener.created")',
            'LaunchDiagnostics.mark("viewer.listener.installed")',
            'LaunchDiagnostics.mark("viewer.qr.begin")',
            'LaunchDiagnostics.mark("viewer.qr.ready")',
        ):
            self.assertIn(marker, APP + CONTENT + PEER + VIEWER + QR)
        self.assertIn("MM_DIAG", APP)
        diagnostics = APP.split("enum LaunchDiagnostics", 1)[1]
        for forbidden in ("token", "serviceName", "pairingPayload", "receivedFrame"):
            self.assertNotIn(forbidden, diagnostics)

    def test_cold_app_launch_does_not_construct_camera_pipeline(self):
        self.assertNotIn("CameraProcessor()", APP)
        self.assertNotIn(".environmentObject(camera)", APP)
        self.assertIn("@StateObject private var camera = CameraProcessor()", SENDER)
        self.assertIn("private lazy var session = AVCaptureSession()", CAMERA)
        self.assertIn("private lazy var output = AVCaptureVideoDataOutput()", CAMERA)
        self.assertIn("private lazy var ciContext = CIContext", CAMERA)
        self.assertIn(
            "Privately share a perspective-corrected view of an angled monitor between two nearby Apple devices.",
            CONTENT,
        )

    def test_qr_generation_is_off_main_and_shows_immediate_placeholder(self):
        self.assertIn("@State private var image", QR)
        self.assertIn(".task(id: value)", QR)
        self.assertIn("Task.detached", QR)
        self.assertIn("private static let context = CIContext", QR)
        self.assertIn("Self.context.createCGImage", QR)
        self.assertIn("ProgressView", QR)
        self.assertNotIn("private let context = CIContext()", QR)
        self.assertNotIn("private let filter = CIFilter.qrCodeGenerator()", QR)
        body = QR.split("var body: some View", 1)[1].split("private", 1)[0]
        self.assertNotIn("makeImage()", body)

    def test_qr_payload_and_renderer_avoid_first_use_restart_and_gpu_contention(self):
        self.assertIn("encoder.outputFormatting = [.sortedKeys]", PAIRING)
        self.assertIn(".useSoftwareRenderer: true", QR)
        self.assertIn("struct RenderedQRCode: @unchecked Sendable", QR)
        self.assertIn("QRCodeRenderer.image(for:", QR)
        self.assertNotIn("QRCodeRenderer.pngData(for:", QR)
        self.assertNotIn("UIImage(data:", QR)
        self.assertNotIn(".pngData()", QR)

    def test_viewer_publishes_pairing_before_listener_initialization(self):
        start = PEER.split("func startViewerSession()", 1)[1].split("func regenerateViewerCode", 1)[0]
        self.assertIn("prepareViewerListener", start)
        self.assertLess(start.index("pairingPayload = payload"), start.index("prepareViewerListener"))
        self.assertNotIn("NWListener(", start)
        prepare = PEER.split("private func prepareViewerListener", 1)[1].split("private func installViewerListener", 1)[0]
        self.assertIn("networkQueue.async", prepare)
        self.assertIn("NWListener(", prepare)
        self.assertIn("installViewerListener", prepare)

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

    def test_graceful_end_session_packet_is_sent_and_stops_new_frames(self):
        self.assertIn("endSessionPacket: UInt8 = 2", PEER)
        self.assertIn("func endSession()", PEER)
        self.assertIn("endingSession", PEER)
        end = PEER.split("func endSession()", 1)[1].split("func stop()", 1)[0]
        self.assertIn("if sendInFlight", end)
        self.assertIn("sendEndSessionPacket()", end)
        self.assertNotIn("endSessionTimeoutTask = Task", end)
        self.assertIn("pendingFrame = nil", end)
        final_send = PEER.split("private func sendEndSessionPacket()", 1)[1].split("private func sendPendingFrameIfNeeded", 1)[0]
        self.assertIn("makePacket(type: Self.endSessionPacket", final_send)
        self.assertIn("contentContext: .finalMessage", final_send)
        self.assertIn("isComplete: true", final_send)
        self.assertIn("endSessionTimeoutTask = Task", final_send)
        self.assertIn("if error != nil", final_send)
        ended = PEER.split("private func handleConnectionEnded", 1)[1].split("private func beginConnectionTimeout", 1)[0]
        self.assertIn("if endingSession", ended)
        self.assertIn("finishSession()", ended)
        send = PEER.split("func sendCorrectedFrame", 1)[1].split("func endSession", 1)[0]
        self.assertIn("!endingSession", send)
        frame_completion = PEER.split("private func sendPendingFrameIfNeeded", 1)[1].split("private func receiveHeader", 1)[0]
        self.assertIn("if self.endingSession", frame_completion)
        self.assertIn("self.sendEndSessionPacket()", frame_completion)

    def test_header_eof_does_not_cancel_before_declared_payload_is_read(self):
        header = PEER.split("private func receiveHeader", 1)[1].split("private func receivePayload", 1)[0]
        self.assertIn("data, _, _, error", header)
        self.assertNotIn("if isComplete", header)
        self.assertIn("receivePayload(type: type, length: length", header)

    def test_receiver_processes_graceful_end_and_clears_session(self):
        receive = PEER.split("private func receivePayload", 1)[1].split("private func handleReceiveFailure", 1)[0]
        self.assertIn("type == Self.endSessionPacket", receive)
        self.assertIn("finishSession()", receive)
        finish = PEER.split("private func finishSession()", 1)[1].split("private func", 1)[0]
        self.assertIn("stop()", finish)
        self.assertIn("sessionEndSequence", finish)

    def test_both_views_dismiss_after_graceful_session_end(self):
        self.assertIn("@Environment(\\.dismiss)", SENDER)
        self.assertIn("@Environment(\\.dismiss)", VIEWER)
        self.assertIn(".onChange(of: peer.sessionEndSequence)", SENDER)
        self.assertIn(".onChange(of: peer.sessionEndSequence)", VIEWER)
        stop_button = SENDER.split('Button(camera.isSharing ? "Stop Sharing"', 1)[1].split(".buttonStyle", 1)[0]
        self.assertIn("endSharingSession()", stop_button)
        end_helper = SENDER.split("private func endSharingSession()", 1)[1].split("private func", 1)[0]
        self.assertIn("peer.endSession()", end_helper)
        self.assertIn("camera.stop()", end_helper)

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
            "sendInFlight = false",
            "endingSession = false",
            "endSessionPacketSent = false",
        ):
            self.assertIn(required, stop)


if __name__ == "__main__":
    unittest.main(verbosity=2)
