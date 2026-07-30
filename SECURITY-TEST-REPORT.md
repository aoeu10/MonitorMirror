# Monitor Mirror 1.1.0 RC6 — H.264, Transport, and Lifecycle Review

**Scope:** Source-level and structural review on Linux
**Version:** 1.1.0 (Build 17) RC6
**Runtime status:** RC5 H.264 streaming is physically confirmed working; RC6 Xcode compilation and About-sheet UI confirmation remain pending.

## Executive summary

RC6 leaves the physically confirmed RC5 H.264 implementation, diagnostics, and QR-authenticated Network.framework TLS-PSK connection unchanged. It adds only an in-app About sheet containing product information, release notes, dependency disclosure, and the requested public website link. Media packets remain length-prefixed and bounded. Sender backpressure permits one active send plus one dependency-valid pending access unit. If that slot is full, it requests a fresh keyframe and rejects later deltas until recovery rather than breaking the H.264 reference chain. The encrypted graceful end command remains packet type 2 and cannot overtake active media.

Linux checks establish source intent and project structure only. They cannot prove VideoToolbox API linkage, hardware codec behavior, output callback timing, real-device readability, thermal behavior, or peer-to-peer performance.

## Source-level safeguards

| Safeguard | Source evidence | Status |
|---|---|---:|
| JPEG rollback | `jpeg-1.0.x`, `v1.0.1-rc10`, immutable RC10 ZIP and checksum | PASS |
| Mixed-build rejection | QR protocol version 3; versions 1 and 2 rejected | PASS |
| Short-lived 256-bit pairing | 32 bytes from `SecRandomCopyBytes`; 120-second expiry | PASS |
| Mandatory encrypted transport | TLS 1.2 PSK parameters only; no plaintext fallback | PASS |
| Explicit cipher | `TLS_PSK_WITH_AES_128_GCM_SHA256` | PASS |
| Public identity independence | Random Bonjour service name, not token/hash/PSK | PASS |
| Explicit peer-to-peer route | `includePeerToPeer = true` on listener, browser, and connection parameters | PASS |
| One authenticated viewer | Listener rejects expired or additional clients | PASS |
| H.264 encoder | Real-time `VTCompressionSession`, Baseline profile, no frame reordering, one-frame maximum compression delay | PASS |
| Fixed output | Aspect-fit corrected image rendered to 960×540 BGRA canvas | PASS |
| Bounded GOP | Forced initial keyframe; maximum two-second keyframe interval | PASS |
| Decoder configuration | SPS/PPS included with every keyframe | PASS |
| Access-unit framing | Flags + bounded SPS/PPS/sample lengths + AVCC sample bytes | PASS |
| Payload validation | Unknown flags, malformed lengths, empty samples, and invalid configuration placement rejected | PASS |
| Bounded media backlog | One active send plus one dependency-valid pending access unit | PASS |
| Dependency recovery | Queue pressure retains valid pending media, requests a keyframe, and rejects deltas until recovery | PASS |
| Decoder startup | Delta frame rejected until keyframe configuration exists | PASS |
| Decoder reset | Session recreated when SPS/PPS changes | PASS |
| Codec teardown | Compression/decompression sessions flushed or awaited, invalidated, and released | PASS |
| Graceful session end | Reject new media, drop pending media, drain active media, send packet 2 as `.finalMessage` | PASS |
| Camera lifecycle | Capture and encoder stop on disconnect, reset, navigation teardown, or Stop Sharing | PASS |
| Delayed permission race | Camera run intent rechecked before capture starts | PASS |
| Frame persistence | No Photos, Files, database, or media log path | PASS |
| Sensitive logging | Fixed lifecycle labels and elapsed time only | PASS |
| Source regressions | 35 tests | PASS |

## H.264 packet format

The existing outer TLS/TCP frame remains:

```text
packet type:  UInt8
payload size: UInt32 big-endian
payload:      exact declared bytes
```

Application packet types are:

```text
2 = authenticated graceful end-session command
3 = H.264 access unit
```

The packet-3 payload is:

```text
flags:         UInt8 (bit 0 = keyframe)
SPS length:    UInt16 big-endian
PPS length:    UInt16 big-endian
sample length: UInt32 big-endian
SPS bytes
PPS bytes
AVCC sample bytes
```

Keyframes require non-empty SPS and PPS. Delta frames prohibit parameter sets. The complete payload is bounded to four MiB. VideoToolbox frame reordering is disabled, so access units can be decoded in reliable-stream order without B-frame reordering state.

## Backpressure and Stop Sharing

The sender keeps no unbounded encoded queue. If no send is active, an access unit enters Network.framework immediately. While a send is active, one dependency-valid access unit may wait. If another delta arrives while that slot is occupied, the sender retains the older valid unit, asks the encoder for a new keyframe, and rejects subsequent deltas until that independent recovery point arrives. The keyframe may replace a pending delta because it carries fresh SPS/PPS and has no dependency on the skipped chain.

**Stop Sharing** sets the ending state, rejects new encoded access units, clears the pending access unit, waits for any active send's `.contentProcessed` completion, and only then queues packet type 2 with `.finalMessage` and `isComplete: true`. The established one-second fallback begins after that final command enters the send pipeline.

## Physical test matrix

1. Compile RC6 with Xcode and the installed iOS SDK.
2. Install build 17 on both physical devices; confirm the About sheet displays and dismisses correctly on iPhone and iPad.
3. Confirm first keyframe displays after Share and no stale frame survives from a previous session.
4. Test shared infrastructure Wi-Fi and Wi-Fi enabled but unjoined on both devices.
5. Run Stop Sharing while an H.264 access unit is active; confirm both views return to role selection.
6. Reconnect repeatedly and confirm each session starts from fresh SPS/PPS and a keyframe.
7. Introduce route congestion and confirm memory/latency remain bounded and keyframes are not displaced.
8. Test format/session reset behavior, background/foreground, device lock, process termination, permission denial, and third-device rejection.
9. Stream for 10–30 minutes while measuring readability, latency, bandwidth, memory, battery, and thermal behavior.
10. Capture traffic and confirm no QR material, parameter sets, access units, or monitor content is readable outside TLS records.

## Compliance boundary

Encryption, no intentional media persistence, and no cloud service are useful technical safeguards. They do not independently establish HIPAA compliance; device controls, risk analysis, organizational policies, incident response, and operational procedures remain required.

The JPEG RC10 candidate remains unchanged and directly restorable from `jpeg-1.0.x`, `v1.0.1-rc10`, or its immutable ZIP.
