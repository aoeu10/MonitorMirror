# Monitor Mirror Security Test Report

**Test time:** 2026-07-30 01:29:08 UTC

**Project reviewed:** `/home/dradis/MonitorMirror`

**Scope:** Source-level automated security checks plus prepared physical-device adversarial tests

## Executive result

- Automated source-security checks: **14 passed, 0 failed**
- Normal two-device operation: **PASS, user-confirmed** (Scott reported “Monitor Mirror works great”)
- Physical adversarial tests: **Pending device access**
- Packet-level confidentiality capture: **Pending Mac/iPhone access**

A source audit confirms that the application requests mandatory Apple Multipeer Connectivity encryption and does not contain a cloud client, persistence layer, telemetry, or frame logging. It does not independently prove the runtime traffic cipher or resistance to an active network attacker; those require physical-device execution and packet capture.

## Automated checks

| Test | Result | Evidence |
|---|---:|---|
| Transport encryption mandatory | PASS | `MCSession(... encryptionPreference: .required)`; no optional/none setting present |
| 256-bit secure pairing secret | PASS | 32 bytes generated with `SecRandomCopyBytes` |
| Pairing expiration and version validation | PASS | Payload requires current version and `expiresAt > Date()`; default lifetime 120 seconds |
| Secret not broadcast in discovery | PASS | Discovery publishes SHA-256 token hash only |
| Sender binds discovery to QR peer | PASS | Expected peer name and token hash must both match |
| Incorrect/expired invitation rejected | PASS (source path) | Exact token and valid payload required; otherwise `invitationHandler(false, nil)` |
| Frames require connected session | PASS | Sender checks `session.connectedPeers` before sending |
| Disconnect clears state | PASS | Session disconnect plus token, payload, and received-frame clearing |
| No cloud/general network client | PASS | No URLSession, Network.framework connection, WebSocket, endpoint, Firebase, or Analytics reference |
| No frame/token persistence | PASS | No filesystem, UserDefaults, Core Data, SwiftData, or Photos write API |
| No sensitive application logging | PASS | No `print`, `Logger`, or `os_log` calls |
| Required permissions declared | PASS | Camera, Local Network, and `_monmirror._tcp` Bonjour declarations present |
| Privacy manifest | PASS | Tracking false; collected-data list empty |
| Embedded-secret scan | PASS | No private-key PEM or common API credential patterns found |

## Prepared physical-device QR tests

The folder `security-test-assets/` contains:

1. `01-malformed-payload.png`
   - Expected: iPhone displays “This is not a valid Monitor Mirror pairing code.”
   - Expected: no Multipeer invitation and no connection.

2. `02-expired-payload.png`
   - Expected: iPhone displays “This pairing code has expired. Create a new session on the iPad.”
   - Expected: no Multipeer invitation and no connection.

3. `03-unsupported-version.png`
   - Expected: rejected as expired/invalid by the current validation path.
   - Expected: no Multipeer invitation and no connection.

These are test-only payloads containing random non-production tokens.

## Remaining device tests

### A. Altered-token test

Requires a screenshot of a currently displayed iPad QR. Decode it, preserve the iPad peer name and expiration, replace the token, and generate an altered QR.

Expected result: the sender finds no advertiser whose SHA-256 discovery hash matches; no connection occurs.

### B. Third-device rejection

Requires a third iPhone/iPad with the app installed.

1. Display a valid QR on the intended iPad.
2. Pair the intended iPhone.
3. Attempt to join from the third device without the QR or with an altered token.

Expected result: third device cannot connect; advertiser stops after the first valid connection.

### C. Disconnect cleanup

1. Start sharing video.
2. Force-quit Monitor Mirror on the iPhone.
3. Observe the iPad.
4. Reopen the iPhone app and attempt to reuse the old QR.

Expected result: iPad reports disconnection; old session stops; a new pairing code is required.

### D. Network confidentiality capture

Use a Mac connected to the iPhone over USB and Apple’s Remote Virtual Interface where available:

1. Obtain the iPhone UDID from Xcode Devices and Simulators.
2. Start an RVI interface with `rvictl -s <UDID>`.
3. Capture with `tcpdump -i rvi0 -s 0 -w monitormirror.pcap` while streaming.
4. Stop capture and inspect in Wireshark.
5. Confirm that no JPEG headers, readable image payloads, pairing JSON, or display content appear in plaintext.
6. Confirm session traffic is opaque and that no internet destination receives media.

Multipeer may select Apple Wireless Direct Link, infrastructure Wi-Fi, or another nearby route. If RVI does not expose the media path, capture the relevant macOS/AWDL or Wi-Fi interface instead.

## Security observation

The app requires encrypted `MCSession` transport, but its certificate callback currently accepts the framework-presented certificate:

```swift
certificateHandler(true)
```

This is compatible with Apple-managed Multipeer encryption, while QR possession and token comparison control invitation acceptance. It is not certificate pinning. For a higher-assurance clinical threat model, add a QR-bound application-level ephemeral public key and authenticated key confirmation, or pin a verifiable application identity.

## Compliance boundary

The tests support claims of local-only design, mandatory Apple transport encryption, short-lived QR pairing, no intentional storage, and no third-party telemetry. They do not independently certify HIPAA compliance. Organizational access control, device management, risk analysis, incident response, and policy controls remain required.
