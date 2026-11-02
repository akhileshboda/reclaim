# Security Policy

Reclaim permanently deletes files, so in this project a bug that deletes the wrong thing is a security issue, not just a bug.

## What to report privately

- Reclaim deleted, or could be made to delete, anything outside a drive's Trash folder or the hidden-file types it lists in the README.
- A way around `SafetyPolicy`: symbolic links, hard links, renamed or swapped folders, race conditions, unusual file systems.
- Reclaim touching the startup disk or a Time Machine backup drive when it shouldn't.
- Anything that lets another app or user make Reclaim act on their behalf.

Ordinary crashes, wrong numbers and UI problems are fine as [public issues](../../issues/new/choose).

## How to report

Use GitHub's private reporting: open the repository's **Security** tab and choose **Report a vulnerability**. Only the maintainer can see the report.

Please include your Reclaim version, macOS version, the drive's format (APFS, exFAT, …), and the steps or folder layout that cause it. If files were lost, say so first. I'll prioritise that report over everything else.

Please don't post details publicly until a fix is released.

## What to expect

Reclaim is maintained by one person in their spare time, so these are targets, not guarantees:

- An acknowledgement within 3 days.
- For a confirmed data-loss bug: a fixed release, or the affected feature turned off, as soon as possible, and a published advisory that credits you (unless you'd rather not be named).

## Supported versions

Only the latest release, including the latest beta, gets security fixes. Check for updates from Reclaim's menu (**Check for Updates…**).
