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

## CLI Resolution

`WindowManager` resolves CLI path in this order:

1. `WINDOW_MANAGER_CLI` env var
2. `tools/window-manager/.build/debug/window-manager`
3. `window-manager` from PATH
