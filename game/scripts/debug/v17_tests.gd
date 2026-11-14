extends Node
## v17 art-rig regression and review gallery. Pose gallery uses controlled visual states;
## actual detachment/rocket and production Free/Campaign flows are tested separately below.
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
func check(label: String, ok: bool, detail := "") -> void:
	passed += int(ok)
	failed += int(not ok)
	print("AT|test v17_%s %s %s" % [label, "PASS" if ok else "FAIL", detail])
func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func run_all(_which: String) -> void:
	at.set("scenario_running", true)
	at.set("max_time", 1.0e9)
	await geometry_and_gallery()
	await production_lifecycle()
	print("AT|tests passed=%d failed=%d" % [passed, failed])

func verify_joints(id: String, state: String, v: RobotVisual) -> void:
	if not v.art_profile.enabled():
		check("samurai_legacy_" + state, v.art_torso == null and v.head.video_part == null)
		return
	for side in v.arms:
		var a: ArmVisual = v.arms[side]
		var expected := v.art_profile.anchor("shoulder_l" if side == &"arm_l" else "shoulder_r", v.art_torso, v.torso)
		check(id + "_" + state + "_" + String(side), a.video_part.position.distance_to(expected) < 0.001)
	for side in v.legs:
		var l: LegVisual = v.legs[side]
		var expected := v.art_profile.anchor("hip_l" if side == &"leg_l" else "hip_r", v.art_torso, v.torso)
		check(id + "_" + state + "_" + String(side), l.video_part.position.distance_to(expected) < 0.001)
	check(id + "_" + state + "_neck", v.head.transform * v.head.video_part.position == v.head.visual_neck or (v.head.transform * v.head.video_part.position).distance_to(v.head.visual_neck) < 0.001)

