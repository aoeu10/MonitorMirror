# Release notes

## Current main — Adaptive orientation, responsive layouts, and rear-camera lenses

- Supports sender rotation before and during sharing, and derives H.264 output dimensions from the perspective-corrected monitor while preserving its natural aspect ratio
- Enlarges the QR scanner and calibration preview in landscape with responsive two-column layouts, and gives the connected iPad viewer a larger aspect-fit viewport
- Discovers only rear camera lenses physically available on the sender and offers Ultra Wide, Wide, and Telephoto selection where supported
- Safely switches capture inputs on the camera queue, stops sharing, clears stale calibration, and re-enables Auto-Detect because lens changes invalidate prior corner coordinates
- Uses Apple’s valid `.builtInUltraWideCamera` AVFoundation device type and retains the secure protocol-3 H.264 transport and manual-calibration protections

## 1.1.0 (Build 17) RC6 — In-app About information

- Adds a small About button to the main role-selection page
- Adds the app description, current version/build, concise changelog, and website link
- Discloses that Monitor Mirror includes no third-party libraries or external open-source packages and lists the Apple system frameworks used
- Leaves the physically verified RC5 H.264 media, transport, pairing, and teardown behavior unchanged

## 1.1.0 (Build 16) RC5 — Device-supported low-latency encoder configuration

- Removes `kVTCompressionPropertyKey_MaxFrameDelayCount = 1`, which the physical iPhone VideoToolbox encoder rejected
- Retains real-time mode, disabled frame reordering, expected frame rate, bitrate, and keyframe limits
- Retains the bounded transport invariant of one active complete access unit plus at most one dependency-valid pending unit
- Retains RC4 dropped-frame handling, keyframe recovery, and privacy-safe stage diagnostics

## 1.1.0 (Build 15) RC4 — Nonfatal encoder drops and keyframe recovery

- Treats VideoToolbox `.frameDropped` callbacks as nonfatal rather than surfacing a generic H.264 processing error
- Keeps forcing recovery keyframes until a keyframe is actually emitted, preventing a dropped first keyframe from leaving the viewer without SPS/PPS
- Synchronizes keyframe state between the capture queue and asynchronous compression callback
- Requests keyframe recovery after synchronous submission, callback, or access-unit construction failures
- Retains RC3's fixed, privacy-safe encoder-stage diagnostics

## 1.1.0 (Build 14) RC3 Diagnostic — H.264 encoder stage isolation

- Replaces the generic iPhone encoder failure message with fixed, stage-specific descriptions
- Distinguishes session creation, each VideoToolbox property, preparation, input-frame allocation, frame submission, output copying, format description, and SPS/PPS extraction
- Emits only fixed `MM_DIAG` lifecycle labels plus elapsed time; no status values, pairing material, media, or codec payloads are logged
- Does not change H.264 encoding, framing, transport, or pairing behavior

## 1.1.0 (Build 13) RC2 — Xcode decoder type fix

- Removes a redundant conditional downcast from `CMFormatDescription` to its `CMVideoFormatDescription` typealias that Xcode rejects
- Adds a regression preventing the invalid conditional cast from returning
- Preserves the H.264 protocol, transport behavior, approved branding, and immutable RC1/JPEG rollback artifacts

## 1.1.0 (Build 12) RC1 — VideoToolbox H.264 transport

- Preserves the complete JPEG implementation at branch `jpeg-1.0.x`, tag `v1.0.1-rc10`, and its immutable RC10 ZIP
- Replaces JPEG generation with lazy, real-time VideoToolbox H.264 encoding after perspective correction
- Renders corrected output to a fixed 960×540 canvas at approximately 15 FPS and 1.5 Mbps
- Disables frame reordering, bounds the VideoToolbox compression window to one delayed frame, and emits SPS/PPS with periodic keyframes for decoder startup and recovery
- Adds bounded, validated AVCC access-unit framing as packet type 3 while retaining packet type 2 for graceful session termination
- Keeps one active send and one pending access unit; on pressure, retains the valid pending unit and forces a recovery keyframe instead of dropping H.264 dependencies
- Adds VideoToolbox decoding on the iPad and destroys encoder/decoder state on disconnect, reset, or **Stop Sharing**
- Bumps QR protocol compatibility to version 3 so JPEG and H.264 builds fail explicitly rather than hanging
- Adds H.264 parser, codec, lifecycle, backpressure, and rollback regressions; full source regression count is now 35

