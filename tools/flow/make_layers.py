"""Google Flow stills -> runtime layers for EpicShalban (deterministic, sources stay in Assets/Flow).

usage:
  python -I make_layers.py strip <src[,src2,...]> <out.png> [--key magenta] [--height 360] [--overlap 0.05]
      keyed hill band(s), cropped to the silhouette, chained A->B->..->A at the best-matching columns with a short
      cross-fade (seamless horizontal tiling, longer repeat period with several sources), resized; prints the mean
      bottom colour (used as the flat fill below the strip at runtime)
  python -I make_layers.py plain <src> <out.png> [--size 1024x576]
      opaque backdrop (sky), resized
  python -I make_layers.py parts <src> <out_dir> <prefix> [--key green] [--max 256] [--min_area 0.002] [--merge 9]
      keyed sheet of separate objects -> one tight PNG per object (sorted left->right, top->bottom)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from flow_key import key  # noqa: E402


def opt(args, name, default):
    return type(default)(args[args.index(name) + 1]) if name in args else default


def _load_band(src, k):
    im = key(np.asarray(Image.open(src).convert("RGB")), k)
    w = im.shape[1]
    m = int(w * 0.01)
    return im[:, m: w - m].astype(np.float32)             # generators often leave a seam on the very border


def _feat(f):
    small = f[::4, ::2]
    wa = small[..., 3:4] / 255.0
    return np.concatenate([small[..., :3] * wa, small[..., 3:4] * 3.0], -1)


def _best_seam(fa, fb, ovs):
    """column j in the right 40 % of A and i in the left 40 % of B whose windows look most alike
    (silhouette/alpha weighted 3x), so the short cross-fade never ghosts a tree or a fence"""
    sa, sb = fa.shape[1], fb.shape[1]
    best = None
    for i in range(0, int(sb * 0.4)):
        b = fb[:, i: i + ovs]
        for j in range(sa - int(sa * 0.4), sa - ovs):
            c = np.abs(fa[:, j: j + ovs] - b).mean()
            if best is None or c < best[0]:
                best = (c, j * 2, i * 2)
    return best


def strip(srcs, out, args):
    """One or more hill bands chained into one horizontally seamless strip (A -> B -> ... -> back to A)."""
    k = opt(args, "--key", "magenta")
    bands = [_load_band(s, k) for s in srcs]
    hmin = min(b.shape[0] for b in bands)
    bands = [b[b.shape[0] - hmin:] for b in bands]          # bottom-aligned, same height
    top = min(int(np.nonzero((b[..., 3] > 128).any(1))[0].min()) for b in bands)
    bands = [b[max(top - 4, 0):] for b in bands]
    if "--mirror" in args:
        # no seam surgery: the runtime tiles A, flipped A, A, ... which is seamless by construction;
        # --trim l,r cuts fractions off the ends so the mirror axis never splits a striking object
        b = bands[0]
        tl, tr = (float(v) for v in opt(args, "--trim", "0,0").split(","))
        b = b[:, int(b.shape[1] * tl): b.shape[1] - int(b.shape[1] * tr)]
        _save_strip(b, out, args)
        return
    ov = int(bands[0].shape[1] * opt(args, "--overlap", 0.05))
    feats = [_feat(b) for b in bands]
    n = len(bands)
    seams = []                                              # seams[k] = (end col in band k, start col in band k+1)
    for a in range(n):
        c, j, i = _best_seam(feats[a], feats[(a + 1) % n], max(2, ov // 2))
        seams.append((j, i))
        print(f"seam {a}->{(a + 1) % n}: end {j} / start {i}, cost {c:.1f}")
    t = np.linspace(1.0, 0.0, ov)[None, :, None]           # weight of the previous band's tail
    parts = []
    for a in range(n):
        start = seams[a - 1][1]                              # where the previous seam enters this band
        end = seams[a][0]
        prev, pend = bands[a - 1], seams[a - 1][0]
        head = prev[:, pend: pend + ov] * t + bands[a][:, start: start + ov] * (1 - t)
        parts += [head, bands[a][:, start + ov: end]]
    _save_strip(np.concatenate(parts, 1), out, args)


def _save_strip(res, out, args):
    img = Image.fromarray(np.clip(res, 0, 255).astype(np.uint8), "RGBA")
    bottom = np.asarray(img)[-6:, :, :3].reshape(-1, 3).mean(0) / 255.0
    print("bottom colour: Color(%.3f, %.3f, %.3f)" % tuple(bottom))
    H = opt(args, "--height", 360)
    img = img.resize((round(img.width * H / img.height), H), Image.LANCZOS)
    img.save(out, optimize=True)
    print(f"strip -> {out} {img.size}")


def plain(src, out, args):
    W, H = (int(v) for v in opt(args, "--size", "1024x576").split("x"))
    img = Image.open(src).convert("RGB")
    c = opt(args, "--crop", 0.04)                            # painted paper borders / stains on the edges
    img = img.crop((int(img.width * c), int(img.height * c), int(img.width * (1 - c)), int(img.height * (1 - c))))
    img = img.resize((W, H), Image.LANCZOS)
    from PIL import ImageEnhance
    img = ImageEnhance.Color(img).enhance(opt(args, "--sat", 1.0))
    img = ImageEnhance.Brightness(img).enhance(opt(args, "--bright", 1.0))
    img.save(out, optimize=True)
    print(f"plain {Path(src).name} -> {out} {img.size}")


def texture(src, out, args):
    """Greyscale multiply-detail texture, made seamless in 2D (offset-blend), mean ~--mean, darkest ~--floor."""
    S = opt(args, "--size", 512)
    lum = np.asarray(Image.open(src).convert("L").resize((S, S), Image.LANCZOS)).astype(np.float32) / 255.0
    rolled = np.roll(lum, (S // 2, S // 2), (0, 1))
    y, x = np.mgrid[0:S, 0:S] / (S - 1)
    m = np.sqrt(np.sin(np.pi * x) * np.sin(np.pi * y))
    t = m * lum + (1 - m) * rolled
    t = (t - t.mean()) / (t.std() + 1e-6)                   # unit contrast around 0
    mean, floor = opt(args, "--mean", 0.95), opt(args, "--floor", 0.80)
    t = mean + t * (mean - floor) / 2.5                     # ~2.5 sigma darkest -> floor
    img = Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8), "L")
    img.save(out, optimize=True)
    print(f"texture {Path(src).name} -> {out} {img.size} mean {np.clip(t, 0, 1).mean():.3f}")


def parts(src, out_dir, prefix, args):
    k = opt(args, "--key", "green")
    im = key(np.asarray(Image.open(src).convert("RGB")), k)
    a = im[..., 3] > 100
    merged = ndimage.binary_dilation(a, iterations=opt(args, "--merge", 9))
    lab, n = ndimage.label(merged)
    objs = ndimage.find_objects(lab)
    min_area = opt(args, "--min_area", 0.002) * a.size
    found = []
    for i, sl in enumerate(objs):
        mask = (lab[sl] == i + 1) & a[sl]
        if mask.sum() < min_area:
            continue
        found.append((sl, i + 1))
    rowh = im.shape[0] / 4
    found.sort(key=lambda s: (int(s[0][0].start // rowh), s[0][1].start))
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    mx = opt(args, "--max", 256)
    for j, (sl, idx) in enumerate(found):
        crop = im[sl].copy()
        crop[..., 3] = np.where(lab[sl] == idx, crop[..., 3], 0)
        ys, xs = np.nonzero(crop[..., 3] > 8)
        crop = crop[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
        p = Image.fromarray(crop, "RGBA")
        s = min(1.0, mx / max(p.size))
        p = p.resize((max(1, round(p.width * s)), max(1, round(p.height * s))), Image.LANCZOS)
        p = Image.fromarray(np.pad(np.asarray(p), ((2, 2), (2, 2), (0, 0))), "RGBA")
        p.save(Path(out_dir) / f"{prefix}_{j:02d}.png", optimize=True)
        print(f"{prefix}_{j:02d}.png {p.size}")


if __name__ == "__main__":
    a = sys.argv[1:]
    {"strip": lambda: strip(a[1].split(","), a[2], a), "texture": lambda: texture(a[1], a[2], a), "plain": lambda: plain(a[1], a[2], a),
     "parts": lambda: parts(a[1], a[2], a[3], a)}[a[0]]()
