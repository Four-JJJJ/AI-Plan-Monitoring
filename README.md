# AIBalanceMonitor (macOS Menu Bar)

A macOS menu bar app for monitoring:
- Official Codex quota (local `codex app-server`)
- `open.ailinyu.de` token/billing usage via `sk-` token

## Requirements
- macOS 14+
- Xcode / Swift 6 toolchain
- `codex` CLI installed and logged in locally

## Run
```bash
swift run
```

The app appears in the menu bar as `AI`.

## Configure Tokens
- Open the menu bar window.
- In `open.ailinyu.de`, paste your `sk-...` token and click `Save`.
- Token is stored in macOS Keychain (not plain text config).

## Data Sources
- Codex:
  - `account/read`
  - `account/rateLimits/read`
- Open:
  - `/api/usage/token/`
  - `/v1/dashboard/billing/subscription`
  - `/v1/dashboard/billing/usage`

## Behavior
- Per-provider enable/disable toggle
- Per-provider low-remaining threshold
- Backoff policy: 60s default, 120s after first failure, 300s after repeated failures
- Alerts:
  - low remaining
  - auth/token failure
  - repeated fetch failures

## Dragon Placeholder
`dragoncode.codes` provider is stubbed for v2 and intentionally disabled by default.
