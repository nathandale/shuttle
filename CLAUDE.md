# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Shuttle** is a native macOS menu bar app (Objective-C/Cocoa) that acts as an SSH address book and local network scanner. It lives in the menu bar with no Dock icon. The app is a Universal Binary (arm64 + x86_64) targeting macOS 12+.

## Build

```bash
xcodebuild -scheme Shuttle -configuration Release build
```

Output lands in `~/Library/Developer/Xcode/DerivedData/Shuttle-*/Build/Products/Release/Shuttle.app`.

There is no automated test suite — testing is manual. Test fixtures are in `tests/` (sample JSON config, SSH config files).

## Architecture

All meaningful logic lives in two files:

- **`Shuttle/AppDelegate.m`** (~1,100 lines) — the entire application core:
  - Config loading/watching (`~/.shuttle.json`)
  - Menu bar construction
  - Terminal detection via `NSWorkspace`/Launch Services
  - SSH command generation and terminal launching
  - LAN scanner (GCD parallel port-22 sweep + Bonjour/mDNS via `NSNetServiceBrowser`)

- **`Shuttle/ServerManagerWindowController.m`** (~400 lines) — the "SSH Manager" split-view window:
  - Left sidebar: `NSOutlineView` with categories as group headers and servers as children
  - Right pane: form for editing server fields
  - Writes changes back to `~/.shuttle.json` and triggers a menu reload via AppDelegate

Supporting files: `AboutWindowController`, `LaunchAtLoginController`, `MainMenu.xib`, `AboutWindowController.xib`.

## Configuration Schema

The user config lives at `~/.shuttle.json`. The modern format:

```json
{
  "terminal": "ghostty",
  "editor": "default",
  "launch_at_login": false,
  "show_ssh_config_hosts": false,
  "categories": ["Work", "Personal"],
  "servers": [
    {
      "name": "My Server",
      "hostname": "example.com",
      "user": "admin",
      "port": 22,
      "identity_file": "~/.ssh/id_ed25519",
      "category": "Work",
      "terminal": "iterm"
    }
  ]
}
```

The default config template is at `Shuttle/shuttle.default.json`.

## Terminal Support

Terminals are detected at runtime by querying Launch Services for bundle IDs (see `installedTerminals` in `AppDelegate.m`). Launching strategy varies by terminal:

- **Terminal.app, iTerm2**: AppleScript
- **Ghostty, Alacritty, kitty, Hyper, Rio**: `NSWorkspace openURL` + `sh -c` wrapper
- **Warp**: URL scheme (`warp://action/new_tab?command=…`)

Per-server terminal overrides are respected in `openHost:`.

## LAN Scanner

`scanLAN` runs 50 concurrent GCD async probes with a 300ms timeout per IP across the local subnet. Results are merged with Bonjour (`_ssh._tcp.`) discoveries, reverse-DNS resolved, deduplicated by hostname, and sorted by last IP octet. Results are cached until the user triggers "Scan Now".
