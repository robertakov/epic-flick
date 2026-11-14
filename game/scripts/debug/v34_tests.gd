extends Node
## v34 release-polish tests (debug only, not exported). --scenario=v34_all (needs -Window), --scenario=v34_qa.
## Prints "AT|test v34_<name> PASS|FAIL <details>".
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const IDLE_S := 30.0


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test v34_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run_all(which: String) -> void:
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	match which:
		"v34_qa":
			await qa()
		"v34_polish_qa":
			await polish_qa()
		"v34_tickprobe":
			for cfg in [[120, 1.0], [1920, 16.0], [960, 8.0]]:
				Engine.physics_ticks_per_second = int(cfg[0])
				Engine.time_scale = float(cfg[1])
				Engine.max_physics_steps_per_frame = 256
				await frames(5)
				var p0 := Engine.get_physics_frames()
				var dts := []
				for k in 10:
					await get_tree().process_frame
					dts.append(get_physics_process_delta_time())
				print("AT|tick ticks=%d scale=%.1f physics_delta=%.6f steps_per_frame=%.1f" % [cfg[0], cfg[1], dts[-1], float(Engine.get_physics_frames() - p0) / 15.0])
			Engine.physics_ticks_per_second = 120
			Engine.time_scale = 1.0
			Engine.max_physics_steps_per_frame = 8
		_:
			hp_tests()
			await preview_tests()
			settings_tests()
			await free_run_hud_tests()
			await rocket_skip_tests()
			await continue_confirm_tests()
			await polish_tests()
			await tutorial_tests()
	Engine.time_scale = 1.0
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ---------------- v34 polish additions: Rastabot art, camera, menu size, decorative menu robot ----------------

func polish_tests() -> void:
	# Rastabot: joint + smoke gone from every head frame; atlas / rig layout unchanged
	var img: Image = (load("res://assets/robots/tin/head.png") as Texture2D).get_image()
	var bad := []
	for i in 7:
		var ox := i * 254
		var smoke := 0
		var paper := 0
		for y in range(40, 166):
			for x in range(203, 254):
				if img.get_pixel(ox + x, y).a > 0.05:
					smoke += 1
		for y in range(134, 151):
			for x in range(166, 200):
				var c := img.get_pixel(ox + x, y)
				if c.a > 0.5 and c.r > 0.86 and c.g > 0.84 and c.b > 0.78:
					paper += 1
		if smoke > 0 or paper > 0:
			bad.append("frame %d smoke %d paper %d" % [i, smoke, paper])
	check("rastabot_joint_and_smoke_removed_all_frames", bad.is_empty() and img.get_width() == 1778 and img.get_height() == 203, str(bad))
	var pv := RobotPreview.new()
	add_child(pv)
	pv.show_robot(gm.catalog.get_by_id("tin"), gm.robot_config)
	await frames(3)
	check("rastabot_rig_intact", pv.head != null and pv.head.video_part != null and pv.art_torso != null and pv.legs.size() == 2 and pv.arms.size() == 2)
	pv.queue_free()
	# camera: the follow framing shows ~10% more world (scale 0.9), close-up cap / min zoom / flight curve kept
	var cam := gm.camera
	var phone := Vector2(2400, 1080)
	var bad_z := []
	for h in [0.0, 300.0, 800.0, 1600.0, 5000.0]:
		var old_z := clampf(cam.usable_size().y * 0.82 / (h + 420.0), cam.min_zoom, cam.base_zoom)
		var z := cam.responsive_zoom(h, cam.usable_size(), phone)
		if not is_equal_approx(z, maxf(old_z * 0.9, cam.min_zoom)):
			bad_z.append("%d: %.3f vs %.3f" % [h, z, old_z])
	check("camera_modest_zoom_out", is_equal_approx(CameraController.FRAMING_SCALE, 0.9) and is_equal_approx(cam.base_zoom, 0.88) and is_equal_approx(cam.min_zoom, 0.34) and bad_z.is_empty(),
		"ground %.3f (was %.3f); %s" % [cam.responsive_zoom(0.0, cam.usable_size(), phone), cam.base_zoom, str(bad_z)])
	# main menu: bigger circles, still inside the menu and not overlapping
	gm.go_menu()
	await frames(6)
	var ui := gm.ui
	var rects := []
	for b in ui.menu_buttons:
		rects.append(b.get_global_rect())
	var overlap := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			overlap = overlap or (rects[i] as Rect2).grow(-2).intersects(rects[j])
	var vp := get_viewport().get_visible_rect()
	var inside := rects.all(func(r: Rect2) -> bool: return vp.encloses(r))
	check("menu_buttons_larger_no_overlap", ui.menu_circle_diameter() >= 125.0 and not overlap and inside
		and not ui.menu_title.get_global_rect().grow(-4).intersects(rects[0]), "D %.0f (was ~113)" % ui.menu_circle_diameter())
	await jumper_tests()


