"""Giant flicking hand (956869304_*.mp4 = brief's 33056.mp4) -> keyed sprite frames.

usage: python -I extract_hand.py <hand_frames_dir> <game_dir>
Thin generation artefacts (the rubber-band bridge between thumb and finger, speed lines, the spark)
are removed by a morphological opening of the alpha mask; the game draws its own impact VFX.
"""
import sys, os, json
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from keylib import load_rgb, green_key, opening, largest_components, bleed_rgb, dilate

HAND_DIR, GAME = sys.argv[1], sys.argv[2]
OUT_H = os.path.join(GAME, "assets", "hand")
os.makedirs(OUT_H, exist_ok=True)

HAND_SCALE = 0.6
# source frame indices (0-based): wind-up, thumb loading, tension hold, FLICK (119-121), recoil
HAND_FRAMES = [0, 8, 16, 24, 30, 34, 36, 37, 38, 39, 40, 42, 44, 50, 60, 80, 100, 118,
               119, 120, 121, 122, 123, 125, 128, 131, 133, 135, 137, 140]
HX0, HY0, HX1, HY1 = 260, 190, 1820, 910
OPEN_R = 14
meta = {"frames": [], "scale": HAND_SCALE, "crop": [HX0, HY0, HX1, HY1], "flick_index": HAND_FRAMES.index(119)}
for k, i in enumerate(HAND_FRAMES):
    rgb = load_rgb(os.path.join(HAND_DIR, "f%03d.png" % (i + 1)))[HY0:HY1, HX0:HX1]
    rgba, a = green_key(rgb, lo=22, hi=70)
    solid = opening((a > 0.5).astype(np.uint8), OPEN_R).astype(bool)
    solid = largest_components(solid, keep=2, min_frac=0.05)
    keep = dilate(solid.astype(np.uint8), 2).astype(bool)
    rgba[..., 3] *= keep
    rgba = bleed_rgb(rgba)
    im = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
    im = im.resize((round(im.width * HAND_SCALE), round(im.height * HAND_SCALE)), Image.LANCZOS)
    im.save(os.path.join(OUT_H, "hand_%02d.png" % k))
    meta["frames"].append(i)
col = load_rgb(os.path.join(HAND_DIR, "f001.png"))[:, HX0 + 2]
dark = np.nonzero(col.max(axis=1) < 50)[0]
meta["sleeve_y"] = [round((int(dark.min()) - HY0) * HAND_SCALE, 1), round((int(dark.max()) - HY0) * HAND_SCALE, 1)]
meta["size"] = [round((HX1 - HX0) * HAND_SCALE), round((HY1 - HY0) * HAND_SCALE)]
with open(os.path.join(OUT_H, "hand.json"), "w") as f:
    json.dump(meta, f, indent=1)
print("hand done", meta["sleeve_y"])
