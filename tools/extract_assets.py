"""Builds all game sprites from the two source videos (frames pre-extracted with ffmpeg).

usage: python -I extract_assets.py <robot_frames_dir> <hand_frames_dir> <game_dir>

Robot (33052 / 1013372432_*.mp4): 3x2 grid, one module per cell. Limbs are cut into rigid pieces
(shoulder / fist, cap / boot); the coil between them is redrawn in-game as a real simulated spring
using coil_ring.png generated here from the source palette.
Hand (33056 / 956869304_*.mp4): keyed frames, thin "rubber band" bridges removed by morphological opening.
Writes <game>/assets/robot/*.png, <game>/assets/hand/*.png and <game>/assets/robot/rig.json (anchors).
"""
import sys, os, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(__file__))
from keylib import load_rgb, green_key, opening, largest_components, bbox, bleed_rgb, erode

ROBOT_DIR, HAND_DIR, GAME = sys.argv[1], sys.argv[2], sys.argv[3]
OUT_R = os.path.join(GAME, "assets", "robot")
OUT_H = os.path.join(GAME, "assets", "hand")
os.makedirs(OUT_R, exist_ok=True)
os.makedirs(OUT_H, exist_ok=True)

SCALE = 0.5  # robot sprite export scale
CELLS = [(9, 2, 645, 524), (656, 2, 1273, 524), (1285, 2, 1911, 524),
         (9, 536, 645, 1080), (656, 536, 1273, 1080), (1285, 536, 1911, 1080)]
BASE_FRAME = 1


def frame(i, d=ROBOT_DIR):
    return load_rgb(os.path.join(d, "f%03d.png" % i))


def key_cell(rgb, cell):
    x0, y0, x1, y1 = CELLS[cell]
    rgba, a = green_key(rgb[y0:y1, x0:x1])
    keep = largest_components(a > 0.5, keep=6, min_frac=0.03)
    # grow the kept mask a little so soft edges survive
    from keylib import dilate
    keep = dilate(keep.astype(np.uint8), 2).astype(bool)
    rgba[..., 3] *= keep
    return rgba


def seal_cut_edges(rgba, top=False, bottom=False, thick=5):
    """Source art is clipped by the video frame on some cells; draw an ink line over the cut."""
    a = rgba[..., 3] > 128
    h = a.shape[0]
    if top:
        cols = a[0]
        rgba[:thick, cols, :3] = 18
        rgba[:thick, cols, 3] = 255
    if bottom:
        cols = a[h - 1]
        rgba[h - thick:, cols, :3] = 18
        rgba[h - thick:, cols, 3] = 255
    return rgba


def region_mask(shape, poly):
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).polygon([tuple(p) for p in poly], fill=255)
    return np.asarray(im) > 0


def save_piece(rgba, name, mask=None, anchors=None, feather=1.5):
    """Crop to content, scale, save; return anchor dict converted into output-pixel space (origin top-left)."""
    rgba = rgba.copy()
    if mask is not None:
        m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(feather))
        rgba[..., 3] *= np.asarray(m).astype(np.float32) / 255.0
    x0, y0, x1, y1 = bbox(rgba[..., 3] / 255.0, thr=0.03, pad=6)
    crop = bleed_rgb(rgba[y0:y1, x0:x1])
    im = Image.fromarray(np.clip(crop, 0, 255).astype(np.uint8), "RGBA")
    w, h = max(1, round(im.width * SCALE)), max(1, round(im.height * SCALE))
    im = im.resize((w, h), Image.LANCZOS)
    im.save(os.path.join(OUT_R, name + ".png"))
    res = {"size": [w, h]}
    for k, (ax, ay) in (anchors or {}).items():
        res[k] = [round((ax - x0) * SCALE, 1), round((ay - y0) * SCALE, 1)]
    return res


rig = {"scale": SCALE}
base = frame(BASE_FRAME)

# ---------------- torso ----------------
torso = key_cell(base, 1)
rig["torso"] = save_piece(torso, "torso", anchors={
    "neck": (350, 52), "shoulder_l": (112, 135), "shoulder_r": (548, 118),
    "hip_l": (268, 420), "hip_r": (408, 420), "center": (330, 250)})

# ---------------- legs ----------------
# leg_l = cell 5 (toe points screen-left), leg_r = cell 4 (toe points right)
LEGS = {
    "leg_l": dict(cell=5, cap=[(190, 0), (370, 0), (370, 112), (190, 112)], cap_top=(280, 45), cap_bot=(287, 108),
                  boot=[(0, 268), (636, 268), (636, 544), (0, 544)], boot_top=(343, 282), sole=(305, 540)),
    "leg_r": dict(cell=4, cap=[(270, 0), (450, 0), (450, 128), (270, 128)], cap_top=(362, 55), cap_bot=(345, 122),
                  boot=[(0, 260), (636, 260), (636, 544), (0, 544)], boot_top=(290, 272), sole=(300, 540)),
}
for name, L in LEGS.items():
    px = seal_cut_edges(key_cell(base, L["cell"]), bottom=True)
    m_cap = region_mask(px.shape, L["cap"])
    m_boot = region_mask(px.shape, L["boot"])
    rig[name] = {
        "cap": save_piece(px, name + "_cap", m_cap, {"top": L["cap_top"], "bottom": L["cap_bot"]}),
        "boot": save_piece(px, name + "_boot", m_boot, {"top": L["boot_top"], "sole": L["sole"]}),
        "coil_rest_vec": [round((L["boot_top"][0] - L["cap_bot"][0]) * SCALE, 1), round((L["boot_top"][1] - L["cap_bot"][1]) * SCALE, 1)],
    }

