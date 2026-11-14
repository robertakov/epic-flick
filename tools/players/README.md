# Playable robot rigs (v28, authoritative)

Run (deterministic, ~5 s):

```powershell
& "python" -B -I tools/players/build_player_rigs.py   # all five
& "python" -B -I tools/players/build_player_rigs.py samurai   # one
& "G:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path game --editor --import --quit
```

| id (persistent) | Name | Master (Characters/Players, read-only) |
|---|---|---|
| tin | Растабот | Rastabot.png |
| hopper | Кенгуробот | Kengurobot.png |
| heavy | Сумобот | sumobot.png |
| rocket | Хронобот | Chronobot.png |
| samurai | Самуробот | file_000000007ab881f6bf1f9325d404bb87.png (new master, motion ref gemini_generated_video_99bb73b0.mp4) |

Files:
* `build_player_rigs.py` – the builder (joints per robot in `DATA`, master pixel coordinates).
* `rigkit.py` – matte (measured key colour, flood-connected unmixing, no erosion, edge despill, no shadow) and
  segmentation (seeded watershed over the ink map so every cut follows a drawn outline; zones as hard limits;
  sliver / fragment cleanup that never moves pieces outside a part's zone).
* `rig_seeds.json` – per robot: `seeds` (polylines inside each part) and `zones` (polygons a part may not leave).
  To fix a bad cut: add a seed line inside the wrongly assigned region, or a zone; re-run; inspect
  `reports/v28_rigs/<id>_parts.png`.

Outputs: `game/assets/robots/<id>/` head.png (7-frame face atlas), torso.png, arm_l/arm_r.png, leg_l/leg_r.png,
(hopper) tail.png, manifest.json, visual_rig.json. Diagnostics: `reports/v28_rigs/` (part overlays, reconstruction
board, qa.json with unassigned pixels / green fringe / shadow residue per robot).

Rules: textures contain the character only – never draw or bake a ground shadow. Do not regenerate from MP4 frames.
Only lower-z parts get a 2 px geodesic overlap under their upper neighbour (seamless when intact, clean when detached).
The superseded v23/v27 tools (process_png_characters.py, build_samurobot_master.py) were removed (they are in git
history at checkpoint 79b8b636).

## MK2 rigs (v35)

```powershell
& "python" -B -I tools/players/build_mk2_rigs.py           # all five MK2
& "python" -B -I tools/players/build_mk2_rigs.py rocket_mk2
```

* Separate builder: it imports the base builder's helpers but never rebuilds the base robots, so the hand-repaired base
  art (v29 Kengurobot tail, v34 Rastabot without joint) can not be overwritten.
* Masters: `Assets/Characters/Players/{rastabot mk2,kengurobot mk2,sumorobot mk2,chronobot mk2,Samurobot MK2}.png`
  (read-only). Samurobot MK2 is cleaned in memory first (`clean_samurai`: the stray blade above the helmet is removed).
* Data: `mk2_rig_data.json` (joints in master px, scale, rear-decoration fill, Chronobot MK2 nozzle anchors) and
  `rig_seeds_mk2.json` (watershed seeds). Output: `game/assets/robots/<id>_mk2/` (same schema as the base rigs).
* Rear decorations (Kengurobot MK2 tail, Chronobot MK2 cape = the torso-attached `tail` slot) get the pixels hidden
  behind the glove / legs reconstructed (`fill_rear`: closing + edge continuation + profile transplant), so no
  occluder-shaped hole shows when those parts move or detach.
* Physics / collision never come from these files: RigData keeps `res://assets/robot/rig.json` + the base
  RobotDefinition (proved by `--scenario=mk2_all`, collision_identical_*).
