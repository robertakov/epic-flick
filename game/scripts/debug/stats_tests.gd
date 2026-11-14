extends Node
## Debug-only tests for records / statistics (not exported). All files live under user://test/.
##   --scenario=stats        unit tests of StatsStore + full game-flow tests (bot plays real attempts,
##                           buttons pressed with real mouse and touch events)
##   --scenario=stats_print  prints what the game loaded from --stats_path (restart persistence check)
## Prints "AT|test <name> PASS|FAIL <details>".

var gm: GameManager
var at: Node
var passed := 0
var failed := 0

const DIR := "user://test/"


func run_all(which: String) -> void:
	if which == "stats_print":
		var d := gm.stats.data
		print("AT|loaded status=%s attempts=%d best=%.1f total=%.1f recent=%d menu_label=%s" % [gm.stats.last_load_status,
			d.attempts, d.best_m, d.total_m, d.recent.size(), gm.ui.best_label_menu.text])
		return
	gm.profile.tutorial.handled=true # Returning-player statistics flow; fresh onboarding tested separately.
	DirAccess.make_dir_recursive_absolute(DIR)
	at.set("max_time", 1.0e9)
	_unit_tests()
	await _flow_tests()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


func _check(name: String, ok: bool, details: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("AT|test %s %s %s" % [name, "PASS" if ok else "FAIL", details])


func _fresh(name: String) -> StatsStore:
	var p := DIR + name
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(p + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p + suffix))
	var s := StatsStore.new(p)
	s.load_data()
	return s


func _att(id: String, d: float, good := 3, bad := 1, charge := 0.5, boosted := 1, full := 0) -> Dictionary:
	return {"id": id, "distance_m": d, "duration_s": 12.5, "landings": good + bad, "good": good, "bad": bad,
		"max_charge": charge, "boosted": boosted, "full_boosts": full}


# ---------------- StatsStore unit tests ----------------

func _unit_tests() -> void:
	var s := _fresh("unit.json")
	_check("missing_file_defaults", s.last_load_status == "missing" and s.best_m() == 0.0 and int(s.data.attempts) == 0,
		"status=%s" % s.last_load_status)
	# 1. first attempt creates the save
	var r1 := s.record_attempt(_att("a1", 100.0))
	_check("first_attempt_creates_save", FileAccess.file_exists(s.path) and r1.saved and r1.record, "res=%s" % r1)
	# 2. new record
	var r2 := s.record_attempt(_att("a2", 150.5, 4, 0, 1.0, 2, 1))
	_check("new_record_written", r2.record and is_equal_approx(s.best_m(), 150.5), "best=%.1f" % s.best_m())
	# 3. worse attempt keeps the record
	var r3 := s.record_attempt(_att("a3", 80.0, 1, 3, 0.2, 0, 0))
	_check("worse_keeps_record", not r3.record and is_equal_approx(s.best_m(), 150.5), "best=%.1f record=%s" % [s.best_m(), r3.record])
	# 4. totals
	var d := s.data
	_check("totals_sum", d.attempts == 3 and is_equal_approx(d.total_m, 330.5) and d.good_landings == 8 and d.bad_landings == 4
		and d.boosted_bounces == 3 and d.full_charge_bounces == 1 and is_equal_approx(d.best_attempt_charge, 1.0)
		and is_equal_approx(d.total_time_s, 37.5),
		"attempts=%d total=%.1f good=%d bad=%d boosted=%d full=%d charge=%.2f time=%.1f" % [d.attempts, d.total_m,
		d.good_landings, d.bad_landings, d.boosted_bounces, d.full_charge_bounces, d.best_attempt_charge, d.total_time_s])
	# 10. the same attempt can never be stored twice
	var dup := s.record_attempt(_att("a3", 80.0))
	_check("same_attempt_once", dup.get("duplicate", false) and s.data.attempts == 3 and s.data.recent.size() == 3,
		"dup=%s attempts=%d" % [dup, s.data.attempts])
	# 5. only the last 10 results
	for i in 12:
		s.record_attempt(_att("b%d" % i, 10.0 + i))
	var rec: Array = s.data.recent
	_check("only_last_10", rec.size() == 10 and is_equal_approx(rec[0].distance_m, 21.0) and is_equal_approx(rec[9].distance_m, 12.0),
		"size=%d newest=%.0f oldest=%.0f" % [rec.size(), rec[0].distance_m, rec[9].distance_m])
	# 6. reload restores everything (same file, new store = what a restart does)
	var s2 := StatsStore.new(s.path)
	s2.load_data()
	_check("reload_restores", s2.last_load_status == "ok" and JSON.stringify(s2.data) == JSON.stringify(s.data),
		"status=%s attempts=%d best=%.1f" % [s2.last_load_status, s2.data.attempts, s2.best_m()])
	# negative distance is clamped
	var neg := _fresh("neg.json")
	neg.record_attempt(_att("n", -50.0))
	_check("no_negative_results", neg.data.recent[0].distance_m == 0.0 and neg.best_m() == 0.0, "stored=%.1f" % neg.data.recent[0].distance_m)
	# 7. damaged / odd files never crash and never lose a valid record
	var cases := {
		"garbage": "{{{ not json at all ]]",
		"empty": "",
		"array": "[1, 2, 3]",
		"wrong_types": JSON.stringify({"version": 1, "best_m": "lots", "attempts": -4, "recent": "nope", "total_m": 55.0}),
		"old_version": JSON.stringify({"best_m": 77.0, "attempts": 2, "recent": [{"distance_m": 77.0}, {"distance_m": "x"}, 5]}),
		"record_below_recent": JSON.stringify({"version": 1, "best_m": 10.0, "recent": [{"distance_m": 99.0}]}),
	}
	var out := []
	var ok7 := true
	for k in cases:
		var p: String = DIR + "bad_" + k + ".json"
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(cases[k])
		f.close()
		var b := StatsStore.new(p)
		b.load_data()
		var r := b.record_attempt(_att("x_" + k, 5.0))   # must still work and save
		out.append("%s:%s/best=%.0f/att=%d/recent=%d/saved=%s" % [k, b.last_load_status, b.best_m(), b.data.attempts, b.data.recent.size(), r.saved])
		match k:
			"garbage", "empty", "array":
				ok7 = ok7 and b.last_load_status == "corrupt" and FileAccess.file_exists(p + ".corrupt") and b.data.attempts == 1
			"wrong_types":
				ok7 = ok7 and b.last_load_status == "repaired" and is_equal_approx(b.data.total_m, 60.0) and b.data.attempts == 1
			"old_version":
				ok7 = ok7 and b.last_load_status == "repaired" and is_equal_approx(b.best_m(), 77.0) and b.data.recent.size() == 2
			"record_below_recent":
				ok7 = ok7 and is_equal_approx(b.best_m(), 99.0)
	_check("damaged_files_safe", ok7, " | ".join(out))
	# legacy v0.1 best distance import (temp copy, never the real file)
	var leg := DIR + "legacy_progress.cfg"
	var cf := ConfigFile.new()
	cf.set_value("progress", "best_m", 321.0)
	cf.save(leg)
	var m := StatsStore.new(DIR + "migrated.json")
	if FileAccess.file_exists(m.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(m.path))
	m.legacy_path = leg
	m.load_data()
	_check("legacy_import", m.last_load_status == "migrated" and is_equal_approx(m.best_m(), 321.0), "status=%s best=%.0f" % [m.last_load_status, m.best_m()])


