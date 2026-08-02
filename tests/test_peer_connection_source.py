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
README = (ROOT / "README.md").read_text()
H264_ACCESS_UNIT_PATH = ROOT / "MonitorMirror/H264AccessUnit.swift"
H264_ACCESS_UNIT = H264_ACCESS_UNIT_PATH.read_text() if H264_ACCESS_UNIT_PATH.exists() else ""
H264_ENCODER_PATH = ROOT / "MonitorMirror/H264Encoder.swift"
H264_ENCODER = H264_ENCODER_PATH.read_text() if H264_ENCODER_PATH.exists() else ""
H264_DECODER_PATH = ROOT / "MonitorMirror/H264Decoder.swift"
H264_DECODER = H264_DECODER_PATH.read_text() if H264_DECODER_PATH.exists() else ""


class NetworkPeerConnectionSourceTests(unittest.TestCase):
    def test_protocol_three_defines_bounded_self_contained_h264_access_units(self):
        self.assertIn("static let currentVersion = 3", PAIRING)
        self.assertIn("struct H264AccessUnit", H264_ACCESS_UNIT)
        self.assertIn("static let maximumSampleBytes", H264_ACCESS_UNIT)
        self.assertIn("func encodedPayload() throws -> Data", H264_ACCESS_UNIT)
        self.assertIn("init(payload: Data) throws", H264_ACCESS_UNIT)
        self.assertIn("guard flags & ~Self.supportedFlags == 0", H264_ACCESS_UNIT)
        self.assertIn("guard sampleLength > 0", H264_ACCESS_UNIT)
        self.assertIn("guard sampleLength <= Self.maximumSampleBytes", H264_ACCESS_UNIT)
        self.assertIn("guard payload.count == Self.headerBytes + spsLength + ppsLength + sampleLength", H264_ACCESS_UNIT)
        self.assertIn("guard !isKeyFrame || (sps != nil && pps != nil)", H264_ACCESS_UNIT)
        self.assertIn("guard isKeyFrame || (sps == nil && pps == nil)", H264_ACCESS_UNIT)

    def test_h264_encoder_uses_realtime_videotoolbox_with_recovery_keyframes(self):
        self.assertIn("import VideoToolbox", H264_ENCODER)
        self.assertIn("VTCompressionSessionCreate", H264_ENCODER)
        self.assertIn("static let maximumDimension = 960", H264_ENCODER)
        self.assertIn("width: Int32(width)", H264_ENCODER)
        self.assertIn("height: Int32(height)", H264_ENCODER)
        self.assertIn("kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary", H264_ENCODER)
        self.assertIn("kVTCompressionPropertyKey_RealTime", H264_ENCODER)
        self.assertIn("kVTCompressionPropertyKey_ProfileLevel", H264_ENCODER)
        self.assertIn("kVTProfileLevel_H264_Baseline_AutoLevel", H264_ENCODER)
        self.assertIn("kVTCompressionPropertyKey_AllowFrameReordering", H264_ENCODER)
        self.assertIn("kVTCompressionPropertyKey_ExpectedFrameRate", H264_ENCODER)
        self.assertIn("kVTCompressionPropertyKey_AverageBitRate", H264_ENCODER)
        self.assertIn("kVTCompressionPropertyKey_MaxKeyFrameInterval", H264_ENCODER)
        self.assertIn("kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration", H264_ENCODER)
        self.assertNotIn("kVTCompressionPropertyKey_MaxFrameDelayCount", H264_ENCODER)

    def test_h264_encoder_failures_report_privacy_safe_fixed_stages(self):
        self.assertIn("enum H264EncoderSetting", H264_ENCODER)
        self.assertIn("case encoderConfigurationFailed(H264EncoderSetting, OSStatus)", H264_ENCODER)
        self.assertIn("var diagnosticEvent: String", H264_ENCODER)
        self.assertNotIn('"h264.encoder.config.max-frame-delay.failed"', H264_ENCODER)
        self.assertIn("LaunchDiagnostics.mark(codecError.diagnosticEvent)", CAMERA)
        self.assertIn("reportH264Error(error)", CAMERA)
        self.assertNotIn("LaunchDiagnostics.mark(\"\\(error", CAMERA)
        self.assertIn("VTCompressionSessionGetPixelBufferPool", H264_ENCODER)
        self.assertIn("kVTEncodeFrameOptionKey_ForceKeyFrame", H264_ENCODER)
        self.assertIn("VTCompressionSessionEncodeFrame", H264_ENCODER)

    def test_h264_encoder_treats_dropped_frames_as_nonfatal_and_preserves_keyframe_recovery(self):
        self.assertIn("infoFlags.contains(.frameDropped)", H264_ENCODER)
        self.assertIn("encoder.markKeyFrameNeeded()", H264_ENCODER)
        self.assertIn("if accessUnit.isKeyFrame", H264_ENCODER)
        self.assertIn("encoder.markKeyFrameDelivered()", H264_ENCODER)
        self.assertIn("private let keyFrameLock = NSLock()", H264_ENCODER)
        self.assertNotIn(
            "guard status == noErr else { throw H264CodecError.encodeFailed(status) }\n        needsKeyFrame = false",
            H264_ENCODER,
        )
        self.assertIn("CMVideoFormatDescriptionGetH264ParameterSetAtIndex", H264_ENCODER)
        self.assertIn("CMBlockBufferCopyDataBytes", H264_ENCODER)
        self.assertIn("VTCompressionSessionCompleteFrames", H264_ENCODER)
        self.assertIn("VTCompressionSessionInvalidate", H264_ENCODER)

    def test_camera_lazily_encodes_corrected_images_as_h264_and_stops_codec(self):
        self.assertIn("private var h264Encoder: H264Encoder?", CAMERA)
        self.assertIn("private var storedFrameHandler: ((H264AccessUnit) -> Void)?", CAMERA)
        self.assertIn("var frameHandler: ((H264AccessUnit) -> Void)?", CAMERA)
        self.assertIn("private func ensureEncoder(for image: CIImage) throws", CAMERA)
        self.assertIn("let encoder = try H264Encoder(", CAMERA)
        self.assertIn("try h264Encoder?.encode(corrected)", CAMERA)
        self.assertIn("private func stopEncoder()", CAMERA)
        self.assertIn("h264Encoder?.invalidate()", CAMERA)
        self.assertNotIn("makeJPEG", CAMERA)
        self.assertNotIn("jpegData", CAMERA)
        self.assertIn("activePeer?.sendEncodedFrame(accessUnit)", SENDER)
        self.assertNotIn("sendCorrectedFrame", SENDER)

    def test_sender_orientation_and_encoder_canvas_follow_the_corrected_frame(self):
        phone_orientations = INFO.split(
            "<key>UISupportedInterfaceOrientations</key>", 1
        )[1].split("<key>UISupportedInterfaceOrientations~ipad</key>", 1)[0]
        self.assertIn("UIInterfaceOrientationLandscapeLeft", phone_orientations)
        self.assertIn("UIInterfaceOrientationLandscapeRight", phone_orientations)

        self.assertIn("UIDevice.orientationDidChangeNotification", CAMERA)
        self.assertIn("private var captureOrientation: CGImagePropertyOrientation = .right", CAMERA)
        self.assertIn("private func updateCaptureOrientation", CAMERA)
        orientation_update = CAMERA.split("private func updateCaptureOrientation", 1)[1].split(
            "private func configureAndStart", 1
        )[0]
        self.assertIn("case .portrait:\n            orientation = .right", orientation_update)
        self.assertIn("case .portraitUpsideDown:\n            orientation = .left", orientation_update)
        self.assertIn("case .landscapeLeft:\n            orientation = .up", orientation_update)
        self.assertIn("case .landscapeRight:\n            orientation = .down", orientation_update)
        self.assertIn(".oriented(captureOrientation)", CAMERA)
        self.assertNotIn("CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)", CAMERA)

        self.assertIn("static func dimensions(for extent: CGRect)", H264_ENCODER)
        self.assertIn("width: Int,\n        height: Int,", H264_ENCODER)
        self.assertNotIn("static let width = 960", H264_ENCODER)
        self.assertNotIn("static let height = 540", H264_ENCODER)
        self.assertIn("private var encoderDimensions: CGSize?", CAMERA)
        self.assertIn("private func ensureEncoder(for image: CIImage) throws", CAMERA)
        self.assertIn("if encoderDimensions != dimensions", CAMERA)
        self.assertIn("try ensureEncoder(for: corrected)", CAMERA)

        self.assertIn("if decompressionSession == nil || sps != currentSPS || pps != currentPPS", H264_DECODER)
        self.assertIn(".scaledToFit()", VIEWER)
        self.assertIn(".frame(maxWidth: .infinity, maxHeight: .infinity)", VIEWER)

    def test_sender_uses_two_column_landscape_layouts_for_pairing_and_calibration(self):
        self.assertIn("GeometryReader { geometry in", SENDER)
        self.assertIn("geometry.size.width > geometry.size.height", SENDER)
        self.assertIn("private func landscapePairingView", SENDER)
        self.assertIn("private func landscapeCalibrationView", SENDER)
        self.assertIn("HStack(spacing: 16)", SENDER)
        self.assertIn("HStack(spacing: 12)", SENDER)
        self.assertIn("ScrollView", SENDER)
        self.assertNotIn(".frame(maxWidth: 520, maxHeight: 520)", SENDER)

    def test_connected_viewer_overlays_status_instead_of_reserving_a_separate_row(self):
        self.assertIn("private var connectedViewer", VIEWER)
        self.assertIn(".overlay(alignment: .bottom)", VIEWER)
        self.assertIn(".padding(6)", VIEWER)
        self.assertNotIn("VStack(spacing: 18) {\n            if peer.isConnected", VIEWER)

    def test_sender_offers_only_available_rear_lenses_and_resets_calibration_when_switching(self):
        self.assertIn("enum CameraLens: String, CaseIterable, Identifiable, Hashable", CAMERA)
        self.assertIn("@Published private(set) var availableLenses", CAMERA)
        self.assertIn("@Published private(set) var selectedLens", CAMERA)
        self.assertIn(".builtInUltraWideAngleCamera", CAMERA)
        self.assertIn(".builtInWideAngleCamera", CAMERA)
        self.assertIn(".builtInTelephotoCamera", CAMERA)
        self.assertIn("AVCaptureDevice.DiscoverySession", CAMERA)
        self.assertIn("func selectLens(_ lens: CameraLens)", CAMERA)
        switch_lens = CAMERA.split("func selectLens(_ lens: CameraLens)", 1)[1].split(
            "func requestKeyFrame", 1
        )[0]
        self.assertIn("self.sharing = false", switch_lens)
        self.assertIn("self.stopEncoder()", switch_lens)
        self.assertIn("self.locked = false", switch_lens)
        self.assertIn("self.autoDetectionEnabled = true", switch_lens)
        self.assertIn("self.activeCorners = nil", switch_lens)
        self.assertIn("session.beginConfiguration()", CAMERA)
        self.assertIn("session.removeInput", CAMERA)
        self.assertIn("session.canAddInput", CAMERA)
        self.assertIn("let restoredPreviousInput", switch_lens)
        self.assertIn("self.session.removeOutput(self.output)", switch_lens)
        self.assertIn("self.configured = false", switch_lens)
        self.assertIn("case lensRollbackFailed", CAMERA)
        self.assertIn('Picker("Camera Lens"', SENDER)
        self.assertIn("camera.selectLens", SENDER)

    def test_manual_corner_adjustment_pauses_auto_detection_until_auto_detect_is_tapped(self):
        self.assertIn("private var autoDetectionEnabled = true", CAMERA)

        update_corner = CAMERA.split("func updateCorner", 1)[1].split("private var isRunRequested", 1)[0]
        self.assertIn("self.autoDetectionEnabled = false", update_corner)

        redetect = CAMERA.split("func redetect", 1)[1].split("func setCalibrationLocked", 1)[0]
        self.assertIn("self.autoDetectionEnabled = true", redetect)
        self.assertIn("self.activeCorners = nil", redetect)

        self.assertIn("if autoDetectionEnabled && !locked && frameNumber % 12 == 0", CAMERA)
        self.assertIn('Label("Auto-Detect", systemImage: "viewfinder")', SENDER)
        self.assertNotIn('Button("Re-detect", systemImage: "viewfinder")', SENDER)
        auto_detect_label = SENDER.split('Label("Auto-Detect", systemImage: "viewfinder")', 1)[1].split(
            ".buttonStyle(.bordered)", 1
        )[0]
        self.assertIn(".lineLimit(1)", auto_detect_label)
        self.assertIn(".frame(maxWidth: .infinity)", auto_detect_label)

    def test_h264_decoder_requires_configuration_and_tears_down_async_work(self):
        self.assertIn("import VideoToolbox", H264_DECODER)
        self.assertIn("CMVideoFormatDescriptionCreateFromH264ParameterSets", H264_DECODER)
        self.assertIn("var pointers: [UnsafePointer<UInt8>]", H264_DECODER)
        self.assertNotIn("as? CMVideoFormatDescription", H264_DECODER)
        self.assertIn("VTDecompressionSessionCreate", H264_DECODER)
        self.assertIn("CMBlockBufferCreateWithMemoryBlock", H264_DECODER)
        self.assertIn("CMBlockBufferReplaceDataBytes", H264_DECODER)
        self.assertIn("CMSampleBufferCreateReady", H264_DECODER)
        self.assertIn("VTDecompressionSessionDecodeFrame", H264_DECODER)
        self.assertIn("._EnableAsynchronousDecompression", H264_DECODER)
        self.assertIn("._1xRealTimePlayback", H264_DECODER)
        self.assertIn("CIImage(cvPixelBuffer: imageBuffer)", H264_DECODER)
        self.assertIn("VTDecompressionSessionWaitForAsynchronousFrames", H264_DECODER)
        self.assertIn("VTDecompressionSessionInvalidate", H264_DECODER)
        self.assertIn("guard accessUnit.isKeyFrame || decompressionSession != nil", H264_DECODER)

    def test_readme_stays_focused_on_the_native_product(self):
        self.assertIn("## Features", README)
        self.assertIn("## Current transport", README)
        self.assertNotIn("MVP", README)
        self.assertNotIn("Two-QR web alternative", README)
        self.assertNotIn("static web application", README)
        self.assertNotIn("PWA", README)
        self.assertNotIn("MM_DIAG", README)
        self.assertNotIn("Build 10 RC9", README)

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

    def test_main_page_offers_about_details_changelog_dependencies_and_website(self):
        self.assertIn("@State private var isShowingAbout = false", CONTENT)
        self.assertIn('Label("About", systemImage: "info.circle")', CONTENT)
        self.assertIn(".sheet(isPresented: $isShowingAbout)", CONTENT)
        self.assertIn("private struct AboutView: View", CONTENT)
        self.assertIn("@Environment(\\.dismiss) private var dismiss", CONTENT)
        self.assertNotIn("@Environment(\\\\.dismiss)", CONTENT)
        self.assertIn('(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.1.0"', CONTENT)
        self.assertIn('(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""', CONTENT)
        self.assertIn("Privately share a perspective-corrected view", CONTENT)
        self.assertIn('Text("Changelog")', CONTENT)
        self.assertIn('Text("Libraries")', CONTENT)
        self.assertIn("No third-party libraries or external open-source packages", CONTENT)
        self.assertIn('URL(string: "https://monitor-mirror.com")!', CONTENT)

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

    def test_sender_recovers_with_keyframe_instead_of_dropping_h264_dependencies(self):
        self.assertIn("pendingAccessUnit", PEER)
        self.assertIn("sendInFlight", PEER)
        self.assertIn("private var waitingForKeyFrame = false", PEER)
        self.assertIn("var keyFrameRequestHandler: (() -> Void)?", PEER)
        self.assertIn("accessUnit.isKeyFrame || !waitingForKeyFrame else", PEER)
        self.assertIn("if pendingAccessUnit != nil, !accessUnit.isKeyFrame", PEER)
        self.assertIn("waitingForKeyFrame = true", PEER)
        self.assertIn("keyFrameRequestHandler?()", PEER)
        self.assertIn("if accessUnit.isKeyFrame", PEER)
        self.assertIn("waitingForKeyFrame = false", PEER)
        self.assertIn("func requestKeyFrame()", CAMERA)
        self.assertIn("h264Encoder?.requestKeyFrame()", CAMERA)
        self.assertIn("activePeer.keyFrameRequestHandler", SENDER)

    def test_transport_sends_packet_three_h264_and_decodes_without_jpeg(self):
        self.assertIn("h264FramePacket: UInt8 = 3", PEER)
        self.assertIn("func sendEncodedFrame(_ accessUnit: H264AccessUnit)", PEER)
        self.assertIn("try accessUnit.encodedPayload()", PEER)
        self.assertIn("makePacket(type: Self.h264FramePacket", PEER)
        self.assertIn("let accessUnit = try H264AccessUnit(payload: data)", PEER)
        self.assertIn("try decoder.decode(accessUnit)", PEER)
        self.assertIn("decoder?.invalidate()", PEER)
        self.assertNotIn("framePacket: UInt8 = 1", PEER)
        self.assertNotIn("UIImage(data: data)", PEER)

    def test_camera_frame_handler_is_synchronized_across_queues(self):
        camera = (ROOT / "MonitorMirror/CameraProcessor.swift").read_text()
        self.assertIn("frameHandlerLock", camera)
        self.assertIn("NSLock", camera)
        self.assertIn("let handler = self.frameHandler", camera)
        self.assertIn("handler?(accessUnit)", camera)

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
        join = PEER.split("func joinViewer", 1)[1].split("func sendEncodedFrame", 1)[0]
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

    def test_qr_protocol_version_rejects_incompatible_media_builds(self):
        self.assertIn("static let currentVersion = 3", PAIRING)
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
        self.assertIn("pendingAccessUnit = nil", end)
        final_send = PEER.split("private func sendEndSessionPacket()", 1)[1].split("private func sendPendingAccessUnitIfNeeded", 1)[0]
        self.assertIn("makePacket(type: Self.endSessionPacket", final_send)
        self.assertIn("contentContext: .finalMessage", final_send)
        self.assertIn("isComplete: true", final_send)
        self.assertIn("endSessionTimeoutTask = Task", final_send)
        self.assertIn("if error != nil", final_send)
        ended = PEER.split("private func handleConnectionEnded", 1)[1].split("private func beginConnectionTimeout", 1)[0]
        self.assertIn("if endingSession", ended)
        self.assertIn("finishSession()", ended)
        send = PEER.split("func sendEncodedFrame", 1)[1].split("func endSession", 1)[0]
        self.assertIn("!endingSession", send)
        frame_completion = PEER.split("private func sendPendingAccessUnitIfNeeded", 1)[1].split("private func receiveHeader", 1)[0]
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
        share_label = SENDER.index('Label(camera.isSharing ? "Stop Sharing" : "Share"')
        share_button = SENDER[SENDER.rfind("Button {", 0, share_label):share_label]
        self.assertIn("endSharingSession()", share_button)
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
            "pendingAccessUnit = nil",
            "decoder?.invalidate()",
            "sendInFlight = false",
            "endingSession = false",
            "endSessionPacketSent = false",
        ):
            self.assertIn(required, stop)


if __name__ == "__main__":
    unittest.main(verbosity=2)
