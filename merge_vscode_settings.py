"""
Merge the keys required by the bebop setup kit into VSCode's Machine settings.json
(~/.vscode-server/data/Machine/settings.json).

- Creates the file with `{}` if it doesn't exist.
- Backs up the existing file to `<path>.bak.<unix-ts>` before writing.
- Preserves any keys we don't manage. Warns (but still overwrites) if one of our
  managed keys is already set to a different value.
- Idempotent: re-running is a no-op (no backup is written) when all keys already
  have the desired values.
"""

import json
import os
import shutil
import sys
import time
from pathlib import Path

SETTINGS_PATH = Path.home() / ".vscode-server" / "data" / "Machine" / "settings.json"

DESIRED = {
    "r.rterm.linux": str(Path.home() / ".local" / "bin" / "R"),
    "r.rpath.linux": str(Path.home() / ".local" / "bin" / "R"),
    "r.bracketedPaste": True,
    "r.sessionWatcher": True,
    "r.alwaysUseActiveTerminal": True,
    "r.plot.useHttpgd": True,
    "quarto.render.renderOnSave": True,
}


def main() -> int:
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)

    if SETTINGS_PATH.exists():
        with SETTINGS_PATH.open() as f:
            text = f.read()
        try:
            existing = json.loads(text) if text.strip() else {}
        except json.JSONDecodeError as exc:
            print(f"[error] {SETTINGS_PATH} is not valid JSON: {exc}", file=sys.stderr)
            print("        Refusing to overwrite. Please fix the file by hand.", file=sys.stderr)
            return 1
        if not isinstance(existing, dict):
            print(f"[error] {SETTINGS_PATH} top level is not a JSON object", file=sys.stderr)
            return 1
    else:
        existing = {}

    changes = []
    conflicts = []
    for key, want in DESIRED.items():
        if key not in existing:
            changes.append((key, None, want))
        elif existing[key] != want:
            conflicts.append((key, existing[key], want))
            changes.append((key, existing[key], want))

    if not changes:
        print(f"[skip] {SETTINGS_PATH} already has all required keys")
        return 0

    if SETTINGS_PATH.exists():
        backup = SETTINGS_PATH.with_suffix(SETTINGS_PATH.suffix + f".bak.{int(time.time())}")
        shutil.copy2(SETTINGS_PATH, backup)
        print(f"[backup] {backup}")

    for key, old, new in changes:
        if old is None:
            print(f"[add]    {key} = {json.dumps(new)}")
        else:
            print(f"[update] {key}: {json.dumps(old)} -> {json.dumps(new)}")

    merged = dict(existing)
    merged.update(DESIRED)

    with SETTINGS_PATH.open("w") as f:
        json.dump(merged, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"[wrote]  {SETTINGS_PATH}")

    if conflicts:
        print("", file=sys.stderr)
        print("[warn] The following keys had different prior values and were overwritten:", file=sys.stderr)
        for key, old, new in conflicts:
            print(f"  {key}: was {json.dumps(old)}, now {json.dumps(new)}", file=sys.stderr)
        print("  The previous file is preserved in the .bak above.", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