Native Xcode compilation and physical iPhone/iPad H.264 testing are required before promotion.

## 1.0.1 (Build 11) RC10 — Receding monitor perspective

- Refines the approved logo so the monitor's top and lower edges share the same upper-right vanishing direction
- Uses the approved receding-perspective artwork above the **Monitor Mirror** title and for the iPhone/iPad Home Screen icon
- Regenerates the opaque 1024×1024 app icon and exact 1×, 2×, and 3× in-app derivatives from one master image
- Tightens the README by removing the obsolete two-QR web alternative, temporary RC-specific timing instructions, and outdated MVP wording
- Adds a README regression that keeps product documentation focused on the native app; full source regression count is now 30

## 1.0.1 (Build 10) RC9 — Perspective monitor identity

- Adds an original perspective-skewed monitor logo with four correction handles, reflected light, and a monitor stand
- Replaces the generic SF Symbol above the **Monitor Mirror** title with the branded artwork
- Adds an opaque 1024×1024 universal iOS app icon for the Home Screen
- Adds matching 1×, 2×, and 3× in-app image assets
- Wires the new asset catalog into the Xcode resources phase and selects `AppIcon` for Debug and Release
- Adds structural asset checks for PNG dimensions, opacity/color type, image scales, project membership, and SwiftUI usage; full source regression count is now 29

## 1.0.1 (Build 9) RC8 — First-use QR responsiveness

- Makes pairing JSON deterministic with sorted keys so SwiftUI's QR task ID remains stable across view reevaluations
- Uses Core Image's software renderer for the small QR image to avoid first-use GPU/Metal contention with SwiftUI
- Returns an immutable `CGImage` from the detached renderer and constructs `UIImage` directly on the main actor
- Removes the previous PNG encoding, transfer, and decoding round trip
- Retains temporary `MM_DIAG` timing for one physical confirmation run
- Adds a focused regression for stable payload encoding and the low-contention rendering path; full source regression count is now 28

RC7 physical timing showed Home Screen relaunches were instant. The remaining fresh-launch delay occurred only when starting through Xcode. Its first **View Monitor** trace showed listener construction completed in one millisecond, but QR rendering restarted and held up main-actor listener installation for several seconds.

## 1.0.1 (Build 8) RC7 — Launch timing diagnostics and SF Symbol correction

- Replaces the nonexistent `iphone.gen3.camera` SF Symbol with the backward-compatible `iphone` symbol
- Adds temporary `MM_DIAG` lifecycle timing for app/root construction and appearance
- Times first viewer construction, pairing payload creation, listener queueing/construction/installation, and QR rendering
- Uses fixed public event labels and elapsed time only; it never logs QR data, tokens, service identities, frames, or payloads
- Separates listener construction on the network queue from installation on the main actor to expose either delay
- Adds two focused symbol/diagnostic regressions; full source regression count is now 27

This is a diagnostic release candidate. Capture all `MM_DIAG` lines from a fresh launch and first **View Monitor** tap before removing the temporary instrumentation.

## 1.0.1 (Build 7) RC6 — Responsive cold launch and QR setup

