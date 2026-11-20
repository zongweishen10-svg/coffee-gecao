#!/usr/bin/env python3
"""Decode _chunks/*.b64 (listed in _chunks/manifest.json) into their real paths.

The GitHub connector used to publish this repo can only write text files, so binaries
(index.pck, icons, the subset font) arrive as base64. Every file is verified by size +
sha256; on success _chunks/ is removed (the workflow then commits the real binaries).
"""
import base64, hashlib, json, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CH = ROOT / "_chunks"


def main() -> int:
    man = CH / "manifest.json"
    if not man.exists():
        print("no _chunks/manifest.json; nothing to assemble")
        return 0
    for e in json.loads(man.read_text()):
        data = base64.b64decode((CH / e["file"]).read_text().encode("ascii"))
        got = hashlib.sha256(data).hexdigest()
        if len(data) != e["size"] or got != e["sha256"]:
            raise SystemExit(f"{e['name']}: size {len(data)} sha {got} != {e['size']} {e['sha256']}")
        dest = ROOT / e["name"]
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        print(f"wrote {e['name']} ({len(data)} bytes)")
    shutil.rmtree(CH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
