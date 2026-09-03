# Mac Stats Privacy Policy

Effective date: August 29, 2026

Mac Stats is designed to monitor the Mac on which it is running. It does not require an account and does not include advertising, tracking, or crash-reporting SDKs.

## Data processed on your Mac

To provide its features, Mac Stats reads system resource usage, hardware details, thermal and fan sensor values when available, battery status, network throughput, and process names or executable paths. These values are displayed locally and are not transmitted to the developer or any third party.

App preferences—such as refresh interval, appearance, memory accounting, launch-at-login, menu bar selections, and desktop appearance options—are stored locally using macOS preferences.

When the optional desktop appearance feature is enabled, Mac Stats reads the current wallpaper file, creates a locally processed copy with the selected menu bar and corner treatment, and asks macOS to use that copy. Original wallpaper locations and display options are retained locally so the wallpaper can be restored. Generated wallpaper files are stored in the user’s Application Support folder and are never uploaded.

## Optional anonymous usage statistics

Anonymous usage statistics are enabled by default and can be turned off at any time in Settings. Mac Stats may send only these aggregate events:

- first use;
- one daily active event;
- an app version change.

Each event contains the Mac Stats version and build, macOS major version, processor architecture, coarse language category (Chinese, English, or other), and direct-download release channel. It does not contain a name, email address, account, device or installation identifier, serial number, precise timestamp from the Mac, IP address, location, hardware model, process information, resource measurements, sensor readings, network throughput, or wallpaper data.

Events are sent directly to a publisher-controlled Cloudflare Worker and stored as aggregate counters in Cloudflare Analytics Engine. The Worker does not read or write request IP addresses, countries, cookies, browser identifiers, or fingerprints. As with any internet request, the infrastructure provider necessarily handles connection metadata while routing the request; Mac Stats does not place that metadata in the analytics dataset.

The public website may use Cloudflare Web Analytics to understand aggregate page views without cookies or cross-site tracking. Installer downloads may also be counted by the download host.

Mac Stats does not sell personal data or use usage statistics for advertising, profiling, or tracking across apps and websites.

## Retention

Live samples are held in memory only as needed to render the interface. Preferences and local delivery markers for anonymous statistics remain on the Mac until the user changes them or removes the app’s local preferences. Aggregate usage events are retained only for product adoption and version-support decisions, subject to the storage limits of the analytics service.

## Changes

If a future version changes its data practices, this policy and the release notes will be updated before that version is distributed.

Publisher: Zhang Yida. Privacy and product questions may be sent to support@macstats.cc. Security reports should be sent to security@macstats.cc.