## Visual QA shots of the polish items (needs -Window --shots=<dir>).
func polish_qa() -> void:
	var ui := gm.ui
	gm.profile.owned = ["tin", "hopper", "heavy", "rocket", "samurai"] as Array[String]
	gm.profile.select("tin")
	gm.go_menu()
	gm._refresh_menu_robot()
	await frames(20)
	at.call("_shot", "p_menu_rasta_default")
	var picks := [{"id": "samurai", "enemy": false}, {"id": "devil", "enemy": true}, {"id": "heavy", "enemy": false}, {"id": "shark", "enemy": true}, {"id": "cowboy", "enemy": true}, {"id": "hopper", "enemy": false}]
	for o in picks:
		ui.menu_jumper.show_choice(o)
		await _wait_s(1.6 + randf())
		at.call("_shot", "p_menu_jumper_%s" % o.id)
		await _wait_s(0.35)
		at.call("_shot", "p_menu_jumper_%s_b" % o.id)
	gm.open_robot_select()
	await frames(20)
	at.call("_shot", "p_select_rasta")
	gm.go_menu()
	ui.open_settings()
	await frames(15)
	at.call("_shot", "p_settings")
	ui.close_settings()
	# camera before (0.88) / after (0.80): same seed, same moment
	for z in [1.0, 0.9]:
		gm.camera.set_meta("qa_framing", z)
		gm.go_menu()
		await frames(2)
		gm.mode = &"free"
		gm.debug_track_seed = 777
		gm.start_run()
		gm.debug_track_seed = -1
		var tt := 0
		while gm.state != GameManager.State.RUN and tt < 1200:
			await get_tree().physics_frame
			tt += 1
		at.call("_shot", "p_camera_%s_0start" % str(z).replace(".", ""))
		await _wait_s(1.0)
		await _wait_until(func() -> bool: return is_instance_valid(gm.robot) and gm.robot.global_position.y > gm.terrain.height_at(gm.robot.global_position.x) - 140.0, 12.0)
		await _wait_s(0.8)
		at.call("_shot", "p_camera_%s_0low" % str(z).replace(".", ""))
		print("AT|camera z=%.2f zoom=%.3f" % [z, gm.camera.zoom.x])
		await _wait_s(2.0)
		at.call("_shot", "p_camera_%s_a" % str(z).replace(".", ""))
		await _wait_s(2.0)
		at.call("_shot", "p_camera_%s_b" % str(z).replace(".", ""))
	gm.camera.remove_meta("qa_framing")
	# rocket head prompt
	var r := gm.robot
	r._launch_rocket({"point": r.global_position, "normal": Vector2.UP})
	await _wait_s(0.4)
	at.call("_shot", "p_rocket_0_4s_no_prompt")
	await _wait_s(0.6)
	at.call("_shot", "p_rocket_1_0s_prompt")
	await _wait_until(func() -> bool: return gm.state != GameManager.State.ROCKET, 30.0)
	await frames(30)
	gm.ui.continue_card.show_offer(600, 1234, "Голова приземлилась")
	await frames(10)
	at.call("_shot", "p_continue_offer")
	gm.ui.continue_card._open_confirm()
	await frames(10)
	at.call("_shot", "p_continue_confirm")
	gm.ui.continue_card.visible = false
	gm.go_menu()
	check("polish_qa_done", true)


func jumper_tests() -> void:
	var ui := gm.ui
	var j := ui.menu_jumper
	var big := ui.menu_robot_preview
	var pool := j.pool()
	var enemies := pool.filter(func(o: Dictionary) -> bool: return o.enemy)
	check("jumper_exists_separate_from_menu_robot", j != null and j != big and (j as Node) is Node2D and big.get_parent() == ui.menu_stage
		and pool.size() == gm.catalog.robots.size() + enemies.size() and enemies.size() >= 5, "pool %d (%d enemies)" % [pool.size(), enemies.size()])
	# every protagonist AND enemy builds and fits on a button
	var fits := []
	for o in pool:
		j.show_choice(o)
		await frames(2)
		var b := j.preview.art_bounds()
		var h := b.size.y * j.preview.scale.y
		if h < ui.menu_circle_diameter() * 0.5 or h > ui.menu_circle_diameter() * 1.1:
			fits.append("%s h=%.0f" % [o.id, h])
	check("jumper_all_protagonists_and_enemies_fit", fits.is_empty(), str(fits))
	j.pick(big.def.id if big.def else "")
	# the original menu robot is untouched while the jumper plays; jumping presses nothing, saves nothing
	var big_before := [big.def.id if big.def else "", big.position, big.scale, big.get_parent()]
	var presses := [0]
	for b in ui.menu_buttons:
		b.pressed.connect(func() -> void: presses[0] += 1)
	var prof := str([gm.profile.coins, gm.profile.selected, gm.profile.owned, gm.profile.star_wallet, gm.profile.campaign, gm.stats.data.attempts, gm.settings.values])
	var state0 := gm.state
	var j0 := j.jumps
	var visited := {}
	var t := 0.0
	while t < 12.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		visited[j.at_index] = true
	var prof_after := str([gm.profile.coins, gm.profile.selected, gm.profile.owned, gm.profile.star_wallet, gm.profile.campaign, gm.stats.data.attempts, gm.settings.values])
	var big_after := [big.def.id if big.def else "", big.position, big.scale, big.get_parent()]
	check("jumper_hops_varied_route", j.jumps - j0 >= 5 and visited.size() >= 3, "jumps %d, buttons visited %d" % [j.jumps - j0, visited.size()])
	check("jumper_never_presses_or_mutates", presses[0] == 0 and gm.state == state0 and prof == prof_after and not ui.is_settings_open() and not ui.is_stats_open())
	check("original_menu_robot_unchanged", big_before == big_after, str(big_after))
	# a real tap on a button the jumper may be standing on still reaches that button
	var stats_b: Button = ui.menu_buttons[2]
	j.at_index = 2
	j.position = j.spot(2)
	await _tap(stats_b.get_global_rect().get_center())
	await frames(3)
	var opened := ui.is_stats_open()
	ui.close_stats()
	check("touch_passes_through_jumper_to_buttons", opened)
	# lifecycle: leaving the menu freezes it; coming back picks a (possibly new) robot and keeps hopping
	gm.open_robot_select()
	await frames(4)
	var p_hidden := j.position
	await frames(30)
	var frozen := j.position == p_hidden
	gm.go_menu()
	await frames(4)
	check("jumper_lifecycle_menu_leave_enter", frozen and j.preview != null and j.is_visible_in_tree(), "now %s" % j.current_id)


