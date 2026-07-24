# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Approach
- Read existing files before writing. Don't re-read unless changed.
- Thorough in reasoning, concise in output.
- Skip files over 100KB unless required.
- No sycophantic openers or closing fluff.
- No emojis or em-dashes.
- Do not guess APIs, versions, flags, commit SHAs, or package names. Verify by reading code or docs before asserting.

## Project state

This is a fresh Xcode SwiftUI macOS app scaffold. `ContentView.swift` and `CaddyManagerApp.swift` still contain the default "Hello, world!" template — none of the product described in `README.md` is implemented yet. The README is the design intent; the code is not there yet. Expect to build features from scratch.

## What this app is meant to be

A macOS **menu bar** app that manages a **single global [Caddy](https://caddyserver.com) instance** for local development. Key architectural rule: there is ONE Caddy process. Each enabled virtual host is a site block/route *inside that one instance's config* — the app does not spawn one Caddy process per vhost. Any implementation must reflect this: adding/removing a vhost means editing the shared config and reloading Caddy, not starting/stopping separate processes.

Per-vhost capabilities the app should support:
- Static site — Caddy `file_server` serving a folder
- PHP app — Caddy `php_fastcgi` over a PHP-FPM unix socket
- Reverse proxy — forward to a local address (e.g. `127.0.0.1:3000`)
- Per-vhost SSL toggle — HTTPS via Caddy's local/internal CA
- Start/stop the Caddy instance and view its logs from the menu bar

## Tech Stack & Target

- **Swift 5.9+**, Xcode project (`.xcodeproj`), macOS app target
- **SwiftUI** `MenuBarExtra` for the menu bar UI → minimum deployment target **macOS 13 (Ventura)**
  - If you need to support macOS 12 or earlier, the menu bar UI must be rewritten on `NSStatusItem` + AppKit instead. Default assumption here is **SwiftUI-first, MenuBarExtra**.
- **Caddy** (external binary — see §6) as the webserver/reverse proxy
- Distribution: **Developer ID, direct download, notarized app** (not Mac App Store). The sandbox would block the subprocess spawning, `/etc/hosts` / `pf` editing, and privileged helper that this app needs. Do not add App Sandbox capability.

## Build / run / test

Single target and scheme, both named `CaddyManager`. No CocoaPods/SPM/Carthage manifests — pure Xcode project.

```bash
# Build (Debug)
xcodebuild -project CaddyManager.xcodeproj -scheme CaddyManager -configuration Debug build

# Run: open in Xcode and Cmd+R (menu bar / GUI app — no CLI run target)
open CaddyManager.xcodeproj
```

Note: default build configuration is **Release** if `-configuration` is omitted.

## Project facts

- Bundle ID: `dev.mahmudz.CaddyManager`
- macOS deployment target: 26.4
- Swift 5.0 language version, SwiftUI
