# Download and Install

## Latest Download

- [Latest Release](https://github.com/Four-JJJJ/AI-Plan-Monitoring/releases/latest)
- Recommended asset: `AI Plan Monitor.dmg`

## Install on macOS

1. Download `AI Plan Monitor.dmg` from the latest release.
2. Open the DMG.
3. Drag `AI Plan Monitor.app` into `Applications`.
4. Launch from `Applications`.

## First Launch on GitHub Builds

Because GitHub-distributed builds may not always be notarized, macOS can block first launch.

Use this order:

1. Right-click `AI Plan Monitor.app`
2. Choose `Open`
3. Click `Open` again in the system dialog

If macOS still blocks it:

1. Open `System Settings`
2. Go to `Privacy & Security`
3. Find the message for `AI Plan Monitor`
4. Click `Open Anyway`

## Terminal Fallback

If the app is quarantined and the GUI path still fails:

```bash
xattr -dr com.apple.quarantine "/Applications/AI Plan Monitor.app"
```

Then launch the app again.

## What Users Need to Know

- The app is macOS only.
- Minimum supported version is macOS 14.
- Some providers rely on local desktop sessions, local browser state, or manually pasted credentials.
- Third-party relay templates hide most of the technical configuration and only ask for required fields.

## Troubleshooting

### The app does not open

- Re-copy the app from the latest DMG into `Applications`
- Remove quarantine using the command above
- Make sure you are launching the newest copy from `Applications`

### A provider shows auth expired

- Re-login to the official app or website
- Re-save the token or cookie if the provider uses manual credentials
- For supported relays, switch to browser-first credential mode if that is more stable

### Codex account switching needs verification

- The local desktop account has been switched
- If Codex asks for re-verification, complete that flow in the Codex desktop app once

## For Maintainers

To build the release asset locally:

```bash
./scripts/package_dmg.sh
```

The output DMG is written to `dist/AI Plan Monitor.dmg`.
