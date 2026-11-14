"""v36 colour schemes (cosmetic only): semantic, region-by-region repaint of the approved robot art.

For every robot artwork (BASE and MK2 asset dir) and every alternate scheme this writes a sibling asset dir
game/assets/robots/<dir>__<scheme>/ with the SAME parts, sizes, pivots and manifest geometry (the rig, colliders
and physics never read these files). Only colour changes:
  * pixels are processed in CIE Lab: the lightness L is kept (x an optional gentle factor), so outlines, shading,
    specular highlights, texture detail and antialiasing survive; only chroma / hue move;
  * each scheme is a list of material RULES (Lab hue range x lightness range x chroma range, soft-edged) that map
    one material family (lacquer, trim gold, panels, accents, ...) to its new colour - never one global hue shift;
  * per-part PROTECT masks keep faces, gloves, eyes, ink and dark springs untouched where required.
Run:  python -B -I tools/players/build_color_schemes.py [scheme_key ...]   (reports/v36/schemes/*.png sheets)
"""
import json, os, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ROBOTS = ROOT / "game/assets/robots"
REPORT = ROOT / "reports/v36/schemes"

# ------------------------------------------------------------------ colour space

def srgb_to_lab(rgb):
    c = rgb / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return L, a, b


def lab_to_srgb(L, a, b):
    fy = (L + 16) / 116
    fx = fy + a / 500
    fz = fy - b / 200
    def inv(t):
        return np.where(t ** 3 > 216 / 24389, t ** 3, (116 * t - 16) / (24389 / 27))
    xyz = np.stack([inv(fx), inv(fy), inv(fz)], -1) * np.array([0.95047, 1.0, 1.08883])
    Mi = np.array([[3.2404542, -1.5371385, -0.4985314], [-0.9692660, 1.8760108, 0.0415560], [0.0556434, -0.2040259, 1.0572252]])
    c = np.clip(xyz @ Mi.T, 0, 1)
    c = np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)
    return np.clip(c * 255.0 + 0.5, 0, 255)


def soft_range(x, lo, hi, feather):
    return np.clip((x - lo) / feather + 0.5, 0, 1) * np.clip((hi - x) / feather + 0.5, 0, 1)


def hue_member(h, h0, h1, feather=10.0):
    """Soft membership of Lab hue angle h (deg) in [h0, h1] (wraps)."""
    if h0 <= h1:
        return soft_range(h, h0, h1, feather)
    return np.maximum(soft_range(h, h0, 360.0 + feather, feather), soft_range(h, -feather, h1, feather))

# ------------------------------------------------------------------ schemes
# rule: hue [h0,h1] (Lab deg), L [l0,l1], C [c0,c1] (default [8, 200]); target: to_h (deg) or dh, c (chroma x),
#       c_add, l (lightness x), l_add.  protect: list of {L:[..], C:[..], h:[..]} kept as authored.
WARM_RED = [15, 48]        # red lacquer / red cloth
ORANGE = [48, 70]          # orange metal / copper shading
GOLD = [70, 100]           # gold / brass / yellow
GREEN = [110, 175]
TEAL = [175, 250]
FACE = {"L": [72, 101], "C": [0, 32], "h": [40, 100]}         # pale cream skin / gloves / clock faces
WHITE = {"L": [86, 101], "C": [0, 14]}
INK = {"L": [-1, 14]}

