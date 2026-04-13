# Supported Services

This page summarizes what AI Plan Monitor can currently monitor and how each service is typically connected.

## Official Providers

| Provider | Typical Source | Notes |
| --- | --- | --- |
| Codex | local desktop auth + web/API overlays | Supports multiple desktop accounts and local switching |
| Claude | API, CLI, or web session depending on mode | Web overlays can enrich usage windows |
| Gemini | official API/web quota data | Supports model-specific windows |
| GitHub Copilot | local GitHub auth | Reads Copilot usage and quota state |
| Cursor | official/local session data | Monthly and on-demand usage |
| Windsurf | official API | Daily and weekly windows |
| Kimi | official API | Session and overall usage |
| Amp | official API | Free and credit views |
| Z.ai | official API | Session, weekly, and web usage |
| JetBrains AI | local data | Local XML usage parsing |
| Kiro | CLI/local output | Credit-based usage |

## Third-Party Relay Templates

Known templates reduce setup friction by hiding endpoint and parser details behind validated presets.

| Template | Typical Credential | Extra Field |
| --- | --- | --- |
| `open.ailinyu.de` | Cookie | optional user ID override |
| `platform.moonshot.cn` | Bearer or Cookie | auto-resolves org context |
| `platform.xiaomimimo.com` | Cookie | none |
| `platform.minimaxi.com` | Cookie | `GroupId` |
| `hongmacc.com` | Bearer | none |
| `platform.deepseek.com` | Bearer | none |
| `dragoncode.codes` | relay token | support is still evolving |
| generic New API | Bearer or Cookie | depends on the site |

## Relay Credential Modes

Relay sites can use one of three credential strategies:

- `Manual Preferred`
  Saved token or cookie first, browser-derived credentials as fallback.

- `Browser Preferred`
  Browser-derived credentials first, saved token or cookie as fallback.

- `Browser Only`
  Use browser state only and ignore saved credentials.

## Diagnostic States

For relay providers, the app classifies fetch failures into stable user-facing states:

- auth expired
- rate limited
- endpoint misconfigured
- unreachable

This makes it easier to tell the difference between:
- a bad token
- a changed site response
- a temporary network problem

## Notes on Third-Party Coverage

Third-party sites change more often than official APIs. AI Plan Monitor tries to keep them stable through:

- per-site templates
- browser-first credential fallback
- dynamic parameter detection
- clearer user-facing diagnostics

If a relay changes its payload or auth flow, it may need a template update.