func geometry_and_gallery() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	gm.add_child(layer)
	var background := ColorRect.new()
	background.color = Color(0.17, 0.20, 0.24)
	background.size = Vector2(1280, 720)
	background.z_index = -100
	layer.add_child(background)
	var title := Label.new()
	title.position = Vector2(20, 15)
	title.add_theme_font_size_override("font_size", 24)
	layer.add_child(title)
	var robots: Array[RobotController] = []
	var legacy_heads: Array[HeadVisual] = []
	for i in gm.catalog.robots.size():
		var def: RobotDefinition = gm.catalog.robots[i]
		var r := gm.build_robot(def, null, null)
		r.freeze = true
		r.position = Vector2(128 + i * 256, 290)
		layer.add_child(r)
		r.set_physics_process(false)
		r.visual.set_physics_process(false)
		r.visual.identity.set_process(false)
		robots.append(r)
		var label := Label.new()
		label.text = def.display_name
		label.position = Vector2(45 + i * 256, 585)
		label.add_theme_font_size_override("font_size", 25)
		layer.add_child(label)
		var old_rig := RigData.new(r.config)
		old_rig.art = {}
		var h := HeadVisual.new()
		h.setup(old_rig)
		h.set_neck(r.visual._neck)
		legacy_heads.append(h)
		check(def.id + "_physical_rig", r.visual.rig.raw == old_rig.raw and r.visual.head.center_local == h.center_local)
		if r.visual.art_profile.enabled():
			for side in r.visual.legs:
				var l: LegVisual = r.visual.legs[side]
				check(def.id + "_" + String(side) + "_unchanged_dimensions", l.cap_len == l.leg.cap_len and l.boot_len == l.leg.boot_len)
				var art := l.video_part
				art.fit_limb(Vector2.ZERO, Vector2(0, 70), art.art_rig.limb_scale(String(side)), 0.3)
				var verts := art.mesh.polygon
				var width := verts[-1].distance_to(verts[-2])
				art.fit_limb(Vector2.ZERO, Vector2(0, 180), art.art_rig.limb_scale(String(side)), 0.3)
				verts = art.mesh.polygon
				check(def.id + "_" + String(side) + "_rigid_boot", is_equal_approx(width, verts[-1].distance_to(verts[-2])))
				check(def.id + "_" + String(side) + "_source_coil", art.art_coil != null and art.art_coil.ring is AtlasTexture)
		await frames(2)
	var states := ["idle", "airborne", "manual_rotation", "compression", "release", "body_impact", "head_impact", "fast_rotation", "low_hp"]
	for state in states:
		title.text = "v17 visual rig review — " + state + " (controlled presentation fixture; Samurai reference)"
		for i in robots.size():
			var r := robots[i]
			var v := r.visual
			var id := r.config.robot_id
			r.rotation = 0.0
			v.scale = Vector2.ONE * (0.75 if state in ["airborne", "manual_rotation", "fast_rotation", "body_impact"] else 1.0)
			v.squash = 0.0
			v.head.angle = 0.0
			v.head.offset_pos = Vector2.ZERO
			var old_head := legacy_heads[i]
			old_head.angle = 0.0
			old_head.offset_pos = Vector2.ZERO
			v.frame.gravity_local = Vector2(0, 1800)
			v.frame.accel_local = Vector2.ZERO
			v.frame.w = 0
			v.frame.alpha = 0
			if state == "airborne": r.rotation = -0.6
			if state == "manual_rotation": r.rotation = 0.65
			if state == "compression": v.squash = 0.32
			if state == "release": v.squash = -0.25
			if state == "body_impact":
				v.squash = 0.25
				v.head.set_expression(&"angry", 1, 6)
			if state == "head_impact":
				v.head.angle = 0.6
				old_head.angle = 0.6
				v.head.offset_pos = Vector2(12, 4)
				old_head.offset_pos = Vector2(12, 4)
				v.head.set_expression(&"dizzy", 1, 6)
			if state == "fast_rotation":
				r.rotation = 1.9
				v.frame.w = 18.0
				v.frame.alpha = 24.0
			if state == "low_hp": v.head.set_expression(&"scared", 1, 6)
			v._apply_squash()
			for side in v.legs:
				var l: LegVisual = v.legs[side]
				l.length = l.cfg.coil_min_length if state == "compression" else (l.cfg.coil_max_length if state == "release" else l.cfg.coil_rest_length)
				l.swing = 0.3 if state in ["airborne", "fast_rotation"] else 0.0
				l.boot_tilt = 0.1 if state == "fast_rotation" else 0.0
				l._apply()
			for side in v.arms:
				var a: ArmVisual = v.arms[side]
				a.p = a.exit + a.rest + (Vector2(18, -14) if state in ["fast_rotation", "body_impact"] else Vector2.ZERO)
				a._apply()
			v.head.step(0.0, v.frame)
			old_head.scale = v.head.scale
			old_head.set_neck(v._sq(v._neck))
			old_head.step(0.0, v.frame)
			check(id + "_" + state + "_head_launch_transform_unchanged", v.head.transform == old_head.transform)
			verify_joints(id, state, v)
		await frames(3)
		at.call("_shot", "v17_state_" + state)
	# Timed source-animation review, at the original curated cadence (presentation fixture).
	title.text = "v17 connector stability — atlas loops / fixed physical rig"
	for r in robots:
		var v := r.visual
		r.rotation = 0
		v.scale = Vector2.ONE
		v.squash = 0
		v.head.angle = 0
		v.head.offset_pos = Vector2.ZERO
		v.head.set_expression(&"neutral", 100, 7)
		for side in v.legs:
			var l: LegVisual = v.legs[side]
			l.length = l.cfg.coil_rest_length
			l.swing = 0
			l.boot_tilt = 0
		for side in v.arms:
			var a: ArmVisual = v.arms[side]
			a.p = a.exit + a.rest
		v._apply_squash()
		v.head.step(0, v.frame)
	for index in 12:
		await frames(12)
		at.call("_shot", "v17_loop_%02d" % index)
	# All source frames retain the functional anchor and their own constant terminal dimensions.
	for r in robots:
		var v := r.visual
		if not v.art_profile.enabled(): continue
		for side in v.arms:
			var art: VideoRobotPart = v.arms[side].video_part
			var origin := art.position
			var valid := true
			for f in art.frames.size():
				art._set_frame(f)
				valid = valid and art.position == origin and art.mesh.polygon.size() == 22
			check(r.config.robot_id + "_" + String(side) + "_frame_anchor_stable", valid)
		v.head.offset_pos = Vector2.ZERO
		v.head.angle = 0
		var h := legacy_heads[robots.find(r)]
		h.offset_pos = Vector2.ZERO
		h.angle = 0
		h.angle_vel = v.head.angle_vel
		h.offset_vel = v.head.offset_vel
		var equal := true
		for j in 60:
			v.head.step(1.0 / 120, v.frame)
			h.step(1.0 / 120, v.frame)
			equal = equal and v.head.transform == h.transform
		check(r.config.robot_id + "_60step_head_transform_parity", equal)
	for h in legacy_heads: h.free()
	layer.queue_free()
	await frames(3)

