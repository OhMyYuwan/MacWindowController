# WinCtlManager

WinCtlManager is a native macOS window layout manager for organizing visible windows, saving and restoring desktop layouts, and editing zones, stacks, and window routing through a visual Workbench.

This project is managed with **ACP — Agent Content Protocol** for request, plan, and change records.

[中文版](./README.md)

## Release v0.0.1

v0.0.1 is the first usable release. It focuses on basic window control, forced desktop zones, stack tab bars, saved layouts, and the visual Workbench.

### Highlights

- Basic window operations: list, move, resize, and tile app windows.
- Frontmost-window actions: tile the focused window or send it into the left stack.
- Desktop layouts: save, list, restore, import, export, and delete layouts.
- Forced zones: partition a desktop into zones and reassign windows by zone rules.
- Window stacks: group multiple windows in one zone into a tab-like stack with one active window.
- Visual Workbench: native AppKit UI for layout modes, split ratios, routing rules, temporary windows, and saved layouts.
- Stack tab styling: choose, preview, save, and apply Stack Tab GlassStyle variants.
- Uncontrollable-window handling: detect windows that should not be moved through AX operations and keep them out of forced layout flows.
- ACP-managed history: the project keeps `Request -> Plan -> Change` records for ongoing evolution.

## Requirements

- macOS 13 or later
- Swift Package Manager
- Accessibility permission: grant Accessibility access to the terminal or app that runs WinCtlManager before controlling windows

## Build

```bash
cd tools/window-manager
swift build
```

Run tests:

```bash
cd tools/window-manager
swift test
```

## Packaging Release

`scripts/release-macos.sh` now follows the same packaging pattern as TimeDiary:
- Reuse existing `dist/WinCtlManager.app`
- Build DMG from a temp folder containing `WinCtlManager.app` + `Applications` symlink
- Do not rebuild the app bundle during packaging
- Apply ad-hoc signing (`codesign -s -`) by default to prevent stale-signature “App is damaged” issues

Run:

```bash
cd /Volumes/DevLayer/WinCtlManager
scripts/release-macos.sh 0.0.2
```

Optional:

```bash
# Create git tag
scripts/release-macos.sh v0.0.2 --tag

# Use a custom app source
APP_SOURCE=/absolute/path/WinCtlManager.app scripts/release-macos.sh 0.0.2

# Optional signing
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/release-macos.sh 0.0.2
```

## Open Workbench

```bash
cd tools/window-manager
swift run window-manager open-workbench
```

Edit the current desktop directly:

```bash
swift run window-manager edit-current --name current_desktop
```

## Common CLI Commands

List windows:

```bash
swift run window-manager list-windows --all
```

Tile a specific window:

```bash
swift run window-manager tile-window --bundle-id com.google.Chrome --position left
```

Tile the currently focused window:

```bash
swift run window-manager tile-frontmost --position right
```

Save the current desktop layout:

```bash
swift run window-manager save-desktop --name work
```

Restore a desktop layout:

```bash
swift run window-manager apply-desktop --name work
```

Open and edit a saved layout:

```bash
swift run window-manager edit-desktop --name work
```

Show all commands:

```bash
swift run window-manager help
```

## Project Structure

```text
WinCtlManager/
├── tools/window-manager/        # Swift Package, CLI, and AppKit Workbench
├── src/.acp/                    # ACP project state and change records
├── acp-protocol/                # Read-only ACP protocol payload
├── AGENTS.md                    # Agent instructions
├── README.md                    # Chinese app README
└── README_EN.md                 # English app README
```

## Current Limits

- WinCtlManager controls third-party app windows through the macOS Accessibility API. It can move, resize, tile, and raise windows, but public APIs cannot permanently convert arbitrary third-party windows into true system-level always-on-top windows.
- Some system windows, unstable bundle-id windows, special overlays, or security-restricted windows may be observable but not controllable.
- Desktop/Space switching and fullscreen Space behavior still need careful handling.

## Development Workflow

This is an ACP-managed project. Feature-oriented source changes follow:

```text
Request -> Plan -> Change
```

Project state lives in `src/.acp/`; `acp-protocol/` is treated as read-only.

## ACP and Related Links

- Protocol Name: **ACP — Agent Content Protocol**
- ACP Handbook: [HANDBOOK.md](./HANDBOOK.md)
- ProtoCodeBase: [protocodebase.com](https://protocodebase.com)
- Agent Skills: [OhMyYuwan/ProtoCodeBase.Skill](https://github.com/OhMyYuwan/ProtoCodeBase.Skill)
