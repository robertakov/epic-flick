"""v35 MK2 rig builder (the BASE builder build_player_rigs.py is NOT run and NOT modified by this).

Builds the five MK2 visual rigs from the approved MK2 masters (Assets/Characters/Players, read-only):
  tin_mk2      "rastabot mk2.png"      hopper_mk2  "kengurobot mk2.png"
  heavy_mk2    "sumorobot mk2.png"     rocket_mk2  "chronobot mk2.png"
  samurai_mk2  "Samurobot MK2.png"     (cleaned copy: the stray blade above the helmet removed, see clean_samurai)
Same part structure / schema as the base robots (head 7-frame face atlas, torso, arm_l/r, leg_l/r, optional rear
"tail" decoration attached to the torso: Kengurobot's tail, Chronobot MK2's cape). Physics / collision never come
from these files - RigData keeps using res://assets/robot/rig.json + the base RobotDefinition (identical colliders).
Rear decorations hidden behind moving parts (glove over the tail, legs over the cape) get their occluded pixels
reconstructed from their own colours (fill_rear), so no hand / leg shaped hole can show when those parts move.
usage: python -B -I tools/players/build_mk2_rigs.py [ids...] [--out DIR]
"""
from pathlib import Path
import json, hashlib, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

HERE = Path(__file__).resolve().parent
TOOLS = Path("G:/Godot/EpicShalban/tools/players") if not (HERE / "rigkit.py").exists() else HERE
sys.path.insert(0, str(TOOLS))
import rigkit  # noqa
import build_player_rigs as base  # noqa  (helpers only: extract, face_variants, local, Z)

ROOT = TOOLS.parents[1]
SRC = ROOT / "Assets/Characters/Players"
WORK = (ROOT / "reports/v35_mk2/rigs") if HERE == TOOLS else (HERE / "work")
SEEDS = json.loads((HERE / "rig_seeds_mk2.json").read_text(encoding="utf8"))
DATA = json.loads((HERE / "mk2_rig_data.json").read_text(encoding="utf8"))


def clamp01(v):
    return max(0.0, min(1.0, v))


def clean_samurai(rgb):
    """Removes the unwanted blade + dark fin above the helmet dome (between the crescent horns) of the approved
    Samurobot MK2 master: everything above the measured dome edge in x 557..705 becomes background; the dome's ink
    edge is redrawn where the blade sat on it. Nothing else of the approved art changes."""
    im = rgb.astype(float)
    key = np.median(im[5:40, 5:40].reshape(-1, 3), axis=0)
    old_pts = [(556, 104.0), (580, 102.0), (600, 102.0), (640, 103.0), (662, 106.0), (700, 116.0), (720, 123.0)]
    ox = np.array([p[0] for p in old_pts], float); oy = np.array([p[1] for p in old_pts], float)
    old_edge = lambda x: float(np.interp(x, ox, oy))  # noqa
    for x in range(557, 706):
        im[30:int(old_edge(x)) - 2, x] = key
    # v36: the blade had flattened the dome top and left two gold remnants of its collar on it (a diagonal sliver
    # at x 590..616 and the finial oval at x 620..655, y ~100..112). Both become dome metal, and the dome gets its
    # natural rounded top back (a gentle arc instead of the flat cut).
    dome = im[118:136, 566:592].reshape(-1, 3)
    lum = dome @ np.array([.299, .587, .114])
    sel = (lum > 15) & (lum < 75) & (np.abs(dome[:, 0] - dome[:, 2]) < 25)   # neutral dark metal only (no gold, no rim)
    dark = np.median(dome[sel], axis=0) if sel.any() else np.array([44.0, 40, 42])
    edge_pts = [(556, 104.0), (572, 100.0), (592, 97.0), (615, 95.5), (638, 96.5), (654, 99.5), (668, 106.0), (700, 116.0), (720, 123.0)]
    xs = np.array([p[0] for p in edge_pts], float); ys = np.array([p[1] for p in edge_pts], float)
    edge = lambda x: float(np.interp(x, xs, ys))  # noqa
    # the whole remnant band (gold sliver, finial oval, the flat cut and the background notch at its right end)
    # becomes plain dome metal from the new rounded edge down to where the ribs begin; slightly darker at the top
    orig = im.copy()
    for x in range(578, 672):
        top = int(edge(x))
        bottom = 116 if x < 662 else int(old_edge(x)) + 3
        for y in range(top, bottom):
            t = (y - top) / max(bottom - top, 1)
            metal = dark * (0.82 + 0.18 * t)
            fade = clamp01((bottom - y) / 6.0) if x < 662 else 1.0   # soft lower edge: blends into the dome shading
            im[y, x] = metal * fade + orig[y, x] * (1.0 - fade)
    for x in range(640, 668):                                       # background pocket left under the old cut
        for y in range(int(edge(x)), int(old_edge(x)) + 6):
            if np.abs(im[y, x] - key).sum() < 200:
                im[y, x] = dark * 0.85
    S = 6
    out = Image.fromarray(im.astype(np.uint8))
    ink = Image.new("L", (out.width * S, out.height * S), 0)
    ImageDraw.Draw(ink).line([(x * S, (edge(x) - 1.0) * S) for x in np.arange(556, 668, 0.5)], fill=255, width=int(3.6 * S))
    w = np.array(ink.resize(out.size, Image.LANCZOS)) / 255.0
    im = im * (1 - w[..., None]) + np.array([22, 16, 14.0]) * w[..., None]
    return im.astype(np.uint8)


