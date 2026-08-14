# Caddock — Greenfield Rebuild Specification

> Hand this document to an agent (or developer) to rebuild the app from scratch.
> It describes the **product to ship**, not the current messy codebase.
> Prefer clean architecture and the defect fixes listed in §16 over copying old file layout.

**Product name:** Caddock  
**Platform:** macOS menu bar app (not Mac App Store)  
**Bundle ID (app):** `dev.mahmudz.Caddock`  
**Bundle ID (helper):** `dev.mahmudz.Caddock.Helper`  
**Team ID (current):** `SP792GFSPZ`  
**Distribution:** Developer ID signed + notarized DMG  

---

## 0. Mission

Build a polished macOS **menu bar** app that manages a **single global [Caddy](https://caddyserver.com)** process for local development.

Users define virtual hosts (static / PHP / reverse proxy). The app writes one shared Caddyfile, hot-reloads Caddy via the admin API, optionally installs a privileged helper for port 80/443 redirects + `/etc/hosts`, and trusts Caddy’s local HTTPS CA so browsers stop warning.

**Non-goals:** Mac App Store, App Sandbox, one Caddy process per site, public ACME certs for fake TLDs.

---

## 1. Hard architectural rules (do not violate)

1. **One Caddy process.** Adding/removing a vhost edits the shared config and reloads — never spawn per-vhost servers.
2. **Unprivileged app + privileged helper.** Main app never runs as root. `pf`, `/etc/hosts`, `/etc/resolver` go through an `SMAppService.daemon` over XPC.
3. **No App Sandbox.** Subprocess spawn, helper install, and network tools require it off. Use Hardened Runtime + Developer ID.
4. **High ports + pf redirect.** Caddy binds `127.0.0.1:8880` / `:8843` (configurable). Helper installs `pf` rdr on `lo0` for `80 → httpPort` and `443 → httpsPort` (Valet-style).
5. **Caddyfile → adapt → admin `/load`.** Generate human Caddyfile, `caddy adapt`, `POST` JSON to admin API. First boot uses `caddy run` if admin is down.
6. **HTTPS via `tls internal`.** Never ACME for `.test` / local TLDs. Trust the local Root CA in the **GUI process** (not via `sudo` / helper `osascript`).
7. **Menu bar first.** After setup, app is `LSUIElement` / activation policy `.accessory`. Setup wizard may use `.regular` temporarily.
8. **SwiftUI-first**, `MenuBarExtra`, deployment target **macOS 14+** (Ventura 13 minimum only if forced; prefer 14 for modern window APIs).

---

## 2. Targets & project layout (recommended)

### 2.1 Xcode targets

| Target | Type | Notes |
|---|---|---|
| `Caddock` | macOS App | Menu bar UI, Caddy control, XPC client |
| `CaddockHelper` | Command-line tool | Root daemon, implements XPC protocol |
| `CaddockTests` (optional but recommended) | Unit tests | Pure logic: config builder, validator, domain policy |

Embed helper binary into the app. Copy LaunchDaemon plist to:

```
Caddock.app/Contents/Library/LaunchDaemons/dev.mahmudz.Caddock.Helper.plist
```

Commit a shared `.xcscheme` for `Caddock` (release script depends on it).

### 2.2 Suggested source layout

```
Caddock/
├── App/
│   ├── CaddockApp.swift          # Scenes: MenuBarExtra, Windows, Settings, Setup
│   └── AppDelegate.swift              # Activation policy, login item sync, finishSetup
├── Domain/
│   ├── Models/                        # Vhost, AppSettings, LogSource, ValidationIssue
│   ├── Policies/                      # LocalDomainPolicy, VhostValidator
│   └── Services/                      # Protocols for testability
├── Caddy/
│   ├── CaddyConfigBuilder.swift
│   ├── CaddyAdapter.swift
│   ├── CaddyAdminClient.swift
│   ├── CaddyProcessController.swift
│   ├── CaddyInstallation.swift        # locate / version
│   └── CaddyInstaller.swift           # brew + GitHub download
├── Privileged/
│   ├── HelperClient.swift
│   ├── HelperInstaller.swift          # SMAppService register / approval UX
│   └── (protocol lives in Shared/)
├── Networking/
│   ├── LocalDNSResponder.swift        # UDP responder for wildcards
│   └── HealthCheckService.swift
├── Certificates/
│   ├── CertificateStatusChecker.swift # fingerprint-based status
│   ├── CertificateTrustInstaller.swift# GUI SecTrustSettings install
│   └── MobileCertShareServer.swift    # optional QR share
├── Persistence/
│   └── VhostStore.swift               # vhosts.json + regenerateAndReload orchestration
├── Features/
│   ├── Onboarding/                    # multi-step Setup wizard
│   ├── MenuBar/
│   ├── Vhosts/
│   ├── Logs/
│   ├── DockerCompose/
│   └── Settings/
└── Support/
    ├── AppLog.swift
    └── AppWindowPresenter.swift

CaddockHelper/
├── main.swift
├── HelperTool.swift
├── HelperListenerDelegate.swift       # code-signing check on XPC peer
├── PFRedirectManager.swift
├── HostsFileManager.swift
├── ResolverManager.swift
└── HelperStateStore.swift             # persist ports / domains for boot reapply

Shared/
├── HelperProtocol.swift
└── HelperConstants.swift

LaunchDaemonPlist/
└── dev.mahmudz.Caddock.Helper.plist

scripts/
└── release.sh
```

**Design principle:** Anything that shells out, talks XPC, or touches `/etc` sits behind a small protocol so `CaddyConfigBuilder` and `VhostValidator` are pure and unit-tested.

---

## 3. Identity & constants

```
App bundle ID:     dev.mahmudz.Caddock
Helper bundle ID:  dev.mahmudz.Caddock.Helper
Mach service:      dev.mahmudz.Caddock.Helper
Launchd label:     dev.mahmudz.Caddock.Helper
Daemon plist name: dev.mahmudz.Caddock.Helper.plist
pf anchor name:    dev.mahmudz.Caddock
DNS listen port:   53535
```

LaunchDaemon plist essentials:

- `Label` = launchd label  
- `BundleProgram` = `Contents/MacOS/CaddockHelper`  
- `MachServices` = `{ "dev.mahmudz.Caddock.Helper": true }`  
- `AssociatedBundleIdentifiers` = `["dev.mahmudz.Caddock"]`

XPC accept policy: require peer code signature with identifier `dev.mahmudz.Caddock`. Prefer also verifying Team ID / Developer ID when practical.

---

## 4. Domain model

### 4.1 Vhost

```swift
struct Vhost: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case staticSite
        case phpSite
        case reverseProxy
    }

    var id: UUID
    var domain: String                 // e.g. myapp.test or *.myapp.test
    var aliases: [String]              // extra hostnames, same site block
    var kind: Kind
    var documentRoot: String?          // static + php
    var phpSocketPath: String?         // php — unix path or host:port
    var proxyTarget: String?           // proxy — e.g. 127.0.0.1:3000
    var sslEnabled: Bool               // default true
    var isEnabled: Bool                // default true; disabled = omitted from Caddyfile
    var compressionEnabled: Bool       // default true → encode gzip
    var indexFiles: String?            // nil = kind default
    var websocketEnabled: Bool         // proxy default true
    var preserveHostHeader: Bool       // proxy default false
    var forwardProxyHeaders: Bool      // proxy default true
    var logSource: VhostLogSource      // none | file(path) | docker(container)
}
```

**Validation (central `VhostValidator`):**

- Domain lowercase, no whitespace, valid hostname; wildcards only as `*.label.tld` on primary domain (not aliases).
- Block public TLDs for local use (com/net/org/…); warn on `.local` (Bonjour); prefer `.test` / `.localhost` / `.example`.
- Unique domains across primary + aliases.
- Kind-specific required/forbidden fields.
- PHP socket: warn (not hard-fail) if not accepting connections — use real `connect()` probe for unix/TCP, **not** `FileManager.fileExists` alone.
- Proxy target shape sanity check.

### 4.2 AppSettings (UserDefaults)

| Key | Default | Purpose |
|---|---|---|
| `caddyBinaryPathOverride` | nil | Custom / downloaded binary |
| `httpPort` | 8880 | Caddy HTTP bind |
| `httpsPort` | 8843 | Caddy HTTPS bind |
| `adminPort` | 2019 | Admin API |
| `launchAtLogin` | false | `SMAppService.mainApp` |
| `hasTrustedCaddyCA` | false | Cache only — never sole source of truth |
| `clearLogsOnRestart` | false | Truncate caddy.log on stop→start |
| `hasCompletedSetup` | false | Setup wizard finished |

Rename from `hasCompletedCaddyOnboarding` if rebuilding — setup is multi-step now.

### 4.3 Persistence paths

| Data | Path |
|---|---|
| Vhosts | `~/Library/Application Support/Caddock/vhosts.json` |
| Generated Caddyfile | `~/Library/Application Support/Caddock/Caddy/Caddyfile` |
| Managed Caddy binary | `~/Library/Application Support/Caddock/bin/caddy` |
| Caddy process log | `~/Library/Logs/Caddock/caddy.log` |
| App log | `~/Library/Logs/Caddock/app.log` |
| Caddy PKI root | `~/Library/Application Support/Caddy/pki/authorities/local/root.crt` |
| Helper persisted state | `/Library/Application Support/Caddock/HelperState.json` |
| pf anchor | `/etc/pf.anchors/dev.mahmudz.Caddock` |

Atomic writes for JSON/Caddyfile. Import/export format: `.caddock` (JSON array of vhosts).

---

## 5. Caddy integration

### 5.1 Binary location order

1. User override (if executable)  
2. `/opt/homebrew/bin/caddy`  
3. `/usr/local/bin/caddy`  
4. Managed download path  
5. `/usr/bin/which caddy`

### 5.2 Install methods (setup + Settings)

1. **Homebrew:** `brew install caddy` (in-app Process with proper `PATH`, or open Terminal). Detect brew at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`.
2. **Official download:** GitHub Releases via **API asset endpoint**  
   `GET https://api.github.com/repos/caddyserver/caddy/releases/assets/{id}`  
   with `Accept: application/octet-stream`  
   (Do **not** rely only on `browser_download_url` → `github.com`; that fails from some GUI/network environments.)  
   Fallback: `/usr/bin/curl -L`. Extract `tar.gz`, `chmod +x`, clear quarantine xattr, verify `caddy version`. Store under Application Support `bin/caddy` and set override.

### 5.3 Lifecycle

| Action | Behavior |
|---|---|
| Start | If admin reachable → adapt + `POST /load`; else `caddy run --config <Caddyfile> --adapter caddyfile` |
| Reload | adapt + `POST /load` |
| Stop | `POST /stop` if reachable + terminate process |
| Status | Process monitor + admin `/config/` reachability |

Redirect Caddy stdout/stderr to `caddy.log`. Optionally clear log when restarting if setting enabled.

### 5.4 Caddyfile rules

**Global options:**

```caddyfile
{
    http_port 8880
    https_port 8843
    admin 127.0.0.1:2019
}
```

**Per enabled vhost:**

- SSL on → site addresses = domains; include `tls internal`
- SSL off → each address `http://domain` (no TLS)
- Static: `root *`, optional `encode gzip`, `file_server { index … }`
- PHP: same + `php_fastcgi unix/<abs-path>` or TCP target
- Proxy: `reverse_proxy` with optional websocket flush/timeouts, `header_up Host`, `X-Forwarded-*`

Only enabled vhosts are emitted. Aliases share one site block.

### 5.5 Example blocks

```caddyfile
myproject.test, www.myproject.test {
    tls internal
    encode gzip
    root * /Users/dev/Sites/myproject/public
    php_fastcgi unix//opt/homebrew/var/run/php/php8.3.sock
    file_server {
        index index.html index.php
    }
}

api.test {
    tls internal
    reverse_proxy 127.0.0.1:3000 {
        flush_interval -1
        transport http {
            read_timeout 0
            write_timeout 0
        }
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
        header_up X-Real-IP {remote_host}
    }
}

http://plain.test {
    root * /Users/dev/Sites/plain
    file_server
}
```

---

## 6. Privileged helper (XPC)

### 6.1 Protocol

```objc
@objc protocol HelperProtocol {
    func getVersion(reply: (String) -> Void)
    func installPFRedirect(httpPort: Int, httpsPort: Int, reply: (Bool, String?) -> Void)
    func removePFRedirect(reply: (Bool, String?) -> Void)
    func syncHosts(domains: [String], reply: (Bool, String?) -> Void)
    func removeHosts(reply: (Bool, String?) -> Void)
    func syncResolvers(tlds: [String], dnsPort: Int, reply: (Bool, String?) -> Void)
    func removeResolvers(reply: (Bool, String?) -> Void)
    func uninstallAll(reply: (Bool, String?) -> Void)
}
```

**Do not put Root CA trust on the helper for the primary UX path.** Trust must run in the GUI app so Security Agent can prompt. A helper trust API is optional/legacy only.

### 6.2 Behaviors

| API | Behavior |
|---|---|
| `installPFRedirect` | Write pf anchor, ensure `pfctl -e`, load anchor; persist ports for reboot |
| `syncHosts` | Marker-bounded block in `/etc/hosts` → `127.0.0.1\tdomain` for non-wildcard enabled hosts |
| `syncResolvers` | `/etc/resolver/<tld>` with `nameserver 127.0.0.1` + `port 53535` for wildcard TLDs |
| `uninstallAll` | Remove pf + hosts + resolvers + state file |

On helper launch: start XPC listener, then reapply persisted pf/hosts/resolvers (reboot recovery).

### 6.3 SMAppService approval UX (critical)

`SMAppService.daemon.register()` **does not show a password dialog**. Status becomes `.requiresApproval` until the user enables the item in:

**System Settings → General → Login Items & Extensions → Background Items → Caddock**

Required UX:

1. Call `register()`.
2. If status is `.requiresApproval` **or** register throws “not permitted” / SMAppService approval errors → treat as approval-needed (not a hard failure).
3. Present a **modal alert** (do **not** auto-jump to Settings first — that steals focus from the alert):
   - Title: “Enable Privileged Helper”
   - Message: explain Background Items path
   - Buttons: **Open Login Items Settings** → `SMAppService.openSystemSettingsLoginItems()`, **Later**
4. Keep a **Check Again** action; on app `didBecomeActive`, refresh status and continue if `.enabled`.
5. Never disable the only CTA while waiting for approval.

### 6.4 When to sync privileged networking

Call sync after: helper enable, Caddy reload, ports change, vhost domain set change, app launch (with retries ~30s — helper may not be ready immediately after reboot).

---

## 7. Certificates & HTTPS trust (rebuild carefully)

### 7.1 Correct status algorithm (fixes real bug)

**Bug in prior app:** after `caddy untrust` + Keychain delete, UI could still show “Installed and Trusted” because it accepted *any* certificate summary containing “Caddy Local Authority”, or mismatched file vs trust store. Browser then failed.

**Required algorithm:**

1. Read current `root.crt` from Caddy PKI path. If missing → `.notInstalled`.
2. Parse to `SecCertificate`; compute SHA-256 fingerprint of **this** cert.
3. Check trust settings for **that exact certificate** in `.user` and `.admin` domains (`SecTrustSettingsCopyTrustSettings`).
4. Optionally verify SecTrust evaluation for a sample local HTTPS host.
5. Status:
   - file missing → Not Installed  
   - file present, not trusted → Installed, Not Trusted  
   - file present + trusted → Installed and Trusted  

**Never** treat “some other Caddy Local Authority exists” as proof the **current** CA is trusted.

### 7.2 Install Root CA (GUI process only)

1. Ensure Caddy has run with at least one TLS site so `root.crt` exists (start/reload with a temp or real SSL vhost if needed).
2. Flip activation policy to `.regular` and activate app so Security Agent sheets work (menu bar accessory cannot present auth UI otherwise).
3. `SecTrustSettingsSetTrustSettings` for **user** domain with `trustRoot`.
4. Best-effort System keychain via `/usr/bin/security add-trusted-cert` **without** osascript elevation.
5. Refresh status using fingerprint algorithm; set `hasTrustedCaddyCA` cache only if truly trusted.
6. Restore accessory policy when no windows remain.

### 7.3 Open Keychain Access (fixes real bug)

Do **not** rely only on filesystem paths that break across macOS versions.

Preferred:

```swift
NSWorkspace.shared.openApplication(
    at: URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"),
    configuration: NSWorkspace.OpenConfiguration()
)
// Fallback: bundle identifier
let conf = NSWorkspace.OpenConfiguration()
NSWorkspace.shared.openApplication(at: /* URL from NSWorkspace.urlForApplication(withBundleIdentifier: "com.apple.keychainaccess") */, configuration: conf)
```

Handle failure with a user-visible error. On newer macOS, Keychain Access may also be opened via Spotlight URL schemes if needed — verify on target OS.

### 7.4 Untrust / repair UX

Provide in Certificates settings:

- Refresh (recompute fingerprint status)
- Install / Re-install Root CA
- Open Keychain Access
- Clear guidance when status is Not Trusted after manual untrust

If user ran `caddy untrust`, status must flip away from Trusted after Refresh. Re-install must re-trust the **current** `root.crt`.

### 7.5 Optional: mobile share

Temporary local HTTP server serving `root.crt` + QR code for phones on same LAN. Stop when pane disappears.

---

## 8. Local DNS

| Case | Mechanism |
|---|---|
| Normal domain (`app.test`) | Helper writes `/etc/hosts` → `127.0.0.1 app.test` |
| Wildcard (`*.app.test`) | Helper writes `/etc/resolver/test` (or TLD) pointing to `127.0.0.1:53535`; app runs `LocalDNSResponder` answering A records with `127.0.0.1` |

Browser URL helper: with helper enabled, omit non-standard ports for 80/443 UX; without helper, include `:httpPort` / `:httpsPort`.

---

## 9. Setup wizard (first launch)

Gate: `hasCompletedSetup == false` **or** Caddy binary missing → show Setup window; **do not insert menu bar** until finished (`MenuBarExtra(isInserted:)`).

Window style:

```swift
WindowGroup("Setup", id: "setup") {
    SetupWizardView()
        .containerBackground(.thinMaterial, for: .window)
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
.defaultLaunchBehavior(setupComplete ? .suppressed : .presented)
```

Closing setup before completion **quits** the app (`applicationShouldTerminateAfterLastWindowClosed` when incomplete).

### Steps

1. **Caddy** — Homebrew | Download side by side; Install / Continue; start Caddy after success.  
2. **Privileged Helper** — Enable (skippable); approval alert with Open Login Items Settings.  
3. **HTTPS Trust** — Install Root CA (skippable); mint CA by starting Caddy if needed.  
4. **Ready** — Summary + Launch at Login toggle + **Get Started** → mark setup complete, insert menu bar, start services.

Navigation: Back, Skip (helper/cert only), primary CTA. Progress capsules at top. Material glass; no custom NSWindow hacks.

---

## 10. UI surfaces

### 10.1 Menu bar panel

- Caddy status + start/stop toggle  
- Last error / helper sync error  
- New Vhost, Manage Vhosts  
- Search + list of enabled vhosts (open in browser, site logs)  
- Import / Export  
- Docker Compose inject  
- Logs, Settings  
- Install Caddy… if binary missing  
- Quit  

### 10.2 Windows

- Vhosts list (filter all/enabled/disabled, CRUD)  
- Vhost editor (content-sized)  
- Global logs  
- Per-site logs (`WindowGroup` by vhost id)  
- Docker Compose injector  
- Setup wizard  

### 10.3 Settings tabs

1. **General** — Caddy detect/version, custom path, Install Caddy…, Launch at Login, Clear logs on restart  
2. **Ports** — HTTP / HTTPS / Admin (1024–65535); changing ports must trigger Caddy reload **and** pf reinstall if helper enabled  
3. **Certificates** — status, install, Keychain Access, Firefox note, mobile QR  
4. **Advanced** — Privileged helper enable/disable/reinstall + approval alert  
5. **About** — version  

Use grouped Form style consistent with macOS Settings.

---

## 11. Secondary features

### Health checks

Periodic (~30s):

- Reverse proxy: probe backend target  
- Static/PHP: `HEAD http://127.0.0.1:<httpPort>/` with `Host: domain`  
- Wildcards: may remain unknown  

Show status in menu/list (healthy / failing / unknown).

### Docker Compose inject

Parse compose services (pragmatic YAML is OK if documented; prefer a small YAML lib if rebuild). Write `docker-compose.override.yml` injecting:

- `extra_hosts: ["domain:host-gateway"]`  
- Mount/copy of root CA for container trust  

### Site logs

- File tail of a path, or  
- `docker logs -f <container>`  

### Logging

Central app logger to `app.log` + OSLog categories. Never log secrets.

---

## 12. App lifecycle

```
Launch
  ├─ binary missing OR !hasCompletedSetup
  │    → activationPolicy .regular
  │    → present Setup (menu bar not inserted)
  │    → close window ⇒ quit
  └─ setup complete
       → activationPolicy .accessory
       → insert MenuBarExtra
       → start health checks
       → regenerateAndReload Caddy
       → if helper enabled: ensurePrivilegedNetworking with retries
```

`finishSetup()`:

1. Persist `hasCompletedSetup = true`  
2. Insert menu bar  
3. Enter accessory mode  
4. Start Caddy + privileged sync  

Opening any real window may temporarily use `.regular` then hide Dock icon when no windows remain.

---

## 13. Concurrency & quality bar

- `@MainActor` for UI and store orchestration.  
- Async/await for Process, URLSession, XPC wrappers.  
- `@Observable` for shared state (Settings, Store, ProcessController, HelperInstaller, SetupGate).  
- No force-unwraps in production paths.  
- User-facing errors are short and actionable.  
- Unit test: `CaddyConfigBuilder`, `VhostValidator`, `LocalDomainPolicy`, cert fingerprint status helper.  
- Avoid God-objects: `VhostStore` orchestrates but does not own pf/hosts implementations.

---

## 14. Distribution

Script equivalent of current `scripts/release.sh`:

1. `xcodebuild archive` Release scheme `Caddock`  
2. Export / codesign Developer ID Application  
3. Build UDZO DMG: app + `/Applications` symlink → `dist/Caddock-<version>.dmg`  
4. `notarytool submit` + staple  
5. Flags: `--skip-notarize`, `--skip-sign`  

Prereqs: Developer ID cert, notary credentials profile.

---

## 15. Implementation order (recommended for agent)

1. Xcode project, bundle IDs, no sandbox, helper target + plist embed  
2. Models + `VhostStore` persistence + validator + domain policy  
3. `CaddyConfigBuilder` + tests  
4. `CaddyInstallation` / process controller / admin client / adapt  
5. Menu bar + vhost list/editor + start/stop/reload  
6. Settings: General + Ports  
7. Shared protocol + helper: hosts, pf, resolvers + client  
8. HelperInstaller + approval alert UX  
9. LocalDNSResponder + wire sync into store  
10. Certificates: fingerprint status + GUI trust installer + Keychain open  
11. Setup wizard gating menu bar  
12. Logs, health, Docker inject, import/export  
13. `release.sh` + smoke test on clean Mac  

---

## 16. Known defects from the iteration codebase (must fix in rebuild)

| # | Defect | Correct behavior |
|---|---|---|
| 1 | Keychain Access button often does nothing | Open via bundle ID / modern `openApplication` API; surface errors |
| 2 | Cert UI says Trusted after `caddy untrust` / Keychain delete | Fingerprint-based status against **current** `root.crt` only |
| 3 | Trust status uses “any Caddy Local Authority” match | Match exact cert / fingerprint |
| 4 | Helper trust API vs GUI installer duplicated / unused | Single GUI trust path; delete or isolate helper trust |
| 5 | Approval approval feels stuck | Modal alert + Open Login Items; Check Again; don’t auto-open Settings before alert |
| 6 | GitHub `browser_download_url` fails in app | Use releases/assets API + curl fallback |
| 7 | PHP socket check via `fileExists` | Use unix/TCP connect probe |
| 8 | Ports change may not reinstall pf | Ports save → reload Caddy → `installPFRedirect` |
| 9 | Docs/README lag reality | Keep this SPEC as source of truth; trim aspirational README |
| 10 | No unit tests | Add for pure modules |
| 11 | Scheme not in repo | Commit shared xcscheme |
| 12 | Hardcoded CA CN years in helper delete list | Prefer fingerprint / dynamic CN from `root.crt` |

---

## 17. Acceptance checklist

- [ ] Fresh Mac: Setup wizard appears; menu bar hidden until Get Started  
- [ ] Install Caddy via Download and via Homebrew  
- [ ] Create static, PHP, and reverse-proxy vhosts; hot reload works  
- [ ] SSL on → HTTPS with internal CA; SSL off → http:// site  
- [ ] Enable helper → Login Items alert → approve → `https://myapp.test` works on 443  
- [ ] `/etc/hosts` updates when enabling/disabling/renaming domains  
- [ ] Wildcard `*.app.test` resolves via resolver + local DNS  
- [ ] Install Root CA → Safari/Chrome accept without warning  
- [ ] `caddy untrust` + delete from Keychain → UI shows Not Trusted after Refresh; Re-install fixes browser  
- [ ] Open Keychain Access button opens the app  
- [ ] Disable helper / uninstall cleans pf + hosts markers  
- [ ] Launch at login works  
- [ ] Notarized DMG installs and runs Gatekeeper-clean  
- [ ] Quit from menu; setup-close-before-finish quits  

---

## 18. Reference behavior (from prior implementation)

Use as behavioral reference only — **do not copy structure blindly**:

- Repo path: this project’s `Caddock/` + `CaddockHelper/` + `Shared/`  
- Release: `scripts/release.sh`  
- Prior README architecture table still valid for *decisions* (high ports, helper, Caddyfile+adapt)  

When uncertain, prefer this SPEC over old code.

---

## 19. Agent instructions (copy into the prompt)

```
Rebuild Caddock as a new clean macOS project following REBUILD_SPEC.md exactly.

Rules:
- One global Caddy process; Caddyfile → adapt → admin /load
- No App Sandbox; SMAppService privileged helper for pf/hosts/resolvers
- Certificate trust in GUI process; fingerprint-based status
- Setup wizard gates menu bar; helper approval uses alert with Open Login Items Settings
- Prefer macOS 14+, SwiftUI MenuBarExtra, @Observable, async/await
- Unit-test CaddyConfigBuilder and VhostValidator
- Commit shared scheme; provide release.sh for Developer ID + notarized DMG
- Do not port dead code paths (helper caddy-trust via sudo, FileManager socket checks, path-only Keychain open)

Work in the implementation order in §15. Stop after each major milestone for a build check.
```
