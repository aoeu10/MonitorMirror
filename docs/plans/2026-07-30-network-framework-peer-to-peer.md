# Network.framework Peer-to-Peer Migration Plan

> **For Hermes:** Execute task-by-task with tests before production changes.

**Goal:** Replace unreliable implicit Multipeer Connectivity transport with explicit Apple peer-to-peer Network.framework transport while preserving QR-only pairing, encrypted local communication, and the existing SwiftUI API.

**Architecture:** The iPad is a Bonjour-advertised `NWListener`; the iPhone is an `NWBrowser` and `NWConnection` client. Listener, browser, and connection parameters opt into Apple peer-to-peer Wi-Fi. TLS 1.2 PSK uses a key derived from the existing 256-bit short-lived QR token, so unknown nearby devices fail during TLS authentication.

**Tech stack:** Swift, Network.framework, Security TLS-PSK, CryptoKit SHA-256, Bonjour, UIKit.

---

## Task 1: Define transport security/lifecycle invariants

- Replace Multipeer-specific source assertions in `tests/test_peer_connection_source.py`.
- Assert explicit `includePeerToPeer`, TLS-PSK, TLS 1.2, exact service matching, expiration rejection, single-client listener policy, bounded framing, and no plaintext fallback.
- Run tests and verify they fail against the Multipeer implementation.

## Task 2: Replace PeerSession transport

- Modify `MonitorMirror/PeerSession.swift` without changing its public role/state/pairing/frame API.
- Viewer: create TLS-PSK `NWListener`, advertise `_monmirror._tcp`, and reject expired or duplicate clients.
- Sender: browse with peer-to-peer enabled, match the exact QR service name, and create TLS-PSK `NWConnection`.
- Apply the existing 30-second timeout and actionable Wi-Fi warning.
- Cancel listener, browser, connection, sends, and received frame state during teardown.

## Task 3: Add bounded frame protocol

- Prefix each message with one byte type and four-byte big-endian payload length.
- Reject zero-length or oversized payloads.
- Decode received JPEGs only in memory.
- Keep at most one pending JPEG while a send is active, replacing it with the newest frame.

## Task 4: Preserve security and metadata

- Keep 32-byte QR token generation and two-minute expiration.
- Use SHA-256 of the token text as the 32-byte TLS PSK; use the public random Bonjour service name as the independent TLS PSK identity.
- Do not advertise the token or token hash in Bonjour metadata.
- Keep Local Network and `_monmirror._tcp` declarations.
- Update README, changelog, and version to 1.0.1 build 5 RC4.

## Task 5: Verify and package

- Run all source regression tests.
- Parse every Swift source with tree-sitter.
- Parse Xcode project and metadata.
- Confirm no Multipeer symbols or plaintext Network parameters remain.
- Build an RC archive while retaining stable 1.0.0 unchanged.
- Final compile and direct peer-to-peer behavior require Xcode and physical devices.
