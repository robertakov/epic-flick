"""v30: extracts the isolated exclusion-zone objects from the provided concept/sprite sheet
Assets/Biom/Chernobil (2).png (read-only) into game/assets/biomes/zone/<name>.png (transparent, trimmed).

The sheet is a grid of objects drawn on a beige paper background separated by thin lines. Each object is cut by:
  * its row band and column range (CELLS below, measured on the sheet),
  * a background matte: the paper colour is measured per cell (border median); pixels close to it become
    transparent with a soft edge; the object's own ink outline stops the flood, so beige parts INSIDE an object
    (concrete, signs) stay opaque (flood fill from the cell border only),
  * the separator lines are excluded by an inset.
Sheet 1 (Chernobil (1).png) is a finished scene: it is used as the art-direction reference for the palette and
the sky; nothing is cut from it.
usage: python -B -I tools/biomes/extract_zone_sprites.py
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from scipy import ndimage as nd

ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "Assets/Biom/Chernobil (2).png"
OUT = ROOT / "game/assets/biomes/zone"
# name: (x0, y0, x1, y1) on the 1536x1024 sheet (cell interiors, separator lines excluded)
CELLS = {
    "block_bear": (8, 14, 205, 240), "block_a": (212, 14, 418, 240), "block_b": (424, 14, 604, 240),
    "block_atom": (612, 14, 820, 240), "reactor": (826, 14, 1140, 240), "cooling_tower": (1146, 14, 1300, 240),
    "ferris_wheel": (1306, 14, 1530, 240),
    "pylon_a": (6, 246, 188, 396), "pylon_b": (192, 246, 296, 396), "pole": (300, 246, 396, 396),
    "crane": (400, 246, 540, 396), "watchtower": (546, 246, 660, 396), "bunker": (664, 246, 822, 396),
    "bus": (826, 246, 1046, 396), "truck": (1050, 246, 1302, 396), "car": (1306, 246, 1530, 396),
    "tree_dead_a": (6, 414, 112, 556), "tree_dead_b": (116, 414, 214, 556), "tree_dead_c": (218, 414, 324, 556),
    "log_pile": (328, 414, 432, 556), "tree_dead_d": (436, 414, 540, 556), "pine_a": (544, 414, 610, 556),
    "pine_b": (612, 414, 680, 556), "pine_c": (682, 414, 764, 556), "bush_dead": (766, 414, 872, 556),
    "sign_pripyat": (878, 414, 1046, 556), "sign_radiation": (1050, 414, 1152, 556),
    "sign_chernobyl": (1156, 414, 1392, 556), "sign_danger": (1396, 414, 1530, 556),
    "slab_a": (6, 568, 88, 657), "slab_b": (90, 568, 168, 657), "slab_rebar": (170, 568, 296, 657),
    "rubble": (300, 568, 400, 657), "sandbags": (404, 568, 536, 657), "pipes_concrete": (540, 568, 656, 657),
    "barrels": (660, 568, 778, 657), "crates": (780, 568, 862, 657), "spool_a": (864, 568, 958, 657),
    "spool_b": (960, 568, 1052, 657), "pipe_rusty": (1056, 568, 1238, 657), "barrier_rail": (1240, 568, 1432, 657),
    "valve": (1434, 568, 1530, 657),
    "fence_rail": (6, 664, 248, 750), "bridge_rail": (252, 664, 532, 750), "fence_chain": (536, 664, 686, 750),
    "fence_broken": (688, 664, 800, 750), "gate_star": (802, 664, 900, 750), "concrete_panels": (902, 664, 994, 750),
    "fence_chain_b": (996, 664, 1124, 750), "tires": (1126, 664, 1248, 750), "hedgehog": (1250, 664, 1356, 750),
    "slab_c": (1358, 664, 1430, 750), "slab_d": (1432, 664, 1530, 750),
}


KEEP_PAPER = {"sign_pripyat", "sign_chernobyl", "sign_danger", "sign_radiation"}


def matte(cell, name=""):
    a = cell.astype(np.float64)
    border = np.concatenate([a[:3].reshape(-1, 3), a[-3:].reshape(-1, 3), a[:, :3].reshape(-1, 3), a[:, -3:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    d = np.sqrt(((a - bg) ** 2).sum(2))
    near = d < 34
    seed = np.zeros(near.shape, bool)
    seed[0] = near[0]; seed[-1] = near[-1]; seed[:, 0] = near[:, 0]; seed[:, -1] = near[:, -1]
    ext = nd.binary_propagation(seed, mask=near)
    alpha = np.ones(d.shape)
    alpha[ext] = 0.0
    # soft edge: pixels next to the exterior that are still close-ish to the paper get partial alpha
    # enclosed paper (between lattice beams, spokes, fence mesh): flat paper-coloured holes become transparent too;
    # sign boards keep their (intentionally pale) faces
    if name not in KEEP_PAPER:
        lab, n = nd.label(near & ~ext)
        if n:
            sizes = np.bincount(lab.ravel())
            for k in range(1, n + 1):
                if sizes[k] < 40:
                    continue
                m = lab == k
                if d[m].mean() < 18.0:
                    ext |= m
    # separator lines: thin (<=3 px) opaque vertical / horizontal strips next to the cell edge
    solid = ~ext
    for x in list(range(0, 8)) + list(range(solid.shape[1] - 8, solid.shape[1])):
        if solid[:, x].mean() > 0.55:
            ext[:, x] = True
    for y in list(range(0, 6)) + list(range(solid.shape[0] - 6, solid.shape[0])):
        if solid[y].mean() > 0.6:
            ext[y] = True
    ring = nd.binary_dilation(ext, iterations=2) & ~ext
    alpha[ext] = 0.0
    alpha[ring] = np.clip((d[ring] - 20.0) / 50.0, 0.0, 1.0)
    # keep the largest components only (drop paper specks)
    lab, n = nd.label(alpha > 0.5)
    if n:
        sizes = np.bincount(lab.ravel()); sizes[0] = 0
        good = []
        for k, sl in enumerate(nd.find_objects(lab), start=1):
            if sl is None or sizes[k] < max(60, sizes.max() * 0.02):
                continue
            if sl[1].stop - sl[1].start <= 5 or sl[0].stop - sl[0].start <= 5:
                continue                     # leftover separator line
            good.append(k)
        keep = np.isin(lab, good)
        alpha[~nd.binary_dilation(keep, iterations=2)] = 0.0
    rgba = np.dstack([a, alpha * 255]).astype(np.uint8)
    ys, xs = np.where(alpha > 0.05)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = np.array(Image.open(SHEET).convert("RGB"))
    meta = {}
    for name, (x0, y0, x1, y1) in CELLS.items():
        rgba = matte(sheet[y0:y1, x0:x1], name)
        Image.fromarray(rgba, "RGBA").save(OUT / f"{name}.png")
        meta[name] = list(rgba.shape[1::-1])
    (OUT / "sprites.json").write_text(json.dumps({"source": "Assets/Biom/Chernobil (2).png", "sizes": meta}, indent=1), encoding="utf8", newline="\n")
    print(len(meta), "sprites ->", OUT)


if __name__ == "__main__":
    main()
