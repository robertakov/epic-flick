extends Node
## v28 playable-character QA (debug only, not exported).   --scenario=v28_qa --shots=<dir>
## For all five robots: selection screen (preview inside its box, not over the info card), standing, strong spring
## compression / extension, airborne spin, left+right arm and leg detachment, full destruction -> head-only jet.
## Also static checks of the rebuilt runtime textures (no green fringe, no baked shadow, no floating fragments).
## Prints "AT|test v28_<name> PASS|FAIL" and "AT|qa <shot> x y" (robot screen position).
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const IDS := ["tin", "hopper", "heavy", "rocket", "samurai"]


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test v28_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run_all(_which: String) -> void:
	at.set("scenario_running", true); at.set("max_time", 1.0e9)
	textures()
	for id in IDS:
		await select_screen(id)
		await gameplay(id)
	print("AT|tests passed=%d failed=%d" % [passed, failed])


func _shot(name: String, node: Node) -> void:
	await frames(2)
	var p := Vector2.ZERO
	if node is Node2D and is_instance_valid(node):
		p = (node as Node2D).get_global_transform_with_canvas().origin
	elif node is Control and is_instance_valid(node):
		p = (node as Control).get_global_rect().get_center()
	print("AT|qa %s %d %d" % [name, int(p.x), int(p.y)])
	at.call("_shot", name)


# ---------------- static texture checks ----------------
func textures() -> void:
	for id in IDS:
		var greenish := 0
		var shadow_rows := 0
		var frags := 0
		for part in ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r", "tail"]:
			var path := "res://assets/robots/%s/%s.png" % [id, part]
			if not ResourceLoader.exists(path):
				continue
			var img := (load(path) as Texture2D).get_image()
			img.decompress()
			var w := img.get_width()
			var h := img.get_height()
			for y in range(0, h, 2):
				for x in range(0, w, 2):
					var c := img.get_pixel(x, y)
					if c.a > 0.08 and c.a < 0.98 and c.g > c.r + 0.1 and c.g > c.b + 0.1 and id != "tin":
						greenish += 1
			# a baked ground shadow would be a wide, dark, semi-transparent band under the boots
			if part.begins_with("leg"):
				for y in range(h - 6, h):
					var semi_dark := 0
					for x in w:
						var c := img.get_pixel(x, y)
						if c.a > 0.08 and c.a < 0.7 and c.v < 0.25:
							semi_dark += 1
					if semi_dark > w * 0.5:
						shadow_rows += 1
		check(id + "_no_green_fringe", greenish < 12, "semi-transparent greenish samples=%d" % greenish)
		check(id + "_no_baked_shadow", shadow_rows == 0, "dark semi rows under boots=%d" % shadow_rows)
		var mf := RobotArtLibrary.manifest(id)
		check(id + "_v28_source", String(mf.get("source", {}).get("builder", "")).begins_with("tools/players/build_player_rigs.py"), str(mf.get("source", {})))


# ---------------- selection screen ----------------
func select_screen(id: String) -> void:
	if not gm.profile.owned.has(id):
		gm.profile.owned.append(id)
	gm.profile.select(id)
	gm.go_menu(); await frames(4)
	gm.open_robot_select(); await frames(30)
	var sel := gm.ui.robot_select
	check(id + "_select_shows_robot", sel.current().id == id and sel.preview.def != null and sel.preview.def.id == id)
	var box := sel._preview_box.get_global_rect()
	var panel := (sel._preview_box.get_parent() as Control).get_child(2) as Control
	var b := sel.preview.art_bounds()
	var g := sel.preview.get_global_transform() * b.position
	var g2 := sel.preview.get_global_transform() * b.end
	var art := Rect2(g, g2 - g).abs()
	var vp := get_viewport().get_visible_rect()
	check(id + "_select_fits_box", box.grow(12).encloses(art), "art=%s box=%s" % [art, box])
	check(id + "_select_not_over_card", not art.grow(-18).intersects(panel.get_global_rect()), "art=%s card=%s" % [art, panel.get_global_rect()])
	check(id + "_select_on_screen", vp.encloses(art), "art=%s" % art)
	await _shot("v28_select_" + id, sel._preview_box)
	gm._close_select(); await frames(2)


# ---------------- gameplay states ----------------
func _legs(r: RobotController, length: float) -> void:
	for side in r.visual.legs:
		var lv: LegVisual = r.visual.legs[side]
		if lv.leg != null and lv.leg.attached:
			lv.leg.length = length       # test pose only (robot frozen); the visual follows the physical leg
	await frames(3)


func gameplay(id: String) -> void:
	gm.mode = &"free"
	at.call("start_seen_run"); await frames(5)
	gm.hand.playing = false
	var r := gm.robot
	r.freeze = true; await frames(4)
	await _shot("v28_stand_" + id, r)
	var cfg := r.contact_config
	await _legs(r, cfg.coil_min_length)
	await _shot("v28_compress_" + id, r)
	await _legs(r, cfg.coil_max_length)
	await _shot("v28_extend_" + id, r)
	await _legs(r, cfg.coil_rest_length)
	# spring meshes stay attached: every limb mesh starts at its socket on the torso
	var attached := true
	for side in r.visual.legs:
		var lv: LegVisual = r.visual.legs[side]
		if lv.video_part:
			attached = attached and lv.video_part.position.distance_to(lv.hip + lv.visual_hip_delta) < 0.5
	for side in r.visual.arms:
		var av: ArmVisual = r.visual.arms[side]
		if av.video_part:
			attached = attached and av.video_part.position.distance_to(av.socket + av.visual_socket_delta) < 0.5
	check(id + "_limbs_attached_to_sockets", attached)
	r.freeze = false
	gm._on_flick(Vector2.ZERO)
	for k in 55:
		await get_tree().physics_frame
	r.freeze = true
	await _shot("v28_air_" + id, r)
	r.rotation += 2.4; await frames(2)
	await _shot("v28_spin_" + id, r)
	r.rotation -= 2.4; await frames(2)
	var info := {"event": 2828, "impact": 1000.0, "point": r.global_position, "normal": Vector2.UP}
	var arms: Array = [r.visual.arms[&"arm_l"], r.visual.arms[&"arm_r"]]
	var legs: Array = [r.visual.legs[&"leg_l"], r.visual.legs[&"leg_r"]]
	r._on_limb_lost(&"arm_l", info); await frames(8)
	r._on_limb_lost(&"leg_r", info); await frames(8)
	await _shot("v28_lost_armL_legR_" + id, r)
	r._on_limb_lost(&"arm_r", info); await frames(8)
	r._on_limb_lost(&"leg_l", info); await frames(8)
	await _shot("v28_lost_all_limbs_" + id, r)
	var detached := arms.all(func(a: Node) -> bool: return a.get_parent() is DetachablePart) and legs.all(func(l: Node) -> bool: return l.get_parent() is DetachablePart)
	check(id + "_all_four_limbs_detach", detached)
	var head := r.visual.head
	r._launch_rocket(info); await frames(70)
	check(id + "_head_only_rocket", head.get_parent() is RocketHead and not head.visual_anchor_enabled)
	await _shot("v28_head_" + id, gm.rocket if is_instance_valid(gm.rocket) else r)
	gm.go_menu(); await frames(3)
