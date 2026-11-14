class_name AutoTest
extends Node
## Debug-only harness, enabled with user args:  -- --autotest=bot [--bot=smart|cw|ccw|random]
##   [--lean=20] [--runs=3] [--shots=<dir>] [--shot_every=0.5] [--max_time=60] [--start_run]
## Drives the single input like a player would and prints telemetry lines (prefix "AT|").
## Never shipped behaviour: GameManager only adds this node when --autotest is present.

var gm: GameManager
var args := {}
var bot := "smart"
var lean := 20.0
var runs := 1
var shots_dir := ""
var shot_every := 0.5
var max_time := 60.0
var _run_index := 0
var _t := 0.0
var _shot_t := 0.0
var _shot_n := 0
var _rng := RandomNumberGenerator.new()
var _random_hold_until := 0.0
var _stats := {}
var _all := []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	bot = args.get("bot", bot)
	input_mode = args.get("input", "virtual")
	if args.has("novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	lean = float(args.get("lean", lean))
	runs = int(args.get("runs", runs))
	shots_dir = args.get("shots", "")
	shot_every = float(args.get("shot_every", shot_every))
	max_time = float(args.get("max_time", max_time))
	_rng.seed = int(args.get("seed", 1))
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	if args.has("spin_off"):
		var sc: SpinChargeConfig = gm.spin_config.duplicate()
		sc.enabled = false
		gm.spin_config = sc
	if args.has("cam_zoom"):
		gm.camera.base_zoom = float(args.cam_zoom)
		gm.camera.min_zoom = float(args.cam_zoom)
	if args.get("mode", "") == "campaign":
		gm.mode = &"campaign"
		gm.node_id = String(args.get("node", "r1"))
		for id in gm.campaign.order:   # tests may start any node
			gm.profile.ensure_campaign_start(id) if id == gm.node_id else null
	gm.run_started.connect(_on_run_started)
	gm.run_finished.connect(_on_run_finished)
	print("AT|start bot=%s lean=%.1f runs=%d" % [bot, lean, runs])
	_terrain_report()
	if args.has("menu_shot"):
		await get_tree().create_timer(0.6).timeout
		_shot("menu")
	if args.has("scenario"):
		await get_tree().create_timer(0.3).timeout
		# scenarios drive the game flow themselves
		gm.run_started.disconnect(_on_run_started)
		gm.run_started.connect(func() -> void: _t = 0.0)
		gm.run_finished.disconnect(_on_run_finished)
		var sc_name := String(args.scenario)
		var script_path := "res://scripts/debug/damage_scenarios.gd"
		if sc_name.begins_with("achievements"):
			script_path = "res://scripts/debug/achievement_tests.gd"
		elif sc_name.begins_with("technical_"):
			script_path = "res://scripts/debug/technical_tests.gd"
		elif sc_name == "biome_probe":
			script_path = "res://scripts/debug/biome_probe.gd"
		elif sc_name.begins_with("qa_"):
			script_path = "res://scripts/debug/qa_soak_tests.gd"
		elif sc_name.begins_with("v39_"):
			script_path = "res://scripts/debug/v39_audio_tests.gd"
		elif sc_name.begins_with("v37_"):
			script_path = "res://scripts/debug/v37_audio_tests.gd"
		elif sc_name.begins_with("v36_"):
			script_path = "res://scripts/debug/v36_tests.gd"
		elif sc_name.begins_with("mk2_"):
			script_path = "res://scripts/debug/mk2_tests.gd"
		elif sc_name.begins_with("loc_"):
			script_path = "res://scripts/debug/loc_tests.gd"
		elif sc_name.begins_with("v34_"):
			script_path = "res://scripts/debug/v34_tests.gd"
		elif sc_name.begins_with("v33_"):
			script_path = "res://scripts/debug/v33_tests.gd"
		elif sc_name.begins_with("v32_"):
			script_path = "res://scripts/debug/v32_tests.gd"
		elif sc_name.begins_with("profiles"):
			script_path = "res://scripts/debug/profile_tests.gd"
		elif sc_name.begins_with("biome"):
			script_path = "res://scripts/debug/biome_tests.gd"
		elif sc_name.begins_with("v28_"):
			script_path = "res://scripts/debug/v28_tests.gd"
		elif sc_name.begins_with("v27_"):
			script_path = "res://scripts/debug/v27_tests.gd"
		elif sc_name.begins_with("v23_"):
			script_path = "res://scripts/debug/v23_tests.gd"
		elif sc_name.begins_with("v21_"):
			script_path = "res://scripts/debug/v21_tests.gd"
		elif sc_name.begins_with("v19_"):
			script_path = "res://scripts/debug/v19_tests.gd"
		elif sc_name.begins_with("v18_"):
			script_path = "res://scripts/debug/v18_tests.gd"
		elif sc_name.begins_with("v17_"):
			script_path = "res://scripts/debug/v17_tests.gd"
		elif sc_name.begins_with("v16_"):
			script_path = "res://scripts/debug/v16_tests.gd"
		elif sc_name.begins_with("v15_"):
			script_path = "res://scripts/debug/v15_tests.gd"
		elif sc_name in ["currency", "free_challenges", "free_layout", "free_calibration", "free_report"]:
			script_path = "res://scripts/debug/v14_tests.gd"
		elif sc_name in ["springs", "camera", "abandon", "tutorial", "tutorial_layout"]:
			script_path = "res://scripts/debug/continuation_tests.gd"
		elif sc_name in ["menu_layout", "feedback", "ai_bands", "campaign_distribution"]:
			script_path = "res://scripts/debug/release_tests.gd"
		elif sc_name.begins_with("stats"):
			script_path = "res://scripts/debug/stats_tests.gd"
		elif sc_name == "stress" or sc_name == "track" or sc_name == "recycle" or sc_name == "track_probe" or sc_name == "layout" or sc_name == "fontmem" or sc_name == "terrain_view" or sc_name.begins_with("settings_"):
			script_path = "res://scripts/debug/stress_tests.gd"
		elif sc_name == "stars" or sc_name == "star_layout" or sc_name == "star_report":
			script_path = "res://scripts/debug/star_tests.gd"
		elif sc_name == "campaign" or sc_name == "ai_sim" or sc_name == "campaign_shots":
			script_path = "res://scripts/debug/campaign_tests.gd"
		var sc_script: GDScript = load(script_path)
		if sc_script == null or not sc_script.can_instantiate():
			print("AT|tests passed=0 failed=1 (scenario script failed to load: %s)" % script_path)
			get_tree().quit(1)
			return
		var sc: Node = sc_script.new()
		sc.set("gm", gm)
		sc.set("at", self)
		add_child(sc)
		await sc.call("run_all", String(args.scenario))
		print("AT|done")
		get_tree().quit()
		return
	if args.has("ui_shots") and shots_dir != "":
		_shot("v9_menu")
		gm.open_robot_select()
		for i in gm.catalog.robots.size():
			await get_tree().create_timer(0.7).timeout
			_shot("v9_select_%d_%s" % [i, gm.ui.robot_select.current().id])
			gm.ui.robot_select.step(1)
		gm._close_select()
		gm.ui.open_settings()
		await get_tree().create_timer(0.4).timeout
		_shot("v9_settings")
		gm.ui.show_settings_page(1)
		await get_tree().create_timer(0.3).timeout
		_shot("v9_settings_rotation")
		gm.ui.show_settings_page(0)
		gm.ui.close_settings()
	if args.has("menu_wait"):
		await get_tree().create_timer(float(args.menu_wait)).timeout
	if args.has("click"):
		await get_tree().create_timer(0.5).timeout
		_click_button("ИГРАТЬ")
	else:
		start_seen_run.call_deferred()


func _on_run_started() -> void:
	_t = 0.0
	_stats = {"touchdown": {}, "landing": {}, "body": 0, "limbs": [], "rocket": false, "dmg": [], "hp0_t": -1.0, "rocket_t": -1.0, "charge_uses": [], "charge_lost": 0, "max_speed": 0.0, "max_height": 0.0, "max_charge": 0.0, "full_spin_rps": 0.0, "cam_out_frames": 0, "cam_frames": 0, "min_zoom": 9.0}
	await get_tree().process_frame
	var r := gm.robot
	var icons_ok := true
	for k in gm.ui.module_icons:
		if gm.ui.module_icons[k].modulate != Color.WHITE:
			icons_ok = false
	print("AT|runstart run=%d hp=%.0f limbs=%s ui_hp=%.0f ui_modules_reset=%s rocket_fired=%s" % [_run_index, r.damage.health, r.damage.limbs_remaining, gm.ui._hp_value, icons_ok, r.damage.rocket_fired])
	r.touchdown.connect(func(i: Dictionary) -> void:
		_count("touchdown", "%s/%s" % [i.type, i.quality])
		print("AT|touchdown t=%.2f type=%s q=%s impact=%.0f lean=%.1f x=%.0f" % [_t, i.type, i.quality, i.impact, i.lean, i.point.x]))
	r.landed.connect(func(i: Dictionary) -> void:
		_count("landing", "%s/%s" % [i.type, i.quality])
		print("AT|spin t=%.2f type=%s/%s w_in=%.2f w_out=%.2f rev/s | spring=%.2f solver=%.2f ctrl=%.2f dur=%.2f" % [_t, i.type, i.quality, i.get("w_in", 0.0) / TAU, i.get("w_out", 0.0) / TAU, i.get("dw_spring", 0.0) / TAU, i.get("dw_solver", 0.0) / TAU, i.get("dw_ctrl", 0.0) / TAU, i.duration])
		print("AT|landing t=%.2f type=%s q=%s in=%.0f out=%.0f vout=(%.0f,%.0f) dur=%.3f" % [_t, i.type, i.quality, i.speed_in, i.speed_out, i.velocity_out.x, i.velocity_out.y, i.duration]))
	r.body_hit.connect(func(i: Dictionary) -> void:
		_stats.body += 1
		print("AT|bodyhit t=%.2f kind=%s impact=%.0f" % [_t, i.kind, i.impact]))
	r.damaged.connect(func(amount: float, cls: StringName, hp: float, i: Dictionary) -> void:
		_stats.dmg.append("%s:%d" % [cls, int(amount)])
		if hp <= 0.0 and _stats.hp0_t < 0.0:
			_stats.hp0_t = _t
		print("AT|dmg t=%.2f event=%d zone=%s class=%s amount=%.0f hp=%.0f upgrade=%s impact=%.0f" % [_t, i.get("event", -1), i.get("zone", "?"), cls, amount, hp, i.get("upgrade", false), i.get("impact", 0.0)]))
	r.charge_released.connect(func(c: float, dv: Vector2, i: Dictionary) -> void:
		_stats.charge_uses.append("%s:%d%%>%d%%" % [i.zone_class, int(c * 100), int(i.effective * 100)])
		print("AT|charge_use t=%.2f charge=%.2f zone=%s effective=%.2f type=%s dv=(%.0f,%.0f) |dv|=%.0f" % [_t, c, i.zone_class, i.effective, i.get("type", ""), dv.x, dv.y, dv.length()]))
	r.spin_charge.charge_lost.connect(func(a: float, why: StringName) -> void:
		_stats.charge_lost += 1
		print("AT|charge_lost t=%.2f amount=%.2f why=%s" % [_t, a, why]))
	r.limb_lost.connect(func(l: StringName, _p: RigidBody2D) -> void:
		_stats.limbs.append(String(l))
		print("AT|limb t=%.2f %s" % [_t, l]))
	r.rocket_launched.connect(func(h: RigidBody2D) -> void:
		_stats.rocket = true
		_stats.rocket_t = _t
		var d: Vector2 = (h as RocketHead).launch_direction()
		print("AT|rocket t=%.2f dir=(%.2f,%.2f) angle=%.0f vel=(%.0f,%.0f)" % [_t, d.x, d.y, rad_to_deg(d.angle()), h.linear_velocity.x, h.linear_velocity.y]))


var _ext_x := [0.0, 0.0]
var _extreme_n := 0


## Track sanity on a long geometry-only build of the current seed: monotonic x, no gaps, slope limits,
## template usage / repeats, and the steepest turn at template seams.
func _terrain_report() -> void:
	var tb := TerrainBuilder.new()
	tb.build_nodes = false
	add_child(tb)
	tb.build(gm.level_config, gm.track_seed)
	tb.ensure_ahead(200000.0)
	var pts := tb.points
	var mono := true
	var max_step := 0.0
	var max_deg := -90.0
	var min_deg := 90.0
	var extreme := 0
	var max_turn := 0.0
	var prev_deg := 0.0
	for k in pts.size() - 1:
		var d := pts[k + 1] - pts[k]
		mono = mono and d.x > 0.0
		max_step = maxf(max_step, d.length())
		if pts[k].x > 760.0:
			var deg := rad_to_deg(atan2(d.y, d.x))
			max_deg = maxf(max_deg, deg)
			min_deg = minf(min_deg, deg)
			if deg < -30.0 or deg > 60.0:
				extreme += 1
			if k > 0 and pts[k - 1].x > 760.0:
				max_turn = maxf(max_turn, absf(deg - prev_deg))
			prev_deg = deg
	var span := tb.end_x() - 760.0
	var drop := tb.height_at(tb.end_x()) - tb.height_at(760.0)
	var used := {}
	var repeats := 0
	var prev := ""
	for s in tb.sections:
		if s.name == "start":
			continue
		used[s.name] = used.get(s.name, 0) + 1
		if s.name == prev:
			repeats += 1
		prev = s.name
	var pal := {}
	for s in tb.sections:
		pal[s.palette] = pal.get(s.palette, 0) + 1
	print("AT|terrain seed=%d km=%.0f points=%d monotonic=%s max_step=%.1f overall_slope=%.1f deg steepest=%.1f most_uphill=%.1f extreme(<-30|>60)=%d max_turn_per_sample=%.1f templates_used=%d/15 sections=%d back_to_back=%d palettes=%s first10=%s" % [
		gm.track_seed, span / 100000.0, pts.size(), mono, max_step, rad_to_deg(atan2(drop, span)), max_deg, min_deg, extreme,
		max_turn, used.size(), tb.sections.size() - 1, repeats, pal, ",".join(tb.sections.slice(1, 11).map(func(s: Dictionary) -> String: return s.name))])
	tb.queue_free()

func max_step_fix(v: float) -> float:
	return v


func _count(k: String, key: String) -> void:
	_stats[k][key] = _stats[k].get(key, 0) + 1


func _on_run_finished(distance: float) -> void:
	_stats["distance"] = distance
	_stats["time"] = _t
	_stats["reason"] = gm._end_reason
	_stats["hp_end"] = gm.robot.damage.health if is_instance_valid(gm.robot) else -1.0
	print("AT|perf avg_process_ms=%.2f avg_physics_ms=%.2f max_process_ms=%.2f objects=%d" % [_perf_proc / maxf(_perf_n, 1), _perf_phys / maxf(_perf_n, 1), _perf_max, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("AT|input mode=%s hold_frames=%d frames=%d router_holding_now=%s" % [input_mode, _hold_frames, _frames, gm.input.holding])
	if gm.mode == &"campaign" and not gm.campaign_result.is_empty():
		var cr := gm.campaign_result
		print("AT|race node=%s won=%s player=%.1f enemies=%s coins=%d kind=%s skin=%s attempts=%d mod=%+.3f->%+.3f" % [cr.node, cr.won, cr.player_m,
			cr.enemies.map(func(e: Dictionary) -> String: return "%s/%s:%.1f(%s,skill %.2f)" % [e.name, e.robot, e.m, e.reason, e.skill]),
			cr.coins, cr.coins_kind, cr.skin_name, cr.attempts, cr.mod_before, cr.mod_after])
	print("AT|finish run=%d distance=%.1f time=%.1f stats=%s" % [_run_index, distance, _t, JSON.stringify(_stats)])
	_all.append(_stats)
	_run_index += 1
	await get_tree().create_timer(0.6).timeout
	_ui_block_check()
	if shots_dir != "":
		_shot("result_%d" % _run_index)
	if _run_index >= runs:
		print("AT|done")
		get_tree().quit()
	else:
		await get_tree().create_timer(0.3).timeout
		if args.has("click"):
			_click_button("ЕЩЁ РАЗ!")
		else:
			gm.start_run()


var _ptimer := 0.0
## Set by scenario tests that drive the input themselves.
var scenario_running := false


func _physics_process(dt: float) -> void:
	if scenario_running:
		return
	if gm.ui.awareness.visible and gm.ui.awareness.kind=="campaign":
		gm.ui.awareness.confirm.pressed.emit()
	_ptimer += dt
	if args.has("perf_trace") and _ptimer > 1.0:
		_ptimer = 0.0
		print("AT|trace chunk_ms=%.2f chunks=%d state=%d fps=%d phys_ms=%.2f proc_ms=%.2f bodies=%d pairs=%d" % [gm.terrain.last_chunk_usec / 1000.0, gm.terrain._chunks.size(), gm.state, Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)])
	if gm.state == GameManager.State.MENU or gm.state == GameManager.State.RESULT:
		return
	_t += dt
	if _t > max_time:
		print("AT|timeout")
		gm._finish("timeout")
		return
	if gm.state == GameManager.State.RUN and is_instance_valid(gm.robot) and _stats.has("max_speed"):
		var rr := gm.robot
		_stats.max_speed = maxf(_stats.max_speed, rr.linear_velocity.length())
		_stats.max_height = maxf(_stats.max_height, gm.terrain.height_at(rr.global_position.x) - rr.global_position.y)
		_stats.max_charge = maxf(_stats.max_charge, rr.spin_charge.charge)
		# camera must keep the followed piece on screen
		var cam := gm.camera
		var half := get_viewport().get_visible_rect().size / (2.0 * cam.zoom.x)
		var view := Rect2(cam.get_screen_center_position() - half, half * 2.0)
		_stats.cam_frames += 1
		_stats.min_zoom = minf(_stats.min_zoom, cam.zoom.x)
		if not view.grow(-20.0).has_point(rr.global_position):
			_stats.cam_out_frames += 1
		if rr.spin_charge.charge >= 0.999:
			_stats.full_spin_rps = maxf(_stats.full_spin_rps, rr.angular_velocity / TAU)
	if args.has("trace_rocket") and gm.state == GameManager.State.ROCKET and is_instance_valid(gm.rocket) and Engine.get_physics_frames() % 6 == 0:
		var rk := gm.rocket
		print("AT|rk t=%.2f pos=(%.0f,%.0f) vel=(%.0f,%.0f) w=%.1f burn=%s contacts=%d ground_y=%.0f" % [_t, rk.global_position.x, rk.global_position.y, rk.linear_velocity.x, rk.linear_velocity.y, rk.angular_velocity, rk.burning, rk.get_contact_count(), gm.terrain.height_at(rk.global_position.x)])
	var want := gm.state == GameManager.State.RUN and is_instance_valid(gm.robot) and _decide(gm.robot)
	_apply_input(want)


var input_mode := "virtual"
var _sent := false
var _hold_frames := 0
var _frames := 0


## Feeds the decision through the real input pipeline (InputEventMouseButton / Key / ScreenTouch).
func _apply_input(want: bool) -> void:
	_frames += 1
	if want:
		_hold_frames += 1
	if input_mode == "virtual":
		gm.input.set_virtual_hold(want)
		return
	if want == _sent:
		return
	_sent = want
	var pos := get_viewport().get_visible_rect().size * Vector2(0.6, 0.5)
	var ev: InputEvent
	match input_mode:
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = want
			mb.position = pos
			ev = mb
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = KEY_SPACE
			k.keycode = KEY_SPACE
			k.pressed = want
			ev = k
		"touch":
			var t := InputEventScreenTouch.new()
			t.index = 0
			t.pressed = want
			t.position = pos
			ev = t
	Input.parse_input_event(ev)


var _perf_proc := 0.0
var _perf_phys := 0.0
var _perf_max := 0.0
var _perf_n := 0.0


func _click_button(text: String) -> void:
	if text == "ИГРАТЬ" and gm.ui.menu.visible:
		text = "СВОБОДНЫЙ ЗАБЕГ"
	for b in gm.ui._buttons:
		if b.text == text and b.is_visible_in_tree():
			var pos := b.get_global_rect().get_center()
			for pressed in [true, false]:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT
				mb.pressed = pressed
				mb.position = pos
				mb.global_position = pos
				Input.parse_input_event(mb)
				await get_tree().process_frame
			print("AT|clicked %s at %s" % [text, pos])
			if text != "ИГРАТЬ" and gm.ui.is_robot_select_open():
				await get_tree().create_timer(0.3).timeout
				await _click_button("ИГРАТЬ")
			elif text == "ИГРАТЬ" and gm.ui.is_robot_select_open():
				await get_tree().create_timer(0.3).timeout
				await _click_button(text)
			return
	print("AT|click failed: no visible button %s" % text)


func _process(dt: float) -> void:
	if gm.state == GameManager.State.RUN or gm.state == GameManager.State.ROCKET:
		var pp := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_perf_proc += pp
		_perf_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_perf_max = maxf(_perf_max, pp)
		_perf_n += 1.0
	if shots_dir == "" or gm.state == GameManager.State.MENU:
		return
	_shot_t += dt
	if _shot_t >= shot_every:
		_shot_t = 0.0
		_shot("r%d_%03d" % [_run_index, _shot_n])
		_shot_n += 1


func _shot(n: String) -> void:
	if shots_dir == "":
		return
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img != null and not img.is_empty():
		img.save_png(shots_dir.path_join(n + ".png"))


# ---------------- bots ----------------

func _decide(r: RobotController) -> bool:
	match bot:
		"cw":
			return false
		"ccw":
			return true
		"random":
			if _t > _random_hold_until:
				_random_hold_until = _t + _rng.randf_range(0.1, 0.6)
				return _rng.randf() < 0.5
			return gm.input.holding
		"charger":
			return _charger(r)
	return _smart(r)


## Plans hold time so the robot's up axis meets the predicted landing normal + `lean` degrees.
func _smart(r: RobotController) -> bool:
	var pred := _predict_impact(r)
	if pred.is_empty():
		return false
	var tau: float = pred.t
	var n: Vector2 = pred.normal
	var target := atan2(n.x, -n.y) + deg_to_rad(lean)
	var w1 := r.rotation_ctl.auto_rps() * TAU
	var w2 := -r.config.counterclockwise_rotation_speed * TAU
	var rr := r.config.rotation_response
	var theta := r.global_rotation
	var w0 := r.angular_velocity
	# plan: hold for h seconds, then release until impact; omega follows w' = rr*(target - w)
	var best_h := 0.0
	var best_err := INF
	var h := 0.0
	while h <= tau + 0.0001:
		var e1 := exp(-rr * h)
		var th1 := theta + w2 * h + (w0 - w2) * (1.0 - e1) / rr
		var wh := w2 + (w0 - w2) * e1
		var t2 := tau - h
		var th2 := th1 + w1 * t2 + (wh - w1) * (1.0 - exp(-rr * t2)) / rr
		var err := absf(wrapf(th2 - target, -PI, PI))
		if err < best_err - 0.01:
			best_err = err
			best_h = h
		h += 0.01
	return best_h > 0.005

## Charge-greedy player (v0.9: the AUTOMATIC clockwise spin charges): keeps the screen released as long as
## possible and only holds in a final correction phase so the robot still lands with the wanted lean.
## Plan = release for (tau - h), then hold for h; the smallest h within tolerance is chosen; hold only once
## the remaining time reaches h.
func _charger(r: RobotController) -> bool:
	var pred := _predict_impact(r)
	if pred.is_empty():
		return false
	var tau: float = pred.t
	var n: Vector2 = pred.normal
	var target := atan2(n.x, -n.y) + deg_to_rad(lean)
	var w1 := r.rotation_ctl.auto_rps() * TAU
	var w2 := -r.config.counterclockwise_rotation_speed * TAU
	var rr := r.config.rotation_response
	var theta := r.global_rotation
	var w0 := r.angular_velocity
	var best_h := -1.0
	var fallback_h := 0.0
	var best_err := INF
	var h := 0.0
	while h <= tau + 0.0001:
		var t1 := tau - h
		var e1 := exp(-rr * t1)
		var th1 := theta + w1 * t1 + (w0 - w1) * (1.0 - e1) / rr
		var wr := w1 + (w0 - w1) * e1
		var th2 := th1 + w2 * h + (wr - w2) * (1.0 - exp(-rr * h)) / rr
		var err := absf(wrapf(th2 - target, -PI, PI))
		if err < 0.14 and best_h < 0.0:
			best_h = h
		if err < best_err:
			best_err = err
			fallback_h = h
		h += 0.01
	if best_h < 0.0:
		best_h = fallback_h
	return best_h > 0.005 and best_h >= tau - 0.02

func _predict_impact(r: RobotController) -> Dictionary:
	var p := r.global_position
	var v := r.linear_velocity
	var g := 1800.0
	var dt := 1.0 / 60.0
	var t := 0.0
	var reach := 150.0
	while t < 2.5:
		var gy := gm.terrain.height_at(p.x)
		if p.y + reach >= gy:
			return {"t": t, "normal": gm.terrain.normal_at(p.x), "x": p.x}
		v.y += g * dt
		p += v * dt
		t += dt
	return {}


## Touch on a UI button must not register as a hold.
func _ui_block_check() -> void:
	var btn: Button = null
	for b in gm.ui._buttons:
		if b.is_visible_in_tree():
			btn = b
			break
	if btn == null:
		print("AT|uiblock no visible button")
		return
	var t := InputEventScreenTouch.new()
	t.index = 3
	t.pressed = true
	t.position = btn.get_global_rect().get_center()
	var before := gm.input.holding
	gm.input._unhandled_input(t)
	print("AT|uiblock button=%s holding_before=%s holding_after=%s" % [btn.text, before, gm.input.holding])
	t.pressed = false
	gm.input._unhandled_input(t)


## Fixtures acknowledge the same production cards as a player.
func start_seen_run() -> void:
	gm.start_run()
	if gm.ui.awareness.visible: gm.ui.awareness.confirm.pressed.emit()

func begin_seen_tutorial(destination: StringName) -> void:
	gm.begin_tutorial(destination)
	gm.ui.awareness.confirm.pressed.emit()