# ---------------- input helpers (real events) ----------------

func _mouse(pressed: bool, pos := Vector2(220, 560)) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await frames(1)


func _tap(pos := Vector2(220, 560)) -> void:
	await _mouse(true, pos)
	await frames(2)
	await _mouse(false, pos)
	await frames(2)


func _wait_s(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += 1.0 / 120.0


func _wait_until(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while t < max_s:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += 1.0 / 120.0
	return bool(cond.call())


## Robot snapshot for the idle-gate checks.
func _snap() -> Dictionary:
	var r := gm.robot
	return {"p": r.global_position, "rot": r.rotation, "v": r.linear_velocity, "w": r.angular_velocity,
		"c": r.spin_charge.ratio(), "hp": r.damage.health}


## TEST 1 at one gate: no input for IDLE_S -> nothing gameplay-critical changes; UI (Skip) stays responsive.
func _idle_gate(td: TutorialDirector, label: String) -> void:
	var a := _snap()
	var step := td.step
	await _wait_s(IDLE_S)
	var b := _snap()
	var still := (a.p as Vector2).distance_to(b.p) < 0.5 and absf(float(a.rot) - float(b.rot)) < 0.001 \
		and absf(float(a.c) - float(b.c)) < 0.0001 and is_equal_approx(float(a.hp), float(b.hp))
	# UI responsive while frozen: Skip opens its confirmation, НЕТ closes it, the gate is still closed
	var ov := gm.ui.tutorial_overlay
	ov.skip.pressed.emit()
	await frames(2)
	var ui_ok := ov.confirm.visible
	ov.confirm_no.pressed.emit()
	await frames(2)
	ui_ok = ui_ok and not ov.confirm.visible
	check("idle_%ds_gate_%s" % [int(IDLE_S), label], still and td.step == step and (td.gated or step == TutorialDirector.Step.FLICK) and ui_ok and gm.tutorial == td,
		"moved %.2f px, rot %.4f, charge %.3f->%.3f" % [(a.p as Vector2).distance_to(b.p), absf(float(a.rot) - float(b.rot)), a.c, b.c])


## A beginner's steering: hold while the robot leans clockwise past upright, release otherwise (real input only).
## Returns the airtime from the gate opening to the first contact.
func _steer_to_feet(td: TutorialDirector, step: int, max_s := 6.0) -> float:
	var t := 0.0
	var holding := false
	var landed_t := -1.0
	while t < max_s and td.step == step and not td.gated and td.active:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		var r := gm.robot
		if not is_instance_valid(r):
			break
		if r.contacts.any_contact and landed_t < 0.0:
			landed_t = t
		var n := gm.terrain.normal_at(r.global_position.x)
		var err := wrapf(r.rotation - (Vector2.UP.angle_to(n)), -PI, PI)
		var want := err > 0.08
		if want != holding:
			holding = want
			await _mouse(holding)
	if holding:
		await _mouse(false)
	return landed_t


func _start_tutorial() -> TutorialDirector:
	gm.go_menu()
	await frames(2)
	gm.profile.tutorial = {"handled": false, "completed": false}
	gm.begin_tutorial(&"campaign")
	if gm.ui.awareness.visible:
		gm.ui.awareness.confirm.pressed.emit()
	await frames(4)
	return gm.tutorial


func _tap_flick() -> void:
	await _wait_until(func() -> bool: return gm.ui.flick_bar.active and not gm.ui.flick_bar.locked and gm.ui.flick_bar.locked_tier in ["NORMAL", "STRONG"], 8.0)
	await _tap(Vector2(640, 560))


# ======================================================================================================
# 1. HP
# ======================================================================================================

const HP := {"tin": 95.0, "hopper": 100.0, "heavy": 170.0, "rocket": 100.0, "samurai": 155.0}

func hp_tests() -> void:
	var ok := true
	var rows := []
	var top := ""
	var top_hp := 0.0
	for id in HP:
		var def := gm.catalog.get_by_id(id)
		var art := def.make_configs(gm.robot_config, gm.contact_config, gm.damage_config, [SecretArtifact.module(def.base_stats(), gm.catalog)])
		var plain := def.make_configs(gm.robot_config, gm.contact_config, gm.damage_config)
		ok = ok and is_equal_approx(def.max_health, float(HP[id])) and is_equal_approx(plain.damage.max_health, float(HP[id])) \
			and is_equal_approx(art.damage.max_health, float(HP[id]) + 15.0) and is_equal_approx(def.max_health, float(HP[id]))   # v36: +15 HP
		rows.append("%s %d (artifact %.2f)" % [id, HP[id], art.damage.max_health])
		if def.max_health > top_hp:
			top_hp = def.max_health
			top = id
	check("robot_hp_final", ok and top == "heavy" and is_equal_approx(top_hp, 170.0), ", ".join(rows))
	var r := gm.build_robot(gm.catalog.get_by_id("heavy"), InputRouter.new(), gm.fx)
	gm.dynamic.add_child(r)
	r.damage.health = 0.0
	r.damage.restore_for_continue(gm.economy.continue_hp_ratio, 1.0)
	var cont := r.damage.health
	var hits := 0
	r.damage.health = r.damage.max_health
	var lost := []
	r.damage.limb_lost.connect(func(l: StringName, _i: Dictionary) -> void: lost.append(l))
	while r.damage.health > 0.0 and hits < 20:
		r.damage.invulnerable_left = 0.0
		r.damage._apply(&"head", {"point": Vector2.ZERO, "normal": Vector2.UP})
		hits += 1
	check("sumobot_170_continue_136_and_dies", is_equal_approx(cont, 136.0) and hits == 4 and lost.size() == 4, "continue %.1f, head hits to 0: %d" % [cont, hits])
	r.free()


# ======================================================================================================
# 2. Самуробот presentation scale
# ======================================================================================================

func preview_tests() -> void:
	gm.go_menu()
	await frames(2)
	var rs := gm.ui.robot_select
	var res := {}
	for id in ["samurai", "tin"]:
		rs.open(gm.catalog, gm.robot_config, id, gm.profile.owned, gm.profile.coins)
		await frames(4)
		rs._place_preview()
		var p := rs.preview
		var b := p.art_bounds()
		res[id] = {"scale": p.scale.x, "feet": p.position.y + b.end.y * p.scale.y, "h": b.size.y * p.scale.y}
	gm.ui.close_robot_select()
	var cfg := gm.catalog.get_by_id("samurai").make_configs(gm.robot_config, gm.contact_config, gm.damage_config)
	check("samurai_preview_scale_0_88_only_presentation", is_equal_approx(RobotPreview.presentation_scale("samurai"), 0.88)
		and is_equal_approx(RobotPreview.presentation_scale("tin"), 1.0) and is_equal_approx(cfg.robot.rig_scale, 0.42)
		and float(res.samurai.h) < float(res.tin.h) * 1.12, "samurai h %.0f vs tin h %.0f" % [res.samurai.h, res.tin.h])
	check("samurai_preview_feet_grounded", absf(float(res.samurai.feet) - float(res.tin.feet)) < 40.0, "feet y %.0f vs %.0f" % [res.samurai.feet, res.tin.feet])


# ======================================================================================================
# 6. fixed release physics
# ======================================================================================================

func settings_tests() -> void:
	var fresh := SettingsStore.new("user://test/v34/fresh_settings.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fresh.path))
	fresh.load_data()
	var fixed_ok := true
	for k in SettingsStore.FIXED:
		fixed_ok = fixed_ok and is_equal_approx(fresh.get_value(k), float(SettingsStore.FIXED[k]))
	check("new_install_release_baseline", fixed_ok and is_equal_approx(fresh.get_value("shake"), 90.0) and is_equal_approx(fresh.get_value("vibration"), 100.0)
		and is_equal_approx(fresh.get_value("auto_rps"), 0.9) and is_equal_approx(fresh.get_value("manual_rps"), 1.1) and is_equal_approx(fresh.get_value("invuln_s"), 0.7)
		and is_equal_approx(fresh.get_value("recovery_s"), 0.7) and is_equal_approx(fresh.get_value("spring_power"), 200.0) and fresh.get_value("bounce_spin") == 0.0)
	# an old build's customised file
	var path := "user://test/v34/old_custom_settings.json"
	DirAccess.make_dir_recursive_absolute("user://test/v34")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2, "gameplay_tuning_version": 1, "auto_rps": 2.0, "manual_rps": 0.4, "invuln_s": 1.6,
		"flick": 60.0, "spin_accel": 0.0, "recovery_s": 0.1, "recovery_pct": 90.0, "bounce_spin": 100.0, "spring_power": 75.0,
		"shake": 40.0, "vibration": 30.0, "sfx_volume": 55.0}))
	f.close()
	var old := SettingsStore.new(path)
	old.load_data()
	var old_ok := true
	for k in SettingsStore.FIXED:
		old_ok = old_ok and is_equal_approx(old.get_value(k), float(SettingsStore.FIXED[k]))
	check("old_custom_save_cannot_change_physics", old_ok and is_equal_approx(old.get_value("shake"), 40.0) and is_equal_approx(old.get_value("vibration"), 30.0)
		and is_equal_approx(float(old.unrelated.get("sfx_volume", 0)), 55.0))
	old.set_value("spring_power", 75.0)
	old.set_value("auto_rps", 2.0)
	old.reset_to_defaults()
	var reset_ok := true
	for k in SettingsStore.FIXED:
		reset_ok = reset_ok and is_equal_approx(old.get_value(k), float(SettingsStore.FIXED[k]))
	check("set_and_reset_cannot_change_physics", reset_ok and is_equal_approx(old.get_value("shake"), 90.0) and is_equal_approx(old.get_value("vibration"), 100.0))
	# runtime + UI: no physics controls; shake / vibration still act
	gm.reset_settings()
	check("runtime_uses_release_physics", is_equal_approx(gm.robot_config.clockwise_rotation_speed, 0.9) and is_equal_approx(gm.robot_config.counterclockwise_rotation_speed, 1.1)
		and is_equal_approx(gm.contact_config.spring_power_scale, 2.0) and is_equal_approx(gm.contact_config.bounce_spin_scale, 0.0)
		and is_equal_approx(gm.robot_config.recovery_time, 0.7) and is_equal_approx(gm.robot_config.recovery_start_ratio, 0.25))
	check("settings_ui_only_presentation", gm.ui._sliders.keys() == ["shake", "vibration"] and gm.ui._tab_buttons.is_empty(), str(gm.ui._sliders.keys()))
	gm.ui.setting_changed.emit("shake", 40.0)
	gm.ui.setting_changed.emit("vibration", 0.0)
	var ok := is_equal_approx(gm.camera.shake_scale, 0.4) and is_equal_approx(gm.haptics.vibration_scale, 0.0)
	gm.reset_settings()
	check("shake_vibration_still_adjustable", ok and is_equal_approx(gm.camera.shake_scale, 0.9) and is_equal_approx(gm.haptics.vibration_scale, 1.0))


