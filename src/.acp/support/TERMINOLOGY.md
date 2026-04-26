# WinCtlManager Core Terminology

This glossary is the single source of truth for domain wording in product docs,
ACP requests/plans/changes, CLI descriptions, and UI copy.

## 1) 显示器 (Display)

- Canonical Term: `display`
- Definition: A physical monitor recognized by macOS.
- Scope: The outermost visual container. Multiple displays can exist at once.
- Constraint: Desktop/workspace and zone coordinates are always interpreted within a selected display.

## 2) 桌面 (Desktop / Space)

- Canonical Term: `desktop`
- Definition: A macOS desktop space on a specific display.
- Scope: A user can have multiple desktops (spaces), and each desktop can have independent window layout state.
- Constraint: Layout restore must target the same display + desktop context, or apply explicit fallback rules.

## 3) 分区/分块 (Zone)

- Canonical Term: `zone`
- Definition: A geometric region inside one desktop, used as the placement and stacking container for windows.
- Scope: A desktop can be partitioned into one or multiple zones by layout mode and split ratios.
- Constraint: Every managed window belongs to at most one active zone in one layout pass.

## 4) 堆叠模式 (Stacking Mode)

- Canonical Term: `stacking_mode`
- Allowed Values:
  - `unordered`: Windows in the zone are not organized as tabs; ordering has no tab semantics.
  - `tabbed`: Windows in the zone are organized as a tab-like stack with one active window.
- Constraint: Stacking mode is a per-zone behavior contract, not a global desktop-wide flag.

## 5) 标签栏与内容栏 (Tab Bar vs Content Area)

- Applies When: `stacking_mode = tabbed`
- Canonical Terms:
  - `tab_bar`
  - `content_area`
- Definition:
  - `tab_bar`: The top strip for tab items and active-tab selection.
  - `content_area`: The remaining area used to present the active window content.
- Required Rule: In `tabbed` mode, each zone MUST be partitioned into `tab_bar + content_area`.
- Geometry Rule: `tab_bar` and `content_area` must form one complete non-overlapping zone rectangle.

## Naming Guidance

- Prefer `display / desktop / zone / stacking_mode / tab_bar / content_area` in code and docs.
- Avoid mixing synonyms in one feature spec unless they are mapped once in this glossary.
