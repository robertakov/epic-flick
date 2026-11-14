"""v28 AUTHORITATIVE playable-robot rig builder (replaces process_png_characters.py / build_samurobot_master.py).

Rebuilds all five playable robots from the master PNGs in Characters/Players (read-only; never modified):
  tin     Rastabot.png                               hopper  Kengurobot.png
  heavy   sumobot.png                                rocket  Chronobot.png
  samurai file_000000007ab881f6bf1f9325d404bb87.png  (new Samurobot master, 2026-10-15)
The MP4s next to them are motion references only (never runtime textures).

Pipeline per robot (tools/players/rigkit.py):
  1. matte: key colour measured from the image, flood-connected green unmixing (no erosion, ink outlines kept,
     green art like Rastabot's hat/shoes untouched), edge despill, speckle removal. No shadow is added anywhere.
  2. parts: seeded watershed over the ink map (seeds + optional zones in tools/players/rig_seeds.json) -> every cut
     follows a drawn outline. Only LOWER-z parts get a hidden 3 px overlap under their upper neighbours
     (legs under torso, torso under arms/head, tail under torso/legs) so intact robots have no seams and detached
     upper parts carry no foreign pixels.
  3. runtime: head (7-frame face atlas: neutral, blink, happy, scared, angry, look_left, look_right - eye-region
     warps of the master face, silhouette identical in all frames), torso, arm_l/r, leg_l/r (+ hopper tail),
     manifest.json + visual_rig.json in game/assets/robots/<id>/ (schema unchanged: png_modular runtime path).
Joints (DATA) are measured in master pixels. Diagnostics: reports/v28_rigs/ (overlay of the part labels,
reconstruction board, per-robot QA json).
usage: python -B -I tools/players/build_player_rigs.py   (Python with Pillow, numpy and scipy)
"""
from pathlib import Path
import json, hashlib, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as nd

sys.path.insert(0, str(Path(__file__).parent))
import rigkit  # noqa

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "Assets/Characters/Players"   # masters moved here by the user (2026-10-15)
OUT = ROOT / "game/assets/robots"
WORK = ROOT / "reports/v28_rigs"
SEEDS = json.loads((Path(__file__).parent / "rig_seeds.json").read_text(encoding="utf8"))

# center = torso pivot, sole = lowest boot row, neck/shoulders/hips = attachment points on the torso,
# spring_arm / spring_leg = master rows where the coil deforms, hands / feet = limb end points, eyes = boxes.
DATA = {
    "tin": dict(file="Rastabot.png", visual="rasta", scale=.25, center=[640, 544], sole=1165, neck=[640, 413],
                shoulders=[[555, 472], [739, 476]], hips=[[574, 674], [701, 674]], spring_arm=[530, 610],
                spring_leg=[708, 885], feet=[[476, 1165], [819, 1165]], hands=[[418, 753], [878, 746]],
                eyes=[[623, 200, 705, 277], [715, 184, 782, 265]]),
    "hopper": dict(file="Kengurobot.png", visual="kenguru", scale=.24, center=[604, 647], sole=1319, neck=[606, 508],
                   shoulders=[[523, 558], [698, 556]], hips=[[531, 798], [678, 795]], spring_arm=[615, 711],
                   spring_leg=[837, 1049], feet=[[402, 1319], [804, 1319]], hands=[[343, 840], [876, 837]],
                   eyes=[[570, 256, 670, 366], [689, 256, 736, 344]]),
    "heavy": dict(file="sumobot.png", visual="sumo", scale=.25, center=[595, 758], sole=1307, neck=[600, 476],
                  shoulders=[[410, 561], [811, 573]], hips=[[414, 1037], [773, 1044]], spring_arm=[656, 731],
                  spring_leg=[1040, 1103], feet=[[343, 1307], [847, 1307]], hands=[[163, 885], [1019, 874]],
                  eyes=[[605, 269, 695, 351], [717, 270, 754, 345]]),
    "rocket": dict(file="Chronobot.png", visual="chronos", scale=.24, center=[579, 659], sole=1339, neck=[578, 502],
                   shoulders=[[447, 558], [697, 563]], hips=[[497, 834], [648, 826]], spring_arm=[637, 742],
                   spring_leg=[845, 1083], feet=[[365, 1339], [781, 1339]], hands=[[292, 903], [855, 903]],
                   eyes=[[580, 260, 660, 357], [680, 261, 733, 350]], rigid_middle=[928, 1010]),
    "samurai": dict(file="file_000000007ab881f6bf1f9325d404bb87.png", visual="samurai", scale=.26, center=[630, 640],
                    sole=1226, neck=[630, 482], shoulders=[[452, 528], [808, 528]], hips=[[548, 762], [712, 762]],
                    spring_arm=[560, 688], spring_leg=[822, 988], feet=[[395, 1226], [875, 1226]],
                    hands=[[300, 800], [960, 800]], eyes=[[552, 310, 618, 380], [642, 310, 708, 380]],
                    lid=(244, 236, 222)),
}
Z = {"tail": -3, "leg_l": -1, "leg_r": -1, "torso": 0, "arm_l": 1, "arm_r": 1, "head": 2}
OVERLAP = 2


