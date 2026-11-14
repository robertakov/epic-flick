"""v34: surgical removal of Rastabot's joint + smoke from the head atlas (all 7 expression frames).
Source of truth: art_backup/v34_rastabot/head.png (original, untouched). Output: game/assets/robots/tin/head.png.
The joint / smoke region (y >= 40, x >= 160 in every 254x203 frame) is pixel-identical across the 7 frames, so one
repair of frame 0 is pasted into each frame there; the expression (eyes / brows / nose) pixels are never touched.
Repair of frame 0 (frame coordinates):
  - smoke + joint parts outside the head silhouette -> transparent
  - face skin under the joint rebuilt by vertical interpolation between the visible skin above / below
  - the hidden face contour redrawn as an anti-aliased arc joining the visible contour ends
  - the dreadlock behind the joint continued with its own bead texture from one bead pair above
  - the mouth closed with a small smile corner where the joint was held
Run: python tools/players/remove_rasta_joint.py   (writes a before/after QA sheet next to the output in reports/v34)
"""
import os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art_backup", "v34_rastabot", "head.png")
OUT = os.path.join(ROOT, "game", "assets", "robots", "tin", "head.png")
QA = os.path.join(ROOT, "reports", "v34", "rastabot_joint_removal.png")
FW, FH, N = 254, 203, 7
SS = 6  # supersampling for the drawn strokes

JOINT = [(162, 138), (165, 133.5), (222, 134.5), (237, 139), (237, 159), (222, 161), (200, 157), (171, 150), (162, 144)]


def poly_mask(pts, w, h):
    m = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(m).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return np.array(m.resize((w, h), Image.LANCZOS)) / 255.0


