# Contributing to Reclaim

Thanks for helping. Reclaim permanently deletes files, so a few rules matter more here than in most projects.

## Safety rules

1. **Never run destructive code against your real drives while developing.** Use the throwaway disks:
   ```sh
   Scripts/sandbox.sh up && Scripts/sandbox.sh seed
   make run                 # the app in sandbox mode: RTEST-* drives only
   make test-integration
   ```
2. **Every deletion goes through `SafetyPolicy`.** Don't call `FileManager.removeItem` (or anything else that deletes) from new code paths. Add a method to `TrashEmptier` or `JunkCleaner` that validates first.
3. **List files with `FileTree`, not `FileManager`.** Foundation hides names starting with `._`, which are exactly the files Reclaim cares about.
4. **New deletion behaviour needs a test that proves what it *doesn't* delete**: symlink targets, decoys, files outside the root.

## Development loop

```sh
make test        # unit tests inside the kernel write sandbox
make app-dev     # quick arm64 debug build
make run         # launch it in sandbox mode
make capture     # the running app renders its panel and Settings to PNG
```

Requires macOS 14+ and Swift 6 (Xcode or Command Line Tools).

## Style

- Match the surrounding code: small types, comments that explain *why*, Swift 6 concurrency (UI on the main actor, file work in detached tasks).
- UI follows Apple's Human Interface Guidelines: system text styles and colours, SF Symbols, VoiceOver labels, title-style capitalisation, an ellipsis on commands that ask for confirmation.
- Keep it dependency-free.

## Pull requests

- Describe the user-visible change and how you tested it (which RTEST disks, which tests).
- Include before/after screenshots for UI changes (`make capture`).
- Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.
- CI must pass.
- Found a way to make Reclaim delete the wrong thing? Don't open a PR or issue with the details: see [SECURITY.md](SECURITY.md).

## Releasing (maintainer)

1. Move the **Unreleased** notes in CHANGELOG.md under a new `## [x.y.z]` heading and update the links at the bottom.
2. Put the same version in `VERSION`. A version with a pre-release part, like `0.2.0-beta.1`, is published as a GitHub pre-release and offered only to people already running a beta.
3. Merge to `main`, then tag and push: `git tag v$(cat VERSION) && git push origin v$(cat VERSION)`.
4. The Release workflow checks that the tag, VERSION and CHANGELOG agree, runs the tests, and publishes the DMG and zip, their checksums and the CHANGELOG section as release notes.
