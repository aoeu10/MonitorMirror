# Monitor Mirror

Monitor Mirror is a universal iPhone/iPad app that captures a computer monitor from an angled iPhone rear camera, detects and rectifies the monitor quadrilateral, and sends the corrected view directly to a nearby iPad.

The project uses only Apple frameworks. It has no package-manager dependencies, accounts, cloud backend, analytics, recording, or persistent media storage.

## MVP capabilities

- One universal app target for iPhone and iPad
- One-scan QR pairing
- Two-minute, single-session QR invitations with 256-bit random secrets
- Peer discovery through Bonjour using Apple Network.framework
- Explicit Apple peer-to-peer Wi-Fi opt-in on listener, browser, and connection
- TLS 1.2 PSK encryption and mutual authentication using the QR’s 256-bit secret
- Exact QR-named Bonjour service matching without broadcasting the secret or its hash
- Rear-camera capture on iPhone
- Automatic monitor detection using Vision rectangle detection
- Manual adjustment of all four monitor corners
- Perspective correction using Core Image
- Corrected JPEG frames sent directly to the iPad at approximately 10 FPS
- No frame persistence on either device

## Requirements

- macOS with Xcode 16 or newer
- iOS/iPadOS 17 or newer
- Apple developer signing team (free personal signing works for local testing)
- One physical iPhone and one physical iPad
- Wi-Fi and Bluetooth enabled on both devices

Camera and nearby Network.framework transport are not meaningfully testable in the simulator. Use physical devices.

## Build in Xcode

1. Copy the entire `MonitorMirror` folder to your Mac.
2. Open `MonitorMirror.xcodeproj`.
3. Select the **MonitorMirror** project in the navigator.
4. Select the **MonitorMirror** app target.
5. Open **Signing & Capabilities**.
6. Enable **Automatically manage signing**.
7. Select your Apple Developer team.
8. Change the bundle identifier from `com.example.MonitorMirror` to a unique value, for example:

   ```text
   com.yourname.MonitorMirror
   ```

9. Connect the iPhone by cable or enable wireless development.
10. Select the iPhone as the run destination and press **Run**.
11. Trust the developer certificate on the iPhone if prompted.
12. Repeat with the iPad using the same Xcode project and signing team.

The same build runs on both devices.

## First-run permissions

Allow these prompts on both devices:

- **Camera:** required for QR scanning; also required for monitor capture on iPhone.
- **Local Network:** required for private device discovery and connection.

If a permission was denied, restore it under **Settings → Apps → Monitor Mirror**.

## Use

### On the iPad

1. Launch Monitor Mirror.
2. Choose **View Monitor**.
3. Keep the QR code visible.

### On the iPhone

1. Launch Monitor Mirror.
2. Choose **Share Monitor**.
3. Scan the QR code displayed by the iPad.
4. Wait for **Securely connected**.
5. Mount the iPhone near the monitor edge with the rear camera aimed at the monitor.
6. Wait for the yellow quadrilateral to detect the monitor.
7. Drag any incorrect corner marker into place.
8. Tap **Lock Corners**.
9. Tap **Share**.

The iPad displays only the perspective-corrected monitor rectangle.

## Architecture

```text
iPad Viewer
  ├─ Creates 256-bit random pairing token
  ├─ Starts a Bonjour NWListener with peer-to-peer enabled
  ├─ Uses the QR token as the TLS pre-shared key
  └─ Accepts only one connection while the QR is unexpired

                         TLS 1.2 PSK over TCP
                         (explicit peer-to-peer opt-in)
                                   ▲
                                   │ bounded corrected JPEG messages
                                   │
iPhone Camera                     │
  ├─ Scans QR                     │
  ├─ Browses for exact service ───┘
  ├─ Authenticates with QR-derived TLS key
  ├─ Captures rear camera
  ├─ Detects monitor with Vision
  ├─ Accepts manual corner edits
  └─ Applies Core Image perspective correction
```

## Security design

- Pairing secrets contain 256 bits from `SecRandomCopyBytes`.
- QR invitations expire after two minutes.
- The scanner accepts only Monitor Mirror payload version 2; version 1 identifies the incompatible Multipeer transport.
- The QR token is transformed into a 32-byte SHA-256 TLS pre-shared key; TLS authenticates both endpoints before application data can flow.
- Bonjour advertises only a random, short-lived service name; it does not publish the token or token hash.
- The sender connects only to the exact service name encoded in the QR.
- Listener, browser, and connection explicitly opt into Apple peer-to-peer Wi-Fi through Network.framework.
- TLS uses the explicit `TLS_PSK_WITH_AES_128_GCM_SHA256` suite. Its public PSK identity is the random Bonjour service name, which is independent of the secret key. There is no plaintext transport fallback.
- Frames are held in memory and are not written to Photos, Files, logs, or a database.
- There are no external SDKs, network APIs, telemetry systems, or crash-reporting services.

This design provides strong technical safeguards, but software architecture alone does not establish organizational HIPAA compliance. Deployment still requires device access controls, risk analysis, incident procedures, workforce policies, and appropriate administrative safeguards.

## Current MVP tradeoffs

The compile-ready MVP transmits corrected JPEG frames at roughly 10 FPS. This keeps the implementation small and inspectable while validating pairing, capture, correction, and transport. A low-latency Apple VideoToolbox H.264 transport is planned for version 1.1.0 to improve frame rate, bandwidth, battery use, and thermal behavior without changing the pairing or security architecture. See [`ROADMAP.md`](ROADMAP.md) for scope and acceptance criteria.

Network.framework uses infrastructure Wi-Fi when available and explicitly opts into Apple peer-to-peer Wi-Fi for nearby operation. Bluetooth may assist nearby discovery, but it does not carry the video. No internet service or external server is required. For peer-to-peer operation without a shared Wi-Fi network, Wi-Fi and Bluetooth must remain enabled on both devices.

## Two-QR web alternative

A static web application can be hosted on any trusted HTTPS host without hosting signaling or video. The iPad can encode a WebRTC offer into one QR, and the iPhone can encode its answer into a second QR. The devices then communicate directly.

That design still depends on the HTTPS host to load the application, unless it is installed and cached as a PWA. WebRTC SDP and ICE data can also exceed comfortable single-QR capacity, Safari may suspend capture, and reconnection requires repeating the exchange. Those limitations are why the native app is the primary implementation.

## Troubleshooting

### The devices do not find each other

- Confirm Local Network permission on both devices. If the app reports that permission is unavailable, open **Settings → Apps → Monitor Mirror → Local Network**, enable it, and pair again.
- Keep both app screens open.
- Turn on Wi-Fi and Bluetooth on both devices. Peer-to-peer mode does not require joining a Wi-Fi network, but the Wi-Fi radios must remain enabled.
- If Wi-Fi was disabled in Settings, enable it there before pairing again.
- Move the devices close together.
- Generate a new QR code; codes expire after two minutes.

### The monitor is not detected

- Make the full monitor border visible.
- Reduce glare.
- Increase contrast between the monitor and background.
- Use **Re-detect**, then manually position the corner markers.

### Video becomes delayed

The JPEG transport permits only one active send and keeps at most one pending image, replacing that pending image with the newest frame. This bounds application-level backlog on the reliable TLS/TCP stream. Reduce distance or Wi-Fi congestion if video becomes delayed. A future VideoToolbox transport will further reduce bandwidth.
