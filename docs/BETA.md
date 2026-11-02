# Reclaim beta tester guide

Thanks for testing Reclaim. The goal of this beta is to find out how it behaves on Macs and drives other than the developer's, **before** it's announced more widely. A report that says "everything worked on my setup" is as useful as a bug report.

The beta runs for about three weeks per build. You can stop at any time.

## Before you start

- **Have a backup.** Reclaim only deletes what's in a Trash folder, plus a few kinds of hidden macOS files on external drives, and only after you confirm. But it's beta software that deletes files, so make sure Time Machine (or another backup) is up to date.
- **Empty nothing you might want back.** Before using Reclaim on a drive, look through that drive's Trash and put back anything you're not ready to lose.
- **Test on a throwaway drive first.** You don't need spare hardware. In **Disk Utility**, choose **File › New Image › Blank Image…**, set Size to 1 GB and Format to **ExFAT** (or APFS, or MS-DOS FAT), and save. Double-click the `.dmg` to mount it like a USB drive, copy some files you don't need onto it, then move them to the Trash in Finder.

## Install

1. Download `Reclaim-<version>.dmg` from the [latest pre-release](https://github.com/akhileshboda/reclaim/releases).
2. Open it, drag **Reclaim** onto the **Applications** shortcut, then eject the image. Open Reclaim from Applications, not from the image or Downloads.
3. The first time you open it, macOS blocks it because it isn't notarized yet. On macOS 15 or later, open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. On macOS 14, right-click Reclaim.app and choose **Open**.
4. Reclaim lives in the menu bar (there's no Dock icon). Click its icon to open the panel.

Updates: beta builds check GitHub once a day and tell you when the next beta or the final release is out. Because betas aren't signed with an Apple certificate yet, **macOS forgets Reclaim's Full Disk Access after each update**. Turn it off and on again in Privacy & Security after installing a new build.

## What to try

Do whatever applies to your setup. You don't need to do everything.

### The basics

- [ ] Open the panel. Do the Used / In Trash / Purgeable / Free numbers for each drive look right compared with Finder's **Get Info**?
- [ ] Empty the Trash on your throwaway drive. Did the In Trash number drop to zero and Free go up?
- [ ] Open **Trash peek** on a drive. Try **Show in Finder** and erasing a single item.
- [ ] Clean hidden clutter from a USB stick or SD card that's been used on a Mac. Then check that your own files on it are all still there.
- [ ] Eject a drive from the panel.
- [ ] Try the menu bar badge and the global shortcut (⌃⌥⌘R).

### The startup disk

- [ ] Follow the banner to give Reclaim **Full Disk Access**, quit and reopen it, and check your startup disk's Trash now shows.
- [ ] Empty the startup disk's Trash (after checking there's nothing in it you want).

### Different drives

Each of these is useful to hear about, even if it just worked:

- [ ] APFS external SSD or hard drive
- [ ] Mac OS Extended (HFS+) drive
- [ ] exFAT or FAT32 USB stick / SD card, especially one also used with Windows, a camera or a TV
- [ ] A **Time Machine backup drive**. Reclaim should refuse to remove hidden clutter from it, and must **never** touch the backups themselves. (Emptying its Trash is fine: that only holds files you deleted.) Please tell us right away if anything else happens.
- [ ] A network share (SMB) or a NAS
- [ ] Two drives with the same name plugged in at once

### Awkward moments (throwaway drive only)

- [ ] Unplug or eject the drive while Reclaim is emptying its Trash. Reclaim shouldn't crash, and the drive should still mount afterwards.
- [ ] Put the Mac to sleep with Reclaim running and a drive attached, then wake it.
- [ ] Rename a drive in Finder while the panel is open.
- [ ] Leave Reclaim running for a few days. Does it stay responsive? (If you know Activity Monitor, its memory use is interesting too.)

## Reporting

- **A bug or crash:** choose **Report a Bug…** in Reclaim's menu (click the **⋯** button in the panel, or right-click the menu bar icon). It opens a GitHub form with your versions filled in. If Reclaim crashed, the form explains where to find the crash report.
- **How it went overall:** fill in a [Beta test report](https://github.com/akhileshboda/reclaim/issues/new?template=beta_feedback.yml), ideally after a week of use.
- **Reclaim deleted something outside a Trash folder:** stop using it and please [report it privately](https://github.com/akhileshboda/reclaim/security/advisories/new). This is the most important kind of report.

You need a free GitHub account to report. Don't include file names or screenshots you'd rather keep private: GitHub issues are public.

## Known limitations

- Not notarized, so the first-launch security prompt and the Full Disk Access reset after each update are expected.
- Emptying a very large Trash shows a spinner rather than a progress bar.
- Network drives and iCloud Drive's trash haven't been tested much (iCloud isn't supported yet).

## Uninstall

Turn off **Open Reclaim at login** in Settings, quit Reclaim, and drag it from Applications to the Trash. The [README](../README.md#uninstall) lists the optional clean-up steps.
