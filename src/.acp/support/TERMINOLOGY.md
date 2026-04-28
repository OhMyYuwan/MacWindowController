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

## 6) 满宽两端对齐 (Full-Width Alignment)

- Canonical Term: `full_width_alignment`
- Definition: A visual frame/card/row stretches to the full available width of
  its containing display area; its left and right edges align with the content
  region boundaries.
- Not Equivalent To: Content-internal spacing alone. A row can have left text and
  right controls, but if the outer frame shrinks to the content's intrinsic
  width, it is NOT `full_width_alignment`.
- Required Rule: Workbench setting panels, rule panels, cards, and action rows
  should use `full_width_alignment` unless there is an explicit compact-control
  reason not to.
- UI Rule: Internal content should still use two-end composition where useful:
  primary label/function name on the left, controls/status/notes on the right.

## 7) 不可控窗口 (Uncontrollable Window)

- Canonical Term: `uncontrollable_window`
- Definition: A visible window that can be observed by CoreGraphics but should
  not be controlled through AX layout operations.
- Auto-Detection: A window is uncontrollable when it has no stable controllable
  app identity, such as `unknown.bundle`, an empty bundle id, or an invalid
  window number.
- Required Rule: `uncontrollable_window` entries must be excluded from zone
  resize, forced return, stack/bucket assignment, and drag-to-zone operations.
- UI Rule: Users may still see these windows in routing diagnostics and mark
  matching App/title rules as `不可控窗口`.

## Naming Guidance

- Prefer `display / desktop / zone / stacking_mode / tab_bar / content_area / full_width_alignment / uncontrollable_window` in code and docs.
- Avoid mixing synonyms in one feature spec unless they are mapped once in this glossary.
