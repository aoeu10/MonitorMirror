# Monitor Mirror Roadmap

This document tracks work that still requires physical-device validation.

## 1.1.0 H.264 transport

**Status:** RC4 corrects nonfatal dropped-frame handling and first-keyframe recovery; full Xcode and physical retesting pending
**Priority:** High

The H.264 branch replaces independent JPEG images with Apple VideoToolbox while retaining perspective correction, QR pairing, explicit Network.framework peer-to-peer routing, TLS-PSK authentication, bounded backpressure, and graceful **Stop Sharing**.

### Implemented in RC1–RC4

- `VTCompressionSession` on the iPhone
- `VTDecompressionSession` on the iPad
- Fixed 960×540 aspect-fit output with black letterboxing
- 15 FPS target and approximately 1.5 Mbps average bitrate
- Real-time Baseline H.264 with frame reordering disabled and at most one delayed encoder frame
- Keyframe at encoder start and at least every two seconds
- SPS/PPS carried with every keyframe
- AVCC access-unit boundaries inside the existing length-prefixed TLS stream
- One active send and one dependency-valid pending access unit
- Backpressure requests a fresh keyframe and rejects deltas until recovery instead of dropping arbitrary H.264 dependencies
- Decoder state recreated from keyframe configuration and destroyed on teardown
- QR protocol version 3 so JPEG/H.264 mixed builds fail explicitly
- No third-party codec, server, account, cloud, recording, or persistence

### Physical acceptance criteria

- Xcode compilation succeeds with the installed iOS SDK
- Shared infrastructure Wi-Fi and Wi-Fi-enabled-but-unjoined peer-to-peer both work
- Decoder displays the first keyframe without a stale frame from a prior session
- Reconnect starts with fresh decoder configuration and a keyframe
- **Stop Sharing** while media is in flight drains the active access unit, sends the authenticated final command, and dismisses both views
- Slow-route testing confirms memory remains bounded and latency does not grow indefinitely
- Monitor text remains readable at the selected bitrate
- Ten-to-thirty-minute runs assess heat, battery, memory, and latency drift
- Backgrounding, device lock, permission denial, process termination, and third-device rejection remain safe
- Packet capture reveals no readable parameter sets, access units, or monitor content outside TLS records

### Tuning after measurement

Resolution, frame rate, bitrate, and keyframe interval should change only from physical readability, latency, bandwidth, battery, and thermal measurements. The immutable JPEG fallback remains branch `jpeg-1.0.x`, tag `v1.0.1-rc10`, and its RC10 candidate ZIP until H.264 is promoted.
