from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class WindowManagerError(RuntimeError):
    """Raised when the window-manager CLI returns a failure."""


@dataclass
class WindowManager:
    cli_path: str | None = None

    def __post_init__(self) -> None:
        if self.cli_path:
            return
        self.cli_path = self._resolve_default_cli_path()

    def list_windows(self, all_windows: bool = False) -> list[dict[str, Any]]:
        args = ["list-windows", "--json"]
        if all_windows:
            args.append("--all")
        data = self._run_json(args)
        if isinstance(data, dict) and "windows" in data:
            return list(data["windows"])
        if isinstance(data, list):
            return data
        raise WindowManagerError("Unexpected list-windows response format.")

    def move_window(self, bundle_id: str, x: float, y: float, window_index: int = 0) -> dict[str, Any]:
        return self._run_json(
            [
                "move-window",
                "--bundle-id",
                bundle_id,
                "--x",
                str(x),
                "--y",
                str(y),
                "--window-index",
                str(window_index),
                "--json",
            ]
        )

    def resize_window(self, bundle_id: str, width: float, height: float, window_index: int = 0) -> dict[str, Any]:
        return self._run_json(
            [
                "resize-window",
                "--bundle-id",
                bundle_id,
                "--width",
                str(width),
                "--height",
                str(height),
                "--window-index",
                str(window_index),
                "--json",
            ]
        )

    def tile_window(
        self,
        bundle_id: str,
        position: str,
        *,
        display_index: int | None = None,
        window_index: int = 0,
    ) -> dict[str, Any]:
        args = [
            "tile-window",
            "--bundle-id",
            bundle_id,
            "--position",
            position,
            "--window-index",
            str(window_index),
            "--json",
        ]
        if display_index is not None:
            args.extend(["--display-index", str(display_index)])
        return self._run_json(args)

    def save_layout(self, name: str, description: str = "") -> dict[str, Any]:
        args = ["save-layout", "--name", name, "--json"]
        if description:
            args.extend(["--description", description])
        return self._run_json(args)

    def restore_layout(self, name: str) -> str:
        return self._run_text(["restore-layout", "--name", name])

    def list_layouts(self) -> list[dict[str, Any]]:
        data = self._run_json(["list-layouts", "--json"])
        if isinstance(data, dict) and "desktops" in data:
            return list(data["desktops"])
        raise WindowManagerError("Unexpected list-layouts response format.")

    def _run_json(self, args: list[str]) -> dict[str, Any] | list[Any]:
        output = self._run_text(args)
        try:
            return json.loads(output)
        except json.JSONDecodeError as exc:
            raise WindowManagerError(f"Expected JSON output, got: {output}") from exc

    def _run_text(self, args: list[str]) -> str:
        assert self.cli_path is not None
        process = subprocess.run(
            [self.cli_path, *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if process.returncode != 0:
            stderr = process.stderr.strip()
            raise WindowManagerError(stderr or f"window-manager failed with code {process.returncode}")
        return process.stdout.strip()

    @staticmethod
    def _resolve_default_cli_path() -> str:
        if env_path := os.getenv("WINDOW_MANAGER_CLI"):
            return env_path

        repo_root = Path(__file__).resolve().parents[2]
        debug_binary = repo_root / "tools" / "window-manager" / ".build" / "debug" / "window-manager"
        if debug_binary.exists():
            return str(debug_binary)

        return "window-manager"

