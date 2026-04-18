# Release Guide

I'm not paying for the Apple Developer Program, so Ping ships as an **unsigned
macOS DMG** built straight from the repo. If that ever changes I would update this.

## Building the DMG

```bash
./scripts/release-macos.sh
```

The DMG ends up at:

```text
build/release/Ping.dmg
```

What the script does:

1. Builds `Ping macOS` (`Release`) with `CODE_SIGNING_ALLOWED=NO`
2. Ad-hoc signs the resulting `Ping.app`
3. Packages it into a UDZO `.dmg`

## What You Will See

Because the app is unsigned, Gatekeeper will complain on first launch.

- Right-click the app → **Open** → **Open** in the dialog, or
- Strip the quarantine attribute from the terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Ping.app
```

## Notes

- Run it from the repo root.
- If you've never opened the project locally, run `xcodegen generate` first
  so `Ping.xcodeproj` exists.
