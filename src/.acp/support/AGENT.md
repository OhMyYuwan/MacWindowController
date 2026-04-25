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
  status: active development
  next_step: open REQ-0004 for multi-display and integration execution
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

## Active Direction

- Last completed request: `REQ-0003`
- Last completed plan: `PLN-0003`
- Last completed change: `CHG-0003`
- Immediate objective: continue Phase 2 feature delivery on YuwanZ branch.