def extract(rgba, mask):
    """crop + half-size like v23 (texel density preserved). Keeps every component >= 120 px (springs seen through
    gaps are real art), drops specks."""
    cut = rgba.copy(); cut[~mask] = 0
    lab, n = nd.label(cut[..., 3] > 30)
    if n:
        sizes = np.bincount(lab.ravel()); sizes[0] = 0
        keep = np.isin(lab, np.where(sizes >= 120)[0])
        cut[~nd.binary_dilation(keep, iterations=2)] = 0
    y, x = np.where(cut[..., 3] > 8)
    box = [max(0, int(x.min()) - 10), max(0, int(y.min()) - 10), min(rgba.shape[1], int(x.max()) + 11), min(rgba.shape[0], int(y.max()) + 11)]
    im = Image.fromarray(cut).crop(box)
    # premultiplied resample avoids dark/green fringes on the half-size texture
    im = im.resize((round(im.width * .5), round(im.height * .5)), Image.Resampling.LANCZOS, reducing_gap=None) if False else _premul_resize(im)
    return im, box


def _premul_resize(im):
    a = np.array(im).astype(np.float64)
    al = a[..., 3:4] / 255.0
    pm = np.dstack([a[..., :3] * al, a[..., 3:4]])
    w, h = round(im.width * .5), round(im.height * .5)
    chans = [np.array(Image.fromarray(pm[..., c].astype(np.float32), "F").resize((w, h), Image.Resampling.LANCZOS)) for c in range(4)]
    out = np.dstack(chans)
    alpha = np.clip(out[..., 3], 0, 255)
    rgb = np.where(alpha[..., None] > 0.5, out[..., :3] / np.maximum(alpha[..., None] / 255.0, 1e-6), 0)
    res = np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8)
    res[res[..., 3] < 2] = 0
    return Image.fromarray(res, "RGBA")


def local(pt, box): return [(pt[0] - box[0]) * .5, (pt[1] - box[1]) * .5]


def face_variants(head, hb, d):
    variants = []
    for state in ["neutral", "blink", "happy", "scared", "angry", "look_left", "look_right"]:
        face = head.copy()
        for eye in d["eyes"]:
            x0, y0 = local(eye[:2], hb); x1, y1 = local(eye[2:], hb)
            x0, y0, x1, y1 = map(round, [x0, y0, x1, y1]); ew = x1 - x0; eh = y1 - y0
            if state in ["look_left", "look_right", "scared", "angry", "happy"]:
                yy, xx = np.mgrid[0:eh, 0:ew].astype(float)
                dx = -3 if state == "look_left" else 3 if state == "look_right" else 0
                sy = 1.1 if state == "scared" else .82 if state in ["angry", "happy"] else 1
                crop = np.array(head.crop((x0, y0, x1, y1))); warped = np.empty_like(crop)
                for c in range(4):
                    warped[:, :, c] = nd.map_coordinates(crop[:, :, c], [np.clip((yy - eh * .55) / sy + eh * .55, 0, eh - 1), np.clip(xx - dx, 0, ew - 1)], order=1)
                m = Image.new("L", (ew, eh)); ImageDraw.Draw(m).ellipse((1, 1, ew - 2, eh - 2), fill=255); m = m.filter(ImageFilter.GaussianBlur(2))
                face.paste(Image.fromarray(warped), (x0, y0), m)
            elif state == "blink":
                lid = face.copy(); dr = ImageDraw.Draw(lid)
                dr.ellipse((x0, y0, x1, y1), fill=tuple(d.get("lid", (223, 174, 100))) + (255,))
                dr.line([(x0 + ew * (.04 + .92 * j / 20), y0 + eh * (.55 + .10 * np.sin(j / 20 * np.pi))) for j in range(21)], fill=(35, 24, 18, 255), width=3)
                m = Image.new("L", head.size); ImageDraw.Draw(m).ellipse((x0 + 1, y0 + 1, x1 - 1, y1 - 1), fill=255); m = m.filter(ImageFilter.GaussianBlur(1.2))
                face = Image.composite(lid, face, m)
        face.putalpha(head.getchannel("A")); variants.append(face)
    return variants