def extend_root(rgba, lab, part, spec, existing=None):
    """v36: continue a rear decoration from its visible cut end UNDER the parts that covered its root, so it meets the
    body when such a part detaches (Kengurobot MK2: the tail root behind the left thigh). The cross-section profile
    just inside the cut (spec["cut"] = two end points) is extruded along spec["dir"] for spec["len"] px, tapering by
    spec["taper"], with an ink rim at its sides. Pixels are written ONLY inside the master silhouette of the
    spec["within"] parts (hidden while those are attached) and only where the part is not already present.
    Returns (rgba, mask of the added pixels)."""
    H, W = lab.shape
    m = lab == rigkit.LABEL[part]
    have = existing if existing is not None else m
    allowed = np.zeros_like(m)
    for o in spec["within"]:
        allowed |= lab == rigkit.LABEL[o]
    a = np.array(spec["cut"][0], float); b = np.array(spec["cut"][1], float)
    d = np.array(spec["dir"], float); d /= np.linalg.norm(d)
    back = float(spec.get("sample_back", 10.0))
    length = float(spec["len"]); taper = float(spec.get("taper", 0.3))
    n = 128
    prof = []
    for i in range(n + 1):
        p = a + (b - a) * (i / n) - d * back
        x, y = int(round(p[0])), int(round(p[1]))
        prof.append(rgba[y, x, :3].astype(float) if 0 <= x < W and 0 <= y < H and m[y, x] else None)
    good = [c for c in prof if c is not None]
    fallback = np.median(np.array(good), axis=0) if good else np.array([200.0, 110, 40])
    prof = [c if c is not None else fallback for c in prof]
    # smooth across the section (no rivet / speckle noise smeared along the extrusion)
    arr = np.array(prof)
    prof = [arr[max(0, i - 3):i + 4].mean(axis=0) for i in range(len(prof))]
    ink = np.array([22.0, 16, 14])
    out = rgba.copy()
    add = np.zeros_like(m)
    mid = (a + b) * 0.5
    for t in np.arange(0.0, length, 0.3):
        k = 1.0 - taper * t / length
        for i in range(n + 1):
            s = i / n
            p = mid + ((a + (b - a) * s) - mid) * k + d * t
            x, y = int(round(p[0])), int(round(p[1]))
            if not (0 <= x < W and 0 <= y < H) or have[y, x] or not allowed[y, x]:
                continue
            col = ink if (s < 0.06 or s > 0.94) else prof[i]
            out[y, x, :3] = col
            out[y, x, 3] = 255
            add[y, x] = True
    # close the sampling pinholes: every gap pixel takes the colour of its nearest written neighbour
    closed = nd.binary_closing(add, structure=np.ones((3, 3)), iterations=2) & allowed & ~have
    holes = closed & ~add
    if holes.any():
        _, (iy, ix) = nd.distance_transform_edt(~add, return_indices=True)
        out[holes, :3] = out[iy[holes], ix[holes], :3]
        out[holes, 3] = 255
    # ink rim along every free edge of the added piece (cartoon outline; none where it tucks under the torso)
    body = lab == rigkit.LABEL["torso"]
    rim = closed & nd.binary_dilation(~(closed | have | body), iterations=2)
    out[rim, :3] = ink
    return out, closed


