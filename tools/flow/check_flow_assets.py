"""Release check for the Flow visual-pass assets: every referenced texture exists and is imported, the runtime folder
holds only PNG + .import (no Flow sources / videos / temp files), and texture sizes / memory stay reasonable.
usage: python -I tools/flow/check_flow_assets.py   (exit code 1 on any problem)"""
import glob
import os
import re
import sys

from PIL import Image

G = "G:/Godot/EpicShalban/game"
problems = []
scripts = ["scripts/world/background.gd", "scripts/world/terrain_builder.gd", "scripts/biomes/biome_painter.gd",
           "scripts/fx/fx.gd"]
for f in scripts:
    for m in re.findall(r'res://[^"%<{\s]+\.(?:png|gdshader)', open(os.path.join(G, f), encoding="utf8").read()):
        if not os.path.exists(os.path.join(G, m[6:])):
            problems.append(f"{f}: missing {m}")
need = ["tuft_0", "tuft_1", "tuft_2", "tuft_3", "flower_0", "flower_1", "flower_2", "bush_0", "bush_1", "rock_0",
        "rock_1", "rock_2", "ground_detail", "sky", "hills_far", "hills_mid"] + ["cloud_%d" % i for i in range(5)]
for n in need:
    if not os.path.exists(f"{G}/assets/flow/green_hills/{n}.png"):
        problems.append(f"green_hills/{n}.png missing")
for st in ["moon", "heavy", "chocolate", "jelly", "portal", "chasms", "cavern", "zone"]:
    for layer in ["sky", "far", "mid"]:
        if not os.path.exists(f"{G}/assets/flow/biomes/{st}/{layer}.png"):
            print(f"  note: {st}/{layer} has no painted layer (procedural fallback by design)")
for i in range(4):
    if not os.path.exists(f"{G}/assets/flow/biomes/chocolate/cloud_{i:02d}.png"):
        problems.append(f"chocolate/cloud_{i:02d}.png missing")
odd = [p for p in glob.glob(G + "/assets/flow/**/*", recursive=True)
       if os.path.isfile(p) and not p.endswith((".png", ".import"))]
problems += [f"non-runtime file in game/assets/flow: {p}" for p in odd]
total_disk, total_ram = 0, 0.0
for p in sorted(glob.glob(G + "/assets/flow/**/*.png", recursive=True)):
    w, h = Image.open(p).size
    imp_path = p + ".import"
    if not os.path.exists(imp_path):
        problems.append(f"not imported: {p}")
        continue
    imp = open(imp_path, encoding="utf8").read()
    vram = '"vram_texture": true' in imp
    ram = w * h * 4 / (4 if vram else 1) / 1e6
    total_disk += os.path.getsize(p)
    total_ram += ram
    if max(w, h) > 2304:
        problems.append(f"oversized texture {p} {w}x{h}")
    if w * h > 600000:
        print(f"  {os.path.relpath(p, G)} {w}x{h} {'VRAM' if vram else 'lossless'} ~{ram:.1f} MB")
print(f"runtime flow PNGs on disk: {total_disk / 1e6:.1f} MB; GPU memory if every biome were loaded: {total_ram:.1f} MB")
print("PROBLEMS:" if problems else "OK: no problems")
for p in problems:
    print("  -", p)
sys.exit(1 if problems else 0)
