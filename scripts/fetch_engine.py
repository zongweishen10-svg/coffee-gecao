#!/usr/bin/env python3
"""Fetch the Godot 4.7.2 web (no-threads) engine wasm into OUT/index.wasm, verified by sha256.

The wasm is the unmodified official export template, so it is not stored in the repo.
Source 1: official Godot export templates (.tpz from the GitHub release).
Source 2 (fallback): an identical copy already served on GitHub Pages.
"""
import hashlib, io, json, sys, urllib.request, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
cfg = json.loads((ROOT / "scripts" / "engine.json").read_text())
out = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / cfg["name"]


def ok(data: bytes) -> bool:
    return len(data) == cfg["size"] and hashlib.sha256(data).hexdigest() == cfg["sha256"]


def from_template() -> bytes:
    tpz = Path("/tmp/templates.tpz")
    if not tpz.exists():
        print("downloading", cfg["template_url"])
        urllib.request.urlretrieve(cfg["template_url"], tpz)
    with zipfile.ZipFile(tpz) as z:
        inner = z.read(cfg["template_zip"])
    with zipfile.ZipFile(io.BytesIO(inner)) as z2:
        return z2.read(cfg["template_member"])


def from_fallback() -> bytes:
    print("downloading", cfg["fallback_url"])
    with urllib.request.urlopen(cfg["fallback_url"]) as r:
        return r.read()


for fn in (from_template, from_fallback):
    try:
        data = fn()
        if ok(data):
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(data)
            print(f"wrote {out} ({len(data)} bytes) via {fn.__name__}")
            sys.exit(0)
        print(fn.__name__, "sha/size mismatch")
    except Exception as ex:  # noqa: BLE001
        print(fn.__name__, "failed:", ex)
sys.exit("could not fetch a verified engine wasm")