# ======================================================================================================
# 3. Free Run challenge list
# ======================================================================================================

func free_run_hud_tests() -> void:
	gm.go_menu()
	await frames(2)
	gm.mode = &"free"
	gm.start_run()
	await frames(3)
	var hud := gm.ui.star_hud
	var at_start := hud.visible and hud.expanded and hud.rows[0].visible and not gm.ui.blocks_point(hud.toggle.get_global_rect().get_center())
	gm.hand.playing = false
	gm._on_flick(Vector2.ZERO)
	await frames(2)
	var after_flick := hud.expanded and hud.rows[0].visible
	gm.restart_attempt()
	await frames(3)
	check("free_run_challenges_always_visible", at_start and after_flick and hud.expanded and hud.rows[0].visible and hud.rows[2].visible)
	gm.go_menu()
	await frames(2)


# ======================================================================================================
# 4. rocket-head skip equivalence
# ======================================================================================================

## One deterministic jet-head flight (fixed seed, fixed launch state). skip: tap after ROCKET_SKIP_MIN_T.
func _rocket_run(skip: bool, mode := &"free") -> Dictionary:
	gm.go_menu()
	await frames(2)
	gm.profile.selected = "samurai"
	gm.mode = mode
	if mode == &"campaign":
		gm.node_id = "r1"
		gm.profile.ensure_campaign_start("r1")
	gm.debug_track_seed = 5151
	gm.ui.biome_intro.instant = true
	gm.start_run()
	gm.debug_track_seed = -1
	if gm.ui.awareness.visible:
		gm.ui.awareness.confirm.pressed.emit()
	await frames(3)
	gm.hand.playing = false
	gm.hand.visible = false
	gm.ui.flick_bar.hide_immediate()
	gm.state = GameManager.State.RUN
	var r := gm.robot
	var x := 3200.0
	r.launch(Vector2.ZERO, 0.0)
	r.global_position = Vector2(x, gm.terrain.height_at(x) - 260.0)
	r.rotation = 0.55
	r.linear_velocity = Vector2(650, -150)
	r.angular_velocity = 0.0
	await physics(1)
	var finishes := [0]
	gm.run_finished.connect(func(_d: float) -> void: finishes[0] += 1)
	r._launch_rocket({"point": r.global_position, "normal": Vector2.UP})
	await physics(2)
	var early := gm.skip_rocket()     # too early (< ROCKET_SKIP_MIN_T): refused
	var attempts0 := int(gm.stats.data.attempts)
	var t := 0.0
	var skipped := false
	var frames_used := 0
	var hint_early := false
	var hint_after := false
	while gm.state == GameManager.State.ROCKET and t < 40.0:
		await get_tree().process_frame
		frames_used += 1
		t += get_process_delta_time()
		if is_instance_valid(gm.rocket) and not gm.rocket_skipping:
			if gm.rocket.time < GameManager.ROCKET_SKIP_MIN_T - 0.05:
				hint_early = hint_early or gm.ui.rocket_hint_visible()
			elif gm.rocket.time > GameManager.ROCKET_SKIP_MIN_T + 0.03:
				hint_after = hint_after or gm.ui.rocket_hint_visible()
		if skip and not skipped and is_instance_valid(gm.rocket) and gm.rocket.time >= GameManager.ROCKET_SKIP_MIN_T + 0.05:
			await _tap(Vector2(640, 420))   # a real tap anywhere free
			skipped = gm.rocket_skipping or gm.state != GameManager.State.ROCKET
	await frames(3)
	var out := {"distance": gm.distance_m, "reason": gm._end_reason, "early_refused": not early, "skipped": skipped,
		"finishes": finishes[0], "frames": frames_used, "attempts": int(gm.stats.data.attempts) - attempts0,
		"coins": int(gm.last_result.get("coins_earned", 0)) if mode == &"free" else 0, "player_final": gm.player_final_m,
		"ticks": Engine.physics_ticks_per_second, "scale": Engine.time_scale, "hint_early": hint_early, "hint_after": hint_after,
		"hint_end": gm.ui.rocket_hint_visible(), "menu": gm.ui.menu.visible}
	return out


