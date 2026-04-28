# Python Integration

This folder contains Python wrappers for the Swift `window-manager` CLI.

## Usage

```python
from src.infra.window_manager import WindowManager

manager = WindowManager()
windows = manager.list_windows()
manager.tile_window("com.apple.Notes", "right")
manager.save_layout("research_mode", "left refs + right notes")
```

## Stable Agent Interface

The following methods are intended as the stable agent-facing surface:

- `list_windows(all_windows=False)`
- `launch_app(bundle_id, background=False)`
- `launch_chrome_windows(count=3)`
- `move_window(bundle_id, x, y, window_index=0)`
- `resize_window(bundle_id, width, height, window_index=0)`
- `tile_window(bundle_id, position, display_index=None, window_index=0)`
- `place_window(bundle_id, zone, window_index=None, window_number=None, window_title_contains=None, display_index=None)`
- `save_layout(name, description="")`
- `list_layouts()`
- `apply_layout(name)`
- `delete_layout(name)`
- `export_layout(name, output_path)`
- `edit_layout(name, create_if_missing=False, description="")`
- `create_stack(name, position, windows)`
- `switch_stack(name, index)`
- `list_stacks()`
- `open_workbench(layout_name=None)`
- `tile_frontmost(position)`
- `bucket_left_frontmost()`

## CLI Resolution

`WindowManager` resolves CLI path in this order:

1. `WINDOW_MANAGER_CLI` env var
2. `tools/window-manager/.build/debug/window-manager`
3. `window-manager` from PATH

## Layout Storage Path

By default, Python wrapper sets:

- `WINDOW_MANAGER_LAYOUTS_DIR=/tmp/winctlmanager-layouts`

Override this env var if you want a different persistent directory.