SCHEMES = {
    # ---- Samurobot: NIGHT SHOGUN - deep blue lacquer, selective violet, cool silver trim, navy-black metal
    "shogun": {"robot": "samurai", "skin_id": "samurai_shogun", "dirs": ["samurai", "samurai_mk2"],
        "rules": [
            {"h": WARM_RED, "L": [42, 101], "C": [22, 200], "to_h": 280, "c": 0.6, "l": 0.63},                  # lacquer -> deep night blue
            {"h": WARM_RED, "L": [0, 42], "C": [12, 200], "to_h": 318, "c": 0.8, "l": 0.86},                   # dark crimson -> violet
            {"h": ORANGE, "L": [0, 101], "C": [16, 200], "to_h": 298, "c": 0.58, "l": 0.66},                  # red-orange shading -> blue-violet
            {"h": [65, 115], "L": [55, 101], "C": [9, 200], "to_h": 268, "c": 0.14, "c_add": 3, "l": 1.0},     # gold trim -> cool silver
            {"h": [65, 115], "L": [0, 55], "C": [8, 200], "to_h": 300, "c": 0.45, "l": 0.9},                 # dark gold -> dusky violet
            {"h": [0, 360], "L": [10, 60], "C": [0, 9], "to_h": 278, "c_add": 7, "c": 0.0},                    # black lacquer -> navy-black
        ],
        "protect": [WHITE, INK],
        "accent": {"part": "torso", "note": "the MK2 dragon / X marks follow the gold / crimson rules (silver / violet)"}},
    # ---- Rastabot: COPPER POT - copper, bright copper, verdigris patina
    "copper": {"robot": "tin", "skin_id": "tin_copper", "dirs": ["tin", "tin_mk2"],
        "rules": [
            {"h": WARM_RED, "L": [0, 101], "C": [18, 200], "to_h": 48, "c": 0.92, "l": 0.92},                 # red -> deep copper
            {"h": GOLD, "L": [0, 101], "C": [20, 200], "to_h": 62, "c": 0.95, "l": 0.95},                    # yellow -> bright copper
            {"h": GREEN, "L": [0, 101], "C": [10, 200], "to_h": 192, "c": 0.62, "l": 1.06},                   # green -> verdigris
            {"h": ORANGE, "L": [0, 101], "C": [16, 200], "dh": -4, "c": 1.05},                               # copper shading stays copper
        ],
        "protect": [FACE, WHITE, INK]},
    # ---- Kengurobot: LIME JUMPER - lime metal, deep green shading, brass kept as the warm contrast
    "lime": {"robot": "hopper", "skin_id": "hopper_lime", "dirs": ["hopper", "hopper_mk2"],
        "rules": [
            {"h": ORANGE, "L": [38, 101], "C": [22, 200], "to_h": 122, "c": 0.95, "l": 1.02},                 # orange metal -> lime
            {"h": WARM_RED, "L": [0, 101], "C": [18, 200], "to_h": 142, "c": 0.85, "l": 0.95},                # red-orange -> green
            {"h": ORANGE, "L": [0, 38], "C": [14, 200], "to_h": 150, "c": 0.8},                               # dark orange -> deep green
            {"h": GOLD, "L": [0, 101], "C": [18, 200], "to_h": 96, "c": 0.9, "l": 1.0},                       # brass -> warm yellow-brass
        ],
        "protect": [FACE, WHITE, INK]},
    # ---- Sumobot: CAST-IRON GUARDIAN - iron grey body, steel-blue cloth, antique bronze
    "iron": {"robot": "heavy", "skin_id": "heavy_iron", "dirs": ["heavy", "heavy_mk2"],
        "rules": [
            {"h": WARM_RED, "L": [0, 101], "C": [18, 200], "to_h": 262, "c": 0.5, "l": 0.84},                 # red belt / trim -> steel blue
            {"h": ORANGE, "L": [0, 101], "C": [16, 200], "to_h": 255, "c": 0.35, "l": 0.86},                 # red-orange shading -> steel
            {"h": GOLD, "L": [0, 101], "C": [22, 200], "to_h": 72, "c": 0.5, "l": 0.84},                     # gold -> antique bronze
            {"h": [40, 110], "L": [55, 101], "C": [4, 32], "to_h": 250, "c": 0.25, "c_add": 1.5, "l": 0.8},  # cream body -> iron grey
        ],
        "protect": [WHITE, INK],
        # the face skin (more saturated than the cream body) and the glove shading keep their authored colours
        "part_protect": {"head": [{"L": [50, 101], "C": [0, 58], "h": [35, 105]}],
                         "arm_l": [{"L": [58, 101], "C": [0, 42], "h": [35, 112]}], "arm_r": [{"L": [58, 101], "C": [0, 42], "h": [35, 112]}]}},
    # ---- Chronobot: SILVER CHRONOMETER (new) - silver brass, midnight-blue panels, violet velvet
    "silver": {"robot": "rocket", "skin_id": "rocket_silver", "dirs": ["rocket", "rocket_mk2"],
        "rules": [
            {"h": GOLD, "L": [0, 101], "C": [14, 200], "to_h": 255, "c": 0.15, "c_add": 2, "l": 1.0},        # brass -> silver
            {"h": ORANGE, "L": [0, 101], "C": [14, 200], "to_h": 250, "c": 0.2, "l": 0.96},                  # brass shading -> silver shade
            {"h": TEAL, "L": [0, 101], "C": [4, 200], "to_h": 268, "c": 1.6, "c_add": 6, "l": 0.92},          # teal panels -> midnight blue
            {"h": [340, 48], "L": [0, 101], "C": [7, 200], "to_h": 318, "c": 0.8, "l": 0.92},               # red coat / band / cape -> violet
        ],
        "protect": [WHITE, INK], "part_protect": {"head": [FACE]}},
}