func rocket_skip_tests() -> void:
	var a: Dictionary = await _rocket_run(false)
	var b: Dictionary = await _rocket_run(true)
	print("AT|rocket natural=%s skipped=%s" % [a, b])
	check("rocket_skip_same_outcome_free_run", b.skipped and absf(float(a.distance) - float(b.distance)) < 0.5 and a.reason == b.reason
		and int(a.coins) == int(b.coins) and int(a.attempts) == 1 and int(b.attempts) == 1,
		"natural %.2f m / skipped %.2f m, %s / %s" % [a.distance, b.distance, a.reason, b.reason])
	check("rocket_skip_is_faster", int(b.frames) * 4 < int(a.frames), "frames %d -> %d" % [a.frames, b.frames])
	check("rocket_skip_not_premature", a.early_refused and b.early_refused and GameManager.ROCKET_SKIP_MIN_T >= 0.7)
	check("rocket_skip_prompt_after_guard_only", not a.hint_early and not b.hint_early and a.hint_after and b.hint_after and not a.hint_end and not b.hint_end,
		"guard %.1f s, prompt '%s'" % [GameManager.ROCKET_SKIP_MIN_T, L.t("HUD_ROCKET_SKIP")])
	check("rocket_skip_tap_isolated", not b.menu and int(b.attempts) == 1 and int(b.finishes) == 1, "")
	check("rocket_skip_single_finish_engine_restored", int(a.finishes) == 1 and int(b.finishes) == 1 and int(b.ticks) == 120 and is_equal_approx(float(b.scale), 1.0))
	var ca: Dictionary = await _rocket_run(false, &"campaign")
	var cb: Dictionary = await _rocket_run(true, &"campaign")
	check("rocket_skip_same_outcome_campaign", cb.skipped and absf(float(ca.player_final) - float(cb.player_final)) < 0.5,
		"natural %.2f m / skipped %.2f m" % [ca.player_final, cb.player_final])
	gm.ui.campaign_result.visible = false
	gm.go_menu()
	await frames(2)


