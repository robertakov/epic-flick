extends Node
## Debug-only stability / stress tests (not exported).
##   --scenario=stress   20 rapid retries, 20 full attempts (bot), stats panel x20, menu<->game x20,
##                       focus loss / app pause while holding, multitouch, Back button, memory trend
##   --scenario=layout   (windowed) UI at 16:9 / 18:9 / 19.5:9 / 20:9 / 21:9 + simulated display cutout
## Every check fails when its data is missing (no silent passes). Prints "AT|test <name> PASS|FAIL ...".

var gm: GameManager
var at: Node
var passed := 0
var failed := 0
var _rng := RandomNumberGenerator.new()
var _quit_called := 0


func run_all(which: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	at.process_mode = Node.PROCESS_MODE_PAUSABLE
	at.set("scenario_running", true)
	_rng.seed = 77
	gm.quit_handler = func() -> void: _quit_called += 1
	at.set("max_time", 1.0e9)   # the bot's per-run timeout must not cut multi-attempt scenarios
	await _frames(20)
	if which == "stress":
		# This suite exercises returning-player controls; onboarding has its own fresh-profile suite.
		gm.profile.tutorial.handled=true
		await _input_lifecycle_tests()
		await _restart_button_tests()
		await _settings_ui_tests()
		await _stats_panel_cycles()
		await _menu_game_cycles()
		await _rapid_retries()
		await _full_attempts()
	elif which == "settings_set":
		gm.set_setting("auto_rps", 1.85)
		gm.set_setting("manual_rps", 0.4)
		gm.set_setting("invuln_s", 1.25)
		print("AT|settings_saved %s" % [gm.settings.values])
	elif which == "settings_print":
		print("AT|settings_loaded status=%s values=%s cw=%.2f ccw=%.2f robot_invuln=%.2f sliders=%.2f/%.2f/%.2f" % [gm.settings.last_load_status,
			gm.settings.values, gm.robot_config.clockwise_rotation_speed, gm.robot_config.counterclockwise_rotation_speed,
			gm.robot.damage.invulnerability_time, gm.ui._sliders.shake.value, gm.ui._sliders.vibration.value, 0.0])
	elif which == "layout":
		await _layout_tests()
	elif which == "track_probe":
		for sd in [80190, 32676]:
			var g := _geometry(sd, 100000.0)
			for i in g.points.size() - 1:
				var d := g.points[i + 1] - g.points[i]
				var deg := rad_to_deg(atan2(d.y, d.x))
				if g.points[i].x > 760.0 and deg > 60.0:
					var sec := g.section_at(g.points[i].x)
					var near := []
					for k in g._ctrl.size() - 1:
						if absf(g._ctrl[k].x - g.points[i].x) < 400.0:
							near.append("%.0f:%.0f" % [g._ctrl[k].x, rad_to_deg((g._ctrl[k + 1] - g._ctrl[k]).angle())])
					print("AT|steep seed=%d x=%.0f deg=%.1f section=%s x0=%.0f ctrl(x:angle)=%s" % [sd, g.points[i].x, deg, sec.name, sec.x0, near])
			g.queue_free()
	elif which == "track":
		await _track_tests()
	elif which == "recycle":
		gm.terrain.reset(99)
		var counts := []
		for x in [0.0, 30000.0, 60000.0, 120000.0, 240000.0]:
			gm.terrain.ensure_ahead(x, x)
			await _frames(2)
			counts.append(gm.terrain._chunks.size())
		var first: float = gm.terrain._chunks[0][0]
		_check("terrain_chunks_recycled", counts.max() <= int((TerrainBuilder.AHEAD + TerrainBuilder.BEHIND) / TerrainBuilder.CHUNK) + 8 and first < 0.0,
			"live chunks at lead 0/30k/60k/120k/240k px = %s, ledge chunk kept=%s" % [counts, first < 0.0])
	elif which == "terrain_view":
		gm.ui.menu.visible = false
		gm.terrain.ensure_ahead(30000.0)
		var k := 0
		for s: Dictionary in gm.terrain.sections.slice(1, 10):
			var nxt: float = s.x0 + 1400.0
			gm.camera.snap_intro(Vector2(nxt, gm.terrain.height_at(nxt) - 150.0), 0.42)
			await _frames(8)
			_shot("tv_%02d_%s_p%d" % [k, s.name, s.palette])
			k += 1
		# a palette boundary close up (blend)
		for s: Dictionary in gm.terrain.sections.slice(2, 5):
			gm.camera.snap_intro(Vector2(s.x0, gm.terrain.height_at(s.x0) - 100.0), 0.5)
			await _frames(8)
			_shot("tv_seam_%s" % s.name)
	elif which == "fontmem":
		await _font_memory_probe()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


func _check(name: String, ok: bool, details: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("AT|test %s %s %s" % [name, "PASS" if ok else "FAIL", details])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(s: float) -> void:
	await _frames(int(s * 120.0))


# ---------------- input helpers (real events) ----------------

func _touch(index: int, pressed: bool, pos := Vector2.ZERO) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.pressed = pressed
	t.position = pos if pos != Vector2.ZERO else get_viewport().get_visible_rect().size * Vector2(0.6, 0.55)
	Input.parse_input_event(t)
	await get_tree().process_frame
	await get_tree().process_frame


func _press(text: String, kind: String) -> bool:
	# v0.10: the menu's play button is "СВОБОДНЫЙ ЗАБЕГ" (next to "КАМПАНИЯ")
	if text == "ИГРАТЬ" and gm.ui.menu.visible:
		text = "СВОБОДНЫЙ ЗАБЕГ"
	for b: Button in gm.ui._buttons:
		if b.text == text and b.is_visible_in_tree():
			var pos := b.get_global_rect().get_center()
			for pressed in [true, false]:
				if kind == "touch":
					var t := InputEventScreenTouch.new()
					t.index = 0
					t.pressed = pressed
					t.position = pos
					Input.parse_input_event(t)
				else:
					var mb := InputEventMouseButton.new()
					mb.button_index = MOUSE_BUTTON_LEFT
					mb.pressed = pressed
					mb.position = pos
					mb.global_position = pos
					Input.parse_input_event(mb)
				await get_tree().process_frame
				await get_tree().process_frame
			# v0.9: menu ИГРАТЬ opens the robot selection; its ИГРАТЬ starts the run
			if (text == "ИГРАТЬ" or text == "СВОБОДНЫЙ ЗАБЕГ") and gm.ui.is_robot_select_open():
				return await _press("ИГРАТЬ", kind)
			return true
	return false


func _key_retry() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_R
	k.keycode = KEY_R
	k.pressed = true
	Input.parse_input_event(k)
	await get_tree().process_frame
	k = k.duplicate()
	k.pressed = false
	Input.parse_input_event(k)
	await get_tree().process_frame


func _notify(what: int) -> void:
	# v36.9: GameManager ignores a 2nd Back within 350 ms (Android 16 double delivery); each call here is a
	# separate physical press
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		gm._last_back_ms = -100000
	get_tree().root.propagate_notification(what)
	await get_tree().process_frame


func _metrics() -> Dictionary:
	var particles := 0
	var bodies := 0
	for n in get_tree().root.find_children("*", "CPUParticles2D", true, false):
		if (n as CPUParticles2D).emitting:
			particles += 1
	for n in gm.dynamic.find_children("*", "RigidBody2D", true, false):
		bodies += 1
	var terrain_nodes := gm.terrain.find_children("*", "", true, false).size() + 1
	return {
		"nodes": get_tree().get_node_count() - terrain_nodes,   # without the streamed terrain
		"terrain_nodes": terrain_nodes,
		"chunks": gm.terrain._chunks.size(),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01),
		"dynamic": gm.dynamic.get_child_count(),
		"fx": gm.fx.get_child_count(),
		"bodies": bodies,
		"particles": particles,
	}


# ---------------- input lifecycle ----------------

func _start_from_menu() -> void:
	if gm.state != GameManager.State.MENU:
		gm.go_menu()
		await _frames(2)
	await _press("ИГРАТЬ", "touch")


func _wait_state(s: int, max_s: float) -> bool:
	var t := 0.0
	while gm.state != s and t < max_s:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	return gm.state == s


func _input_lifecycle_tests() -> void:
	await _start_from_menu()
	gm.hand.rush()
	var launched := await _wait_state(GameManager.State.RUN, 6.0)
	_check("launch_reached", launched, "state=%d" % gm.state)
	if not launched:
		return
	# touch -> counter-clockwise target, release -> clockwise
	await _touch(0, true)
	var held := gm.input.holding and gm.robot.rotation_ctl.target_angular_velocity() < 0.0
	await _frames(20)
	var w_held := gm.robot.angular_velocity
	await _touch(0, false)
	await _frames(20)
	var released := not gm.input.holding and gm.robot.rotation_ctl.target_angular_velocity() > 0.0
	_check("touch_hold_release", held and released and w_held < 0.0, "held=%s w_while_held=%.1f released=%s" % [held, w_held, released])
	# multitouch: holding while ANY finger is down, no flicker between fingers
	var seq := []
	await _touch(0, true); seq.append(gm.input.holding)
	await _touch(1, true); seq.append(gm.input.holding)
	await _touch(0, false); seq.append(gm.input.holding)
	await _touch(2, true); seq.append(gm.input.holding)
	await _touch(1, false); seq.append(gm.input.holding)
	await _touch(2, false); seq.append(gm.input.holding)
	_check("multitouch_consistent", seq == [true, true, true, true, true, false], "holding sequence=%s" % [seq])
	# focus lost while holding: hold is dropped, a late release is harmless, new touches work
	await _touch(0, true)
	var before := gm.input.holding
	await _notify(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var after_focus := gm.input.holding
	await _touch(0, false)
	await _notify(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _touch(0, true)
	var again := gm.input.holding
	await _touch(0, false)
	_check("focus_loss_resets_hold", before and not after_focus and again and not gm.input.holding,
		"before=%s after_focus_out=%s new_touch=%s" % [before, after_focus, again])
	# app sent to background (Android onPause) while holding: frozen + released; resumes cleanly
	await _touch(0, true)
	await _notify(NOTIFICATION_APPLICATION_PAUSED)
	var paused := get_tree().paused
	var pos0 := gm.robot.global_position
	await _frames(30)
	var frozen := gm.robot.global_position.distance_to(pos0) < 0.01
	var hold_paused := gm.input.holding
	await _notify(NOTIFICATION_APPLICATION_RESUMED)
	await _frames(10)
	var moving := gm.robot.global_position.distance_to(pos0) > 1.0
	_check("app_pause_resume", paused and frozen and not hold_paused and not get_tree().paused and moving,
		"paused=%s frozen=%s hold_after_pause=%s resumed_moving=%s" % [paused, frozen, hold_paused, moving])
	await _touch(0, false)
	# Back during a run -> menu; Back in the stats panel -> closes it; Back in the menu -> quit handler
	await _notify(NOTIFICATION_WM_GO_BACK_REQUEST)
	var to_menu := gm.state == GameManager.State.MENU
	await _press("СТАТИСТИКА", "mouse")
	var open := gm.ui.is_stats_open()
	await _notify(NOTIFICATION_WM_GO_BACK_REQUEST)
	var closed := not gm.ui.is_stats_open() and gm.state == GameManager.State.MENU
	await _notify(NOTIFICATION_WM_GO_BACK_REQUEST)
	_check("back_button", to_menu and open and closed and _quit_called == 1,
		"run->menu=%s stats_open=%s back_closed=%s quit_calls=%d" % [to_menu, open, closed, _quit_called])
	# touches on menu buttons never reach the game input
	await _touch(0, true, gm.ui._buttons[0].get_global_rect().get_center())
	var blocked := not gm.input.holding
	await _touch(0, false, gm.ui._buttons[0].get_global_rect().get_center())
	_check("ui_touch_not_game_input", blocked, "holding_after_menu_touch=%s" % (not blocked))


func _stats_panel_cycles() -> void:
	if gm.state != GameManager.State.MENU:
		gm.go_menu()
	var ok := 0
	for i in 20:
		await _press("СТАТИСТИКА", "touch" if i % 2 == 0 else "mouse")
		var opened := gm.ui.is_stats_open()
		match i % 3:
			0:
				await _press("ЗАКРЫТЬ", "mouse" if i % 2 == 0 else "touch")
			1:
				await _notify(NOTIFICATION_WM_GO_BACK_REQUEST)
			2:
				# tap outside the panel (top-left corner of the shade)
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT
				mb.position = Vector2(20, 20)
				mb.global_position = mb.position
				mb.pressed = true
				Input.parse_input_event(mb)
				await get_tree().process_frame
				mb = mb.duplicate()
				mb.pressed = false
				Input.parse_input_event(mb)
				await get_tree().process_frame
		if opened and not gm.ui.is_stats_open() and gm.state == GameManager.State.MENU:
			ok += 1
	# input still works afterwards
	await _press("ИГРАТЬ", "touch")
	var started := gm.state == GameManager.State.INTRO
	_check("stats_panel_20_cycles", ok == 20 and started, "ok_cycles=%d/20 play_after=%s quit_calls=%d" % [ok, started, _quit_called])


func _menu_game_cycles() -> void:
	var ok := 0
	var details := []
	for i in 20:
		if gm.state != GameManager.State.MENU:
			gm.go_menu()
			await _frames(2)
		await _press("ИГРАТЬ", "mouse" if i % 2 == 0 else "touch")
		var in_game := gm.state == GameManager.State.INTRO
		gm.hand.rush()
		await _secs(_rng.randf_range(0.3, 2.5))
		if i % 2 == 0:
			await _notify(NOTIFICATION_WM_GO_BACK_REQUEST)
		else:
			gm.go_menu()
		await _frames(3)
		var good := in_game and gm.state == GameManager.State.MENU and not get_tree().paused and gm.dynamic.get_child_count() <= 2
		if good:
			ok += 1
		else:
			details.append("#%d in_game=%s state=%d dyn=%d" % [i, in_game, gm.state, gm.dynamic.get_child_count()])
	await _frames(5)
	_check("menu_game_20_cycles", ok == 20 and gm.dynamic.get_child_count() == 1, "ok=%d/20 dynamic_now=%d %s" % [ok, gm.dynamic.get_child_count(), details])


# ---------------- retries and full attempts ----------------

func _rapid_retries() -> void:
	gm.go_menu()
	await _frames(3)
	await _press("ИГРАТЬ", "touch")
	await _secs(1.0)
	var base := _metrics()
	var bad := []
	for i in 20:
		gm.hand.rush()
		await _secs(_rng.randf_range(0.3, 3.0))
		if gm.state == GameManager.State.RESULT:
			await _press("ЕЩЁ РАЗ!", "touch")
		elif i % 2 == 0:
			await _press("↻ ЗАНОВО", "touch")
		else:
			await _key_retry()
		await _frames(4)
		# a fresh attempt: full HP, all modules, empty counters, nothing left from the previous one
		var ui_ok := gm.ui._hp_value == gm.robot.damage.max_health and gm.ui.module_icons.values().all(func(h: Control) -> bool: return h.modulate == Color.WHITE)
		if not (gm.state == GameManager.State.INTRO and gm.attempt.landings == 0 and gm.robot.damage.health == gm.robot.damage.max_health
				and gm.robot.spin_charge.charge == 0.0 and gm.robot.damage.invulnerable_left == 0.0
				and gm.dynamic.get_child_count() == 1 and ui_ok):
			bad.append("#%d state=%d dyn=%d hp=%.0f ui_ok=%s" % [i, gm.state, gm.dynamic.get_child_count(), gm.robot.damage.health, ui_ok])
	await _secs(1.0)
	var end := _metrics()
	_check("rapid_retry_20", bad.is_empty() and end.orphans == 0 and end.nodes - base.nodes <= 40,
		"bad=%s nodes %d->%d orphans=%d dynamic=%d mem %.1f->%.1f MB" % [bad, base.nodes, end.nodes, end.orphans, end.dynamic, base.mem_mb, end.mem_mb])


func _full_attempts() -> void:
	var store := gm.stats
	var leans := [12.0, 18.0, 24.0, 30.0, -10.0, 40.0]
	var bots := ["charger", "smart", "random", "charger", "cw"]
	var rows := []
	var bad := []
	var peak := {"bodies": 0, "particles": 0, "fx": 0}
	var samples := []
	if gm.state != GameManager.State.MENU:
		gm.go_menu()
		await _frames(3)
	await _press("ИГРАТЬ", "touch")
	for i in 20:
		var att_before := int(store.data.attempts)
		at.set("bot", bots[i % bots.size()])
		at.set("lean", leans[i % leans.size()])
		at.set("scenario_running", false)
		gm.hand.rush()
		var t := 0.0
		var diag := {"run_at": -1.0, "v1": -1.0, "freeze": false, "paused": get_tree().paused, "hold": gm.input.holding, "start_state": gm.state, "reason": ""}
		while gm.state != GameManager.State.RESULT and t < 120.0:
			await get_tree().physics_frame
			t += 1.0 / 120.0
			if gm.state == GameManager.State.RUN and diag.run_at < 0.0:
				diag.run_at = t
			if diag.run_at >= 0.0 and diag.v1 < 0.0 and t > diag.run_at + 0.5 and is_instance_valid(gm.robot):
				diag.v1 = gm.robot.linear_velocity.length()
				diag.freeze = gm.robot.freeze
			if int(t * 120.0) % 30 == 0:
				var m := _metrics()
				for k in peak:
					peak[k] = maxi(peak[k], m[k])
		at.set("scenario_running", true)
		gm.input.set_virtual_hold(false)
		if gm.state != GameManager.State.RESULT:
			bad.append("#%d did not finish (timeout)" % i)
			gm._finish("test timeout")
		await _secs(1.5)
		var m2 := _metrics()
		samples.append(m2)
		var d := gm.distance_m
		diag.reason = gm._end_reason
		if d < 1.0:
			bad.append("#%d zero distance diag=%s" % [i, diag])
		var saved_once := int(store.data.attempts) == att_before + 1
		rows.append("%d:%s/%.0f=%dm" % [i, bots[i % bots.size()], leans[i % leans.size()], int(d)])
		if not saved_once or d < 0.0 or store.data.recent.size() > 10 or store.best_m() < d - 0.001:
			bad.append("#%d saved_once=%s d=%.1f recent=%d best=%.1f" % [i, saved_once, d, store.data.recent.size(), store.best_m()])
		if i < 19:
			await _press("ЕЩЁ РАЗ!", "mouse" if i % 2 == 0 else "touch")
	# memory / object trend after warm-up (attempt 5 vs attempt 20, both on the result screen)
	var a: Dictionary = samples[4]
	var b: Dictionary = samples[19]
	var reloaded := StatsStore.new(store.path)
	reloaded.load_data()
	var persist_ok := reloaded.last_load_status == "ok" and int(reloaded.data.attempts) == int(store.data.attempts) \
		and is_equal_approx(reloaded.best_m(), store.best_m())
	_check("full_attempts_20", bad.is_empty() and samples.size() == 20 and persist_ok,
		"bad=%s attempts_saved=%d best=%.1f reload_ok=%s results=%s" % [bad, store.data.attempts, store.best_m(), persist_ok, " ".join(rows)])
	var played: bool = rows.size() == 20 and int(store.data.attempts) >= 20 and peak.bodies >= 2
	# streamed terrain: live chunks must stay bounded by the ahead/behind window (no growth with play)
	var max_chunks := int((TerrainBuilder.AHEAD + TerrainBuilder.BEHIND) / TerrainBuilder.CHUNK) + 8
	played = played and samples.all(func(m: Dictionary) -> bool: return m.chunks <= max_chunks)
	_check("memory_trend_20_attempts", played and b.nodes - a.nodes <= 40 and b.orphans == 0 and b.mem_mb - a.mem_mb < 4.0 and b.dynamic <= 6,
		"#5 %s | #20 %s | peak during play %s | max live chunks %d (bound %d)" % [a, b, peak, samples.map(func(m: Dictionary) -> int: return m.chunks).max(), max_chunks])


# ---------------- layout ----------------

const SIZES := [[Vector2i(1280, 720), "16:9"], [Vector2i(1440, 720), "18:9"], [Vector2i(1560, 720), "19.5:9"],
	[Vector2i(1600, 720), "20:9"], [Vector2i(1680, 720), "21:9"]]


func _rect(c: Control) -> Rect2:
	return c.get_global_rect()


## Checks a set of controls: inside the viewport (minus margins), no overlap between them, buttons big enough,
## labels not wider than their box.
func _layout_check(tag: String, ctrls: Dictionary, margin: Vector4) -> Array:
	var vp := get_viewport().get_visible_rect().size
	var inner := Rect2(Vector2(margin.x, margin.y), vp - Vector2(margin.x + margin.z, margin.y + margin.w))
	var errs := []
	var names := ctrls.keys()
	for n in names:
		var c: Control = ctrls[n]
		if not c.is_visible_in_tree():
			errs.append("%s:%s invisible" % [tag, n])
			continue
		var r := _rect(c)
		if not inner.grow(1.0).encloses(r):
			errs.append("%s:%s out of screen %s" % [tag, n, r])
		if c is Button and (r.size.x < 88.0 or r.size.y < 72.0):
			errs.append("%s:%s button too small %s" % [tag, n, r.size])
		if c is Label and c.get_minimum_size().x > r.size.x + 1.0:
			errs.append("%s:%s text clipped" % [tag, n])
	for i in names.size():
		for j in range(i + 1, names.size()):
			var r1 := _rect(ctrls[names[i]])
			var r2 := _rect(ctrls[names[j]])
			if r1.grow(-2.0).intersects(r2.grow(-2.0)):
				errs.append("%s:%s overlaps %s" % [tag, names[i], names[j]])
	return errs


func _button(text: String) -> Button:
	# several screens share captions (e.g. "ЕЩЁ РАЗ!" on Free Run and campaign results): prefer the visible one
	var first: Button = null
	for b: Button in gm.ui._buttons:
		if b.text == text:
			if b.is_visible_in_tree():
				return b
			if first == null:
				first = b
	return first


func _layout_tests() -> void:
	var ui := gm.ui
	for entry in SIZES:
		var size: Vector2i = entry[0]
		var tag: String = entry[1]
		for cut in [false, true]:
			DisplayServer.window_set_size(size)
			ui.debug_safe_margins = Vector4(90, 0, 34, 0) if cut else Vector4(-1, -1, -1, -1)
			ui.apply_safe_area()
			await _frames(6)
			var vp := get_viewport().get_visible_rect().size
			var margin := ui.safe_margins
			var errs := []
			var name := "%s%s" % [tag.replace(":", "x"), "_cutout" if cut else ""]
			# menu
			gm.go_menu()
			await _frames(4)
			errs += _layout_check("menu", {"title": ui.best_label_menu, "play": _button("СВОБОДНЫЙ ЗАБЕГ"), "campaign": _button("КАМПАНИЯ"), "stats": _button("СТАТИСТИКА"), "settings": _button("НАСТРОЙКИ")}, margin)
			_shot(name + "_menu")
			# statistics panel
			ui.open_stats()
			await _frames(12)
			errs += _layout_check("stats", {"close": _button("ЗАКРЫТЬ"), "totals": ui._stats_totals, "recent": ui._stats_recent}, Vector4.ZERO)
			_shot(name + "_stats")
			ui.close_stats()
			ui.open_settings()
			await _frames(30)
			# both tabs: every visible slider on screen and touch-sized
			for page in 2:
				ui.show_settings_page(page)
				await _frames(6)
				var sl := {"defaults": _button("ПО УМОЛЧАНИЮ"), "done": _button("ГОТОВО")}
				for k in ui._sliders:
					if ui._sliders[k].is_visible_in_tree():
						sl[k] = ui._sliders[k]
						if ui._sliders[k].size.y < 56.0:
							errs.append("settings: slider %s too thin for touch" % k)
				errs += _layout_check("settings%d" % page, sl, Vector4.ZERO)
				_shot(name + "_settings%d" % page)
			ui.show_settings_page(0)
			ui.close_settings()
			# HUD during a run (inset by the safe area)
			at.call("start_seen_run")
			gm.hand.rush()
			await _secs(2.5)
			errs += _layout_check("hud", {"distance": ui.distance_label, "hp": ui.health_bar, "charge": ui.charge_bar,
				"modules": ui.module_icons[&"leg_r"].get_parent(), "spin": ui.spin_icon, "restart": ui.restart_button}, margin)
			_shot(name + "_hud")
			# results
			gm._finish("layout test")
			await _secs(1.8)
			errs += _layout_check("results", {"retry": _button("ЕЩЁ РАЗ!"), "menu": _button("МЕНЮ")}, Vector4.ZERO)
			errs += _layout_check("results_panel", {"panel": ui._res_panel}, Vector4.ZERO)
			var pr := _rect(ui._res_panel)
			for lbl in [ui.result_distance, ui.result_best, ui.result_reason, _button("ЕЩЁ РАЗ!"), _button("МЕНЮ")]:
				if not pr.encloses(_rect(lbl)):
					errs.append("results: label outside panel")
			_shot(name + "_results")
			_check("layout_" + name, errs.is_empty() and vp.y == 720.0,
				"viewport=%s margins=%s errors=%s" % [vp, margin, errs])
	ui.debug_safe_margins = Vector4(-1, -1, -1, -1)
	ui.apply_safe_area()


func _shot(n: String) -> void:
	if at.get("shots_dir") != "":
		at.call("_shot", n)


## Diagnostic: memory cost of popup words at many different font sizes (glyph cache per size).
func _font_memory_probe() -> void:
	var p := gm.camera.get_screen_center_position()
	var m0 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	for rep in 3:
		for s in [44, 58, 76, 64, 50, 46, 54]:
			gm.fx.word(p, "CRASH! BOING! ZOOM! -15", Color.WHITE, s)
		await _secs(1.2)
	var m1 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	for s in range(40, 130, 1):
		gm.fx.word(p, "CRASH! BOING! ZOOM! -15 СУПЕР-БОИНГ!", Color.WHITE, s)
		if s % 10 == 0:
			await _frames(2)
	await _secs(1.5)
	var m2 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("AT|fontmem fixed_sizes_x3=%.1fMB  then_90_distinct_sizes=+%.1fMB (start %.1f)" % [m1 - m0, m2 - m1, m0])

# ---------------- instant restart button ----------------

func _snapshot() -> Dictionary:
	return {"id": gm.attempt.id if gm.attempt else "", "saved": int(gm.stats.data.attempts), "best": gm.stats.best_m()}


## A restart must leave exactly one fresh robot and a clean attempt, record nothing, keep records / settings.
func _fresh_after_restart(before: Dictionary, tag: String) -> String:
	await _frames(3)
	var r := gm.robot
	var errs := []
	if gm.state != GameManager.State.INTRO: errs.append("state=%d" % gm.state)
	if gm.attempt.id == before.id: errs.append("same attempt id")
	if int(gm.stats.data.attempts) != before.saved: errs.append("attempt recorded")
	if gm.stats.best_m() != before.best: errs.append("best changed")
	if gm.dynamic.get_child_count() != 1: errs.append("dynamic=%d" % gm.dynamic.get_child_count())
	if r.damage.health != r.damage.max_health or r.damage.limbs_remaining.size() != 4: errs.append("hp/limbs not reset")
	if r.spin_charge.charge != 0.0 or r.damage.invulnerable_left != 0.0 or r.damage.armed: errs.append("charge/invuln not reset")
	if gm.attempt.landings != 0 or gm.attempt.duration_s > 0.05: errs.append("attempt counters")
	if gm.ui._hp_value != r.damage.max_health or gm.ui._charge != 0.0: errs.append("hud not reset")
	if gm.camera.mode != &"intro": errs.append("camera mode %s" % gm.camera.mode)
	if gm.input.holding: errs.append("input holding")
	if get_tree().paused: errs.append("paused")
	return "" if errs.is_empty() else "%s: %s" % [tag, errs]


func _restart_button_tests() -> void:
	gm.go_menu()
	await _frames(3)
	await _press("ИГРАТЬ", "touch")
	var problems := []
	var phases := []
	# 1) during the intro
	var b := _snapshot()
	await _secs(0.4)
	await _press("↻ ЗАНОВО", "touch")
	phases.append("intro")
	var e := await _fresh_after_restart(b, "intro")
	if e != "": problems.append(e)
	# 2) in the air, 3) touching the ground, 4) during the jet head
	at.set("bot", "cw")
	for phase in ["air", "ground", "rocket"]:
		gm.hand.rush()
		at.set("scenario_running", false)
		var t := 0.0
		var reached := false
		while t < 40.0 and not reached:
			await get_tree().physics_frame
			t += 1.0 / 120.0
			if gm.state == GameManager.State.RESULT:
				break
			match phase:
				"air":
					reached = gm.state == GameManager.State.RUN and t > 0.5 and not gm.robot.contacts.any_contact
				"ground":
					reached = gm.state == GameManager.State.RUN and gm.robot.contacts.any_contact and gm.robot.damage.armed
				"rocket":
					reached = gm.state == GameManager.State.ROCKET
		at.set("scenario_running", true)
		gm.input.set_virtual_hold(false)
		if not reached:
			problems.append("%s: phase not reached (state=%d)" % [phase, gm.state])
			if gm.state == GameManager.State.RESULT:
				await _press("ЕЩЁ РАЗ!", "mouse")
			continue
		b = _snapshot()
		await _press("↻ ЗАНОВО", "mouse" if phase == "ground" else "touch")
		phases.append(phase)
		e = await _fresh_after_restart(b, phase)
		if e != "": problems.append(e)
	_check("restart_in_every_phase", problems.is_empty() and phases.size() == 4, "phases=%s problems=%s" % [phases, problems])
	# double taps: several presses within the debounce window -> exactly one new attempt
	await _secs(0.4)
	var id0 := gm.attempt.id
	var ids := {}
	gm.ui.restart_pressed.emit()
	ids[gm.attempt.id] = true
	gm.ui.restart_pressed.emit()
	ids[gm.attempt.id] = true
	await _press("↻ ЗАНОВО", "touch")
	ids[gm.attempt.id] = true
	await _frames(3)
	_check("restart_double_tap_once", ids.size() == 1 and not ids.has(id0) and gm.dynamic.get_child_count() == 1,
		"distinct new attempts=%d robots=%d" % [ids.size(), gm.dynamic.get_child_count()])
	# touching the button never starts the counter-clockwise spin
	await _secs(0.4)
	var rb := gm.ui.restart_button.get_global_rect().get_center()
	await _touch(0, true, rb)
	var held := gm.input.holding
	await _touch(0, false, rb)
	_check("restart_touch_not_game_input", not held, "holding while touching the button=%s" % held)
	# competitive mode: hidden and refused
	gm.allow_instant_restart = false
	gm.ui.restart_enabled = false
	at.call("start_seen_run")
	await _frames(3)
	var id1 := gm.attempt.id
	await _secs(0.4)
	var refused := not gm.restart_attempt()
	var hidden := not gm.ui.restart_button.visible
	gm.allow_instant_restart = true
	gm.ui.restart_enabled = true
	_check("restart_disabled_mode", refused and hidden and gm.attempt.id == id1, "refused=%s hidden=%s" % [refused, hidden])
	gm.go_menu()


# ---------------- settings screen ----------------

func _settings_ui_tests() -> void:
	gm.go_menu()
	await _frames(3)
	gm.reset_settings()
	await _press("НАСТРОЙКИ", "touch")
	var opened := gm.ui.is_settings_open()
	await _frames(30)
	# v34 (legit update): physics sliders were removed; touch drives Shake, mouse drives Vibration
	var s1: HSlider = gm.ui._sliders.shake
	var r1 := s1.get_global_rect()
	await _touch(0, true, r1.position + Vector2(r1.size.x * 0.1, r1.size.y * 0.5))
	await _touch(0, false, r1.position + Vector2(r1.size.x * 0.1, r1.size.y * 0.5))
	var s2: HSlider = gm.ui._sliders.vibration
	var r2 := s2.get_global_rect()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = r2.position + Vector2(r2.size.x * 0.1, r2.size.y * 0.5)
	mb.global_position = mb.position
	mb.pressed = true
	Input.parse_input_event(mb)
	await _frames(2)
	mb = mb.duplicate()
	mb.pressed = false
	Input.parse_input_event(mb)
	await _frames(2)
	var shake := gm.settings.get_value("shake")
	var vib := gm.settings.get_value("vibration")
	var f := SettingsStore.new(gm.settings.path)
	f.load_data()
	var applied := is_equal_approx(gm.camera.shake_scale, shake / 100.0) and is_equal_approx(gm.haptics.vibration_scale, vib / 100.0)
	var not_held := not gm.input.holding
	_check("settings_sliders_touch_mouse", opened and shake < 30.0 and vib < 30.0 and applied and f.get_value("shake") == shake
		and f.get_value("vibration") == vib and not_held and not gm.ui._sliders.has("auto_rps"),
		"shake=%.0f vib=%.0f applied=%s" % [shake, vib, applied])
	# defaults button: presentation defaults back, release physics untouched (fixed)
	await _press(L.t("UI_DEFAULTS"), "touch")
	var d := gm.settings.values
	var defaults_ok: bool = is_equal_approx(d.shake, 90.0) and is_equal_approx(d.vibration, 100.0) and gm.ui._sliders.shake.value == 90.0
	for k in SettingsStore.FIXED:
		defaults_ok = defaults_ok and is_equal_approx(float(d[k]), float(SettingsStore.FIXED[k]))
	defaults_ok = defaults_ok and is_equal_approx(gm.robot_config.clockwise_rotation_speed, 0.9)
	_check("settings_defaults_button", defaults_ok, "values=%s" % [d])
	# Back closes, tap outside closes, play works afterwards
	await _notify(NOTIFICATION_WM_GO_BACK_REQUEST)
	var back_closed := not gm.ui.is_settings_open() and gm.state == GameManager.State.MENU
	await _press("НАСТРОЙКИ", "mouse")
	var mo := InputEventMouseButton.new()
	mo.button_index = MOUSE_BUTTON_LEFT
	mo.position = Vector2(16, 16)
	mo.global_position = mo.position
	mo.pressed = true
	Input.parse_input_event(mo)
	await _frames(2)
	mo = mo.duplicate()
	mo.pressed = false
	Input.parse_input_event(mo)
	await _frames(2)
	var outside_closed := not gm.ui.is_settings_open()
	await _press("ИГРАТЬ", "touch")
	_check("settings_close_and_play", back_closed and outside_closed and gm.state == GameManager.State.INTRO and _quit_called <= 1,
		"back=%s outside=%s state=%d" % [back_closed, outside_closed, gm.state])
	# invulnerability setting reaches the robot immediately
	gm.set_setting("invuln_s", 1.3)
	var inv_ok := is_equal_approx(gm.robot.damage.invulnerability_time, 1.3)
	gm.reset_settings()
	_check("settings_invuln_applied", inv_ok and is_equal_approx(gm.robot.damage.invulnerability_time, 0.5), "")
	gm.go_menu()

# ---------------- track templates (v0.8) ----------------

func _geometry(seed: int, until_x: float) -> TerrainBuilder:
	var tb := TerrainBuilder.new()
	tb.build_nodes = false
	add_child(tb)
	tb.build(gm.level_config, seed)
	tb.ensure_ahead(until_x)
	return tb


func _names(tb: TerrainBuilder) -> PackedStringArray:
	var out := PackedStringArray()
	for s in tb.sections:
		out.append(s.name)
	return out


func _track_tests() -> void:
	# determinism: same seed -> identical points and sections; other seed -> different
	var a := _geometry(4242, 60000.0)
	var b := _geometry(4242, 60000.0)
	var c := _geometry(4243, 60000.0)
	var n := mini(a.points.size(), b.points.size())
	var same := a.points.size() == b.points.size() and _names(a) == _names(b)
	for i in n:
		if a.points[i] != b.points[i]:
			same = false
			break
	var differ := _names(a) != _names(c) or a.points[min(400, a.points.size() - 1)] != c.points[min(400, c.points.size() - 1)]
	_check("track_seed_deterministic", same and differ, "points=%d same_seed_identical=%s other_seed_differs=%s" % [a.points.size(), same, differ])
	for t in [a, b, c]:
		t.queue_free()
	# 20 seeds x 100 km: shape limits, all templates, no repeats, same overall descent
	var bad := []
	var slopes := []
	var t_max := 0.0
	for k in 20:
		var seed := 1000 + k * 7919
		var t0 := Time.get_ticks_usec()
		var g := _geometry(seed, 100000.0)
		t_max = maxf(t_max, (Time.get_ticks_usec() - t0) / 1000.0)
		var used := {}
		var rep := 0
		var prev := ""
		for s in g.sections:
			if s.name == "start":
				continue
			used[s.name] = true
			if s.name == prev:
				rep += 1
			prev = s.name
		var steep := 0
		var up := 0
		var gap := 0.0
		var turn := 0.0
		var pd := 0.0
		for i in g.points.size() - 1:
			var d := g.points[i + 1] - g.points[i]
			gap = maxf(gap, d.length())
			if g.points[i].x <= 760.0 or d.x <= 0.0:
				if d.x <= 0.0:
					bad.append("seed %d non-monotonic" % seed)
				continue
			var deg := rad_to_deg(atan2(d.y, d.x))
			if deg > 60.0: steep += 1
			if deg < -32.0: up += 1
			if i > 0 and g.points[i - 1].x > 760.0:
				turn = maxf(turn, absf(deg - pd))
			pd = deg
		var span := g.end_x() - 760.0
		var slope := rad_to_deg(atan2(g.height_at(g.end_x()) - g.height_at(760.0), span))
		slopes.append(snappedf(slope, 0.1))
		if used.size() != 15 or rep > 0 or steep > 0 or up > 0 or gap > 60.0 or turn > 35.0 or slope < 23.0 or slope > 29.0:
			bad.append("seed %d: used=%d rep=%d steep>60=%d up<-32=%d gap=%.0f turn=%.1f slope=%.1f" % [seed, used.size(), rep, steep, up, gap, turn, slope])
		g.queue_free()
	_check("track_20_seeds_shape", bad.is_empty(), "overall slopes=%s worst_100km_gen_ms=%.0f problems=%s" % [slopes, t_max, bad])
	# live terrain: collision matches the drawn surface everywhere, chunks join without gaps, build cost
	gm.terrain.reset(777)
	var t1 := Time.get_ticks_usec()
	gm.terrain.reset(778)
	var reset_ms := (Time.get_ticks_usec() - t1) / 1000.0
	await _frames(3)
	var worst := 0.0
	var misses := 0
	var space := get_viewport().world_2d.direct_space_state
	var q := PhysicsRayQueryParameters2D.new()
	q.collision_mask = 1
	var x := 800.0
	var built_to: float = gm.terrain._chunks[gm.terrain._chunks.size() - 1][1]
	while x < built_to - 10.0:
		var y := gm.terrain.height_at(x)
		q.from = Vector2(x, y - 400.0)
		q.to = Vector2(x, y + 400.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			misses += 1
		else:
			worst = maxf(worst, absf(hit.position.y - y))
		x += 37.0
	var joins_ok := true
	for i in gm.terrain._chunks.size() - 1:
		if not is_equal_approx(gm.terrain._chunks[i][1], gm.terrain._chunks[i + 1][0]):
			joins_ok = false
	_check("track_collision_matches_surface", misses == 0 and worst <= 3.0 and joins_ok,
		"probes up to x=%.0f misses=%d worst_dev=%.2f px chunk_joins_ok=%s chunks=%d reset_ms=%.1f last_chunk_ms=%.2f" % [built_to, misses, worst,
		joins_ok, gm.terrain._chunks.size(), reset_ms, gm.terrain.last_chunk_usec / 1000.0])
	# new runs get new seeds; a forced seed repeats
	var seeds := {}
	for i in 5:
		at.call("start_seen_run")
		await _frames(2)
		seeds[gm.track_seed] = true
	_check("track_new_seed_per_run", seeds.size() == 5 and gm.attempt.seed == gm.track_seed, "distinct seeds in 5 runs=%d" % seeds.size())
	gm.go_menu()