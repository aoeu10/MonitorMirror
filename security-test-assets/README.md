# Security QR fixtures

- `malformed-monitor-mirror-qr.png`: not a base64url JSON pairing payload; expect **invalid code**.
- `expired-monitor-mirror-qr.png`: Network.framework payload version 2 with a 2000-01-01 expiration; expect **expired code**.
- `unsupported-version-monitor-mirror-qr.png`: legacy Multipeer payload version 1 with a future expiration; expect **incompatible versions**.

The token is deterministic public test data and is not used by any release session. Generate a fresh viewer QR for normal testing.