# ======================================================================================================
# 5. paid continue confirmation
# ======================================================================================================

func continue_confirm_tests() -> void:
	gm.continue_offers_enabled = true
	gm.go_menu()
	await frames(2)
	var price := gm.continue_price()
	gm.profile.coins = price * 2 + 7
	gm.mode = &"free"
	gm.start_run()
	await frames(3)
	gm.hand.playing = false
	gm.state = GameManager.State.RUN
	gm.robot.launch(Vector2(600, -300), 0.0)
	await physics(30)
	gm._finish("Робот остановился")
	var card := gm.ui.continue_card
	var start := gm.profile.coins
	check("continue_button_shows_cost", card.yes.text.contains(str(price)) and card.yes.icon != null and card.price_label.text.contains(str(start)), card.yes.text + " + coin icon")
	await _wait_s(ContinueCard.ARM_S + 0.1)
	card.yes.pressed.emit()
	await frames(1)
	check("continue_needs_confirmation", card.stage == "confirm" and gm.profile.coins == start and gm.state == GameManager.State.OFFER
		and card.confirm_title.text.contains(str(price)))
	card.confirm_yes.pressed.emit()     # double tap right away: still disarmed -> nothing
	await frames(1)
	check("confirm_disarmed_against_double_tap", gm.profile.coins == start and card.stage == "confirm")
	await _wait_s(ContinueCard.CONFIRM_ARM_S + 0.1)
	card.confirm_no.pressed.emit()
	await frames(1)
	check("cancel_spends_nothing_keeps_offer", gm.profile.coins == start and card.stage == "offer" and gm.state == GameManager.State.OFFER
		and not gm._continue_used and card.visible)
	await _wait_s(0.4)
	card.yes.pressed.emit()
	await _wait_s(ContinueCard.CONFIRM_ARM_S + 0.1)
	var robot_before := gm.robot
	# spam + multi-touch: three presses in one frame, plus direct calls
	card.confirm_yes.pressed.emit()
	card.confirm_yes.pressed.emit()
	card.confirm_yes.pressed.emit()
	var second := gm.accept_continue()
	await physics(2)
	var robot_after := gm.robot
	check("confirm_charges_exactly_once", gm.profile.coins == start - price and gm._continue_used and not second and robot_after != robot_before
		and gm.state == GameManager.State.RUN, "coins %d -> %d" % [start, gm.profile.coins])
	card.confirm_yes.pressed.emit()
	await frames(1)
	var r2 := gm.robot
	check("no_second_respawn_or_charge", gm.robot == r2 and gm.profile.coins == start - price)
	gm._finish("Робот остановился")
	check("continue_once_per_run", gm.state == GameManager.State.RESULT and not card.visible and gm.profile.coins == start - price + gm._coins_earned)
	# Back on the confirmation cancels the spend
	gm.profile.coins = price + 1
	gm.start_run()
	await frames(3)
	gm.hand.playing = false
	gm.state = GameManager.State.RUN
	gm.robot.launch(Vector2(600, -300), 0.0)
	await physics(30)
	gm._finish("Робот остановился")
	await _wait_s(ContinueCard.ARM_S + 0.1)
	card.yes.pressed.emit()
	gm._last_back_ms = -100000   # separate physical press (v36.9 Back debounce)
	gm._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(1)
	check("back_cancels_confirmation", card.stage == "offer" and gm.state == GameManager.State.OFFER and gm.profile.coins == price + 1)
	card.no.pressed.emit()
	await frames(2)
	# insufficient funds: no offer, nothing spent, straight to the result
	gm.profile.coins = price - 1
	gm.start_run()
	await frames(3)
	gm.hand.playing = false
	gm.state = GameManager.State.RUN
	gm.robot.launch(Vector2(600, -300), 0.0)
	await physics(30)
	gm._finish("Робот остановился")
	await frames(2)
	check("continue_insufficient_funds_no_offer", not card.visible and gm.state == GameManager.State.RESULT and gm.profile.coins == price - 1 + gm._coins_earned,
		"coins %d" % gm.profile.coins)
	gm.continue_offers_enabled = false
	get_tree().paused = false
	gm.go_menu()
	await frames(2)


