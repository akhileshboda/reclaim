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
- CI must pass.