def recolor(img, scheme, part):
    a = np.array(img.convert("RGBA")).astype(float)
    rgb, alpha = a[..., :3], a[..., 3]
    L, aa, bb = srgb_to_lab(rgb)
    C = np.hypot(aa, bb)
    H = (np.degrees(np.arctan2(bb, aa)) + 360.0) % 360.0
    total = np.zeros_like(L)
    accL = np.zeros_like(L); accA = np.zeros_like(L); accB = np.zeros_like(L)
    for r in scheme["rules"]:
        c0, c1 = r.get("C", [8, 200])
        w = hue_member(H, r["h"][0], r["h"][1]) * soft_range(L, r["L"][0], r["L"][1], 6.0) * soft_range(C, c0, c1, 4.0)
        nh = np.radians(r["to_h"]) if "to_h" in r else np.radians(H + r.get("dh", 0.0))
        nC = C * r.get("c", 1.0) + r.get("c_add", 0.0)
        nL = np.clip(L * r.get("l", 1.0) + r.get("l_add", 0.0), 0, 100)
        accL += w * nL; accA += w * nC * np.cos(nh); accB += w * nC * np.sin(nh)
        total += w
    norm = np.maximum(total, 1.0)
    wt = np.minimum(total, 1.0)
    keep = np.zeros_like(L)
    for p in scheme.get("protect", []) + scheme.get("part_protect", {}).get(part, []):
        m = np.ones_like(L)
        if "L" in p: m *= soft_range(L, p["L"][0], p["L"][1], 4.0)
        if "C" in p: m *= soft_range(C, p["C"][0], p["C"][1], 3.0)
        if "h" in p: m *= hue_member(H, p["h"][0], p["h"][1], 8.0)
        keep = np.maximum(keep, m)
    wt *= (1.0 - keep)
    outL = L * (1 - wt) + (accL / norm) * wt
    outA = aa * (1 - wt) + (accA / norm) * wt
    outB = bb * (1 - wt) + (accB / norm) * wt
    out = lab_to_srgb(outL, outA, outB)
    res = np.dstack([out, alpha]).astype(np.uint8)
    res[alpha == 0] = a[alpha == 0].astype(np.uint8)         # untouched transparent pixels
    return Image.fromarray(res, "RGBA")


def strip_import(src_text):
    keep = []
    for line in src_text.splitlines():
        if line.startswith(("uid=", "path=", "dest_files=")):
            continue
        keep.append(line)
    return "\n".join(keep) + "\n"


def build(key, scheme):
    sheet_rows = []
    for d in scheme["dirs"]:
        src = ROBOTS / d
        dst = ROBOTS / f"{d}__{key}"
        dst.mkdir(parents=True, exist_ok=True)
        mf = json.loads((src / "manifest.json").read_text(encoding="utf8"))
        mf["visual_id"] = f"{mf.get('visual_id', d)}__{key}"
        mf["scheme"] = {"key": key, "skin_id": scheme["skin_id"], "base_dir": d, "builder": "tools/players/build_color_schemes.py v36"}
        (dst / "manifest.json").write_text(json.dumps(mf, ensure_ascii=False, indent=2) + "\n", encoding="utf8", newline="\n")
        if (src / "visual_rig.json").exists():
            (dst / "visual_rig.json").write_bytes((src / "visual_rig.json").read_bytes())
        row = []
        for png in sorted(src.glob("*.png")):
            part = png.stem
            out = recolor(Image.open(png), scheme, part)
            assert out.size == Image.open(png).size
            out.save(dst / png.name)
            imp = png.with_suffix(".png.import")
            if imp.exists():
                (dst / (png.name + ".import")).write_text(strip_import(imp.read_text(encoding="utf8")).replace(f"res://assets/robots/{d}/", f"res://assets/robots/{d}__{key}/"), encoding="utf8", newline="\n")
            row.append((Image.open(png).convert("RGBA"), out, part))
        sheet_rows.append((d, row))
    REPORT.mkdir(parents=True, exist_ok=True)
    tiles = []
    for d, row in sheet_rows:
        for which in (0, 1):
            ims = [(r[which].crop((0, 0, r[which].width // 7, r[which].height)) if r[2] == "head" else r[which]) for r in row]
            h = max(i.height for i in ims); w = sum(i.width + 8 for i in ims)
            t = Image.new("RGBA", (w, h), (92, 92, 100, 255)); x = 0
            for i in ims:
                t.alpha_composite(i, (x, h - i.height)); x += i.width + 8
            tiles.append(t)
    W = max(t.width for t in tiles); H = sum(t.height + 10 for t in tiles)
    sheet = Image.new("RGB", (W, H), (92, 92, 100)); y = 0
    for t in tiles:
        sheet.paste(t, (0, y), t); y += t.height + 10
    sheet.save(REPORT / f"parts_{scheme['robot']}_{key}.png")
    print(key, "->", [f"{d}__{key}" for d in scheme["dirs"]])


if __name__ == "__main__":
    keys = sys.argv[1:] or list(SCHEMES)
    for k in keys:
        build(k, SCHEMES[k])
