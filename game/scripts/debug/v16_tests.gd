extends Node
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
func check(label: String, ok: bool, detail := "") -> void:
	passed += int(ok)
	failed += int(not ok)
	print("AT|test v16_%s %s %s" % [label, "PASS" if ok else "FAIL", detail])
func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func run_all(_which: String) -> void:
	at.set("scenario_running", true)
	at.set("max_time", 1.0e9)
	await assets_and_lifecycle()
	print("AT|tests passed=%d failed=%d" % [passed, failed])
func assets_and_lifecycle() -> void:
	var ids := ["tin", "hopper", "heavy", "rocket"]
	var sources := []
	for id in ids:
		var m := RobotArtLibrary.manifest(id)
		check(id + "_manifest", m.get("robot", "") == id and m.parts.size() == 6)
		check(id + "_cadence", float(m.fps) >= 8 and float(m.fps) <= 12)
		sources.append(m.source.file)
		var def: RobotDefinition = gm.catalog.get_by_id(id)
		var robot := gm.build_robot(def, null, null)
		robot.freeze = true
		robot.position = Vector2(-10000, -10000)
		gm.dynamic.add_child(robot)
		await frames(2)
		var v := robot.visual
		check(id + "_shared_player_ai", v.identity != null and v.identity.profile.robot_id == id and v.rig.art == m)
		check(id + "_six_visual_children", v.art_torso != null and v.head.video_part != null and v.arms.size() == 2 and v.legs.size() == 2)
		check(id + "_original_anchor", v.rig.torso_point("neck").is_equal_approx(Vector2(10, -99) * v.rig.s))
		check(id + "_native_default_colors", robot.config.visual_material == null)
		for part in ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]:
			var spec: Dictionary = m.parts[part]
			var texture := RobotArtLibrary.atlas(id, part)
			var image := texture.get_image()
			check(id + "_" + part + "_alpha", image != null and image.detect_alpha() != Image.ALPHA_NONE)
			check(id + "_" + part + "_pivot", spec.pivot[0] >= 0 and spec.pivot[1] >= 0 and spec.pivot[0] < spec.frame_size[0] and spec.pivot[1] < spec.frame_size[1])
			var valid := true
			for clip in spec.clips.values():
				for frame in clip:
					valid = valid and int(frame) >= 0 and int(frame) < int(spec.count)
			check(id + "_" + part + "_clips", valid and not spec.clips.idle.is_empty())
		var h := v.head
		h.set_expression(&"dizzy", 0.8, 4)
		check(id + "_intentional_face", h.video_part.clip == "dizzy")
		h.want_expression(&"happy")
		check(id + "_face_hold", h.video_part.clip == "dizzy")
		h.video_part.select("unsupported_future_expression")
		check(id + "_expression_fallback", h.video_part.clip == "idle")
		var xf := h.transform
		h.video_part.react(1, 0.7)
		h.video_part._process(0.05)
		check(id + "_child_cannot_move_head_physics", h.transform == xf)
		var before := int(v.identity.event_counts.get("HARD_IMPACT", 0))
		var impact := {"event": 9001, "impact": 1600.0, "point": robot.global_position, "normal": Vector2.UP}
		v.identity.event("HARD_IMPACT", 1.0, impact)
		v.identity.event("HARD_IMPACT", 1.0, impact)
		check(id + "_event_dedup", int(v.identity.event_counts.HARD_IMPACT) == before + 1)
		check(id + "_particle_budget", v.identity.particles.size() <= 24)
		v.identity._process(1.0)
		check(id + "_particles_expire", v.identity.particles.is_empty())
		var lv: LegVisual = v.legs[&"leg_l"]
		var dimensions := Vector2(lv.leg.cap_len, lv.leg.boot_len)
		lv._apply()
		check(id + "_physical_leg_geometry", dimensions.is_equal_approx(Vector2(lv.cap_len, lv.boot_len)))
		if lv.exhaust:
			robot.rotation = 1.1
			lv.swing = 0.3
			lv.boot_tilt = 0.12
			lv._apply()
			lv.exhaust.intensity = 0.8
			lv.exhaust._process(0.1)
			check("rocket_two_independent_flames", (v.legs[&"leg_r"] as LegVisual).exhaust != lv.exhaust)
			check("rocket_flame_world_rotation", is_equal_approx(lv.exhaust.global_rotation, lv.boot.global_rotation))
			check("rocket_flame_visible", lv.exhaust.visible and lv.exhaust.outer.polygon.size() == 5)
			v.launched = true
			robot.contacts.any_leg_contact = true
			v.identity._process(0.01)
			check("rocket_ground_flame_off", lv.exhaust.intensity == 0)
			robot.contacts.any_leg_contact = false
			robot.contacts.any_body_contact = false
			robot.linear_velocity = Vector2(800, -400)
			v.identity._process(0.01)
			var low := lv.exhaust.intensity
			robot.linear_velocity = Vector2(1800, -1200)
			v.identity._process(0.01)
			check("rocket_energy_scaling", lv.exhaust.intensity > low)
			check("rocket_future_sfx_hooks", v.identity.profile.sound_hook("LEG_THRUST_LOW").ends_with("low_thrust") and v.identity.profile.sound_hook("LEG_THRUST_STRONG").ends_with("strong_thrust") and v.identity.profile.sound_hook("CHARGED_LANDING").ends_with("charged_burst"))
			var sounds := []
			v.identity.presentation_event.connect(func(kind: String, energy: float, hook: String) -> void: sounds.append([kind, energy, hook]))
			v.identity._process(0.125)
			check("rocket_thrust_hook_normalized", sounds.any(func(row: Array) -> bool: return row[0] == "LEG_THRUST_STRONG" and row[1] <= 1.0 and row[1] > 0.55))

		var arm: ArmVisual = v.arms[&"arm_l"]
		robot._on_limb_lost(&"arm_l", impact)
		await frames(3)
		check(id + "_arm_detach_art", arm.get_parent() is DetachablePart and arm.video_part != null and not v.arms.has(&"arm_l"))
		robot._on_limb_lost(&"leg_l", impact)
		await frames(3)
		check(id + "_leg_detach_art", lv.get_parent() is DetachablePart and lv.video_part != null and lv.leg == null)
		if lv.exhaust:
			check("rocket_detach_disables_flame", not lv.exhaust.attached and not lv.exhaust.visible and lv.exhaust.intensity == 0)
		var head_center := h.center_local
		robot._launch_rocket(impact)
		await frames(3)
		check(id + "_rocket_head_art", h.get_parent() is RocketHead and h.video_part != null and h.center_local == head_center)
		check(id + "_rocket_single_ignition", v.identity.event_counts.get("ROCKET_PHASE_START", 0) == 1)
		if id == "rocket":
			check("rocket_head_phase_no_leg_flame", (v.legs[&"leg_r"] as LegVisual).exhaust.intensity == 0)
		gm.go_menu()
		await frames(3)
		check(id + "_menu_disposes_particles_robot", not is_instance_valid(robot) and not is_instance_valid(v) and not is_instance_valid(lv) and not is_instance_valid(h))
	check("four_source_mapping", sources.size() == 4 and sources[0] != sources[1] and sources[2] != sources[3])
	check("hopper_editor_frames_excluded", RobotArtLibrary.manifest("hopper").parts.head.source_frames.all(func(n) -> bool: return int(n) < 96))
	check("tin_static_fallback_documented", RobotArtLibrary.manifest("tin").parts.leg_r.count == 1 and not RobotArtLibrary.manifest("tin").parts.leg_r.fallback.is_empty())
	check("samurai_art_not_invented", RobotArtLibrary.manifest("samurai").is_empty() and RobotIdentityProfile.for_robot("samurai").robot_id == "samurai")
	check("future_identity_fallback", RobotIdentityProfile.for_robot("future_robot").robot_id == "samurai")
	for def in gm.catalog.robots:
		var preview := RobotPreview.new()
		preview.show_robot(def, gm.robot_config)
		gm.add_child(preview)
		preview._process(0.01)
		check(def.id + "_preview_parity", (preview.art_torso != null) == ids.has(def.id))
		preview.queue_free()
	var copper := gm.build_robot(gm.catalog.get_by_id("tin"), null, null, "tin_copper")
	gm.dynamic.add_child(copper)
	check("skin_shader_preserved", copper.config.visual_material is ShaderMaterial and copper.visual.art_torso != null)
	gm.go_menu()
	await frames(3)
	gm.set_setting("shake", 0)
	gm.set_setting("vibration", 0)
	gm.profile.selected = "heavy"
	at.call("start_seen_run")
	await frames(4)
	gm.robot.freeze = true
	gm.camera._shake = 0
	gm.robot.visual.identity.event("HARD_IMPACT", 1.0)
	check("identity_respects_zero_shake", gm.camera._shake == 0 and gm.camera.shake_scale == 0)
	check("identity_respects_zero_haptic", gm.haptics.flush(1000000).is_empty() and gm.haptics.vibration_scale == 0)
	gm.go_menu()
	await frames(3)
	gm.open_robot_select()
	for i in gm.catalog.robots.size():
		await frames(25)
		var select := gm.ui.robot_select
		if select.preview.art_torso:
			var bounds := select.preview.art_bounds().grow(-18)
			var screen_bounds := Rect2(select.preview.position + bounds.position * select.preview.scale, bounds.size * select.preview.scale)
			check(select.current().id + "_preview_fits", Rect2(Vector2.ZERO, select._preview_box.size - Vector2(0, 96)).grow(12).encloses(screen_bounds))
		at.call("_shot", "v16_preview_" + gm.ui.robot_select.current().id)
		gm.ui.robot_select.step(1)
	gm._close_select()

	for id in ids:
		gm.profile.selected = id
		if not gm.profile.owned.has(id):
			gm.profile.owned.append(id)
		gm.mode = &"free"
		at.call("start_seen_run")
		await frames(25)
		gm.robot.freeze = true
		gm.hand.playing = false
		check(id + "_free_production_art", gm.robot.visual.rig.robot_id == id and gm.robot.visual.art_torso != null)
		check(id + "_hud_art_parity", (gm.ui.module_icons[&"head"].get_child(0) as TextureRect).texture is AtlasTexture)
		await frames(4)
		at.call("_shot", "v16_free_" + id)
		gm.go_menu()
		await frames(3)