def fill_rear(rgba, lab, part, occluders, radius, edge_occluders=None):
    """Reconstruct a rear decoration under the parts drawn over it: the part's silhouette is closed (radius px)
    only where it is covered by `occluders`; those pixels take the colour of the nearest INTERIOR pixel of the part
    (outline pixels excluded, so no ink is smeared inward); returns (rgba, mask of the completed part)."""
    m = lab == rigkit.LABEL[part]
    if not m.any():
        return rgba, m
    occ = np.zeros_like(m)
    for o in occluders:
        occ |= lab == rigkit.LABEL[o]
    lum = rgba[..., :3].astype(float) @ np.array([.299, .587, .114])
    closed = nd.binary_closing(m, structure=np.ones((3, 3)), iterations=radius) | m
    add = closed & occ & ~m
    occ_all = occ
    if edge_occluders:
        occ = np.zeros_like(m)
        for o in edge_occluders:
            occ |= lab == rigkit.LABEL[o]
    # edge continuation (like the v29 base-tail repair): where the part's top / bottom edge is cut by an occluder,
    # the edge is interpolated between the intact columns on both sides and the band is completed under the occluder
    H, W = m.shape
    xs = np.where(m.any(axis=0))[0]
    col_fill = {}   # (y, x) -> body colour of that column (taken just inside the original edge)
    if xs.size:
        for side in ("top", "bottom"):
            edge = {}
            cut = {}
            for x in xs:
                ys = np.where(m[:, x])[0]
                y = int(ys.min()) if side == "top" else int(ys.max())
                edge[x] = y
                probe = range(max(0, y - 4), y) if side == "top" else range(y + 1, min(H, y + 5))
                cut[x] = any(occ[yy, x] for yy in probe)
            run = []
            for x in list(xs) + [None]:
                if x is not None and cut.get(x):
                    run.append(x); continue
                if run:
                    left, right = run[0] - 1, run[-1] + 1
                    ok_l = left in edge and not cut.get(left)
                    ok_r = right in edge and not cut.get(right)
                    fit = None
                    if not (ok_l and ok_r) and (ok_l or ok_r):
                        # one side is cut too (e.g. the tail runs into the leg): extrapolate the intact side's edge line
                        ref = [x for x in (range(left - 40, left + 1) if ok_l else range(right, right + 41)) if x in edge and not cut.get(x)]
                        if len(ref) >= 8:
                            fit = np.polyfit(np.array(ref, float), np.array([edge[x] for x in ref], float), 1)
                    if (ok_l and ok_r) or fit is not None:
                        for xx in run:
                            if fit is None:
                                t = (xx - left) / float(right - left)
                                target = int(round(edge[left] + (edge[right] - edge[left]) * t))
                            else:
                                target = int(round(fit[0] * xx + fit[1]))
                            lo, hi = (target, edge[xx]) if side == "top" else (edge[xx] + 1, target + 1)
                            # profile transplant: the intact reference column's look from its edge inward (ink rim,
                            # highlight, body) is copied onto the new edge; it also covers the old cut outline
                            refx = left if ok_l else right
                            depth = abs(edge[xx] - target) + 10
                            for k in range(depth):
                                yy = target + k if side == "top" else target - k
                                ry = edge[refx] + k if side == "top" else edge[refx] - k
                                if not (0 <= yy < H and 0 <= ry < H):
                                    continue
                                if occ[yy, xx] or m[yy, xx]:
                                    if occ[yy, xx]:
                                        add[yy, xx] = True
                                    if m[ry, refx]:
                                        col_fill[(yy, xx)] = rgba[ry, refx, :3].astype(float)
                    run = []
    if not add.any():
        return rgba, m
    lum = rgba[..., :3].astype(float) @ np.array([.299, .587, .114])
    # body cloth only (not the dark ink outline, not the bright gold trim): the hidden part continues the fabric
    interior = nd.binary_erosion(m, iterations=4) & (lum > 30) & (lum < 110)
    if not interior.any():
        interior = nd.binary_erosion(m, iterations=4)
    _, (iy, ix) = nd.distance_transform_edt(~interior, return_indices=True)
    out = rgba.copy()
    out[add, :3] = rgba[iy[add], ix[add], :3]
    out[add, 3] = 255
    if col_fill:
        # horizontal median smoothing of the per-column body colours, then paint (edge band + old outline under it)
        for (yy, xx), colr in col_fill.items():
            out[yy, xx, :3] = colr
            out[yy, xx, 3] = 255
    # ink rim on the new outer edge (where the closed silhouette meets transparency / other parts' outside)
    full = m | add
    # the part's OLD outline around the occluder is now inside the completed shape: repaint it like the body
    inner = nd.binary_erosion(full, iterations=3)
    old_rim = m & nd.binary_dilation(add, iterations=5) & (lum < 70) & inner
    for k in col_fill:
        old_rim[k] = False
    out[old_rim, :3] = rgba[iy[old_rim], ix[old_rim], :3]
    rim = full & ~inner & add
    for k in col_fill:
        rim[k] = False
    # remaining walls of the old cut (dark outline running along the occluder inside the completed shape)
    painted = np.zeros_like(m)
    for k in col_fill:
        painted[k] = True
    light = m & (lum >= 70) & nd.binary_erosion(m, iterations=2)
    if light.any():
        _, (ly, lx) = nd.distance_transform_edt(~light, return_indices=True)
        wall = m & nd.binary_dilation(occ, iterations=6) & (lum < 70) & nd.binary_erosion(full, iterations=4) & ~painted
        out[wall, :3] = rgba[ly[wall], lx[wall], :3]
    out[rim, :3] = (22, 16, 14)
    return out, full


