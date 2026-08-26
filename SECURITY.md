# Security

## Supported version

Security fixes are provided for the latest published version of Mac Stats.

## Design

- No account, cloud synchronization, analytics, advertising, or automatic data upload.
- System and process information is read-only and processed on the local Mac.
- External processes are not launched with user-controlled command strings.
- Public builds are intended to use Apple Developer ID signing, the hardened runtime, and Apple notarization.
- Hardware sensor interfaces are optional. Failures degrade gracefully without disabling the rest of the monitor.

## Reporting a vulnerability

Do not publish an unpatched vulnerability. A private security-reporting contact will be added to this document and the product website before public download is enabled.

Include the affected Mac model, macOS version, Mac Stats version, reproduction steps, and any crash report with secrets removed.
