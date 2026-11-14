"""v28 playable-robot rig kit: matte, ink-snapped part segmentation, hidden joins (shared by build_player_rigs.py).

Matte (green screen -> clean alpha, no erosion):
  * the key colour is measured from the image (median of definite background pixels);
  * every pixel that is key-like AND flood-connected to definite background (outside, or enclosed gaps between
    limbs / coils, which contain definite-background pixels themselves) is unmixed: alpha from the green excess
    relative to the key, colour = (C - (1-a) * key) / a;  key-like art (Rastabot's green hat / shoes) is never touched
    because the dark ink outline stops the flood;
  * edge despill: semi-transparent pixels can not keep more green than max(red, blue);
  * tiny islands of opaque pixels that float in the background (compression speckle) are removed.
Segmentation:
  * each part is marked by a few seed polylines drawn through its interior (e.g. along a spring's centre line, so
    every coil ring is seeded); a seeded watershed over the INK map (dark = ridge) assigns all remaining pixels, so
    every cut lands on a drawn outline instead of a straight polygon edge;
  * an optional "zone" polygon per part limits where that part may grow (stops leaks through broken outlines).
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as nd

PARTS = ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r", "tail"]
LABEL = {p: i + 1 for i, p in enumerate(PARTS)}
BG = 99


def matte(rgb_u8):
    a = rgb_u8.astype(np.float64)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    excess = g - np.maximum(r, b)
    sure_bg = (excess > 150) & (g > 170)
    key = np.median(a[sure_bg], axis=0) if sure_bg.any() else np.array([20, 250, 20.0])
    k_ex = key[1] - max(key[0], key[2])
    keyish = excess > 22
    bgreg = nd.binary_propagation(sure_bg, mask=keyish)
    bgreg = nd.binary_dilation(bgreg, iterations=1) & (excess > 4)
    alpha = np.ones(r.shape)
    alpha[bgreg] = np.clip(1.0 - excess[bgreg] / k_ex, 0.0, 1.0)
    alpha[sure_bg] = 0.0
    alpha[alpha < .02] = 0.0
    al = np.maximum(alpha, 1e-3)[..., None]
    col = np.clip((a - (1.0 - alpha[..., None]) * key) / al, 0, 255)
    edge = alpha < .985
    gm = np.maximum(col[..., 0], col[..., 2])
    col[..., 1] = np.where(edge, np.minimum(col[..., 1], gm), col[..., 1])
    col[alpha <= 0] = 0
    # drop isolated speckles (<= 30 px) that are not attached to the character
    lab, n = nd.label(alpha > .5)
    if n:
        sizes = np.bincount(lab.ravel()); sizes[0] = 0
        small = np.isin(lab, np.where((sizes > 0) & (sizes <= 30))[0])
        alpha[nd.binary_dilation(small, iterations=1) & ~nd.binary_dilation(np.isin(lab, np.where(sizes > 30)[0]), iterations=1)] = 0
    return np.dstack([col, alpha * 255]).astype(np.uint8), key


def draw_seeds(shape, seeds, width=5):
    """seeds: {part: [polyline, ...]} with polyline = [[x, y], ...] (single point allowed)."""
    im = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(im)
    for part, lines in seeds.items():
        for line in lines:
            pts = [tuple(p) for p in line]
            if len(pts) == 1:
                x, y = pts[0]; d.ellipse((x - width, y - width, x + width, y + width), fill=LABEL[part])
            else:
                d.line(pts, fill=LABEL[part], width=width * 2, joint="curve")
    return np.array(im).astype(np.int16)


def segment(rgba, seeds, zones=None):
    """returns label map (0 = transparent, LABEL[part] for each part)."""
    rgb = rgba[..., :3].astype(np.float64); alpha = rgba[..., 3] > 8
    lum = rgb @ np.array([.299, .587, .114])
    ink = np.clip(255 - lum, 0, 255)
    ink = nd.gaussian_filter(ink, .8)
    elev = ink.astype(np.uint8)
    markers = draw_seeds(rgba.shape, seeds)
    markers[~alpha] = BG
    lab = nd.watershed_ift(elev, markers)
    lab = lab.astype(np.int16)
    lab[~alpha] = 0
    lab[lab == BG] = 0
    # zones: a part may only own pixels inside its polygon (hard constraint, honoured by every later step)
    allowed = {}
    for part, poly in (zones or {}).items():
        zm = Image.new("L", (rgba.shape[1], rgba.shape[0]), 0)
        ImageDraw.Draw(zm).polygon([tuple(p) for p in poly], fill=1)
        allowed[LABEL[part]] = np.array(zm) > 0

    def ok(L, m):
        return L not in allowed or allowed[L][m].all()

    def enforce():
        for L, zm in allowed.items():
            leak = (lab == L) & ~zm
            if leak.any():
                other = (lab > 0) & (lab != L)
                for L2, z2 in allowed.items():
                    if L2 != L:
                        other &= ~((lab == L2) & ~z2)
                idx = nd.distance_transform_edt(~other, return_distances=False, return_indices=True)
                lab[leak] = lab[idx[0][leak], idx[1][leak]]

    def give(frag, L):
        ring = nd.binary_dilation(frag, iterations=2) & ~frag & (lab > 0) & (lab != L)
        cands = [c for c in np.unique(lab[ring]) if ok(c, frag)]
        if cands:
            counts = [(int((lab[ring] == c).sum()), c) for c in cands]
            lab[frag] = max(counts)[1]
            return True
        return False

    enforce()
    # thin slivers (< ~9 px wide) hanging off a limb next to ANOTHER part are that neighbour's outline stroke
    disk = np.hypot(*np.mgrid[-4:5, -4:5]) <= 4.2
    for name in ["arm_l", "arm_r", "leg_l", "leg_r", "tail"]:
        L = LABEL[name]
        m = lab == L
        if not m.any():
            continue
        thin = m & ~nd.binary_dilation(nd.binary_opening(m, structure=disk), iterations=1)
        comp, n = nd.label(thin, structure=np.ones((3, 3)))
        for c in range(1, n + 1):
            frag = comp == c
            if frag.sum() < 2500:
                give(frag, L)
    # fragments not connected to their part's main body are handed to the neighbour they touch most:
    # a detached limb must never carry floating pieces
    for _ in range(3):
        for L in [v for v in np.unique(lab) if v > 0]:
            comp, n = nd.label(lab == L, structure=np.ones((3, 3)))
            if n <= 1:
                continue
            sizes = np.bincount(comp.ravel()); sizes[0] = 0
            main = sizes.argmax()
            for c in range(1, n + 1):
                if c != main and sizes[c] <= 800:
                    give(comp == c, L)
    # any unlabeled visible pixel joins its nearest labeled neighbour, THEN the zones are enforced a final time
    vis = alpha & (lab == 0)
    if vis.any():
        idx = nd.distance_transform_edt(lab == 0, return_distances=False, return_indices=True)
        lab[vis] = lab[idx[0][vis], idx[1][vis]]
    enforce()
    return lab


def overlay(rgba, lab, path, scale=.5):
    cols = {1: (255, 60, 60), 2: (60, 160, 255), 3: (60, 230, 60), 4: (230, 230, 40), 5: (240, 120, 255), 6: (60, 240, 230), 7: (255, 150, 40)}
    base = rgba[..., :3].astype(float) * .55
    for k, c in cols.items():
        m = lab == k
        base[m] = base[m] * .5 + np.array(c) * .5
    a = rgba[..., 3:4] / 255.0
    out = base * a + np.array([30, 30, 34]) * (1 - a)
    # boundaries in white
    edges = (nd.grey_dilation(lab, size=3) != nd.grey_erosion(lab, size=3)) & (rgba[..., 3] > 8)
    out[edges] = 255
    im = Image.fromarray(out.astype(np.uint8))
    im = im.resize((int(im.width * scale), int(im.height * scale)), Image.Resampling.LANCZOS)
    im.save(path)
