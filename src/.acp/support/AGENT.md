```yaml
quick_entry:
  project_name: WinCtlManager
  project_type: macos_app
  capabilities:
    - basic_window_ops
    - window_stacking
    - desktop_layouts
    - visual_editor
    - cli_surface
  active_request_id: null
  status: ready
  next_step: await next user-directed ACP request
```

# WinCtlManager Agent Guide

## ACP Configuration

```yaml
acp:
  kernel_root: src/.acp/kernel
  support_root: src/.acp/support
  capability_root: src/.acp/capability

  execution_order:
    - AGENT.md
    - PROJECT_MAP.yaml
    - LOAD_RULES.yaml
    - CHANGE_POLICY.yaml
    - capabilities.yaml
```

## Project Overview

WinCtlManager is a native macOS window layout controller inspired by Tangrid.app.
The project priorities are: basic window operations, stack-based window groups,
desktop snapshot persistence, and a visual desktop layout editor.

## Core Terminology

- Canonical glossary location: `src/.acp/support/TERMINOLOGY.md`
- Required baseline:
  - `display` = physical monitor
  - `desktop` = macOS space on a display
  - `zone` = partition block inside one desktop
  - `ordinary_zone` = zone with ≤ threshold windows; all windows overlap to fill zone frame, no tab bar
  - `stack_zone` = zone with > threshold windows; tab bar visible, StackManager manages content
  - `stacking_mode` = `unordered` or `tabbed`
  - in `tabbed` mode, every zone must split into `tab_bar + content_area`
  - `zone_gap` = 8pt gap between adjacent zones for visual separation and handle placement
  - `partition_state` = shared model (mergeMode, splitX/Y, threshold, zone assignments) used by both app canvas and desktop overlay
  - `zone_transfer` = moving a window from one zone to another via ⌘⇧ + drag

## Working Rules

- Always follow `Request -> Plan -> Change` before source mutation.
- Treat `acp-protocol/` as read-only protocol payload.
- Prioritize capabilities in this order:
  1. `basic_window_ops`
  2. `window_stacking`
  3. `desktop_layouts`
  4. `visual_editor`
- Keep CLI behavior deterministic and scriptable.
- Favor additive changes over destructive rewrites unless required by a plan.

## Kernel Numbering Notes

- Historical numbering is intentionally preserved.
- `REQ` numbering is continuous (`REQ-0001` .. `REQ-0036`).
- `PLN` numbering is continuous (`PLN-0001` .. `PLN-0035`) but no longer matches `REQ` one-to-one after older history drift.
- `CHG-0008` is historically missing; do not renumber later changes to fill it.
- Current safe-sync policy: preserve existing filenames/ids, fix status inconsistencies, and rely on explicit cross references (`request:` / `plan:` / `Related Request:`) as the source of truth.

## Active Direction

- Last completed request: `REQ-0048`
- Last completed plan: `PLN-0047`
- Last completed change: `CHG-0047`
- Immediate objective: await next user-directed ACP request.