func production_lifecycle() -> void:
	for id in ["tin", "hopper", "heavy", "rocket"]:
		gm.profile.selected = id
		if not gm.profile.owned.has(id): gm.profile.owned.append(id)
		gm.mode = &"free"
		at.call("start_seen_run")
		await frames(20)
		var r := gm.robot
		r.freeze = true
		gm.hand.playing = false
		var v := r.visual
		check(id + "_free_rig", v.art_profile.enabled())
		var info := {"event": 98761, "impact": 1000.0, "point": r.global_position, "normal": Vector2.UP}
		var left: ArmVisual = v.arms[&"arm_l"]
		var right: ArmVisual = v.arms[&"arm_r"]
		r._on_limb_lost(&"arm_l", info)
		await frames(80)
		at.call("_shot", "v17_" + id + "_one_arm_lost")
		r._on_limb_lost(&"arm_r", info)
		await frames(80)
		check(id + "_both_arms_actual_detach", v.arms.is_empty() and left.get_parent() is DetachablePart and right.get_parent() is DetachablePart)
		check(id + "_detached_mesh_owned", left.video_part.mesh.get_parent() == left.video_part and right.video_part.mesh.get_parent() == right.video_part)
		at.call("_shot", "v17_" + id + "_both_arms_lost")
		var leg: LegVisual = v.legs[&"leg_l"]
		r._on_limb_lost(&"leg_l", info)
		await frames(80)
		check(id + "_actual_leg_detach", leg.get_parent() is DetachablePart and leg.video_part.art_coil.get_parent() == leg.video_part)
		at.call("_shot", "v17_" + id + "_one_leg_lost")
		var head := v.head
		r._launch_rocket(info)
		await frames(100)
		check(id + "_actual_rocket_anchor_released", head.get_parent() is RocketHead and not head.visual_anchor_enabled)
		gm.camera.snap_intro((head.get_parent() as RocketHead).global_position + Vector2(0, 100), 0.88)
		await frames(1)
		at.call("_shot", "v17_" + id + "_rocket_head")
		gm.go_menu()
		await frames(3)
		check(id + "_rig_cleanup", not is_instance_valid(r) and not is_instance_valid(leg))
	for round_id in ["r1", "r7", "r11", "r21", "r28"]:
		gm.mode = &"campaign"
		gm.node_id = round_id
		gm.profile.selected = "samurai"
		gm.profile.ensure_campaign_start(round_id)
		at.call("start_seen_run")
		await frames(20)
		gm.hand.playing = false
		var seen := {}
		for ch in gm.dynamic.get_children():
			if ch is RobotController:
				var r := ch as RobotController
				r.freeze = true
				if r != gm.robot:
					seen[r.config.robot_id] = true
					check(r.config.robot_id + "_production_campaign_enemy_rig", r.visual.art_profile.enabled() == (r.config.robot_id != "samurai" or r.visual.has_meta("enemy_identity")))
		var expected: String = gm.campaign.node(round_id).enemies[0].robot
		check(round_id + "_campaign_enemy_rendered", seen.has(expected))
		await frames(30)
		at.call("_shot", "v17_campaign_enemy_" + expected)
		gm.go_menu()
		await frames(3)
