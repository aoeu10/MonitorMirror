# H.264 Video Transport Implementation Plan

> **For Hermes:** Execute task-by-task with TDD and independent pre-commit review.

**Goal:** Replace JPEG frame transport with low-latency VideoToolbox H.264 while preserving the complete JPEG 1.0.x implementation for immediate rollback.

**Architecture:** Keep camera capture, Vision detection, perspective correction, TLS-PSK pairing, Network.framework peer-to-peer routing, and graceful Stop Sharing unchanged. Render each corrected `CIImage` into a fixed 960×540 BGRA pixel buffer, encode real-time H.264 with VideoToolbox, send bounded AVCC access-unit packets over the existing authenticated TCP stream, and decode with VideoToolbox on the iPad. Each keyframe carries SPS/PPS so the receiver can initialize or recover without separate unordered configuration state.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, Core Image, Core Media, Core Video, VideoToolbox, Network.framework, TLS 1.2 PSK.

**Rollback:** `jpeg-1.0.x`, tag `v1.0.1-rc10`, commit `d81b065d6499ded6e69d5c34442d2468c2104301`, archive `releases/candidates/MonitorMirror-1.0.1-build-11-rc10-Xcode.zip`, SHA-256 `90b05c4188a9d45ceee0785ac7dfa2a42bd592786eab48985ac13cd26595ba9a`.

---

### Task 1: Preserve JPEG and isolate H.264 development

**Files:** Git refs only.

1. Create `jpeg-1.0.x` at `v1.0.1-rc10`.
2. Create and switch to `h264-1.1.0`.
3. Verify the JPEG branch, tag, ZIP, and stable ZIP checksums.

### Task 2: Define protocol-3 H.264 access units

**Files:**
- Create: `MonitorMirror/H264AccessUnit.swift`
- Modify: `MonitorMirror/PairingPayload.swift`
- Modify: `MonitorMirror.xcodeproj/project.pbxproj`
- Test: `tests/test_peer_connection_source.py`

1. Add a failing regression requiring protocol version 3, no JPEG encoder/decoder, and H.264 packet/config validation.
2. Define an immutable access unit containing AVCC sample bytes, keyframe flag, and optional SPS/PPS.
3. Encode a fixed payload header: flags (1), SPS length (2), PPS length (2), sample length (4), followed by SPS, PPS, and AVCC sample bytes.
4. Require SPS/PPS on keyframes; reject malformed lengths, empty/oversized samples, unknown flags, and configuration on delta frames.
5. Bump QR compatibility to protocol 3 so 1.0.x and 1.1.x fail explicitly.

### Task 3: Add a real-time VideoToolbox encoder

**Files:**
- Create: `MonitorMirror/H264Encoder.swift`
- Modify: `MonitorMirror/CameraProcessor.swift`
- Modify: `MonitorMirror/SenderView.swift`
- Modify: `MonitorMirror.xcodeproj/project.pbxproj`
- Test: `tests/test_peer_connection_source.py`

1. Add a failing regression requiring VideoToolbox compression, real-time mode, no frame reordering, baseline H.264, bounded keyframe interval, explicit bitrate/FPS, and invalidation.
2. Create one 960×540 `VTCompressionSession` only when sharing begins.
3. Render aspect-fit corrected images over black into encoder pixel buffers.
4. Encode at 15 FPS with approximately 1.5 Mbps average bitrate and a two-second keyframe interval.
5. Extract AVCC bytes and SPS/PPS from keyframes in the compression callback.
6. Flush/invalidate on Stop Sharing, disconnect, retry, and teardown.

### Task 4: Preserve bounded transport and graceful stop

**Files:**
- Modify: `MonitorMirror/PeerSession.swift`
- Test: `tests/test_peer_connection_source.py`

1. Add a failing regression requiring H.264 packet type 3 and removal of JPEG packet type 1 behavior.
- Keep one in-flight send plus one dependency-valid pending access unit; on pressure, retain the valid pending unit, request a keyframe, and reject deltas until it arrives.
3. Never replace a pending keyframe/configuration with a delta frame.
4. Continue rejecting new frames during graceful end, clear pending video, drain the active send, then queue packet type 2 as `.finalMessage`.
5. Keep the 4 MiB packet bound and existing TLS/peer-to-peer behavior.

### Task 5: Add VideoToolbox decoding

**Files:**
- Create: `MonitorMirror/H264Decoder.swift`
- Modify: `MonitorMirror/PeerSession.swift`
- Modify: `MonitorMirror.xcodeproj/project.pbxproj`
- Test: `tests/test_peer_connection_source.py`

1. Add a failing regression requiring SPS/PPS format creation, AVCC sample buffers, asynchronous real-time decode, and teardown.
2. Build/rebuild `CMVideoFormatDescription` and `VTDecompressionSession` on keyframes carrying SPS/PPS.
3. Reject delta frames until valid configuration/keyframe state exists.
4. Convert decoded pixel buffers to `UIImage` without persistence and publish on the main actor.
5. Wait for asynchronous decode completion and invalidate on reset/disconnect/Stop Sharing.

### Task 6: Version, document, review, and package

**Files:**
- Modify: `MonitorMirror.xcodeproj/project.pbxproj`
- Modify: `VERSION`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `ROADMAP.md`
- Modify: `SECURITY-TEST-REPORT.md`

1. Set `1.1.0 (12) RC1` and document H.264 plus JPEG rollback instructions.
2. Run all source regressions, Swift grammar parsing, PBX/plist/catalog checks, and static security scans.
3. Obtain independent review of VideoToolbox API correctness, callback lifetime, parser bounds, queue semantics, and graceful teardown.
4. Commit/tag only after review passes.
5. Create a new immutable `1.1.0` candidate ZIP from its tag, extract it, rerun checks, and report SHA-256.
6. State clearly that native Xcode compilation and physical encoder/decoder/AWDL testing remain required.
