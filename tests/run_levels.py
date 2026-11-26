"""Run the Godot lesson integration tests with disposable game data on macOS or Linux."""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    if sys.platform == "darwin":
        data_dir = Path.home() / "Library/Application Support"
    elif sys.platform.startswith("linux"):
        data_dir = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    else:
        sys.exit("Run this test launcher on macOS or Linux.")
    data_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="omg-tests-", dir=data_dir) as profile:
        project = Path(profile) / "project"
        shutil.copytree(root, project, ignore=shutil.ignore_patterns(".git", ".godot", "build"))
        config = project / "project.godot"
        lines = config.read_text().splitlines()
        setting = "config/custom_user_dir_name="
        for i, line in enumerate(lines):
            if line.startswith(setting):
                lines[i] = f'{setting}"{Path(profile).name}"'
                break
        else:
            sys.exit("Missing custom user directory setting")
        config.write_text("\n".join(lines) + "\n")

        godot = ["godot", "--headless", "--path", str(project)]
        pack = Path(profile) / "game.pck"
        for args in (["--import"], ["--export-pack", "Linux", str(pack)]):
            subprocess.run([*godot, *args], check=True, stdout=subprocess.DEVNULL, timeout=180)
        # A game-level fatal error can exit Godot with status zero.
        run = subprocess.run(
            ["godot", "--headless", "--max-fps", "60", "--main-pack", str(pack),
             "--script", str(root / "tests/play_levels.gd"), "--", str(root / "tests/levels.json")],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600,
        )
        if run.returncode or "PASS all level regressions" not in run.stdout or any(
            marker in run.stdout for marker in ("FATAL ERROR", "SCRIPT ERROR", "Error calling from signal", "Duplicate section [")
        ):
            sys.exit(run.stdout)
        print("\n".join(line for line in run.stdout.splitlines() if line.startswith("PASS ")))


if __name__ == "__main__":
    main()
