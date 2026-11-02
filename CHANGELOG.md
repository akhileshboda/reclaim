# Changelog

All notable changes to Reclaim are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). The release workflow publishes the section matching each tag as that release's notes.

## [Unreleased]

### Fixed

- Eject now appears for every external drive. USB hard drives that macOS reports as "not ejectable" (though Finder ejects them fine) had no Eject button.

## [0.1.0-beta.1] - 2026-11-02

The first public beta. Builds aren't notarized yet: see the README's Install section for the one-time security prompt.

### Added

- Menu bar panel showing every drive's Used, In Trash, Purgeable and Free space.
- Empty one drive's Trash, or every drive's at once, after a confirmation that lists the item count and size.
- Trash peek: the largest items in a drive's Trash, with Show in Finder and erase-one-item.
- Hidden-clutter cleanup for external drives: `.DS_Store`, orphaned `._` AppleDouble files, temporary items and Windows `Thumbs.db`. `._` files holding Finder tags, comments or resource forks are kept.
- Eject drives from the panel.
- Low-space warnings that say how much the drive's Trash would give back.
- Menu bar badge for reclaimable space and a global shortcut (⌃⌥⌘R).
- Full Disk Access onboarding for the startup disk's Trash, including why it can't be emptied without it.
- Settings: badge threshold, shortcut, low-space alerts, open at login, automatic update checks.
- **Report a Bug…** in the menu, which opens a GitHub issue with the Reclaim and macOS versions filled in.

### Safety

- Every deletion goes through `SafetyPolicy`: exact Trash locations only, no symbolic links in the path, every item strictly inside its root.
- The startup disk and Time Machine backup drives are never cleaned.

[Unreleased]: https://github.com/akhileshboda/reclaim/compare/v0.1.0-beta.1...HEAD
[0.1.0-beta.1]: https://github.com/akhileshboda/reclaim/releases/tag/v0.1.0-beta.1