# ======================================================================================================
# tutorial: freeze gates, fair charge airtime, failed charge reset, slow-human completion
# ======================================================================================================

func tutorial_tests() -> void:
	var td := await _start_tutorial()
	check("tutorial_uses_release_controls", is_equal_approx(gm.robot.config.clockwise_rotation_speed, 0.9) and is_equal_approx(gm.robot.config.counterclockwise_rotation_speed, 1.1)
		and is_equal_approx(Engine.time_scale, 1.0), "%.2f / %.2f" % [gm.robot.config.clockwise_rotation_speed, gm.robot.config.counterclockwise_rotation_speed])
	# FLICK gate (the hand waits at tension)
	await _idle_gate(td, "flick")
	check("flick_waits_indefinitely", td.step == TutorialDirector.Step.FLICK and gm.state == GameManager.State.INTRO)
	await _tap_flick()
	# ROTATE gate: the flicked robot freezes in flight
	var rot_gate := await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.ROTATE and td.gated, 4.0)
	check("rotate_gate_freezes_in_flight", rot_gate and gm.robot.freeze and not gm.robot.contacts.any_contact)
	await _idle_gate(td, "rotate")
	await _mouse(true)     # ЗАЖМИ ЭКРАН
	var rot_ok := await _wait_until(func() -> bool: return td.step != TutorialDirector.Step.ROTATE, 3.0)
	await _mouse(false)
	check("rotate_learned_by_real_hold", rot_ok and td.completions.has("ROTATE"), str(td.completions))
	# FEET gate
	await _wait_until(func() -> bool: return td.gated and td.step == TutorialDirector.Step.FEET, 3.0)
	await _idle_gate(td, "feet")
	var attempts := 0
	while td.step == TutorialDirector.Step.FEET and attempts < 6:
		attempts += 1
		await _wait_until(func() -> bool: return td.gated, 3.0)
		await _mouse(true)    # the press opens the gate (hold to steer)
		await _steer_to_feet(td, TutorialDirector.Step.FEET)
		await _wait_until(func() -> bool: return td.step != TutorialDirector.Step.FEET or td.gated, 3.0)
	check("feet_learned_with_beginner_steering", td.completions.has("FEET"), "attempts %d" % attempts)
	await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.CHARGE and td.gated, 4.0)
	check("rebound_observed", td.completions.has("REBOUND"))
	# CHARGE gate: real airtime with the release spin speed
	await _idle_gate(td, "charge")
	var setup_y := gm.robot.global_position.y
	var ground := gm.terrain.height_at(gm.robot.global_position.x)
	await _tap()           # ТАПНИ — then hands off
	var t0 := 0.0
	var learned := false
	while t0 < 4.0:
		await get_tree().physics_frame
		t0 += 1.0 / 120.0
		if td.step == TutorialDirector.Step.CHARGED:
			learned = true
			break
	check("charge_built_by_real_spin_in_airtime", learned and gm.robot.spin_charge.ratio() >= TutorialDirector.CHARGE_GOAL,
		"charge %.2f after %.2fs, setup height %.0f px" % [gm.robot.spin_charge.ratio(), t0, ground - setup_y])
	# CHARGED gate: the earned charge is kept while frozen, then the beginner steers and lands on the feet
	await _wait_until(func() -> bool: return td.gated, 2.0)
	var kept := gm.robot.spin_charge.ratio()
	await _idle_gate(td, "charged")
	check("charge_kept_while_frozen", is_equal_approx(gm.robot.spin_charge.ratio(), kept) and kept >= TutorialDirector.CHARGE_GOAL)
	var clearance := gm.terrain.height_at(gm.robot.global_position.x) - gm.robot.global_position.y
	await _mouse(true)
	var air := await _steer_to_feet(td, TutorialDirector.Step.CHARGED)
	check("enough_time_to_orient_after_charge", clearance >= TutorialDirector.CHARGED_CLEARANCE - 1.0 and air >= 0.5, "clearance %.0f px, airtime to touchdown %.2fs" % [clearance, air])
	var done := await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.DONE, 3.0)
	var guard := 0
	while not done and guard < 5:
		# a missed charged landing resets the CHARGE lesson (never stuck) - redo it like a slow human
		guard += 1
		await _wait_until(func() -> bool: return td.gated, 4.0)
		if td.step == TutorialDirector.Step.CHARGE:
			await _wait_s(2.0)
			await _tap()
			await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.CHARGED and td.gated, 5.0)
		await _wait_s(2.0)
		await _mouse(true)
		await _steer_to_feet(td, TutorialDirector.Step.CHARGED)
		done = await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.DONE, 3.0)
	check("slow_human_completes_tutorial", done and gm.ui.tutorial_overlay.done_card.visible, "extra charged attempts %d, completions %s" % [guard, td.completions])
	gm.ui.tutorial_overlay.play.pressed.emit()
	await frames(3)
	check("finish_restores_normal_play", gm.tutorial == null and is_equal_approx(Engine.time_scale, 1.0) and bool(gm.profile.tutorial.completed))
	await failed_charge_test()


