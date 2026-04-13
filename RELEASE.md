# Release Guide

This guide covers direct macOS distribution using `scripts/release-macos.sh`.

## Fast Path (No Paid Developer Program)

Use unsigned mode (default) to produce a DMG without notarization:

```bash
./scripts/release-macos.sh
```

Output:

- `build/release/Ping.dmg`

Notes:

- This does **not** require paid Apple Developer Program membership.
- Users may see Gatekeeper warnings when opening/downloading.

## Paid Path (Developer ID + Notarization)

Use this path for trusted distribution with fewer warnings.

### One-time setup

1. Join Apple Developer Program (paid).
2. Install a **Developer ID Application** certificate in Keychain Access.
3. Create an app-specific password for your Apple ID.
4. Store notarization credentials:

```bash
xcrun notarytool store-credentials "ping-notary" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### Per release

```bash
SIGNING_MODE=developer-id \
NOTARIZE=1 \
NOTARY_PROFILE=ping-notary \
TEAM_ID=YOURTEAMID \
./scripts/release-macos.sh
```

## Script Summary

Script path:

```bash
./scripts/release-macos.sh
```

What it does:

1. Builds or archives the app (depending on `SIGNING_MODE`)
2. Produces `Ping.app`
3. Creates `.dmg`
4. Optionally notarizes + staples the DMG

## Key Environment Variables

- `SIGNING_MODE=unsigned|developer-id` (default: `unsigned`)
- `NOTARIZE=0|1` (default: `0`)
- `NOTARY_PROFILE=<profile>`
- `TEAM_ID=<team id>`
- `APP_NAME`, `SCHEME`, `PROJECT`, `CONFIGURATION` if needed

## Common Notes

- Run from repository root.
- Notarization requires `SIGNING_MODE=developer-id`.
- Sparkle 2 is intentionally not included yet; it can be layered on top later.