# ---------------- full game flow ----------------

func _press(text: String, kind: String) -> bool:
	if text == "ИГРАТЬ" and gm.ui.menu.visible:
		text = "СВОБОДНЫЙ ЗАБЕГ"
	for b: Button in gm.ui._buttons:
		if b.text == text and b.is_visible_in_tree():
			var pos := b.get_global_rect().get_center()
			for pressed in [true, false]:
				var ev: InputEvent
				if kind == "touch":
					var t := InputEventScreenTouch.new()
					t.index = 0
					t.pressed = pressed
					t.position = pos
					ev = t
				else:
					var mb := InputEventMouseButton.new()
					mb.button_index = MOUSE_BUTTON_LEFT
					mb.pressed = pressed
					mb.position = pos
					mb.global_position = pos
					ev = mb
				Input.parse_input_event(ev)
				await get_tree().process_frame
				await get_tree().process_frame
			print("AT|press %s via %s" % [text, kind])
			if (text == "ИГРАТЬ" or text == "СВОБОДНЫЙ ЗАБЕГ") and gm.ui.is_robot_select_open():
				text = "ИГРАТЬ"
				return await _press(text, kind)
			return true
	print("AT|press FAILED: no visible button %s" % text)
	return false


func _shot(n: String) -> void:
	if at.get("shots_dir") != "":
		at.call("_shot", n)


## Lets the autotest bot play one attempt to its result screen. Tracks robot / head progress.
func _play_attempt() -> Dictionary:
	at.set("scenario_running", false)
	var info := {"robot_max_x": -INF, "head_max_x": -INF, "rocket": false, "hp_zero_finished": false}
	var t := 0.0
	while gm.state != GameManager.State.RESULT and t < 90.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if gm.state == GameManager.State.RUN and is_instance_valid(gm.robot):
			info.robot_max_x = maxf(info.robot_max_x, gm.robot.global_position.x)
		if gm.state == GameManager.State.ROCKET and is_instance_valid(gm.rocket):
			info.rocket = true
			info.head_max_x = maxf(info.head_max_x, gm.rocket.global_position.x)
	at.set("scenario_running", true)
	gm.input.set_virtual_hold(false)
	info["timeout"] = t >= 90.0
	return info