def build(rid, d, out_root, report):
    src = Path(d["file"]) if Path(d["file"]).is_absolute() else SRC / d["file"]
    rgb = np.array(Image.open(src).convert("RGB"))
    if d.get("clean") == "samurai":
        rgb = clean_samurai(rgb)
        WORK.mkdir(parents=True, exist_ok=True)
        Image.fromarray(rgb).save(WORK / f"{rid}_master_cleaned.png")
    rgba, key = rigkit.matte(rgb)
    s = SEEDS[rid]
    lab = rigkit.segment(rgba, s["seeds"], s.get("zones"))
    WORK.mkdir(parents=True, exist_ok=True)
    rigkit.overlay(rgba, lab, WORK / f"{rid}_parts.png", .5)
    vis = rgba[..., 3] > 0
    parts = [p for p in rigkit.PARTS if (lab == rigkit.LABEL[p]).any()]
    masks = {}
    for p in parts:
        m = lab == rigkit.LABEL[p]
        higher = np.zeros_like(m)
        for q in parts:
            if base.Z[q] > base.Z[p]:
                higher |= lab == rigkit.LABEL[q]
        g = m.copy()
        for _ in range(base.OVERLAP):
            g |= nd.binary_dilation(g) & higher & vis
        masks[p] = g
    tail_rgba = rgba
    if "tail" in parts and d.get("rear_fill"):
        tail_rgba, full = fill_rear(rgba, lab, "tail", d["rear_fill"]["occluders"], int(d["rear_fill"]["radius"]), d["rear_fill"].get("edge_occluders"))
        masks["tail"] = full | masks["tail"]
    if "tail" in parts and d.get("root_extend"):
        tail_rgba, ext = extend_root(tail_rgba, lab, "tail", d["root_extend"], masks["tail"])
        masks["tail"] = ext | masks["tail"]
    dest = Path(out_root) / rid
    dest.mkdir(parents=True, exist_ok=True)
    for f in dest.glob("*.png"):
        if f.stem not in parts:
            f.unlink()
    images, boxes = {}, {}
    for p in parts:
        images[p], boxes[p] = base.extract(tail_rgba if p == "tail" else rgba, masks[p])
    profile = {"png_modular": True, "source_scale": d["scale"], "torso_scale": [1, 1], "head_scale": [1, 1], "torso_offset": [0, 0], "parts": {}, "anchors": {}}
    bodybox = boxes["torso"]
    floor = 159.19
    profile["torso_offset"] = [0, (floor - (d["sole"] - d["center"][1]) * d["scale"]) / .42]
    for name, pt in [("neck", d["neck"]), ("shoulder_l", d["shoulders"][0]), ("shoulder_r", d["shoulders"][1]),
                     ("hip_l", d["hips"][0]), ("hip_r", d["hips"][1])]:
        profile["anchors"][name] = base.local(pt, bodybox)
    mf = {"schema": 2, "robot": d["robot"], "visual_id": d["visual"], "variant": "mk2", "png_modular": True, "fps": 10,
          "source": {"file": Path(d["file"]).name, "sha256": hashlib.sha256(src.read_bytes()).hexdigest(), "builder": "tools/players/build_mk2_rigs.py v35"},
          "parts": {}, "decorations": []}
    for p in ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]:
        box = boxes[p]; img = images[p]
        pt = d["neck"] if p == "head" else d["center"] if p == "torso" else d["shoulders"][0 if p.endswith("l") else 1] if p.startswith("arm") else d["hips"][0 if p.endswith("l") else 1]
        piv = base.local(pt, box)
        geom = {"pivot": piv, "unit_scale": d["scale"] * 2, "z": base.Z[p]}
        if p.startswith(("arm", "leg")):
            side = 0 if p.endswith("l") else 1
            end = d["hands"][side] if p.startswith("arm") else d["feet"][side]
            lo, hi = d["spring_arm"] if p.startswith("arm") else d["spring_leg"]
            geom.update(end=base.local(end, box), spring_rows=[(lo - box[1]) * .5, (hi - box[1]) * .5], inertia_gain=.2, png_modular=True)
            if p.startswith("leg") and "rigid_middle" in d:
                geom["rigid_middle_rows"] = [(d["rigid_middle"][0] - box[1]) * .5, (d["rigid_middle"][1] - box[1]) * .5]
        profile["parts"][p] = geom
        mf["parts"][p] = {"atlas": p + ".png", "frame_size": list(img.size), "columns": 1, "count": 1, "pivot": piv, "clips": {"idle": [0]}, "source_origin": box[:2]}
        if p != "head":
            img.save(dest / f"{p}.png")
    if "tail" in images:
        images["tail"].save(dest / "tail.png")
        profile["tail"] = {"offset": base.local([boxes["tail"][0], boxes["tail"][1]], bodybox), "file": "tail.png", "z": base.Z["tail"]}
    variants = base.face_variants(images["head"], boxes["head"], d)
    atlas = Image.new("RGBA", (images["head"].width * len(variants), images["head"].height))
    for i, f in enumerate(variants):
        atlas.paste(f, (i * images["head"].width, 0))
    atlas.save(dest / "head.png")
    idle = [0] * 27 + [1, 1] + [0] * 12 + [5] * 9 + [0] * 10 + [6] * 8
    mf["parts"]["head"].update(columns=7, count=7, clips={"idle": idle, "neutral": idle, "happy": [2], "scared": [3], "angry": [4],
                               "determined": [0, 0, 6, 6, 0, 0, 5, 5], "dizzy": [5, 6], "dead": [1], "pain": [4]})
    if "nozzle_anchors" in d:
        mf["nozzle_anchors"] = d["nozzle_anchors"]
    (dest / "manifest.json").write_text(json.dumps(mf, ensure_ascii=False, indent=2) + "\n", encoding="utf8", newline="\n")
    (dest / "visual_rig.json").write_text(json.dumps(profile, indent=2) + "\n", encoding="utf8", newline="\n")
    recon = Image.new("RGBA", (rgba.shape[1], rgba.shape[0]))
    for p in sorted(parts, key=lambda q: base.Z[q]):
        pc = images[p].resize((boxes[p][2] - boxes[p][0], boxes[p][3] - boxes[p][1]), Image.Resampling.LANCZOS)
        recon.alpha_composite(pc, (boxes[p][0], boxes[p][1]))
    recon.save(WORK / f"{rid}_reconstruction.png")
    a_err = np.abs(np.array(recon).astype(float)[..., 3] - rgba.astype(float)[..., 3])
    report[rid] = {"parts": {p: list(images[p].size) for p in parts}, "unassigned_visible_px": int((vis & (lab == 0)).sum()),
                   "recon_alpha_mean_err": round(float(a_err.mean()), 3), "recon_alpha_err_px_gt64": int((a_err > 64).sum()),
                   "boxes": {p: [int(v) for v in boxes[p]] for p in parts}}
    return recon


def main():
    args = sys.argv[1:]
    out_root = ROOT / "game/assets/robots"
    if "--out" in args:
        i = args.index("--out"); out_root = Path(args[i + 1]); args = args[:i] + args[i + 2:]
    report = {}
    for rid, d in DATA.items():
        if args and rid not in args:
            continue
        build(rid, d, out_root, report)
    WORK.mkdir(parents=True, exist_ok=True)
    prev = json.loads((WORK / "qa.json").read_text()) if (WORK / "qa.json").exists() else {}
    prev.update(report)
    (WORK / "qa.json").write_text(json.dumps(prev, indent=1), encoding="utf8")
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
