# Privacy Policy for Monitor Mirror

**Effective date:** September 18, 2026

Monitor Mirror is designed to share a perspective-corrected view of a monitor directly between a nearby iPhone and iPad. This policy explains the app's data practices.

## Summary

Monitor Mirror does not collect, transmit to us, store, sell, or share personal information. It has no account system, cloud backend, analytics, advertising, crash-reporting service, or third-party SDKs.

## Camera data

Monitor Mirror uses the rear camera only after you grant camera permission:

- to scan the pairing QR code displayed by your other device; and
- when sharing, to capture the monitor view you choose to stream.

Camera frames are processed in memory for perspective correction and H.264 encoding. They are sent only to the paired nearby device during the active session. The app does not save frames to Photos, Files, logs, a database, or any other persistent storage.

## Nearby network data

Monitor Mirror uses Apple's Network.framework, Bonjour, and peer-to-peer Wi-Fi to discover and connect your two devices. A pairing QR code supplies a short-lived, random secret that authenticates and encrypts the direct connection. The app does not use an internet server or cloud relay.

Bonjour advertising uses a short-lived random service name. The pairing secret is not advertised, stored after the session, or sent to us.

## Information we collect

We do not collect personal information, device identifiers, usage information, location data, diagnostics, or the contents of camera frames. We do not track you across apps or websites.

## Sharing and sale

Because Monitor Mirror does not collect your information, it does not sell or disclose personal information to third parties. The only media transfer is the encrypted, direct transfer between the two devices you pair.

## Permissions

- **Camera:** Required to scan pairing codes and capture the monitor view you elect to share.
- **Local Network:** Required to discover and connect to your paired nearby device.

You can change these permissions at any time in iOS or iPadOS Settings.

## Data retention

Monitor Mirror retains no account, camera, session, or analytics data. Ending a sharing session tears down the connection and clears the final displayed image.

## Children's privacy

Monitor Mirror does not knowingly collect personal information from anyone, including children.

## Changes to this policy

If this policy changes, the updated version and its effective date will be published in this repository.

## Contact

For privacy questions, please open an issue in the [Monitor Mirror repository](https://github.com/aoeu10/MonitorMirror/issues).