# ---------------- arms ----------------
ARMS = {
    # arm_l = cell 3 (shoulder on the right of the drawing, plugs into torso's left socket)
    "arm_l": dict(cell=3, sh_c=(468, 132), sh_r=118, sh_cut=[(352, 0), (636, 0), (636, 260), (352, 260)],
                  disc=(528, 112), sh_exit=(392, 180),
                  fist=[(0, 330), (150, 300), (330, 290), (440, 330), (440, 544), (0, 544)],
                  cuff=(218, 318), knuckles=(270, 470)),
    "arm_r": dict(cell=2, sh_c=(185, 72), sh_r=112, sh_cut=[(70, 0), (282, 0), (282, 175), (70, 175)],
                  disc=(130, 45), sh_exit=(262, 112),
                  fist=[(200, 290), (340, 262), (520, 236), (520, 522), (200, 522)],
                  cuff=(445, 268), knuckles=(330, 420)),
}
for name, A in ARMS.items():
    px = key_cell(base, A["cell"])
    yy, xx = np.mgrid[0:px.shape[0], 0:px.shape[1]]
    circ = (xx - A["sh_c"][0]) ** 2 + (yy - A["sh_c"][1]) ** 2 < A["sh_r"] ** 2
    m_sh = circ & region_mask(px.shape, A["sh_cut"])
    m_fist = region_mask(px.shape, A["fist"])
    rig[name] = {
        "shoulder": save_piece(px, name + "_shoulder", m_sh, {"disc": A["disc"], "exit": A["sh_exit"]}),
        "fist": save_piece(px, name + "_fist", m_fist, {"cuff": A["cuff"], "knuckles": A["knuckles"]}),
        "coil_rest_vec": [round((A["cuff"][0] - A["sh_exit"][0]) * SCALE, 1), round((A["cuff"][1] - A["sh_exit"][1]) * SCALE, 1)],
    }

# ---------------- coil ring (procedural, palette sampled from the source coil) ----------------
import make_coil
rig["coil_ring"] = {"size": make_coil.coil_ring(os.path.join(OUT_R, "coil_ring.png"))}

# ---------------- head expressions (aligned to the base frame) ----------------
EXPRESSIONS = {"neutral": 1, "scared": 45, "angry": 73, "determined": 101, "happy": 125, "dizzy": 141}


def head_rgba(i):
    return seal_cut_edges(key_cell(frame(i), 0), top=True)


ref = head_rgba(EXPRESSIONS["neutral"])
ref_a = ref[..., 3] / 255.0


def align(rgba):
    """Brute-force translation + mild scale search on the helmet (upper 55%) alpha."""
    h, w = ref_a.shape
    top = int(h * 0.55)
    best = (1e18, 0, 0, 1.0)
    for s in (0.94, 0.96, 0.98, 1.0, 1.02, 1.04, 1.06):
        im = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
        sw, sh = round(w * s), round(h * s)
        im_s = im.resize((sw, sh), Image.BILINEAR)
        for dy in range(-30, 31, 3):
            for dx in range(-30, 31, 3):
                canvas = Image.new("RGBA", (w, h))
                canvas.paste(im_s, (round((w - sw) / 2) + dx, round((h - sh) / 2) + dy))
                a = np.asarray(canvas)[..., 3] / 255.0
                err = np.abs(a[:top] - ref_a[:top]).sum()
                if err < best[0]:
                    best = (err, dx, dy, s)
    # refine at 1px around the best
    _, bx, by, s = best
    im = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
    sw, sh = round(w * s), round(h * s)
    im_s = im.resize((sw, sh), Image.BILINEAR if s != 1.0 else Image.NEAREST)
    for dy in range(by - 2, by + 3):
        for dx in range(bx - 2, bx + 3):
            canvas = Image.new("RGBA", (w, h))
            canvas.paste(im_s, (round((w - sw) / 2) + dx, round((h - sh) / 2) + dy))
            a = np.asarray(canvas)[..., 3] / 255.0
            err = np.abs(a[:top] - ref_a[:top]).sum()
            if err < best[0]:
                best = (err, dx, dy, s)
    _, dx, dy, s = best
    canvas = Image.new("RGBA", (w, h))
    sw, sh = round(w * s), round(h * s)
    canvas.paste(im.resize((sw, sh), Image.LANCZOS), (round((w - sw) / 2) + dx, round((h - sh) / 2) + dy))
    print("align", s, dx, dy, best[0])
    return np.asarray(canvas).astype(np.float32)


heads = {}
for nm, idx in EXPRESSIONS.items():
    heads[nm] = ref if nm == "neutral" else align(head_rgba(idx))
# common crop over all expressions so they swap without jumping
union = np.zeros(ref_a.shape, bool)
for v in heads.values():
    union |= v[..., 3] > 8
ys, xs = np.nonzero(union)
x0, y0, x1, y1 = xs.min() - 6, max(ys.min() - 6, 0), xs.max() + 7, ys.max() + 7
for nm, v in heads.items():
    crop = bleed_rgb(v[y0:y1, x0:x1])
    im = Image.fromarray(np.clip(crop, 0, 255).astype(np.uint8), "RGBA")
    im = im.resize((round(im.width * SCALE), round(im.height * SCALE)), Image.LANCZOS)
    im.save(os.path.join(OUT_R, "head_%s.png" % nm))
hw, hh = round((x1 - x0) * SCALE), round((y1 - y0) * SCALE)
rig["head"] = {"size": [hw, hh], "neck": [round((345 - x0) * SCALE, 1), round((478 - y0) * SCALE, 1)],
               "center": [round((340 - x0) * SCALE, 1), round((300 - y0) * SCALE, 1)],
               "expressions": list(EXPRESSIONS.keys())}

with open(os.path.join(OUT_R, "rig.json"), "w") as f:
    json.dump(rig, f, indent=1)
print('done')
