# Monitor Mirror Roadmap

This document tracks planned work after the stable 1.0.0 release. Items are proposals until they are implemented, tested on physical devices, and assigned to a release.

## Planned for 1.1.0

### Low-latency H.264 video transport

**Status:** Planned
**Priority:** High

Replace the current approximately 10 FPS JPEG-frame transport with an Apple VideoToolbox H.264 pipeline while retaining perspective correction, QR pairing, explicit Network.framework peer-to-peer discovery, and mandatory TLS-PSK encryption.

#### Expected benefits

- Smoother 24–30 FPS monitor viewing
- Lower bandwidth, especially for mostly static monitor content
- Reduced CPU usage through Apple hardware encoding and decoding
- Improved battery and thermal behavior during longer sessions
- More consistent performance on congested local Wi-Fi
- Better visual stability than independently compressed JPEG frames

#### Proposed Apple frameworks

- `VTCompressionSession` on the iPhone
- `VTDecompressionSession` on the iPad
- `AVSampleBufferDisplayLayer` or an equivalent low-latency display path
- Existing `MCSession(encryptionPreference: .required)` transport

No third-party codec, server, account, or cloud dependency should be introduced.

#### Low-latency requirements

- Enable real-time encoding
- Disable frame reordering and B-frames
- Use periodic keyframes, initially every one second
- Add sequence numbers, packet chunking, and reassembly
- Detect packet loss and request or force a new keyframe
- Reset the decoder cleanly after reconnecting
- Compress before sending through the encrypted Multipeer session

#### Acceptance criteria

- Sustains at least 24 FPS on the supported physical iPhone/iPad test pair
- Median glass-to-glass latency does not regress relative to version 1.0.0
- Monitor text remains readable at the selected bitrate
- Recovers from packet loss within one keyframe interval
- Reconnects without restarting either app
- Demonstrates lower sustained bandwidth than JPEG transport
- Does not add frame recording, persistence, telemetry, or internet traffic
- Existing QR authentication and required Apple transport encryption remain intact
- JPEG transport remains available during development as a comparison and fallback until H.264 passes on-device tests

#### Suggested initial encoder profile

- Resolution: corrected output up to 960 pixels wide initially
- Frame rate: 30 FPS target, 24 FPS acceptable fallback
- Bitrate: begin testing around 2–5 Mbps
- Real-time mode: enabled
- Frame reordering: disabled
- Keyframe interval: approximately one second

Final bitrate and resolution should be selected from measured readability, latency, bandwidth, battery, and thermal results rather than fixed assumptions.
