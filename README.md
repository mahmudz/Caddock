## 1. Key Architecture Decisions (read before changing behavior)

These are the default choices baked into the rest of this doc. If you disagree with one, change it here first so downstream sections stay consistent.

| Decision | Choice | Why |
|---|---|---|
| Caddy config format sent to Caddy | Author a human-readable **Caddyfile**, shell out to `caddy adapt` to get JSON, then `POST` that JSON to the **admin API** (`/load`) | Caddyfile directives like `php_fastcgi` and `tls internal` are far easier to generate correctly than hand-rolled JSON, but the admin API gives atomic, zero-downtime reloads that reloading via SIGHUP/CLI restart doesn't. Best of both. |
| Binding ports 80/443 | Caddy binds **non-privileged high ports** (e.g. `127.0.0.1:8880` / `127.0.0.1:8843`); a `pf` anchor redirects 80→8880 and 443→8843 | macOS has no `setcap`; running Caddy itself as root is riskier and complicates start/stop from a per-user menu bar app. This is the same trick Laravel Valet uses. `pf` rule installation is the one thing that needs root, and it's a one-time setup step. |
| Privileged operations (`pf` rules, `/etc/hosts` edits, installing `caddy trust`'s CA) | A separate **privileged helper tool** installed via `SMAppService.daemon`, talked to over **XPC** | Keeps the main app un-privileged. Ask once via `SMAppService`/`Authorization Services` prompt, not a `sudo` shell-out per action. |
| Local DNS resolution for custom domains | **MVP:** explicit `/etc/hosts` entries per vhost domain, added/removed by the helper. **Later:** `/etc/resolver/<tld>` + a tiny local DNS responder for wildcard `*.test` support | Hosts-file entries are simplest to implement and reason about; wildcard resolver is a nice v2 upgrade, not required for MVP. |
| Caddy binary source | **MVP:** detect an existing install (`/opt/homebrew/bin/caddy`, `/usr/local/bin/caddy`, or `which caddy`) and prompt `brew install caddy` if missing. **Later:** bundle a signed/notarized `caddy` binary inside the app | Avoids embedded-binary code-signing/notarization complexity for a first version. |
| HTTPS in dev | `tls internal` directive → Caddy's own internal CA. Root cert trust installed once via `caddy trust` (run through the privileged helper) | Caddy will not successfully request a public ACME cert for made-up TLDs like `.test`; `tls internal` is the correct tool. |
| SSL-disabled vhosts | Site address prefixed with `http://` in the Caddyfile (e.g. `http://plain.test`) | Prefixing with the scheme tells Caddy not to attempt automatic HTTPS for that site at all. |

---

## 2. Domain Model

```swift
struct Vhost: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case staticSite    // file_server only
        case phpSite       // file_server + php_fastcgi over a unix socket
        case reverseProxy  // reverse_proxy to a local host:port
    }

    var id: UUID = UUID()
    var domain: String            // e.g. "myproject.test"
    var kind: Kind
    var documentRoot: String?     // required for .staticSite / .phpSite
    var phpSocketPath: String?    // required for .phpSite, e.g. "/opt/homebrew/var/run/php/php8.3.sock"
    var proxyTarget: String?      // required for .reverseProxy, e.g. "127.0.0.1:3000"
    var sslEnabled: Bool = true
    var isEnabled: Bool = true    // included in generated config only if true
}
```

Validation rules worth enforcing centrally (in a `VhostValidator`):

- `domain` is non-empty, lowercase, no whitespace, resolves to a single label chain (basic hostname shape check)
- No two vhosts share the same `domain`
- `documentRoot` / `phpSocketPath` / `proxyTarget` presence is required/forbidden based on `kind`
- `phpSocketPath` should exist on disk at save time (warn, don't hard-block — the socket may not exist yet if PHP-FPM isn't running)

---

## 3. Proposed Project Structure

```
CaddyHost/
├── CaddyHost.xcodeproj
├── CaddyHost/
│   ├── App/
│   │   ├── CaddyHostApp.swift          # @main, MenuBarExtra scene
│   │   └── AppDelegate.swift           # lifecycle hooks, login item registration
│   ├── Models/
│   │   ├── Vhost.swift
│   │   └── AppSettings.swift
│   ├── Stores/
│   │   └── VhostStore.swift            # @Observable; loads/saves vhosts.json
│   ├── CaddyKit/                       # consider extracting as a local SPM package for testability
│   │   ├── CaddyConfigBuilder.swift    # [Vhost] -> Caddyfile text
│   │   ├── CaddyAdapter.swift          # shells out to `caddy adapt`
│   │   ├── CaddyAdminClient.swift      # talks to :2019 admin API (/load, /stop, /config/)
│   │   ├── CaddyProcessController.swift# Process spawn/stop/monitor + stdout/stderr capture
│   │   └── CaddyInstallation.swift     # locate binary, version check, `caddy trust`
│   ├── System/
│   │   ├── HostsFileManager.swift      # requests /etc/hosts edits via helper
│   │   ├── PortForwarder.swift         # requests pf anchor install via helper
│   │   └── PrivilegedHelper/
│   │       ├── HelperProtocol.swift    # shared XPC protocol
│   │       └── HelperClient.swift      # app-side XPC connection
│   ├── Views/
│   │   ├── MenuBarView.swift
│   │   ├── VhostListView.swift
│   │   ├── VhostEditorView.swift
│   │   ├── LogsView.swift
│   │   └── SettingsView.swift
│   └── Resources/
├── CaddyHostHelper/                    # separate target: SMAppService daemon
    └── HelperTool.swift                # implements HelperProtocol, runs as root
```

Design principle: everything that touches the filesystem/network/subprocesses in a way that's hard to unit test (`Process`, XPC, `pf`, `/etc/hosts`) sits behind a small protocol so `CaddyConfigBuilder` and `VhostValidator` can be tested in pure isolation.

---

## 4. Caddy Integration Details

### 4.1 Generation flow

1. `CaddyConfigBuilder` turns the enabled `[Vhost]` into Caddyfile text.
2. Write it to `~/Library/Application Support/CaddyHost/Caddy/Caddyfile`.
3. Run `caddy adapt --config Caddyfile --adapter caddyfile --pretty` to get JSON.
4. `POST` that JSON to `http://127.0.0.1:2019/load` for an atomic, zero-downtime reload.
5. On very first launch (before Caddy is running at all), fall back to `caddy run --config Caddyfile --adapter caddyfile` to boot it.

### 4.2 Example generated Caddyfile blocks

PHP site:
```caddyfile
myproject.test {
    tls internal
    root * /Users/dev/Sites/myproject/public
    encode gzip
    php_fastcgi unix//opt/homebrew/var/run/php/php8.3.sock
    file_server
}
```

Static site:
```caddyfile
static.test {
    tls internal
    root * /Users/dev/Sites/static-site
    encode gzip
    file_server
}
```

Reverse proxy, SSL enabled:
```caddyfile
app.test {
    tls internal
    reverse_proxy 127.0.0.1:3000
}
```

Reverse proxy, SSL disabled:
```caddyfile
http://plain.test {
    reverse_proxy 127.0.0.1:3000
}
```

Global options block (once, at the top of the file) should set the non-privileged listen ports per §1:
```caddyfile
{
    http_port 8880
    https_port 8843
    admin 127.0.0.1:2019
}
```

### 4.3 Admin API reference

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/load` | Replace the entire running config atomically |
| `GET` | `/config/` | Read current running config |
| `POST` | `/stop` | Gracefully stop Caddy |
| `GET` | `/config/apps/http/servers/...` | Inspect a specific config subtree |

### 4.4 Useful CLI commands

```bash
# Validate a Caddyfile before adapting/loading it
caddy validate --config Caddyfile --adapter caddyfile

# Format in place
caddy fmt --overwrite Caddyfile

# Caddyfile -> JSON (what CaddyAdapter shells out to)
caddy adapt --config Caddyfile --adapter caddyfile --pretty

# First boot fallback
caddy run --config Caddyfile --adapter caddyfile

# Hot reload once already running
curl -X POST http://127.0.0.1:2019/load \
  -H "Content-Type: application/json" \
  -d @config.json

# Trust Caddy's local CA in the system keychain (avoids browser warnings)
caddy trust
```

---

## 5. Privileged Operations & Security

Operations that need root, all funneled through `CaddyHostHelper` (an `SMAppService.daemon`, registered from the app, communicating over an XPC `HelperProtocol`):

- Installing/removing the `pf` anchor that redirects 80→8880 and 443→8843
- Adding/removing lines in `/etc/hosts`
- Running `caddy trust` to install the local CA into the System keychain

Do **not** shell out to `sudo` or `osascript "with administrator privileges"` for repeated/ongoing operations — that re-prompts the user constantly and is a poor pattern for a background menu bar tool. Register the helper once via `SMAppService`, which handles the one-time authorization.

The main app process itself should never run as root and should not have the App Sandbox entitlement enabled (follow "Tech Stack & Target").

---

## 6. Persistence & File Locations

| Purpose | Path |
|---|---|
| Vhost definitions (source of truth) | `~/Library/Application Support/CaddyHost/vhosts.json` |
| Generated Caddyfile | `~/Library/Application Support/CaddyHost/Caddy/Caddyfile` |
| Last adapted/applied JSON config | `~/Library/Application Support/CaddyHost/Caddy/config.json` |
| Caddy stdout/stderr log | `~/Library/Logs/CaddyHost/caddy.log` |
| App preferences | `UserDefaults` |
| Privileged helper daemon | `/Library/LaunchDaemons/com.yourteam.caddyhost.helper.plist` (managed by `SMAppService`) |

Suggested bundle identifiers: `com.yourteam.caddyhost` (app), `com.yourteam.caddyhost.helper` (helper).

---

## 7. Build, Run & Test

```bash
# Build (Debug)
xcodebuild -project CaddyHost.xcodeproj -scheme CaddyHost -configuration Debug build
```

If `CaddyKit` is extracted into a local Swift package, its pure logic (`CaddyConfigBuilder`, `VhostValidator`) can also be run with plain `swift test` — prefer this for fast iteration on config-generation logic without booting the full app.

---

## 8. Coding Conventions

- SwiftUI for all UI; MVVM-ish — Views stay dumb, `@Observable` stores/view models hold state and call into `CaddyKit`/`System` layers
- Prefer `async/await` over completion handlers for `Process` execution and XPC calls
- No force-unwraps (`!`) outside of tests; surface failures as typed `Error`s and show them in the UI (Caddy not found, port conflict, invalid socket path, etc.)
- Logging via `os.Logger`, one subsystem per layer (`com.yourteam.caddyhost.caddykit`, `...system`, `...ui`)
- Anything that shells out to `caddy` or talks to the helper should go through a protocol, so it can be mocked in `CaddyConfigBuilderTests` / `VhostValidatorTests`

---

## 9. MVP Feature Checklist

- [ ] Add / edit / delete vhost (all three kinds)
- [ ] Toggle SSL per vhost
- [ ] Enable/disable a vhost without deleting it
- [ ] Generate Caddyfile, adapt, hot-reload on any change
- [ ] Detect missing Caddy install, prompt to `brew install caddy`
- [ ] Install `pf` redirect rules + `/etc/hosts` entries via helper on first run
- [ ] Run `caddy trust` once, surface success/failure in UI
- [ ] Start/stop Caddy from the menu bar; show running/stopped status
- [ ] Basic log viewer (tail `caddy.log`)
- [ ] Launch at login (`SMAppService.mainApp`)

**Not MVP** (explicitly deferred, see §1): wildcard `*.test` DNS via `/etc/resolver`, bundled Caddy binary, Mac App Store distribution.