## TEST 3: a deliberately wrong (upside-down) charged landing resets the CHARGE lesson into a fresh fair attempt.
func failed_charge_test() -> void:
	gm.ui.campaign_map.visible = false
	var td := await _start_tutorial()
	td.set_step(TutorialDirector.Step.CHARGE)
	td.setup_step()
	await frames(2)
	await _tap()
	await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.CHARGED and td.gated, 5.0)
	await _mouse(true)
	await _mouse(false)
	var r := gm.robot
	for k in 120 * 4:
		await get_tree().physics_frame
		if td.step != TutorialDirector.Step.CHARGED or td.gated:
			break
		if is_instance_valid(r):
			r.rotation = PI           # a wrong landing on purpose (head first)
			r.angular_velocity = 0.0
	var reset := await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.CHARGE and td.gated, 4.0)
	var nr := gm.robot
	check("failed_charge_resets_fair_attempt", reset and nr != r and nr.freeze and is_equal_approx(nr.spin_charge.ratio(), 0.0)
		and gm.terrain.height_at(nr.global_position.x) - nr.global_position.y > 1000.0 and td.active, "retries %d" % td.retries)
	gm.ui.tutorial_overlay.skip.pressed.emit()
	await frames(2)
	gm.ui.tutorial_overlay.confirm_yes.pressed.emit()
	await frames(3)
	gm.ui.campaign_map.visible = false
	gm.go_menu()


# ======================================================================================================
# visual QA
# ======================================================================================================

func qa() -> void:
	var td := await _start_tutorial()
	await frames(30)
	at.call("_shot", "v34_t1_flick_gate")
	await _tap_flick()
	await _wait_until(func() -> bool: return td.gated, 4.0)
	await _wait_s(10.0)
	at.call("_shot", "v34_t2_rotate_gate_after_10s")
	await _mouse(true)
	await _wait_until(func() -> bool: return td.step != TutorialDirector.Step.ROTATE, 3.0)
	await _mouse(false)
	await _wait_until(func() -> bool: return td.gated, 3.0)
	await _wait_s(10.0)
	at.call("_shot", "v34_t3_feet_gate_after_10s")
	var n := 0
	while td.step == TutorialDirector.Step.FEET and n < 6:
		n += 1
		await _wait_until(func() -> bool: return td.gated, 3.0)
		await _mouse(true)
		await _steer_to_feet(td, TutorialDirector.Step.FEET)
		await _wait_until(func() -> bool: return td.step != TutorialDirector.Step.FEET or td.gated, 3.0)
	await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.CHARGE and td.gated, 4.0)
	await _wait_s(10.0)
	at.call("_shot", "v34_t5_charge_gate_after_10s")
	await _tap()
	await _wait_s(0.6)
	at.call("_shot", "v34_t5_charge_building")
	await _wait_until(func() -> bool: return td.step == TutorialDirector.Step.CHARGED and td.gated, 5.0)
	await _wait_s(10.0)
	at.call("_shot", "v34_t6_charged_gate_after_10s")
	await _mouse(true)
	await _steer_to_feet(td, TutorialDirector.Step.CHARGED)
	await _wait_s(1.0)
	at.call("_shot", "v34_t7_after_charged")
	check("qa_done", true)
