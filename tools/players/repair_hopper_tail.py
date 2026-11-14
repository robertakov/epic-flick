"""v29 targeted repair of Kengurobot's tail texture (game/assets/robots/hopper/tail.png).

In the master the glove overlaps the tail, so the extracted tail had a hand-shaped bite in its upper edge
(texture columns ~88..160). The art under the glove never existed in the master, so the missing band is
reconstructed from the tail's own pixels:
  * the target top edge follows the tail's smooth thickness between the intact columns on both sides (it keeps the
    sag of the existing lower edge, so the banana curve continues naturally);
  * in each damaged column the band between that target edge and the bite is filled with the column's own body
    colour (taken just below the bite's ink outline, horizontally median-smoothed), and a new ink outline with the
    same thickness / anti-aliasing / dark rim as the intact edge is drawn on the target edge;
  * the bite's old outline (including its vertical walls) is covered by the fill; everything below stays original.
Only tail.png changes. The untouched v28 texture is kept in reports/v29_tail/tail_v28_original.png (the repair
always starts from it, so re-running is idempotent).
usage: python -B -I tools/players/repair_hopper_tail.py
"""
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import median_filter

ROOT = Path(__file__).resolve().parents[2]
TAIL = ROOT / "game/assets/robots/hopper/tail.png"
WORK = ROOT / "reports/v29_tail"
X0, X1 = 87, 161          # intact anchor columns on both sides of the bite
INK = 4.6                 # outline thickness (texture px) measured on the intact upper edge (x 70..86)


def lum(c):
    return c[..., 0] * .299 + c[..., 1] * .587 + c[..., 2] * .114


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    orig = WORK / "tail_v28_original.png"
    if not orig.exists():
        Image.open(TAIL).save(orig)
    src = np.array(Image.open(orig).convert("RGBA")).astype(np.float64)
    a = src[..., 3]
    H, W = a.shape

    def ink_start(x):
        return int(np.where(a[:, x] > 200)[0].min())

    def bottom(x):
        return int(np.where(a[:, x] > 200)[0].max())

    tl, tr = ink_start(X0), ink_start(X1)
    kl, kr = bottom(X0) - tl, bottom(X1) - tr
    cols = range(X0 + 1, X1)
    info = {}
    for x in cols:
        s = ink_start(x)
        e = s
        while e < min(H - 1, s + 30) and (lum(src[e, x]) < 110 or a[e, x] < 250):
            e += 1
        body = np.median(src[e + 1:e + 5, x, :3], axis=0)
        u = (x - X0) / (X1 - X0); u = u * u * (3 - 2 * u)
        t = bottom(x) - (kl * (1 - u) + kr * u)
        info[x] = (s, e, body, t)
    # the lower edge is integer-stepped: replace the target curve by a smooth quadratic through it (no stair steps)
    xs = np.array(list(cols), float); ts = np.array([info[x][3] for x in cols])
    fit = np.polyval(np.polyfit(np.r_[X0, xs, X1], np.r_[tl, ts, tr], 2), xs)
    for k, x in enumerate(cols):
        s, e, b, _ = info[x]
        info[x] = (s, e, b, float(fit[k]))
    bodies = median_filter(np.array([info[x][2] for x in cols]), size=(7, 1), mode="nearest")
    out = src.copy()
    ink_col = np.array([4.0, 2.0, 1.0])
    for k, x in enumerate(cols):
        s, e, _, t = info[x]
        body = bodies[k]
        redraw = t < s + 1.0                   # the new edge is above (or at) the bitten edge
        if not redraw and e <= t + INK + 1.2:
            continue
        for y in range(int(np.floor(t)) - 1, e + 2):
            d = y + .5 - t                     # distance below the target edge (px)
            if d < -.5:
                continue
            if not redraw and d < INK + 1.2:   # keep the original edge, only paint over the bite's inner walls
                continue
            if d < .5:                         # anti-aliased outer edge
                alpha = d + .5
                out[y, x] = [*ink_col, 255 * alpha]
            elif d < INK:
                out[y, x] = [*ink_col, 255]
            elif d < INK + 1.2:                # dark rim like the intact edge (ink blending into the body colour)
                f = (d - INK) / 1.2
                out[y, x, :3] = ink_col * (1 - f) * .55 + body * (.45 + .55 * f); out[y, x, 3] = 255
            elif y <= e:
                out[y, x, :3] = body; out[y, x, 3] = 255
        if redraw:                             # rows above the new edge must be empty
            out[:max(0, int(np.floor(t)) - 1), x] = 0
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA").save(TAIL)
    print("repaired columns", X0 + 1, "..", X1 - 1, "anchors", (X0, tl, kl), (X1, tr, kr))


if __name__ == "__main__":
    main()
