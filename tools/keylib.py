"""Shared helpers for chroma-keying the source videos (numpy + Pillow only)."""
import numpy as np
from PIL import Image


def load_rgb(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32)


def green_key(rgb, lo=18.0, hi=60.0):
    """Return (rgba float array, alpha 0..1). Green dominance -> transparency, with despill."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dom = g - np.maximum(r, b)
    alpha = np.clip((hi - dom) / (hi - lo), 0.0, 1.0)
    # despill: clamp green to the max of the other two channels where it dominates
    g2 = np.where(dom > 0, np.maximum(r, b) + np.clip(dom, 0, 8) * 0.0, g)
    out = np.stack([r, g2, b, alpha * 255.0], axis=-1)
    return out, alpha


def _shift_min(m, r, axis):
    out = m.copy()
    for d in range(1, r + 1):
        out = np.minimum(out, np.roll(m, d, axis=axis))
        out = np.minimum(out, np.roll(m, -d, axis=axis))
    return out


def _shift_max(m, r, axis):
    out = m.copy()
    for d in range(1, r + 1):
        out = np.maximum(out, np.roll(m, d, axis=axis))
        out = np.maximum(out, np.roll(m, -d, axis=axis))
    return out


def erode(m, r):
    return _shift_min(_shift_min(m, r, 0), r, 1)


def dilate(m, r):
    return _shift_max(_shift_max(m, r, 0), r, 1)


def opening(m, r):
    return dilate(erode(m, r), r)


def largest_components(mask, keep=1, min_frac=0.02):
    """Label 4-connected components of a boolean mask (iterative scanline fill) and keep the big ones."""
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    sizes = [0]
    cur = 0
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys, xs):
        if labels[sy, sx]:
            continue
        cur += 1
        stack = [(sy, sx)]
        labels[sy, sx] = cur
        n = 0
        while stack:
            y, x = stack.pop()
            n += 1
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not labels[ny, nx]:
                    labels[ny, nx] = cur
                    stack.append((ny, nx))
        sizes.append(n)
    sizes = np.array(sizes)
    total = sizes[1:].sum() if cur else 1
    order = np.argsort(-sizes[1:])[:keep] + 1
    keepset = [i for i in order if sizes[i] >= min_frac * total]
    return np.isin(labels, keepset)


def bbox(alpha, thr=0.05, pad=4):
    ys, xs = np.nonzero(alpha > thr)
    h, w = alpha.shape
    return (max(xs.min() - pad, 0), max(ys.min() - pad, 0), min(xs.max() + pad + 1, w), min(ys.max() + pad + 1, h))


def to_image(rgba):
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")


def bleed_rgb(rgba, iters=6):
    """Copy colour of opaque pixels into transparent neighbours so bilinear filtering has no green halos."""
    rgb = rgba[..., :3].copy()
    a = rgba[..., 3] > 8
    known = a.copy()
    for _ in range(iters):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(known.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * k[..., None]
            cnt += k
        new = (~known) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][:, None]
        known = known | new
    rgb[~known] = 0
    out = rgba.copy()
    out[..., :3] = rgb
    return out
