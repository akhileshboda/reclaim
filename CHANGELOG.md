# Changelog

All notable changes to Reclaim are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). The release workflow publishes the section matching each tag as that release's notes.

## [Unreleased]

### Fixed

- The panel no longer runs off the bottom of small or scaled displays (13-inch MacBook Air at Larger Text, short external monitors): it fits the screen it opens on and the drive list scrolls.
- When the menu bar icon is hidden behind the notch or by a crowded menu bar, the panel opens in a small floating window at the top right of the screen, instead of off screen or at a stale position after a display was unplugged. It keeps its title bar on screen as the content grows.
- Clicking the menu bar icon to close the panel no longer reopens it.
- Settings reopens on screen when its saved position belonged to a display that's gone.
- A slow, sleeping or unreachable drive no longer freezes the panel: each Trash is measured in parallel with a time limit, the drive shows "Measuring the Trash…", and the result appears when it arrives.
- Far less disk activity: mounting a disk image, emptying one drive or ejecting no longer re-measures every drive's Trash, copying files onto a new drive no longer triggers rescans, and unchanged Trash items aren't re-measured.
- Empty All Trash keeps going when one drive changed while it was asking, and says which drive was left alone, instead of reporting that nothing was erased.
- Empty is no longer offered on read-only drives, and hidden-file cleanup is no longer offered on network shares. Looking for hidden files can be stopped.
- Low-space warnings aren't repeated after every launch, and appear once per APFS container instead of once per volume.

### Changed

- A new panel design: a hero ring and big Ember amount with what your free space becomes after emptying, rounded drive cards with an Ember "in Trash" pill, an Ember Empty All Trash button showing the total, and placeholder cards while the first measurement runs.
- After emptying, a boomerang flies home to the ring and the message reads "Boomerang’s back!". Under Reduce Motion there's no flight.

## [0.1.0-beta.1] - 2026-11-02

The first public beta. Builds aren't notarized yet: see the README's Install section for the one-time security prompt.

### Added

- Reclaim's brand: a boomerang, because what you throw away comes back. It's the app icon, the menu bar glyph, the badge in the panel header, the progress spinner and the mark beside "Reclaimed …" messages. The reclaimable amount shows in Ember orange. See [docs/brand.md](docs/brand.md).
- Menu bar panel showing every drive's Used, In Trash, Purgeable and Free space.
- Empty one drive's Trash, or every drive's at once, after a confirmation that lists the item count and size.
- Trash peek: the largest items in a drive's Trash, with Show in Finder and erase-one-item.
- Hidden-clutter cleanup for external drives: `.DS_Store`, orphaned `._` AppleDouble files, temporary items and Windows `Thumbs.db`. `._` files holding Finder tags, comments or resource forks are kept.
- Eject drives from the panel, including USB hard drives that macOS reports as "not ejectable" though Finder ejects them fine.
- Low-space warnings that say how much the drive's Trash would give back.
- Menu bar badge for reclaimable space and a global shortcut (⌃⌥⌘R).
- Full Disk Access onboarding for the startup disk's Trash, including why it can't be emptied without it. Reclaim appears in the Full Disk Access list with its switch off, so there's no need to add it with **+** or drag it in; the banner opens the pane, then offers **Restart Reclaim** if macOS doesn't offer to reopen it.
- Download as a disk image (`.dmg`) with an Applications shortcut, next to the zip.
- Settings: badge threshold, shortcut, low-space alerts, open at login, automatic update checks.
- **Report a Bug…** in the menu: write what happened and **Send** it privately to the developer (no GitHub account needed, optional email for a reply), or **Open GitHub Issue** with the Reclaim and macOS versions filled in. Nothing is sent until you press Send.

### Safety

- Every deletion goes through `SafetyPolicy`: exact Trash locations only, no symbolic links in the path, every item strictly inside its root.
- The startup disk and Time Machine backup drives are never cleaned.

[Unreleased]: https://github.com/akhileshboda/reclaim/compare/v0.1.0-beta.1...HEAD
[0.1.0-beta.1]: https://github.com/akhileshboda/reclaim/releases/tag/v0.1.0-beta.1
