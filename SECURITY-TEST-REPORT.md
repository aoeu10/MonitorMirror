# Monitor Mirror 1.0.1 RC10 — Branding, Network Transport, and Lifecycle Review

**Scope:** Source-level review on Linux

**Version:** 1.0.1 (Build 11) RC10
**Runtime status:** Xcode compilation, installed-device adversarial tests, and packet capture remain pending.

## Executive summary

The candidate replaces Multipeer Connectivity with Apple Network.framework’s older `NWListener` / `NWBrowser` / `NWConnection` API so iOS 17 remains supported while Apple peer-to-peer Wi-Fi is explicitly enabled. Transport parameters require TLS 1.2 with a pre-shared key derived from the short-lived 256-bit QR token. No plaintext fallback is present.

These source checks establish implementation intent and structural safeguards. They do not prove that the installed build negotiates the intended cipher suite or that Apple peer-to-peer Wi-Fi forms reliably on the target iPhone/iPad combination. Those claims require physical testing.

## Source-level safeguards

| Safeguard | Source evidence | Status |
|---|---|---:|
| 256-bit pairing secret | 32 bytes from `SecRandomCopyBytes` | PASS |
| Short-lived invitation | QR expires after 120 seconds | PASS |
| Incompatible build rejection | QR protocol version 2; old version 1 rejected | PASS |
| Explicit peer-to-peer route | `includePeerToPeer = true` on browser and TLS/TCP parameters used by listener and connection | PASS |
| Mandatory encrypted transport | `NWParameters(tls: tlsOptions, tcp: tcpOptions)` only; no plaintext TCP parameters | PASS |
| Mutual secret authentication | Explicit `TLS_PSK_WITH_AES_128_GCM_SHA256` suite and `sec_protocol_options_add_pre_shared_key` on listener and connection parameters | PASS |
| PSK identity independence | Public random Bonjour service name is used as identity; the PSK or token hash is not exposed as identity | PASS |
| 32-byte TLS PSK | SHA-256 of the high-entropy token text | PASS |
| Secret absent from discovery | Bonjour advertises only random service name and type | PASS |
| Exact viewer selection | Sender matches service name encoded in QR | PASS |
| QR expiration at listener | Incoming candidate accepted only while payload is valid | PASS |
| One client per viewer | Additional incoming candidates cancelled | PASS |
| Bounded input | Four-megabyte maximum payload and length validation | PASS |
| Bounded send backlog | One active send plus one replaceable pending frame | PASS |
| Camera callback synchronization | Lock-protected callback read/write across main and capture queues | PASS |
| Disconnect cleanup | Sender disables sharing and stops capture before retry | PASS |
| Permission/disconnect race | Lock-protected run intent is rechecked after permission and immediately before camera start | PASS |
| Cold-launch isolation | App startup does not construct camera capture or Core Image resources; sender resources are lazy | PASS |
| Viewer first-render isolation | Pairing state is published before off-main QR and TLS/Bonjour listener preparation | PASS |
| Stable low-contention QR rendering | Sorted-key payload encoding stabilizes the task ID; software Core Image rendering returns immutable `CGImage` without a PNG round trip | PASS |
| Graceful session end | Authenticated end-session packet uses final-message semantics, blocks new frames, clears state, and signals both views to dismiss | PASS |
| Frame persistence | Received frames remain in memory; no file/database write path | PASS |
| Discovery timeout | Thirty-second deadline starts when Bonjour browsing begins and resets for TLS authentication | PASS |
| Local Network guidance | Network.framework `EPERM` is mapped to Settings guidance | PASS |
| Teardown | Listener, browser, connection, token, pending frame, and displayed frame cleared | PASS |
| Sensitive logging | Temporary `MM_DIAG` output contains fixed lifecycle labels and elapsed seconds only; no token, service identity, frame, payload, or monitor content | PASS |

## TLS-PSK design

The QR token starts as 32 cryptographically random bytes and is URL-safe encoded. Both devices derive:

```text
PSK      = SHA-256(UTF8(QR token))
identity = UTF8(random Bonjour service name from the QR)
```

TLS 1.2 transmits the PSK identity before the encrypted channel exists. The identity is therefore deliberately public and cryptographically independent from the PSK; it cannot be transformed back into the token or key. The service name is already visible through Bonjour and is used only to select the corresponding PSK. The PSK itself is never advertised and exists only in memory.

TLS is constrained to version 1.2 because Apple documents that Network.framework TLS-PSK is available only through the older Network.framework API and does not support TLS 1.3. This is an intentional compatibility choice for iOS 17+, not a plaintext downgrade.

## Physical status and remaining tests

The user has physically confirmed same-infrastructure Wi-Fi connectivity, iPhone peer-to-peer connectivity while Wi-Fi is enabled but unjoined, and graceful **Stop Sharing** teardown on both devices in the preceding candidates.

1. Compile RC10 with the user’s installed Xcode/iOS SDK.
2. Install the same 1.0.1 build 11 RC10 on both devices.
3. Confirm the approved receding-monitor logo appears above the title and as the Home Screen icon on both iPhone and iPad.
4. Delete the prior app first, launch RC10 from Xcode once, filter the console for `MM_DIAG`, and retain every matching line.
5. Confirm a subsequent Home Screen launch remains immediate; fresh Xcode install/debug launch timing is tracked separately from normal app launch.
6. On the first RC10 run, tap **View Monitor** once and confirm there is only one `viewer.qr.begin`, `viewer.listener.installed` follows promptly, and `viewer.qr.ready` appears without a gesture timeout.
7. Confirm the nonexistent-symbol warning for `iphone.gen3.camera` no longer appears.
8. Reconfirm same-infrastructure and iPhone-unjoined peer-to-peer pairing, streaming, and **Stop Sharing** behavior.
9. Test both devices with Wi-Fi enabled and neither joined.
10. Attempt connection from a third device without the QR token.
11. Attempt expired and version-1 QR codes.
12. Capture traffic and confirm no JPEG signatures or readable monitor content appear outside TLS records.
13. Test disconnect/retry and foreground/background transitions.
14. Stream for at least ten minutes and monitor latency, heat, and memory.

## Compliance boundary

The transport, lack of intentional frame persistence, and absence of cloud services are useful technical safeguards. They do not independently establish HIPAA compliance; device controls, organizational policies, access management, incident response, risk analysis, and operational procedures remain required.

The historical 1.0.0 Multipeer source review is preserved at `docs/security/SECURITY-TEST-REPORT-1.0.0.md`.