def build(rid, d, report):
    src = SRC / d["file"]
    rgba, key = rigkit.matte(np.array(Image.open(src).convert("RGB")))
    s = SEEDS[rid]
    lab = rigkit.segment(rgba, s["seeds"], s.get("zones"))
    rigkit.overlay(rgba, lab, WORK / f"{rid}_parts.png", .5)
    vis = rgba[..., 3] > 0
    parts = [p for p in rigkit.PARTS if (lab == rigkit.LABEL[p]).any()]
    masks = {}
    for p in parts:
        m = lab == rigkit.LABEL[p]
        higher = np.zeros_like(m)
        for q in parts:
            if Z[q] > Z[p]:
                higher |= lab == rigkit.LABEL[q]
        # hidden overlap: grow only under parts drawn on top of this one, 1 px per step through visible pixels
        # (geodesic: never jumps a transparent gap, so a detached part carries no floating shards)
        g = m.copy()
        for _ in range(OVERLAP):
            g |= nd.binary_dilation(g) & higher & vis
        masks[p] = g
    dest = OUT / rid; dest.mkdir(parents=True, exist_ok=True)
    for f in dest.glob("*.png"):
        if f.stem not in parts:
            f.unlink()                 # e.g. a stale tail.png
    images, boxes = {}, {}
    for p in parts:
        images[p], boxes[p] = extract(rgba, masks[p])
    profile = {"png_modular": True, "source_scale": d["scale"], "torso_scale": [1, 1], "head_scale": [1, 1], "torso_offset": [0, 0], "parts": {}, "anchors": {}}
    bodybox = boxes["torso"]
    floor = 159.19                      # physical rest floor at rig.s=.42 (hip 35.7 + cap 13.31 + rest 56 + boot 54.18)
    profile["torso_offset"] = [0, (floor - (d["sole"] - d["center"][1]) * d["scale"]) / .42]
    for name, pt in [("neck", d["neck"]), ("shoulder_l", d["shoulders"][0]), ("shoulder_r", d["shoulders"][1]),
                     ("hip_l", d["hips"][0]), ("hip_r", d["hips"][1])]:
        profile["anchors"][name] = local(pt, bodybox)
    mf = {"schema": 2, "robot": rid, "visual_id": d["visual"], "png_modular": True, "fps": 10,
          "source": {"file": d["file"], "sha256": hashlib.sha256(src.read_bytes()).hexdigest(), "builder": "tools/players/build_player_rigs.py v28"},
          "parts": {}, "decorations": []}
    for p in ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]:
        box = boxes[p]; img = images[p]
        pt = d["neck"] if p == "head" else d["center"] if p == "torso" else d["shoulders"][0 if p.endswith("l") else 1] if p.startswith("arm") else d["hips"][0 if p.endswith("l") else 1]
        piv = local(pt, box)
        geom = {"pivot": piv, "unit_scale": d["scale"] * 2, "z": Z[p]}
        if p.startswith(("arm", "leg")):
            side = 0 if p.endswith("l") else 1
            end = d["hands"][side] if p.startswith("arm") else d["feet"][side]
            lo, hi = d["spring_arm"] if p.startswith("arm") else d["spring_leg"]
            geom.update(end=local(end, box), spring_rows=[(lo - box[1]) * .5, (hi - box[1]) * .5], inertia_gain=.2, png_modular=True)
            if p.startswith("leg") and "rigid_middle" in d:
                geom["rigid_middle_rows"] = [(d["rigid_middle"][0] - box[1]) * .5, (d["rigid_middle"][1] - box[1]) * .5]
        profile["parts"][p] = geom
        mf["parts"][p] = {"atlas": p + ".png", "frame_size": list(img.size), "columns": 1, "count": 1, "pivot": piv, "clips": {"idle": [0]}, "source_origin": box[:2]}
        if p != "head":
            img.save(dest / f"{p}.png")
    if "tail" in images:
        images["tail"].save(dest / "tail.png")
        profile["tail"] = {"offset": local([boxes["tail"][0], boxes["tail"][1]], bodybox), "file": "tail.png", "z": Z["tail"]}
    variants = face_variants(images["head"], boxes["head"], d)
    atlas = Image.new("RGBA", (images["head"].width * len(variants), images["head"].height))
    for i, f in enumerate(variants):
        atlas.paste(f, (i * images["head"].width, 0))
    atlas.save(dest / "head.png")
    idle = [0] * 27 + [1, 1] + [0] * 12 + [5] * 9 + [0] * 10 + [6] * 8
    mf["parts"]["head"].update(columns=7, count=7, clips={"idle": idle, "neutral": idle, "happy": [2], "scared": [3], "angry": [4],
                               "determined": [0, 0, 6, 6, 0, 0, 5, 5], "dizzy": [5, 6], "dead": [1], "pain": [4]})
    (dest / "manifest.json").write_text(json.dumps(mf, ensure_ascii=False, indent=2) + "\n", encoding="utf8", newline="\n")
    (dest / "visual_rig.json").write_text(json.dumps(profile, indent=2) + "\n", encoding="utf8", newline="\n")
    # QA: every visible master pixel belongs to exactly one part; no green; no shadow; reconstruction error
    recon = Image.new("RGBA", (rgba.shape[1], rgba.shape[0]))
    for p in sorted(parts, key=lambda q: Z[q]):
        pc = images[p].resize((boxes[p][2] - boxes[p][0], boxes[p][3] - boxes[p][1]), Image.Resampling.LANCZOS)
        recon.alpha_composite(pc, (boxes[p][0], boxes[p][1]))
    ra = np.array(recon).astype(float); ma = rgba.astype(float)
    a_err = np.abs(ra[..., 3] - ma[..., 3])
    green = 0
    for p in parts:
        t = np.array(images[p]).astype(int)
        green += int(((t[..., 3] > 20) & (t[..., 1] > t[..., 0] + 25) & (t[..., 1] > t[..., 2] + 25) & (t[..., 3] < 250)).sum())
    report[rid] = {"key": [int(v) for v in key], "parts": {p: list(images[p].size) for p in parts},
                   "unassigned_visible_px": int((vis & (lab == 0)).sum()),
                   "recon_alpha_mean_err": round(float(a_err.mean()), 3), "recon_alpha_err_px_gt64": int((a_err > 64).sum()),
                   "green_edge_px": green, "semi_alpha_far_from_solid_px": int(((rgba[..., 3] > 8) & (rgba[..., 3] < 200) & ~nd.binary_dilation(rgba[..., 3] >= 200, iterations=3)).sum())}
    recon.save(WORK / f"{rid}_reconstruction.png")
    return recon


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    only = sys.argv[1:]
    report = {}
    board = Image.new("RGBA", (2000, 760), (42, 48, 57, 255)); dr = ImageDraw.Draw(board)
    for col, (rid, d) in enumerate(DATA.items()):
        if only and rid not in only:
            continue
        recon = build(rid, d, report)
        recon.thumbnail((390, 720)); board.alpha_composite(recon, (col * 400, 30)); dr.text((col * 400 + 10, 8), rid, fill="white")
    board.save(WORK / "reconstruction_board.png")
    prev = json.loads((WORK / "qa.json").read_text()) if (WORK / "qa.json").exists() and only else {}
    prev.update(report)
    (WORK / "qa.json").write_text(json.dumps(prev, indent=1), encoding="utf8")
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
