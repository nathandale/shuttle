# Shuttle

A macOS menu bar SSH address book. Click the icon, connect to a server. No terminal juggling, no remembering hostnames.

Built for macOS 12+ as a Universal Binary (native on Apple Silicon and Intel).

---

## What It Does

Shuttle lives in your menu bar as a small icon. Click it and you get an organized list of your SSH servers, grouped by category. Click a server and it opens a terminal session — no typing, no copy-pasting, no `~/.ssh/config` hunting.

It also scans your local network for hosts with SSH open, lets you browse and connect to them, and lets you save discoveries directly into your address book with one click.

---

## Features

### SSH Address Book
- Store servers with a display name, hostname (or `.local` name or IP), username, port, SSH key, and category
- Servers are grouped under user-defined categories (e.g. LOCAL SERVERS, REMOTE SERVERS, PRODUCTION, etc.)
- All data lives in a simple JSON file at `~/.shuttle.json` — human-readable, version-controllable, easy to share

### Manager Window
Accessible from **Settings → Manager…** in the menu bar. A native macOS split-view window modelled after Contacts.app:

- **Left sidebar** — translucent sidebar with category group headers and server rows. `+`/`−` segmented control to add or remove servers. **New Category** button to create groupings.
- **Right detail pane** — form with Name, Hostname, User, Port, SSH Key picker (auto-populated from `~/.ssh/`), Category, and Terminal override. Save with Return or the Save button. Delete with confirmation.
- Changes are written to `~/.shuttle.json` immediately and the menu bar refreshes automatically.

### Multi-Terminal Support
Shuttle detects which terminal apps are installed on your machine at launch time using macOS Launch Services — it only shows you what you actually have. Supported terminals:

| Terminal | How it opens |
|---|---|
| Terminal.app | AppleScript — runs in existing front window, no duplicate windows |
| iTerm2 | AppleScript — new window with default profile |
| Ghostty | `NSWorkspace` + `sh -c` — no App Management privacy prompts |
| Alacritty | `NSWorkspace` + `sh -c` |
| kitty | `NSWorkspace` + `sh -c` |
| Warp | URL scheme (`warp://action/new_tab?command=…`) |
| Hyper | `NSWorkspace` + `sh -c` |
| Rio | `NSWorkspace` + `sh -c` |

The global default terminal is set in `~/.shuttle.json` with the `"terminal"` key. Individual servers can override it with their own `"terminal"` field — useful when you want most servers in Terminal.app but specific ones in Ghostty.

### Per-Server SSH Key
Each server can specify an SSH identity file. The key is picked from a dropdown populated from your `~/.ssh/` directory — only real private key files are shown (`.pub` files, `known_hosts`, `config`, and `authorized_keys` are excluded). The path is stored and expanded correctly — no tilde issues.

### LAN SSH Scanner
Shuttle can scan your local `/24` subnet for hosts with port 22 open:

- Runs an async parallel sweep using GCD with up to 50 concurrent probes (300ms timeout per host)
- Simultaneously runs an `NSNetServiceBrowser` search for `_ssh._tcp.` Bonjour/mDNS services — this finds `.local` hostnames (Macs, Raspberry Pis running `avahi-daemon`, NAS devices, etc.) without needing an IP sweep
- After the port scan, each discovered IP gets a reverse DNS lookup (`getnameinfo`) to resolve its hostname
- Results from both sources are merged and deduplicated by hostname
- Displayed sorted by last octet of IP address (`.1`, `.2` … `.254`)
- Bonjour-only entries (hostname known, IP not yet resolved) appear at the bottom

Each discovered host shows as a submenu with two options:
- **Connect** — opens an SSH session immediately
- **Save to Address Book…** — prompts for a display name and category, then writes the server to `~/.shuttle.json`

The submenu also shows how long ago the scan ran and a **Scan Now** option to re-scan on demand. The first scan triggers automatically when you open the menu for the first time.

