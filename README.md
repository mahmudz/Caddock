# CaddyManager

macOS menu bar app that manages **one global [Caddy](https://caddyserver.com) process** for local development.

Product source of truth: [`REBUILD_SPEC.md`](REBUILD_SPEC.md).

## What it does

- Virtual hosts: static (`file_server`), PHP (`php_fastcgi`), reverse proxy
- One shared Caddyfile → `caddy adapt` → admin API `POST /load`
- Caddy binds high ports (`127.0.0.1:8880` / `:8843`); optional privileged helper redirects 80/443 via `pf`
- HTTPS via `tls internal`; Root CA trust runs in the GUI process
- Wildcard `*.app.test` via `/etc/resolver` + a local DNS responder

Not Mac App Store. No App Sandbox. Notarized Developer ID DMG.

## Requirements

- macOS 15+
- Xcode 16+
- Caddy (Homebrew or in-app download)

## Build

```bash
xcodebuild -project CaddyManager.xcodeproj -scheme CaddyManager -configuration Debug build
open CaddyManager.xcodeproj
```

## Release

```bash
./scripts/release.sh
./scripts/release.sh --skip-notarize
./scripts/release.sh --skip-notarize --skip-sign
```

Output: `dist/CaddyManager-<version>.dmg`

## Identity

| | |
|---|---|
| App bundle ID | `dev.mahmudz.CaddyManager` |
| Helper bundle ID | `dev.mahmudz.CaddyManager.Helper` |
| Team ID | `SP792GFSPZ` |