func _flow_tests() -> void:
	at.set("scenario_running", true)
	var store := gm.stats
	await get_tree().create_timer(0.4).timeout
	_check("menu_shows_empty_record", gm.ui.best_label_menu.text == "РЕКОРД: —", "label='%s'" % gm.ui.best_label_menu.text)
	_shot("01_menu_empty")
	# 11. statistics panel via touch, close via mouse
	await _press("СТАТИСТИКА", "touch")
	var opened := gm.ui.is_stats_open()
	_shot("02_stats_empty")
	await _press("ЗАКРЫТЬ", "mouse")
	_check("stats_panel_open_close", opened and not gm.ui.is_stats_open() and gm.state == GameManager.State.MENU,
		"opened=%s closed=%s" % [opened, not gm.ui.is_stats_open()])
	# attempt 1 started with a real touch on ИГРАТЬ
	await _press("ИГРАТЬ", "touch")
	_check("play_button_touch", gm.state == GameManager.State.INTRO, "state=%d" % gm.state)
	var first_id := gm.attempt.id
	var a1 := await _play_attempt()
	await get_tree().create_timer(1.6).timeout
	_shot("03_result_record")
	var res1 := gm.last_result
	var file1 := FileAccess.file_exists(store.path)
	# 9. jet head distance counted
	var expect: float = (maxf(a1.robot_max_x, a1.head_max_x) - gm.robot_start.x) / gm.level_config.px_per_meter
	var robot_only: float = (a1.robot_max_x - gm.robot_start.x) / gm.level_config.px_per_meter
	_check("rocket_head_distance_counted", a1.rocket and absf(gm.distance_m - expect) < 0.05 and gm.distance_m >= robot_only,
		"distance=%.2f expected=%.2f robot_only=%.2f head_gain=%.2f m reason=%s rocket=%s" % [gm.distance_m, expect, robot_only, gm.distance_m - robot_only, gm._end_reason, a1.rocket])
	_check("first_result_saved_once", file1 and store.data.attempts == 1 and res1.record and is_equal_approx(store.best_m(), gm.distance_m)
		and store.data.recent.size() == 1, "attempts=%d best=%.1f record=%s" % [store.data.attempts, store.best_m(), res1.record])
	# 10. a second _finish call (late signal, double tap...) must not record again
	gm._finish("duplicate call")
	_check("finish_twice_saved_once", store.data.attempts == 1 and store.data.recent.size() == 1, "attempts=%d" % store.data.attempts)
	# 8. retry (real mouse click): new empty per-attempt counters, totals kept
	var totals_before := JSON.stringify(store.data)
	await _press("ЕЩЁ РАЗ!", "mouse")
	var att := gm.attempt
	_check("retry_resets_attempt_keeps_totals", att.id != first_id and att.landings == 0 and att.good == 0 and att.bad == 0
		and att.max_charge == 0.0 and att.boosted == 0 and att.duration_s < 0.5 and JSON.stringify(store.data) == totals_before
		and gm.robot.damage.health == gm.robot.damage.max_health and gm.ui._hp_value == gm.robot.damage.max_health and gm.ui._charge == 0.0,
		"id_changed=%s counters=%d/%d/%d hp=%.0f totals_kept=%s" % [att.id != first_id, att.landings, att.good, att.bad,
		gm.robot.damage.health, JSON.stringify(store.data) == totals_before])
	# attempt 2: the bot plays worse on purpose (always clockwise) -> normally no record
	at.set("bot", "cw")
	var a2 := await _play_attempt()
	await get_tree().create_timer(1.6).timeout
	_shot("04_result_normal")
	var res2 := gm.last_result
	_check("second_attempt_totals", store.data.attempts == 2 and store.data.recent.size() == 2
		and is_equal_approx(store.data.total_m, float(store.data.recent[0].distance_m) + float(store.data.recent[1].distance_m))
		and is_equal_approx(store.best_m(), maxf(store.data.recent[0].distance_m, store.data.recent[1].distance_m)),
		"d1=%.1f d2=%.1f best=%.1f record2=%s" % [store.data.recent[1].distance_m, store.data.recent[0].distance_m, store.best_m(), res2.record])
	_check("result_screen_values", gm.ui._res_values.landings.text == str(res2.landings) and gm.ui.result_record.visible == res2.record,
		"landings=%s good=%s bad=%s charge=%s boosted=%s time=%s" % [gm.ui._res_values.landings.text, gm.ui._res_values.good.text,
		gm.ui._res_values.bad.text, gm.ui._res_values.max_charge.text, gm.ui._res_values.boosted.text, gm.ui._res_values.duration.text])
	# menu via touch keeps the totals, shows the record, stats panel lists both attempts
	await _press("МЕНЮ", "touch")
	_check("menu_button_touch_keeps_totals", gm.state == GameManager.State.MENU and store.data.attempts == 2
		and gm.ui.best_label_menu.text == "РЕКОРД: %d м" % int(store.best_m()), "label='%s'" % gm.ui.best_label_menu.text)
	await get_tree().create_timer(0.3).timeout
	_shot("05_menu_record")
	await _press("СТАТИСТИКА", "mouse")
	await get_tree().create_timer(0.4).timeout
	_shot("06_stats_panel")
	var rows := gm.ui._stats_recent.get_child_count()
	await _press("ЗАКРЫТЬ", "touch")
	_check("stats_panel_lists_recent", rows == 2 and not gm.ui.is_stats_open(), "rows=%d" % rows)
