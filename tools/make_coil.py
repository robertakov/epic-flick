"""Procedural coil ring in the style of the samurai's springs (dark gunmetal torus, thick ink outline).

The in-game spring renderer stacks these rings along the simulated spring axis, so compression and
extension change ring spacing instead of distorting the art.
"""
import numpy as np
from PIL import Image


def coil_ring(path, w=60, h=24, tube=0.30, ink=0.12, ss=4):
    """w,h = ring outer size in px (at the robot's 0.5 export scale). Saves RGBA and returns size."""
    pad = 4
    W, H = (w + 2 * pad) * ss, (h + 2 * pad) * ss
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    cx, cy = W / 2, H / 2
    a = (w / 2) * ss * (1 - tube / 2 - ink / 2)
    b = (h / 2) * ss * (1 - tube - ink)
    nx, ny = (xx - cx) / a, (yy - cy) / b
    r = np.sqrt(nx * nx + ny * ny)
    # distance from the ring centre-line in units of the ring's minor radius (approximate)
    t = np.abs(r - 1.0) * (b / ((h / 2) * ss)) * 2.2
    body = t < tube
    outline = (t >= tube) & (t < tube + ink)
    front = ny > 0  # lower half is the near side of the ring
    # shading across the tube: lighter towards the outer top edge of each side
    u = (r - 1.0) / max(tube, 1e-3)
    base = np.where(front, 86.0, 46.0)
    shade = base + np.where(front, -u * 18.0, u * 10.0)
    col = np.stack([shade * 1.02, shade * 0.98, shade * 0.94], -1)
    # specular streak on the near side
    spec = front & body & (np.abs(u + 0.35) < 0.18) & (np.abs(nx) < 0.75)
    col[spec] = (178, 172, 164)
    img = np.zeros((H, W, 4), np.float32)
    img[body, :3] = col[body]
    img[body, 3] = 255
    img[outline, :3] = 16
    img[outline, 3] = 255
    im = Image.fromarray(img.astype(np.uint8), "RGBA").resize((W // ss, H // ss), Image.LANCZOS)
    im.save(path)
    return [W // ss, H // ss]


if __name__ == "__main__":
    import sys
    print(coil_ring(sys.argv[1]))
