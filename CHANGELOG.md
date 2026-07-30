# Release notes

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
