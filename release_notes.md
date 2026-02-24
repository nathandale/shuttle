## [1.4.0] - 2026-02-24
### Added
- **Major Rewrite**: Rebuilt for modern macOS (12+) as a Universal Binary (arm64 + x86_64).
- **SSH Manager**: New native split-view window to manage servers and categories without editing JSON manually.
- **LAN Scanner**: Subnet scanner (GCD-based) and Bonjour/mDNS discovery for local SSH hosts.
- **Modern Terminal Support**: Native support for Ghostty, Alacritty, kitty, Warp, Rio, and Hyper.
- **Improved Terminal Launching**: 
  - Fixed "App Management" privacy prompts by using `NSAppleScript` instead of `osascript` sub-processes.
  - Improved grouping in the Dock for Ghostty and other third-party terminals using `NSWorkspace`.
- **Per-Server Settings**: Ability to override the terminal and specify an initial directory on a per-host basis.

### Changed
- Migrated configuration to a flat `servers` + `categories` JSON structure for easier management.
- Updated "About" window with new repository links and attribution.

