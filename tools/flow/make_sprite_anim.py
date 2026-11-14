"""Google Flow clip (flat chroma-green background) -> keyed sprite sheet + still PNG for Godot.

usage: python -I tools/flow/make_sprite_anim.py <clip.mp4> <out_dir> <name> [--fps 12] [--size 256] [--cols 9]
Outputs (out_dir):
  <name>_sheet.png   frames in a grid (cols x rows), RGBA, every frame the same size, the subject centred on
                     the union bounding box of all frames (no per-frame jitter)
  <name>_still.png   frame 0 (same crop), for static use / fallback
  <name>_sheet.json  {"frames": N, "cols": C, "frame_size": S, "fps": F}
  <name>_preview.png the first 9 frames on a checkerboard (review only, keep out of the game folder)
Key: green dominance (g - max(r, b)) mapped to soft alpha + spill suppression; small blobs on the edges of the
frame (video watermark / compression noise) are ignored when measuring the bounding box.
"""
import json
import sys
from pathlib import Path

import av
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from flow_key import key  # noqa: E402


def main() -> None:
    args = sys.argv[1:]
    clip, out_dir, name = Path(args[0]), Path(args[1]), args[2]
    opt = {"--fps": 12, "--size": 256, "--cols": 9}
    for i, k in enumerate(args):
        if k in opt:
            opt[k] = int(args[i + 1])
    out_dir.mkdir(parents=True, exist_ok=True)
    c = av.open(str(clip))
    st = c.streams.video[0]
    src_fps = float(st.average_rate)
    step = src_fps / opt["--fps"]
    frames = []
    for i, fr in enumerate(c.decode(st)):
        if i >= len(frames) * step - 1e-6:
            frames.append(key(fr.to_ndarray(format="rgb24")))
    # union bbox of opaque pixels (ignore a 2 % border band against watermarks / edge noise)
    h, w = frames[0].shape[:2]
    m = int(min(w, h) * 0.02)
    union = np.zeros((h, w), bool)
    for f in frames:
        union |= f[..., 3] > 128
    union[:m, :] = union[-m:, :] = False
    union[:, :m] = union[:, -m:] = False
    ys, xs = np.nonzero(union)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    side = int(max(x1 - x0, y1 - y0) * 1.06) + 4
    box = (int(cx - side / 2), int(cy - side / 2), int(cx - side / 2) + side, int(cy - side / 2) + side)
    S, C = opt["--size"], opt["--cols"]
    tiles = [Image.fromarray(f, "RGBA").crop(box).resize((S, S), Image.LANCZOS) for f in frames]
    n = len(tiles)
    rows = (n + C - 1) // C
    sheet = Image.new("RGBA", (C * S, rows * S), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % C) * S, (i // C) * S))
    sheet.save(out_dir / f"{name}_sheet.png", optimize=True)
    tiles[0].save(out_dir / f"{name}_still.png", optimize=True)
    (out_dir / f"{name}_sheet.json").write_text(json.dumps({"frames": n, "cols": C, "frame_size": S, "fps": opt["--fps"]}))
    # review preview on a checkerboard
    chk = np.indices((3 * S, 3 * S)).sum(0) // 16 % 2
    pv = Image.fromarray(np.dstack([np.where(chk, 200, 120).astype(np.uint8)] * 3 + [np.full((3 * S, 3 * S), 255, np.uint8)]), "RGBA")
    for i, t in enumerate(tiles[: 9 * max(1, n // 9): max(1, n // 9)][:9]):
        pv.alpha_composite(t, ((i % 3) * S, (i // 3) * S))
    pv.save(out_dir / f"{name}_preview.png")
    print(f"{clip.name}: {src_fps:.2f} fps src, {n} frames @ {opt['--fps']} fps, crop {box}, sheet {sheet.size}")


if __name__ == "__main__":
    main()
