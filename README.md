<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Reclaim app icon">
</p>

<h1 align="center">Reclaim</h1>

<p align="center">
  Get your disk space back from the menu bar.<br>
  A free, open-source successor to CleanMyDrive&nbsp;2 for macOS.
</p>

<p align="center">
  <img src="docs/screenshots/panel-light.png" width="340" alt="Reclaim's menu bar panel in light mode, showing three drives with used, trash, purgeable and free space">
  &nbsp;
  <img src="docs/screenshots/panel-dark.png" width="340" alt="The same panel in dark mode">
</p>

## Why

When you delete a file on a Mac, it isn't gone. It moves to a Trash folder **on the same drive**: `~/.Trash` for your startup disk, and a hidden `.Trashes` folder on every external drive. The space only comes back when that Trash is emptied, and Finder gives you no easy way to see how much of each drive is in use, waiting in the Trash, purgeable, or actually free.

Reclaim puts all of that in the menu bar and empties any drive's Trash in one click.

## Features

- **Every drive at a glance.** A bar per drive split into *Used*, *In Trash*, *Purgeable* (caches macOS frees by itself) and *Free*.
- **Empty one drive's Trash, or all of them.** Confirmed with a Finder-style alert that tells you exactly how many items and how much space.
- **Trash peek.** See the largest items in a drive's Trash before you erase them. Show any item in Finder (to Put Back), or erase just that one.
- **Remove hidden clutter** from USB sticks and SD cards: macOS's `.DS_Store`, `._` AppleDouble files and temporary items, plus Windows `Thumbs.db` caches, all of which show up on TVs, cameras, car stereos and other PCs.
- **Eject** drives from the same panel.
- **Low-space warnings** when a drive is almost full, telling you how much its Trash would give back.
- **Menu bar badge** showing reclaimable space (above 1 GB by default) and a **global shortcut**, ⌃⌥⌘R by default.
- Native Swift and SwiftUI, no dependencies, Dark Mode, VoiceOver and keyboard accessible.

## Install

1. Download `Reclaim-x.y.z.zip` from [Releases](../../releases) and unzip it.
2. Move **Reclaim.app** to your Applications folder.
3. Open it. Reclaim isn't notarized by Apple yet (that needs a paid developer account), so macOS blocks the first launch:
   - **macOS 15 Sequoia and later:** open **System Settings › Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to the message about Reclaim, then confirm. (Right-click › Open no longer works for this since Sequoia.)
   - **macOS 14 Sonoma:** right-click Reclaim.app, choose **Open**, then confirm.
   - Or, on any version, remove the download quarantine in Terminal:
     ```sh
     xattr -dr com.apple.quarantine /Applications/Reclaim.app
     ```
4. Optional: to see and empty your **startup disk's** Trash, give Reclaim **Full Disk Access**. Reclaim won't appear in that list by itself: open **System Settings › Privacy & Security › Full Disk Access**, click **+**, choose **Reclaim** in Applications (or drag it in), turn it on, then quit and reopen Reclaim. Reclaim's banner opens that pane and shows the app in Finder for you. External drives don't need it; macOS asks once whether Reclaim may access removable volumes. If you chose Don't Allow, macOS won't ask again: use the **Allow…** button on that drive's row, or turn on Removable Volumes for Reclaim in **Privacy & Security › Files & Folders**.

> Because builds are ad-hoc signed, macOS treats each update as a new app, and you may need to turn Full Disk Access on again after updating.

## How the numbers work

| Segment | What it is | Source |
| --- | --- | --- |
| **Free** | Space available right now | `volumeAvailableCapacity` |
| **Purgeable** | Caches, iCloud copies and snapshots macOS deletes automatically when it needs room | `volumeAvailableCapacityForImportantUsage − free` |
| **In Trash** | What you deleted but haven't emptied. Reclaim gives this back | Allocated size of the drive's Trash folder |
| **Used** | Everything else | Remainder, so the four always add up to the drive's size |

