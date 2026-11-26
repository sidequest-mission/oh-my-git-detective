"""Check navigation and graph right-clicks with an exported game player on macOS or Linux."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    binary = Path(sys.argv[1]).resolve()
    if sys.platform == "darwin":
        data_dir = Path.home() / "Library/Application Support"
    else:
        data_dir = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    data_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="omg-tests-", dir=data_dir) as directory:
        profile = Path(directory)
        player = profile / binary.name
        shutil.copy2(binary, player)
        if binary.parent.name == "MacOS":
            packs = binary.parent.parent / "Resources"
        else:
            packs = binary.parent
        for pack in packs.glob("*.pck"):
            shutil.copy2(pack, profile / pack.name)
        script = Path(__file__).with_name("menu_navigation.gd").resolve()
        (profile / "override.cfg").write_text(
            '[application]\nconfig/custom_user_dir_name=' + json.dumps(profile.name) +
            '\n[autoload]\nMenuCheck=' + json.dumps(str(script)) + '\n'
        )
        result = profile / "result.txt"
        environment = dict(os.environ, OMG_MENU_RESULT=str(result))
        run = subprocess.run(
            [str(player), "--headless", "--max-fps", "60"],
            cwd=profile, env=environment, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=60,
        )
        if run.returncode or not result.exists() or any(
            marker in run.stdout for marker in ("Error calling from signal", "SCRIPT ERROR", "FATAL ERROR")
        ):
            sys.exit(run.stdout or "Packaged menu test did not finish")
        print(result.read_text().strip())


if __name__ == "__main__":
    main()