def stroke_alpha(points, width, w, h):
    m = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(m)
    sp = [(x * SS, y * SS) for x, y in points]
    d.line(sp, fill=255, width=int(width * SS), joint="curve")
    r = width * SS / 2
    for x, y in (sp[0], sp[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    return np.array(m.resize((w, h), Image.LANCZOS)) / 255.0


def bezier(p0, p1, p2, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                    (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]))
    return out


def repair(f):
    f = f.astype(float)
    h, w = f.shape[:2]
    jm = poly_mask(JOINT, w, h) > 0.02
    # 1. smoke: everything right of the silhouette above the joint; joint tip beyond the dreadlocks
    f[40:134, 203:] = 0
    tip = np.zeros_like(jm)
    tip[:, 198:] = True
    f[jm & tip] = 0
    f[128:166, 201:] = 0     # the joint's upper rim / tip anti-aliasing beyond the dreadlocks
    # 2. face skin under the joint (columns left of the hidden contour): vertical interpolation skin-above -> skin-below
    for x in range(160, 183):
        col = np.where(jm[:, x])[0]
        if col.size == 0:
            continue
        y0, y1 = col.min() - 1, col.max() + 1
        top = f[y0, x].copy()
        # first visible skin below the joint in this column (lower face edge may already be outline)
        bot = f[min(y1, 152), x].copy()
        if bot[:3].sum() < 300:   # outline / lock below -> keep the skin tone of the row above
            bot = top
        for y in col:
            t = (y - y0) / max(y1 - y0, 1)
            f[y, x] = top * (1 - t) + bot * t
    # 3. dreadlock behind the joint (right of the contour): continue the bead texture from 18 px above
    for x in range(176, 199):
        col = np.where(jm[:, x])[0]
        for y in col:
            src = f[y - 18, x]
            if src[3] < 10:          # outside the lock above -> lock outline colour
                src = np.array([24, 14, 10, 255.0])
            f[y, x] = src
    # region between the face contour and the lock (behind the face edge): dark lock shadow
    # 4. hidden face contour: from the visible end above (181,133) to the visible end below (170,147.5)
    arc = bezier((181.6, 132.0), (180.0, 142.0), (169.6, 147.8))
    a = stroke_alpha(arc, 2.4, w, h)
    # skin on the face side of the new contour, lock texture on the far side (already filled); clip the face fill
    face_side = poly_mask([(150, 130), (181.6, 132.0), (180.6, 137), (177.5, 143), (169.6, 147.8), (150, 147.8)], w, h)
    ink = np.array([22, 12, 8, 255.0])
    skin_ref = f[128, 172].copy()
    for y in range(133, 151):
        for x in range(160, 186):
            if not jm[y, x]:
                continue
            fs = face_side[y, x]
            if fs < 0.98 and x >= 170:
                # outside the face: lock texture (from above) under any partial skin coverage
                pass
            if fs > 0.02 and x >= 176:
                f[y, x] = skin_ref * fs + f[y, x] * (1 - fs)
    # outside the face contour (between face edge and lock): the dark lower lock continues upward (copied from 10 px below)
    for y in range(133, 152):
        for x in range(164, 188):
            if jm[y, x] and face_side[y, x] < 0.5 and y + 10 < h:
                f[y, x] = f[y + 10, x] if f[y + 10, x, 3] > 200 else np.array([28, 16, 11, 255.0])
    # clean-up: copied texture must stay lock-coloured (the gold earring / skin edge above must not repeat here)
    for y in range(133, 160):
        for x in range(170, 200):
            if jm[y, x] and face_side[y, x] < 0.5 and f[y, x, 0] > 110 and f[y, x, 3] > 0:
                f[y, x, :3] = np.array([62, 36, 24.0]) if (x + y) % 3 else np.array([44, 25, 17.0])
    for y in range(128, 152):
        for x in range(160, 190):
            if a[y, x] > 0:
                f[y, x, :3] = ink[:3] * a[y, x] + f[y, x, :3] * (1 - a[y, x])
                f[y, x, 3] = max(f[y, x, 3], 255 * a[y, x])
    # lock silhouette edge beside the old joint: drop stray pixels past the first gap, ink the edge pixel
    for y in range(132, 160):
        gap = 0
        last = -1
        for x in range(186, 203):
            if gap >= 2:
                f[y, x] = 0
                continue
            if f[y, x, 3] < 128:
                gap += 1
            else:
                gap = 0
                last = x
        if last > 0 and 136 <= y <= 156:
            f[y, last, :3] = ink[:3]
            f[y, last, 3] = 255
    # 5. mouth corner: the smile ends with a small upturn instead of the joint
    corner = stroke_alpha([(160.5, 140.6), (163.2, 139.6), (165.0, 137.9)], 1.7, w, h)
    for y in range(134, 145):
        for x in range(157, 168):
            if corner[y, x] > 0:
                f[y, x, :3] = ink[:3] * corner[y, x] + f[y, x, :3] * (1 - corner[y, x])
    return np.clip(f, 0, 255).astype(np.uint8)


def main():
    src = np.array(Image.open(SRC).convert("RGBA"))
    assert src.shape[1] == FW * N and src.shape[0] == FH, src.shape
    fixed0 = repair(src[:, 0:FW].copy())
    out = src.copy()
    region = (slice(40, FH), slice(160, FW))
    for i in range(N):
        f0 = src[:, 0:FW][region].astype(int)
        fi = src[:, i * FW:(i + 1) * FW][region].astype(int)
        same = np.abs(fi - f0).max(axis=2) <= 8
        tgt = out[:, i * FW:(i + 1) * FW]
        patch = fixed0[region]
        changed = np.abs(patch.astype(int) - f0).max(axis=2) > 0
        sel = changed & same       # only pixels the repair changed AND that are identical to frame 0 there
        tgt[region][sel] = patch[sel]
        leftover = changed & ~same
        print(f"frame {i}: patched {int(sel.sum())} px, skipped (frame-specific) {int(leftover.sum())}")
    Image.fromarray(out).save(OUT)
    # QA sheet: before / after, frames 0 and 1, at 1x and 4x
    before, after = Image.fromarray(src), Image.fromarray(out)
    sheet = Image.new("RGBA", (FW * 4 * 2 + 20, FH * 4 * 2 + 20), (70, 160, 220, 255))
    for r, im in enumerate([before, after]):
        for c, fi in enumerate([0, 1]):
            fr = im.crop((fi * FW, 0, (fi + 1) * FW, FH)).resize((FW * 4, FH * 4), Image.NEAREST)
            sheet.alpha_composite(fr, (c * (FW * 4 + 20), r * (FH * 4 + 20)))
    os.makedirs(os.path.dirname(QA), exist_ok=True)
    sheet.save(QA)
    print("wrote", OUT, "and", QA)


if __name__ == "__main__":
    main()
