"""Shared chroma key for Google Flow generations (flat #00FF00 or #FF00FF backgrounds).

key(rgb, color) -> RGBA uint8 array. Soft alpha from the key-colour dominance, despill (clamps the key channel(s) so no
green / pink fringe survives), 1 px alpha erosion + slight blur so edges never carry a halo of the background.
"""
import numpy as np
from PIL import Image, ImageFilter


def key(rgb: np.ndarray, color: str = "green", lo: int = 25, hi: int = 70, connected: bool = True) -> np.ndarray:
    """connected=True: only key-coloured regions touching the image border count as background, so green
    gumdrops / pink jelly INSIDE the subject never get holes punched into them."""
    a = rgb[..., :3].astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    if color == "green":
        dom = g - np.maximum(r, b)
    elif color == "magenta":
        dom = np.minimum(r, b) - g
    else:
        raise ValueError(color)
    if connected:
        from scipy import ndimage
        bg = dom > lo
        lab, _ = ndimage.label(bg)
        border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
        keep = set(int(v) for v in border[border > 0])
        # enclosed holes (sky seen through an arch / between branches) are background too when they are
        # almost pure key colour; painted green/pink objects are never that pure
        n = int(lab.max())
        if n:
            means = ndimage.mean(dom, lab, index=np.arange(1, n + 1))
            sizes = ndimage.sum(bg, lab, index=np.arange(1, n + 1))
            keep |= {i + 1 for i in range(n) if means[i] > 150 and sizes[i] > 30}
        reach = np.isin(lab, list(keep))
        reach = ndimage.binary_dilation(reach, iterations=3)   # keep the soft edge ramp next to the background
        dom = np.where(reach, dom, -999)
    alpha = np.clip((hi - dom) * (255.0 / (hi - lo)), 0, 255)
    out = a.copy()
    spill = dom > 0
    if color == "green":
        out[..., 1] = np.where(spill, np.maximum(r, b), g)
    else:
        out[..., 0] = np.where(spill, r - dom, r)
        out[..., 2] = np.where(spill, b - dom, b)
    rgba = np.dstack([np.clip(out, 0, 255).astype(np.uint8), alpha.astype(np.uint8)])
    im = Image.fromarray(rgba, "RGBA")
    al = im.split()[3].filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6))
    im.putalpha(al)
    return np.asarray(im).copy()
