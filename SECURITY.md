# Security

## Supported version

Security fixes are provided for the latest published version of Mac Stats.

## Design

- No account, cloud synchronization, advertising, crash-reporting SDK, or personal tracking.
- System and process information is read-only and processed on the local Mac.
- Identifier-free usage statistics are limited to first use, one daily active event, and version changes. They can be disabled in Settings and never include monitoring, process, sensor, network, or wallpaper data.
- External processes are not launched with user-controlled command strings.
- Public builds are intended to use Apple Developer ID signing, the hardened runtime, and Apple notarization.
- Hardware sensor interfaces are optional. Failures degrade gracefully without disabling the rest of the monitor.

## Reporting a vulnerability

Do not publish an unpatched vulnerability. Report it privately to [security@macstats.cc](mailto:security@macstats.cc).

Include the affected Mac model, macOS version, Mac Stats version, reproduction steps, and any crash report with secrets removed.

For ordinary product questions, use [support@macstats.cc](mailto:support@macstats.cc).