*Emptied the Trash but the space didn't come back?* On APFS drives, Time Machine local snapshots can keep deleted files' blocks for up to 24 hours. macOS releases them automatically when space runs low (they're counted as purgeable).

## What Reclaim deletes, and what it never touches

Reclaim only ever deletes:
- the contents of a drive's Trash folder (`~/.Trash` or `<drive>/.Trashes/<your user ID>`), when you confirm
- hidden macOS files on **external** drives, when you confirm

Every deletion first goes through one small, heavily tested `SafetyPolicy`:

- The Trash folder must be exactly one of the two locations above. A symbolic link anywhere in its path means Reclaim refuses.
- Each item must be strictly inside that folder. Symbolic links are removed, never followed, so a link in the Trash pointing at your Documents only deletes the link.
- Hidden-file cleanup checks each file's **contents** (the AppleDouble and `.DS_Store` headers), not just its name, and checks again right before deleting. A file of yours that happens to be called `._notes.txt` is left alone.
- On exFAT and FAT32 drives, a `._` file is where macOS keeps another file's Finder tags, comments, colour label and resource fork. Reclaim reads it and **keeps** any `._` file that holds those, or anything it doesn't recognise. It only removes `._` files that are orphaned or hold nothing but download bookkeeping.
- The startup disk and Time Machine backup drives are never "cleaned".

## Build from source

Requirements: macOS 14 or later, Swift 6 (full Xcode **or** just the Command Line Tools).

```sh
make app          # build/Reclaim.app (universal) and build/Reclaim-<version>.zip
make run          # run in sandbox mode (see below)
make test         # unit tests, run inside the test sandbox
make install      # copy to /Applications
```

### The test sandbox

Reclaim deletes files for a living, so its development setup is built to make it impossible to delete the wrong ones:

1. **Throwaway disks.** `Scripts/sandbox.sh up` creates four sparse disk images (APFS, exFAT, FAT32, HFS+, 5 GB of declared capacity in total) and mounts them as real drives named `RTEST-*`. `Scripts/sandbox.sh seed` fills them with trash, locked files, symlinks pointing outside the drive, and junk with decoys. `Scripts/sandbox.sh down` removes everything.
2. **Kernel write sandbox.** Tests and sandboxed app runs execute under `sandbox-exec` with `Scripts/reclaim-test.sb`, which denies writes everywhere except the build folder, the sandbox folder and `/Volumes/RTEST-*`, and explicitly denies `~/.Trash`. A canary check proves this before every run.
3. **Sandbox mode.** `--sandbox` makes the app see only `RTEST-*` drives and never your startup disk's Trash. It also doesn't touch login items, notifications or your preferences.
4. **The SafetyPolicy above**, which is always on.

```sh
Scripts/sandbox.sh up && Scripts/sandbox.sh seed
make test-integration   # the real app model empties, cleans and ejects the RTEST disks
Scripts/sandbox.sh down
```

### Command Line Tools only?

`Scripts/toolchain.sh` (used by every script and Makefile target) detects and works around some rough edges of Command Line Tools-only installs:
- a stale PackageDescription interface that breaks `Package.swift`
- Swift Testing's plugin and runtime paths
- newer SDKs whose SwiftUI `@State` macro plugin ships only with Xcode

With Xcode installed it does nothing.

## Project layout

```
Sources/ReclaimCore   Space accounting, trash scanning and emptying, junk cleanup, SafetyPolicy
Sources/ReclaimUI     SwiftUI views and the app model (testable without a screen)
Sources/Reclaim       AppKit shell: status item, popover, alerts, hotkey, Settings window
Tests/                Swift Testing unit tests, snapshot renders, sandbox-disk integration tests
Scripts/              Build, test sandbox, icon
```

## Roadmap

Ideas for future releases: Clean & Eject in one step, explaining and thinning Time Machine local snapshots, auto-empty rules, Put Back from Trash peek, a command-line tool and URL scheme, a Homebrew tap (the main Homebrew cask list no longer accepts apps that aren't notarized), and signed, notarized builds.

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md), especially the safety rules.

## License

[MIT](LICENSE) © 2026 Akhilesh Boda.

Reclaim is an independent project and is not affiliated with MacPaw or CleanMyDrive.
