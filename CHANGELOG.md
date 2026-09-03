# Changelog

## 1.0.0 (Build 31) — 2026-08-29

- Enabled basic, identifier-free usage statistics by default while preserving any explicit opt-out.
- Refined the privacy setting copy to clearly separate aggregate version usage from local system data.
- Kept analytics delivery asynchronous, silent on failure, and isolated from all monitoring features.

## 1.0.0 (Build 30) — 2026-08-29

- Added optional, off-by-default anonymous aggregate usage statistics without device or installation identifiers.
- Added first-use, once-daily active, and version-change events with coarse app and system fields only.
- Added a publisher-controlled Cloudflare Worker receiver and Analytics Engine query examples.
- Added configurable website analytics and download links plus a public-facing privacy page.
- Updated the privacy manifest and policy to describe the exact data boundaries.

## 1.0.0 (Build 29) — 2026-08-29

- Added support for static system wallpapers represented by .madesktop descriptors.
- Resolves static desktop packages to their downloaded full-resolution MobileAsset HEIC.
- Distinguishes static packages from Dynamic Desktop and Solar packages before processing.
- Rejects low-resolution descriptor thumbnails when a full-resolution asset is unavailable.

## 1.0.0 (Build 28) — 2026-08-29

- Fixed solid-color options being read from the wrong wallpaper configuration level.
- Resolves named macOS system colors to their actual Solid Colors image assets.
- Uses encoded RGBA values only as a fallback for custom color providers.

## 1.0.0 (Build 27) — 2026-08-29

- Added support for built-in solid-color image wallpapers and color-value providers.
- Never processes macOS DefaultDesktop.heic transition placeholders as real wallpaper sources.
- Added a short stable-selection check before rendering to avoid transient wallpaper rollback.
- Updated Settings to accurately describe support for image and solid-color wallpapers.
- Leaves Dynamic Desktop, Aerial, and video wallpaper providers unchanged.

## 1.0.0 (Build 26) — 2026-08-29

- Fixed static wallpapers no longer being detected after switching through an unsupported Aerial or video wallpaper.
- Decoded image-provider configuration URLs when macOS exposes only its DefaultDesktop placeholder.
- Made the per-user wallpaper Provider authoritative so a stale NSWorkspace URL cannot restore an older wallpaper.
- Reused an existing generated wallpaper on launch instead of rewriting it through transient system configuration states.
- Preserved HEIC output and container metadata for traditional Dynamic Desktop wallpapers.
- Made processed wallpaper cache keys stable across repeated selections of the same source.
- Added least-recently-used cache cleanup capped at 20 files and 500 MB while protecting the visible wallpaper.

## 1.0.0 (Build 25) — 2026-08-29

- Fixed provider-backed wallpapers being mistaken for an unfinished wallpaper switch.
- Read the active provider from the current display's per-user wallpaper store before falling back to system metadata.
- Show the live/video compatibility explanation immediately for Aerial wallpapers instead of waiting indefinitely.

## 1.0.0 (Build 24) — 2026-08-29

- Replaced the menu-bar overlay with wallpaper-integrated notch treatment so macOS keeps native menu text and status icons legible.
- Added a generation-based wallpaper transaction pipeline that cancels stale work and never reapplies an older source after a user wallpaper change.
- Added immediate wallpaper-store observation, self-generated-change suppression, and a short polling fallback without the previous five-second delay.
- Restored static image and multi-frame HEIC Dynamic Desktop processing while leaving unsupported live/video providers unchanged.
- Added explicit waiting, processing, active, unsupported, and failure feedback in Settings.

## 1.0.0 (Build 23) — 2026-08-29

- Replaced wallpaper rewriting with click-through native overlay windows for menu-bar tinting and desktop corners.
- Added compatibility with image, Dynamic Desktop, aerial, video, and system-provider wallpapers without changing the selected wallpaper.
- Added display, Space, wake, and app-lifecycle refresh handling for the overlay windows.
- Updated settings, status, compatibility, and privacy copy to describe the new non-destructive implementation.

## 1.0.0 (Build 22) — 2026-08-29

- Reworked wallpaper monitoring to respond quickly without a fixed settling delay.
- Prevented macOS transition placeholders such as `DefaultDesktop.heic` from being processed or written back as the selected wallpaper.
- Added durable original-wallpaper snapshots before applying notch blending or rounded corners.
- Cancelled outdated rendering immediately when the user selects another wallpaper.
- Made legacy records with missing or placeholder sources non-restorable, preventing another unwanted wallpaper rollback.

## 1.0.0 (Build 21) — 2026-08-29

- Fixed desktop appearance effects overriding a wallpaper newly selected in System Settings.
- Made the current macOS wallpaper the new source automatically, then reapplied notch blending and rounded corners without switching back to an older image.
- Fixed toggling desktop appearance effects restoring an unrelated wallpaper from an earlier session.
- Prevented an outdated background-rendering task from applying after the wallpaper or appearance settings have changed.

## 1.0.0 — 2026-08-26

- Added optional notch blending and adjustable rounded desktop corners.
- Refined notch-hiding copy and placed the desktop’s upper corners below the menu bar when both effects are enabled.
- Added local processing for static and traditional multi-frame HEIC Dynamic Desktop wallpapers.
- Added automatic reapplication across display and Space changes, external-display control, and original-wallpaper restoration.
- Added silent migration from TopNotch-managed wallpapers and generic protection against repeated wallpaper overrides.
- Added display-aware naming for notch-equipped and notch-free Macs, plus refined compatibility, status, and privacy copy.
- Added a compact native dashboard for CPU, memory, disk, battery, network, temperature, and fan status.
- Added two-minute CPU, memory, and CPU-temperature charts with grid and system-time labels.
- Added model-aware hardware information, including detailed Apple chip variants and total memory.
- Added one- and two-fan layouts with automatic support for fanless Macs.
- Added app-aware high-usage process names and a searchable full process window.
- Added up to two selectable menu bar metrics.
- Added launch-at-login, refresh interval, memory accounting, and appearance settings.
- Added Simplified Chinese and English localization.
- Added light and dark appearance support.
- Hardened sensor data parsing and prepared Universal 2, Developer ID, and notarization release workflows.