- Removes global camera-pipeline construction from app launch; the iPhone sender now owns its camera processor
- Lazily initializes `AVCaptureSession`, video output, and camera Core Image resources only when camera work begins
- Publishes the iPad pairing payload before listener setup and constructs the TLS/Bonjour listener on the network queue
- Renders the QR code off the main actor with an immediate progress state instead of blocking the first viewer transition
- Reuses a lazily initialized QR Core Image context for fast subsequent code generation
- Updates the in-app description to: “Privately share a perspective-corrected view of an angled monitor between two nearby Apple devices.”
- Adds three focused cold-path regressions; full source regression count is now 25

Physical Xcode compilation and first-launch testing on an iPad disconnected from infrastructure Wi-Fi are required before promotion from release candidate to stable.

## 1.0.1 (Build 6) RC5 — Graceful Stop Sharing teardown

- Sends an authenticated and encrypted end-session control packet when the iPhone user taps **Stop Sharing**
- Sends the control packet as Network.framework's final message and prevents additional JPEG frames from being queued
- Drains any active JPEG send before queuing the stop command; the fallback begins only after that command enters the send pipeline
- Clears the iPad's last received frame and all pairing/session state
- Returns both the iPhone and iPad to Monitor Mirror's main role-selection screen
- Uses a one-second local fallback so the iPhone still exits cleanly if the peer disappears while stopping
- Adds four focused graceful-teardown regressions; full source regression count is now 22

Physical Xcode compilation and iPhone/iPad validation are required before promotion from release candidate to stable.

## 1.0.1 (Build 5) RC4 — Explicit Network.framework peer-to-peer transport

- Replaces Multipeer Connectivity with Apple Network.framework following Apple TN3213 migration guidance
- Explicitly enables Apple peer-to-peer Wi-Fi on listener, browser, and connection paths
- Uses Bonjour discovery with an exact random service identity carried in the QR code
- Uses mandatory TLS 1.2 PSK authentication with `TLS_PSK_WITH_AES_128_GCM_SHA256`; the PSK is derived from the 256-bit QR secret
- Uses the public random Bonjour service name—not the key or token hash—as the TLS PSK identity
- Does not broadcast the QR token or token hash in Bonjour metadata
- Adds a bounded length-prefixed JPEG protocol and latest-frame-wins send backpressure
- Rejects expired codes, incompatible QR protocol versions, oversized frames, and additional clients
- Preserves a 30-second deadline across both peer discovery and TLS authentication
- Distinguishes Local Network permission failures from general peer-route failures
- Preserves retry controls and actionable Wi-Fi/Bluetooth guidance
- Stops camera capture and sharing immediately after disconnect or pairing reset
- Synchronizes the frame callback shared by the main and camera queues
- Prevents a delayed camera-permission approval from restarting capture after disconnect
- Keeps frames, pairing tokens, and diagnostics out of persistent storage

Physical Xcode compilation and iPhone/iPad peer-to-peer validation are required before promotion from release candidate to stable.

## 1.0.1 (Build 4) RC3 — Peer-to-peer connection reliability

- Keeps Multipeer discovery active throughout the connected session so Apple’s peer-to-peer Wi-Fi route is not torn down after authentication
- Rejects additional invitations after the first authenticated invitation while discovery remains active
- Adds a 30-second connection timeout instead of leaving the app indefinitely at “Authenticating”
- Shows a prominent red warning that Wi-Fi may be disabled and directs the user to check Settings on both devices
- Explains that Wi-Fi and Bluetooth must be enabled even when neither device joins a Wi-Fi network
- Adds a usable retry path after connection failure
- Preserves QR authentication and required Apple session encryption

Physical validation required before promotion from release candidate to stable.

## 1.0.0 (Build 1) — Initial release

- Universal iPhone and iPad application
- QR-authenticated nearby-device pairing
- Required Apple Multipeer Connectivity encryption
- Automatic monitor rectangle detection
- Manual four-corner calibration
- Real-time perspective correction
- Local device-to-device corrected-frame streaming
- No accounts, cloud relay, analytics, recording, or frame persistence

This release has been confirmed by the user to compile and run on physical iPhone and iPad devices.