### Import / Export
- **Settings → Import** — choose a `.json` file to replace your current config. The current config is backed up first; if the import fails, it is automatically restored.
- **Settings → Export** — save your current `~/.shuttle.json` to any location with a file picker. Defaults to `shuttle.json`.

---

## Configuration

Shuttle uses `~/.shuttle.json`. On first launch, a default file is created automatically.

### Full example

```json
{
  "terminal": "ghostty",
  "editor": "default",
  "launch_at_login": false,
  "show_ssh_config_hosts": false,
  "categories": [
    "LOCAL SERVERS",
    "REMOTE SERVERS",
    "PRODUCTION"
  ],
  "servers": [
    {
      "name": "Web Dev",
      "hostname": "wp-dev.local",
      "user": "nathandale",
      "identity_file": "~/.ssh/id_ed25519",
      "category": "LOCAL SERVERS",
      "terminal": "ghostty"
    },
    {
      "name": "Production DB",
      "hostname": "db1.example.com",
      "user": "deploy",
      "port": 2222,
      "identity_file": "~/.ssh/prod_key",
      "category": "PRODUCTION"
    }
  ]
}
```

### Keys

| Key | Values | Description |
|---|---|---|
| `terminal` | `terminal`, `iterm`, `ghostty`, `alacritty`, `kitty`, `warp`, `hyper`, `rio` | Default terminal for all connections |
| `editor` | `default`, `nano`, `vi`, etc. | Editor used by Settings → Edit |
| `launch_at_login` | `true` / `false` | Start Shuttle when you log in |
| `show_ssh_config_hosts` | `true` / `false` | Show hosts from `~/.ssh/config` in the menu (legacy mode) |
| `categories` | array of strings | Category names, in display order |
| `servers` | array of server objects | Your address book entries |

### Server object keys

| Key | Required | Description |
|---|---|---|
| `name` | yes | Display name shown in the menu |
| `hostname` | yes | Hostname, `.local` mDNS name, or IP address |
| `user` | no | SSH username |
| `port` | no | SSH port (omit for default 22) |
| `identity_file` | no | Path to private key, e.g. `~/.ssh/id_ed25519` |
| `category` | yes | Must match an entry in `categories` |
| `terminal` | no | Per-server terminal override — takes precedence over global setting |

---

## Building from Source

Requires Xcode 14+ on macOS 12 Monterey or later.

```bash
git clone https://github.com/nathandale/shuttle.git
cd shuttle
xcodebuild -scheme Shuttle -configuration Release build
```

The built app lands at:
```
~/Library/Developer/Xcode/DerivedData/Shuttle-*/Build/Products/Release/Shuttle.app
```

The app is a Universal Binary — runs natively on both Apple Silicon (arm64) and Intel (x86_64). Deployment target is macOS 12.0.

---

## How It Differs from the Original

This fork of [fitztrev/shuttle](https://github.com/fitztrev/shuttle) is a significant rewrite:

| | Original | This Fork |
|---|---|---|
| Architecture | x86_64 only | Universal Binary (arm64 + x86_64) |
| macOS target | 10.8 | 12.0 |
| Terminal launching | AppleScript `.scpt` files | `NSWorkspace` + AppleScript one-liners |
| Terminal selection | Hardcoded | Detected at runtime via Launch Services |
| Config format | Recursive `hosts` tree | Flat `servers` + `categories` arrays |
| Server management | Hand-edit JSON only | Native Manager window |
| LAN discovery | None | Bonjour/mDNS + port-22 sweep + reverse DNS |
| SSH key selection | Manual in JSON | Dropdown from `~/.ssh/` |
| Per-server terminal | Not supported | Supported |

---

## Credits

Originally created by [Trevor Fitzgerald](https://github.com/fitztrev) and contributors.
Forked and rewritten by Nathan Dale with Claude Code.

Inspired by [SSHMenu](http://sshmenu.sourceforge.net/) for Linux.
