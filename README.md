# AI Plan Monitor

A macOS menu bar app for monitoring AI plan limits, credits, and relay balances in one place.

[Download Latest Release](https://github.com/Four-JJJJ/AI-Plan-Monitoring/releases/latest) · [Install Guide](docs/DOWNLOAD.md) · [Supported Services](docs/PROVIDERS.md)

## Why AI Plan Monitor

Most AI dashboards are fragmented:
- official products expose quota in different formats
- relay sites hide balances behind custom cookies, headers, or account IDs
- desktop usage often lives in local sessions instead of public APIs

AI Plan Monitor pulls those sources back into a single macOS menu bar app so you can check:
- official plan limits
- session and weekly windows
- third-party relay balances
- local desktop account state

## What Makes It Different

- Official + third-party in one app  
  Monitor Codex, Claude, Gemini, Copilot, Cursor, Windsurf, Kimi, and relay sites from the same menu.

- Template-driven relay setup  
  Known relay sites expose only the fields users actually need to fill in. Endpoint paths and field parsing stay hidden behind templates.

- Better relay diagnostics  
  The app distinguishes auth expiry, rate limit, endpoint mismatch, and unreachable states instead of collapsing everything into a generic error.

- Codex desktop multi-account switching  
  Import multiple local `auth.json` profiles, switch accounts from the menu bar, and keep inactive account countdowns visible.

- Menu bar first  
  The active provider can be pinned to the status bar so you always see the signal you care about most.

## Core Features

- Per-provider enable and disable
- Low balance and low quota alerts
- Auth failure and repeated fetch failure alerts
- Launch at login
- Relay credential modes:
  - manual preferred
  - browser preferred
  - browser only
- Relay health diagnostics:
  - auth source
  - endpoint health
  - cached vs live freshness
- Codex profile management:
  - auto-capture current local auth
  - import additional accounts
  - one-click local desktop switching

## Supported Coverage

### Official services

- Codex
- Claude
- Gemini
- GitHub Copilot
- Cursor
- Windsurf
- Kimi
- Amp
- Z.ai
- JetBrains AI
- Kiro

### Third-party relay templates

- `open.ailinyu.de`
- `platform.moonshot.cn`
- `platform.xiaomimimo.com`
- `platform.minimaxi.com`
- `hongmacc.com`
- `platform.deepseek.com`
- `dragoncode.codes`
- generic New API compatible sites

Detailed auth and setup notes live in [Supported Services](docs/PROVIDERS.md).

## Install

1. Download the latest `.dmg` from [Releases](https://github.com/Four-JJJJ/AI-Plan-Monitoring/releases/latest).
2. Drag `AI Plan Monitor.app` into `Applications`.
3. On first launch, right-click the app and choose `Open`.
4. If macOS blocks the app, allow it from `System Settings -> Privacy & Security`.

Full step-by-step instructions are in [docs/DOWNLOAD.md](docs/DOWNLOAD.md).

## Security

- Provider credentials entered in settings are stored in macOS Keychain.
- Legacy `AIBalanceMonitor` keychain entries are migrated to `AI Plan Monitor`.
- App configuration is stored under `~/Library/Application Support/AIBalanceMonitor`.
- The app can read browser-derived credentials for supported sites when browser-first relay mode is enabled.

## Build From Source

Requirements:
- macOS 14+
- Xcode / Swift 6 toolchain

Run locally:

```bash
swift run
```

Build a universal DMG:

```bash
./scripts/package_dmg.sh
```

## Distribution Notes

- Current public builds are GitHub-distributed macOS apps, not App Store releases.
- Unsigned or ad-hoc builds may require `right click -> Open` on first launch.
- Developer ID signing and notarization are supported by the packaging script when credentials are available.

## Roadmap

- richer release automation
- more verified relay templates
- more provider-specific diagnostics
- more install polish for non-technical users

## License

Add the license you want before broader public distribution if you plan to open source the project long term.
