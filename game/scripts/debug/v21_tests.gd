extends Node
## v21 comprehensive verification suite:
## - 100-round campaign, irregular pressure spikes, opponent map previews & profile migration
## - 4 new playable characters (tin/rasta, hopper/kenguru, heavy/sumo, rocket/chronos) + samurai
## - Interactive start flick power bar minigame (4 zones, tap lock, no stuck CCW input, AI 1.00x baseline)
## - 10 new star challenge types (unit + integration positive/negative checks + 300 stars validation)

var gm: GameManager
var at: Node
var passed := 0
var failed := 0

const NEW_PLAYER_IDS := ["tin", "hopper", "heavy", "rocket"]
const EXPECTED_ART_IDS := {"tin": "rasta", "hopper": "kenguru", "heavy": "sumo", "rocket": "chronos", "samurai": "samurai"}
const EXPECTED_NAMES := {"tin": "Растабот", "hopper": "Кенгуробот", "heavy": "Сумобот", "rocket": "Хронобот", "samurai": "Самуробот"}
const NEW_STAR_TYPES := [
	"ROCKET_HEAD_DISTANCE",
	"WIN_MARGIN_OVER",
	"HEAD_LANDINGS",
	"NO_TOUCH_AND_WIN",
	"CCW_TURNS",
	"MAX_HEIGHT_M",
	"FLICK_MAX_POWER",
	"FLICK_MIN_AND_WIN",
]


func check(label: String, ok: bool, detail: String = "") -> void:
	passed += int(ok)
	failed += int(not ok)
	var suffix := (" (" + detail + ")") if detail != "" and not ok else ""
	print("AT|test v21_%s %s%s" % [label, "PASS" if ok else "FAIL", suffix])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run_all(which: String) -> void:
	at.set("scenario_running", true)
	at.set("max_time", 1.0e9)
	if which in ["v21_all", "v21_campaign"]:
		await test_campaign_100_and_map()
	if which in ["v21_all", "v21_players"]:
		await test_new_playable_characters()
	if which in ["v21_all", "v21_flick"]:
		await test_interactive_flick_minigame()
	if which in ["v21_all", "v21_stars"]:
		await test_new_star_challenges()
	if which in ["v21_all", "v21_menu"]:
		await test_main_menu_redesign()
	print("AT|tests passed=%d failed=%d" % [passed, failed])
	if failed > 0:
		get_tree().quit(1)


func test_campaign_100_and_map() -> void:
	var c := gm.campaign
	check("campaign_valid_100", c.load_error == "" and c.order.size() == 100, c.load_error)

	var total_stars_cfg := 0
	var chain_ok := true
	var boss_count := 0
	var duo_count := 0
	var single_count := 0
	for i in 100:
		var id := "r%d" % (i + 1)
		if c.order[i] != id:
			chain_ok = false
		var n := c.node(id)
		total_stars_cfg += n.get("stars", []).size()
		var unl: Array = n.get("next", [])
		if i < 99 and (unl.size() != 1 or String(unl[0]) != "r%d" % (i + 2)):
			chain_ok = false
		if i == 99 and not unl.is_empty():
			chain_ok = false
		var enemies: Array = n.get("enemies", [])
		if enemies.size() == 1:
			single_count += 1
		elif enemies.size() == 2:
			duo_count += 1
		if String(n.get("difficulty", "")) == "boss":
			boss_count += 1
	check("campaign_max_stars_300", total_stars_cfg == 300, "stars=%d" % total_stars_cfg)
	check("campaign_chain_r1_to_r100", chain_ok)
	check("campaign_10_boss_rounds", boss_count == 10, "bosses=%d" % boss_count)
	check("campaign_has_single_and_duo_rounds", single_count >= 50 and duo_count >= 25, "single=%d duo=%d" % [single_count, duo_count])

	# Verify irregular spike rounds in enemy_roster.json
	var roster_rounds: Dictionary = EnemyRoster.data().get("rounds", {})
	check("roster_90_non_boss_rounds", roster_rounds.size() == 90, "size=%d" % roster_rounds.size())
	var pressure_indices: Array[int] = []
	for i in range(1, 101):
		var rid := "r%d" % i
		var slots: Array = roster_rounds.get(rid, [])
		var has_p := false
		for s in slots:
			if bool(s.get("pressure", false)):
				has_p = true
		if has_p:
			pressure_indices.append(i)
	var gaps: Array[int] = []
	var prev_idx := 0
	var unique_gaps := {}
	for idx in pressure_indices:
		var g := idx - prev_idx
		gaps.append(g)
		unique_gaps[g] = true
		prev_idx = idx
	check("pressure_spikes_count_reasonable", pressure_indices.size() >= 14 and pressure_indices.size() <= 20, "count=%d" % pressure_indices.size())
	check("pressure_spikes_irregular_intervals", unique_gaps.size() >= 3, "gaps=%s" % str(gaps))

	# Verify wave difficulty (breather drops exist across 100 rounds)
	var drops := 0
	for i in range(2, 100):
		if i % 10 == 0 or (i - 1) % 10 == 0:
			continue
		var s_prev := float(c.node("r%d" % (i - 1)).enemies[0].skill)
		var s_cur := float(c.node("r%d" % i).enemies[0].skill)
		if s_cur < s_prev - 0.01:
			drops += 1
	check("campaign_wave_progression_has_breathers", drops >= 12, "drops=%d" % drops)

	# Profile migration: r40 completed unlocks r41, and r100 stars persist
	var saved_completed: Array = gm.profile.campaign.completed.duplicate()
	var saved_unlocked: Array = gm.profile.campaign.unlocked.duplicate()
	var saved_stars: Dictionary = gm.profile.campaign.stars.duplicate(true)

	var r1_to_r40: Array = []
	for i in range(1, 41):
		r1_to_r40.append("r%d" % i)
	gm.profile.campaign.completed = r1_to_r40.duplicate()
	gm.profile.campaign.unlocked = r1_to_r40.duplicate()
	gm.profile.campaign.stars = {"r40": [true, true, false], "r100": [true, false, true]}
	gm.profile.save()
	gm.profile.load_data()
	check("profile_migrates_r40_to_r41", gm.profile.is_unlocked("r41"))
	check("profile_persists_r100_stars", gm.profile.stars_of("r100") == [true, false, true])

	# Unlock up to r100 for campaign map visual inspection & opponent preview checks
	var all_ids: Array = []
	for i in range(1, 101):
		all_ids.append("r%d" % i)
	gm.profile.campaign.unlocked = all_ids.duplicate()
	gm.profile.campaign.completed = all_ids.slice(0, 74)
	gm.open_campaign_map()
	await frames(6)
	var map := gm.ui.campaign_map
	check("map_built_100_positions", map._positions.size() == 100, "positions=%d" % map._positions.size())

	var all_previews_ok := true
	for id in c.order:
		var opps := map.round_opponents(id)
		var previews := map.node_previews(id)
		var expected_n: int = c.node(id).get("enemies", []).size()
		if opps.size() != expected_n or previews.size() != expected_n:
			all_previews_ok = false
	check("map_all_100_rounds_have_previews", all_previews_ok)

	for focus_id in ["r1", "r25", "r50", "r75", "r100"]:
		map.select_node(focus_id)
		map.center_on(focus_id)
		await frames(6)
		at.call("_shot", "v21_map_" + focus_id)

	gm.go_menu()
	await frames(3)
	gm.profile.campaign.completed = saved_completed
	gm.profile.campaign.unlocked = saved_unlocked
	gm.profile.campaign.stars = saved_stars
	gm.profile.save()


func test_new_playable_characters() -> void:
	for id in EXPECTED_ART_IDS.keys():
		var def := gm.catalog.get_by_id(id)
		check("char_%s_exists" % id, def != null)
		if def == null:
			continue
		check("char_%s_visual_id" % id, def.effective_visual_id() == EXPECTED_ART_IDS[id], def.effective_visual_id())
		check("char_%s_display_name" % id, def.display_name == EXPECTED_NAMES[id], def.display_name)
		if id != "samurai":
			var manifest := RobotArtLibrary.manifest(id)
			check("char_%s_manifest_loaded" % id, String(manifest.get("visual_id", "")) == EXPECTED_ART_IDS[id] and manifest.get("parts", {}).size() == 6, str(manifest.get("visual_id", "")))

	# Build all 4 new playable characters + samurai in a clean visual gallery and verify rigs & joints
	var layer := CanvasLayer.new()
	layer.layer = 100
	gm.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.14, 0.17, 0.22)
	bg.size = Vector2(1280, 720)
	bg.z_index = -100
	layer.add_child(bg)
	var title := Label.new()
	title.position = Vector2(20, 15)
	title.add_theme_font_size_override("font_size", 24)
	title.text = "v21 Playable Characters — Раста, Кенгуру, Сумоист, Хронос, Самурай"
	layer.add_child(title)

	var all_ids := ["tin", "hopper", "heavy", "rocket", "samurai"]
	var robots: Array[RobotController] = []
	for i in all_ids.size():
		var id: String = all_ids[i]
		var def := gm.catalog.get_by_id(id)
		var r := gm.build_robot(def, null, null)
		r.freeze = true
		r.position = Vector2(130 + i * 250, 340)
		layer.add_child(r)
		r.set_physics_process(false)
		r.visual.set_physics_process(false)
		r.visual.identity.set_process(false)
		robots.append(r)
		var lbl := Label.new()
		lbl.text = "%s (%s)" % [def.display_name, def.effective_visual_id()]
		lbl.position = Vector2(55 + i * 250, 590)
		lbl.add_theme_font_size_override("font_size", 22)
		layer.add_child(lbl)

	await frames(4)
	for state in ["idle", "compression", "release", "airborne"]:
		title.text = "v21 Playable Characters — " + state
		for i in robots.size():
			var id: String = all_ids[i]
			var r := robots[i]
			var v := r.visual
			v.squash = 0.28 if state == "compression" else (-0.22 if state == "release" else 0.0)
			v._apply_squash()
			if v.art_torso != null:
				v.art_torso._process(0)
			if v.head.video_part != null:
				v.head.video_part._process(0)
			for side in v.legs:
				var l: LegVisual = v.legs[side]
				l.length = l.cfg.coil_min_length if state == "compression" else (l.cfg.coil_max_length if state == "release" else l.cfg.coil_rest_length)
				l.swing = 0.25 if state == "airborne" else 0.0
				l._apply()
			for side in v.arms:
				var a: ArmVisual = v.arms[side]
				a.p = a.exit + a.rest
				a._apply()
			v.head.step(0, v.frame)
			v._sync_art_joints()
			if not v.art_profile.enabled():
				check("player_%s_%s_legacy_preserved" % [id, state], v.art_torso == null and v.head.video_part == null)
				continue
			var joints_ok := true
			for side in v.arms:
				var a: ArmVisual = v.arms[side]
				if a.video_part.position.distance_to(v.art_profile.anchor("shoulder_l" if side == &"arm_l" else "shoulder_r", v.art_torso, v.torso)) > 0.01:
					joints_ok = false
			for side in v.legs:
				var l: LegVisual = v.legs[side]
				if l.video_part.position.distance_to(v.art_profile.anchor("hip_l" if side == &"leg_l" else "hip_r", v.art_torso, v.torso)) > 0.01:
					joints_ok = false
			if (v.head.transform * v.head.video_part.position).distance_to(v.head.visual_neck) > 0.01:
				joints_ok = false
			check("player_%s_%s_joints" % [id, state], joints_ok)
		await frames(3)
		at.call("_shot", "v21_players_" + state)

	layer.queue_free()
	await frames(3)

	# Capture Robot Select UI screenshots for all 5 characters
	gm.open_robot_select()
	await frames(6)
	for i in gm.catalog.robots.size():
		await frames(6)
		var cur := gm.ui.robot_select.current()
		at.call("_shot", "v21_select_%s" % cur.id)
		gm.ui.robot_select.step(1)
	gm._close_select()
	await frames(3)


func test_interactive_flick_minigame() -> void:
	# 1. Verify interactive waiting in INTRO when require_flick_tap_in_autotest = true
	gm.require_flick_tap_in_autotest = true
	gm.mode = &"campaign"
	gm.node_id = "r1"
	gm.profile.ensure_campaign_start("r1")
	at.call("start_seen_run")
	await frames(4)

	var bar: FlickPowerBar = gm.ui.flick_bar
	check("flick_bar_exists_and_active_in_intro", bar != null and bar.active and bar.visible and not bar.locked)
	check("flick_hand_holds_at_tension", gm.hand.hold_at_tension)

	# Wait so the hand reaches tension hold and bar needle moves
	var r0: float = bar.marker_ratio
	await get_tree().create_timer(0.45).timeout
	var r1: float = bar.marker_ratio
	check("flick_stay_in_intro_until_tap", gm.state == GameManager.State.INTRO and gm.hand.hold_at_tension)
	check("flick_bar_needle_oscillates", absf(r1 - r0) > 0.02, "r0=%.3f r1=%.3f" % [r0, r1])
	at.call("_shot", "v21_flick_bar_active")

	# Simulate player tap at MAXIMUM zone (0.94) and verify tap locks bar, clears input.holding, and launches run
	bar.marker_ratio = 0.94
	gm.input.holding = true
	gm.input.tapped.emit()
	check("flick_tap_locks_bar_max", bar.locked and bar.locked_tier == "MAXIMUM")
	check("flick_tap_clears_input_holding", not gm.input.holding)
	await frames(2)
	at.call("_shot", "v21_flick_bar_locked_max")
	await get_tree().create_timer(0.28).timeout
	check("flick_transitions_to_run", gm.state == GameManager.State.RUN)
	gm.go_menu()
	await frames(3)

	# 2. Measure launch velocities across all 4 zones and verify AI always launches at 1.00x baseline
	gm.require_flick_tap_in_autotest = false
	var test_ratios := {
		"min": 0.12,
		"normal": 0.46,
		"strong": 0.76,
		"max": 0.95,
	}
	var player_speeds := {}
	var ai_speeds := {}
	for key in ["min", "normal", "strong", "max"]:
		gm.mode = &"campaign"
		gm.node_id = "r1"
		at.call("start_seen_run")
		await frames(2)
		gm.lock_flick_ratio(float(test_ratios[key]))
		if key == "min":
			await frames(2)
			at.call("_shot", "v21_flick_bar_locked_min")
		gm.hand.playing = false
		gm._on_flick(Vector2.ZERO)
		player_speeds[key] = gm.robot.linear_velocity.length()
		ai_speeds[key] = gm.race.competitors[0].robot.linear_velocity.length()
		gm.go_menu()
		await frames(2)

	check("flick_velocity_strictly_monotonic",
		float(player_speeds["min"]) < float(player_speeds["normal"]) - 40.0
		and float(player_speeds["normal"]) < float(player_speeds["strong"]) - 20.0
		and float(player_speeds["strong"]) < float(player_speeds["max"]) - 30.0,
		"speeds=%s" % str(player_speeds))
	check("flick_ratio_min_080x", is_equal_approx(float(player_speeds["min"]) / float(player_speeds["normal"]), 0.80))
	check("flick_ratio_strong_108x", is_equal_approx(float(player_speeds["strong"]) / float(player_speeds["normal"]), 1.08))
	check("flick_ratio_max_120x", is_equal_approx(float(player_speeds["max"]) / float(player_speeds["normal"]), 1.20))
	check("flick_ai_always_baseline_100x",
		is_equal_approx(float(ai_speeds["min"]), float(ai_speeds["normal"]))
		and is_equal_approx(float(ai_speeds["strong"]), float(ai_speeds["normal"]))
		and is_equal_approx(float(ai_speeds["max"]), float(ai_speeds["normal"]))
		and is_equal_approx(float(ai_speeds["normal"]), float(player_speeds["normal"])),
		"ai_speeds=%s" % str(ai_speeds))


func test_new_star_challenges() -> void:
	# 1. Verify stars.json uses all 10 new types across the 100 rounds and all 300 stars validate
	var c := gm.campaign
	var counts := {}
	for t in NEW_STAR_TYPES:
		counts[t] = 0
	var rounds_with_3_stars := 0
	for rid in c.order:
		var st_arr: Array = c.node(rid).get("stars", [])
		if st_arr.size() == 3:
			rounds_with_3_stars += 1
		for ch in st_arr:
			var tp := String(ch.type)
			if counts.has(tp):
				counts[tp] = int(counts[tp]) + 1
	check("stars_100_rounds_loaded", rounds_with_3_stars == 100, "rounds=%d" % rounds_with_3_stars)
	for t in NEW_STAR_TYPES:
		check("star_type_distributed_" + t, int(counts[t]) >= 5, "count=%d" % int(counts[t]))

	# 2. Positive & negative evaluation tests for all 10 new challenge types
	# ROCKET_HEAD_DISTANCE
	var st := StarTracker.new([{"type": "ROCKET_HEAD_DISTANCE", "m": 20}])
	st.sample(0.1, 100.0, 10000.0, false, true, 50.0) # robot_m = 100
	st.sample(0.1, 115.0, 11500.0, false, false, 50.0) # rocket_head_m = 15
	check("star_ROCKET_HEAD_DISTANCE_neg", st.status[0] == 0)
	st.sample(0.1, 122.0, 12200.0, false, false, 50.0) # rocket_head_m = 22
	check("star_ROCKET_HEAD_DISTANCE_pos", st.status[0] == 1)

	# WIN_MARGIN_OVER
	st = StarTracker.new([{"type": "WIN_MARGIN_OVER", "m": 15}])
	st.on_race_result(true, 110.0, 100.0)
	check("star_WIN_MARGIN_OVER_neg_small_lead", st.status[0] == -1)
	st = StarTracker.new([{"type": "WIN_MARGIN_OVER", "m": 15}])
	st.on_race_result(true, 118.0, 100.0)
	check("star_WIN_MARGIN_OVER_pos", st.status[0] == 1)

	# Removed impractical challenges must be rejected and absent everywhere
	check("star_removed_FINISH_WITHIN_ENEMY", not StarChallenges.TYPES.has("FINISH_WITHIN_ENEMY") and StarChallenges.validate({"type": "FINISH_WITHIN_ENEMY", "m": 50, "reward": 20}) != "")
	check("star_removed_KEEP_ENEMY_IN_VIEW", not StarChallenges.TYPES.has("KEEP_ENEMY_IN_VIEW") and StarChallenges.validate({"type": "KEEP_ENEMY_IN_VIEW", "s": 5.0, "reward": 20}) != "")

	# HEAD_LANDINGS
	st = StarTracker.new([{"type": "HEAD_LANDINGS", "n": 3}])
	st.on_head_landing()
	st._head_land_cd = 0.0
	st.on_head_landing()
	st._head_land_cd = 0.0
	check("star_HEAD_LANDINGS_neg_2_of_3", st.status[0] == 0)
	st.on_head_landing()
	check("star_HEAD_LANDINGS_pos_3_of_3", st.status[0] == 1)

	# NO_TOUCH_AND_WIN (must always be 3.5s across all campaign rounds)
	var all_no_touch_35 := true
	for rid in c.order:
		for ch in c.node(rid).get("stars", []):
			if String(ch.type) == "NO_TOUCH_AND_WIN" and not is_equal_approx(float(ch.get("s", 0.0)), 3.5):
				all_no_touch_35 = false
	check("star_NO_TOUCH_AND_WIN_always_3_5s", all_no_touch_35 and int(counts["NO_TOUCH_AND_WIN"]) == 14)
	st = StarTracker.new([{"type": "NO_TOUCH_AND_WIN", "s": 3.5}])
	st.sample_no_touch(2.0, false)
	st.sample_no_touch(0.5, true) # player held input -> resets streak
	st.sample_no_touch(3.0, false)
	st.on_race_result(true, 120.0, 100.0)
	check("star_NO_TOUCH_AND_WIN_neg_interrupted", st.status[0] == -1)
	st = StarTracker.new([{"type": "NO_TOUCH_AND_WIN", "s": 3.5}])
	st.sample_no_touch(4.0, false)
	st.on_race_result(false, 90.0, 100.0)
	check("star_NO_TOUCH_AND_WIN_neg_lost", st.status[0] == -1)
	st = StarTracker.new([{"type": "NO_TOUCH_AND_WIN", "s": 3.5}])
	st.sample_no_touch(3.6, false)
	st.on_race_result(true, 120.0, 100.0)
	check("star_NO_TOUCH_AND_WIN_pos_hands_off_win", st.status[0] == 1)

	# CCW_TURNS
	st = StarTracker.new([{"type": "CCW_TURNS", "n": 3}])
	st.sample_rotation(-TAU * 2.2) # 2.2 CCW turns
	st.sample_rotation(TAU * 4.0)  # v36: meaningful CW rotation breaks the streak (was: ignored)
	check("star_CCW_TURNS_neg_2_turns", st.status[0] == 0)
	st.sample_rotation(-TAU * 0.9) # 2.2 + 0.9 are NOT continuous (v36: one continuous streak required)
	check("star_CCW_TURNS_neg_scattered", st.status[0] == 0)
	st.sample_rotation(-TAU * 2.2) # continuous 3.1 CCW turns
	check("star_CCW_TURNS_pos_3_turns", st.status[0] == 1)

	# MAX_HEIGHT_M
	st = StarTracker.new([{"type": "MAX_HEIGHT_M", "m": 12}])
	st.sample_height(9.5)
	check("star_MAX_HEIGHT_M_neg", st.status[0] == 0)
	st.sample_height(12.4)
	check("star_MAX_HEIGHT_M_pos", st.status[0] == 1)

	# FLICK_MAX_POWER
	st = StarTracker.new([{"type": "FLICK_MAX_POWER", "n": 1}])
	st.on_flick("STRONG", 1.08)
	check("star_FLICK_MAX_POWER_neg_strong", st.status[0] == -1)
	st = StarTracker.new([{"type": "FLICK_MAX_POWER", "n": 1}])
	st.on_flick("MAXIMUM", 1.20)
	check("star_FLICK_MAX_POWER_pos_maximum", st.status[0] == 1)

	# FLICK_MIN_AND_WIN
	st = StarTracker.new([{"type": "FLICK_MIN_AND_WIN", "n": 1}])
	st.on_flick("NORMAL", 1.00)
	check("star_FLICK_MIN_AND_WIN_neg_normal_flick", st.status[0] == -1)
	st = StarTracker.new([{"type": "FLICK_MIN_AND_WIN", "n": 1}])
	st.on_flick("MINIMUM", 0.80)
	st.on_race_result(false, 80.0, 100.0)
	check("star_FLICK_MIN_AND_WIN_neg_min_lost", st.status[0] == -1)
	st = StarTracker.new([{"type": "FLICK_MIN_AND_WIN", "n": 1}])
	st.on_flick("MINIMUM", 0.80)
	st.on_race_result(true, 120.0, 100.0)
	check("star_FLICK_MIN_AND_WIN_pos_min_won", st.status[0] == 1)


func test_main_menu_redesign() -> void:
	gm.mode = &"free"
	gm.best_m = 615.0
	gm.go_menu()
	await frames(6)
	var ui := gm.ui
	var vp := get_viewport().get_visible_rect().size

	# 1. Title & removed texts
	check("menu_title_epic_shalban", ui.menu_title != null and ui.menu_title.text == "ЭПИЧЕСКИЙ ЩЕЛБАН", ui.menu_title.text if ui.menu_title else "null")
	var has_forbidden_text := false
	for ch in ui.menu_content.get_children():
		if ch is Label:
			var t := (ch as Label).text
			if t.contains("Один щелчок") or t.contains("Отпусти — робот крутится"):
				has_forbidden_text = true
	check("menu_removed_subtitle_and_bottom_help", not has_forbidden_text)

	# 2. Top-left record and top-right currency
	var best_rect := ui.best_label_menu.get_global_rect()
	var coins_rect := ui.coins_label_menu.get_global_rect()
	check("menu_record_top_left", best_rect.get_center().x < vp.x * 0.40 and best_rect.get_center().y < vp.y * 0.16 and ui.best_label_menu.text == "РЕКОРД: 615 м", "%s text=%s" % [best_rect, ui.best_label_menu.text])
	check("menu_currency_top_right", coins_rect.get_center().x > vp.x * 0.52 and coins_rect.get_center().y < vp.y * 0.16 and ui.coins_label_menu.text.contains("Монеты:") and ui.coins_label_menu.text.contains("Звёзды доступны:"), "%s text=%s" % [coins_rect, ui.coins_label_menu.text])

	# 3. 4 Circular downhill buttons
	check("menu_four_buttons_present", ui.menu_buttons.size() == 4)
	var all_circular := true
	var diagonal_ok := true
	var no_btn_overlap := true
	for i in ui.menu_buttons.size():
		var b := ui.menu_buttons[i]
		var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
		if not is_equal_approx(b.size.x, b.size.y) or b.size.x < 88.0 or sb == null or sb.corner_radius_top_left < int(b.size.x * 0.45):
			all_circular = false
		if i + 1 < ui.menu_buttons.size():
			var c0 := b.get_global_rect().get_center()
			var c1 := ui.menu_buttons[i + 1].get_global_rect().get_center()
			if not (c0.x < c1.x and c0.y < c1.y):
				diagonal_ok = false
		for j in range(i + 1, ui.menu_buttons.size()):
			if b.get_global_rect().grow(-1.0).intersects(ui.menu_buttons[j].get_global_rect().grow(-1.0)):
				no_btn_overlap = false
	check("menu_buttons_circular", all_circular)
	check("menu_buttons_descending_diagonal", diagonal_ok)
	check("menu_buttons_no_overlap", no_btn_overlap)

	# 4. Selected playable character on the right side + dynamic switching from RobotSelectView
	check("menu_robot_preview_exists_and_right_side", ui.menu_robot_preview != null and ui.menu_robot_preview.position.x > ui.menu_content.size.x * 0.55)
	for id in ["tin", "hopper", "heavy", "rocket", "samurai"]:
		if not gm.profile.owned.has(id):
			gm.profile.owned.append(id)
	var all_switched_ok := true
	for target_id in ["tin", "hopper", "heavy", "rocket", "samurai"]:
		gm.open_robot_select()
		await frames(2)
		for _step_i in gm.catalog.robots.size() + 1:
			if gm.ui.robot_select.current().id == target_id:
				break
			gm.ui.robot_select.step(1)
		gm._close_select()
		await frames(4)
		if gm.profile.selected != target_id or ui.menu_robot_preview.def == null or ui.menu_robot_preview.def.id != target_id:
			all_switched_ok = false
		# Advance a few frames of idle animation and capture screenshot
		for f in 12:
			ui.menu_robot_preview._process(0.04)
		await frames(2)
		at.call("_shot", "v22_menu_%s" % target_id)
	check("menu_character_updates_from_robot_select", all_switched_ok)

	# Restore default tin selection and capture primary menu screenshot
	gm.profile.select("tin")
	gm.go_menu()
	await frames(4)
	at.call("_shot", "v22_menu_main")

	# 5. Diverse idle animations: verify continuous base motion + multiple non-repeating secondary actions over 28s
	for id in ["tin", "hopper", "heavy", "rocket", "samurai"]:
		var def := gm.catalog.get_by_id(id)
		ui.set_menu_robot(def, gm.robot_config, gm.skins.get_by_id(gm.profile.equipped_skin(id)))
		var anim := ui.menu_robot_preview.player_animator
		var distinct_actions := {}
		var back_to_back_repeat := false
		var prev_finished_action := ""
		var last_seen_action := ""
		var max_body_disp := 0.0
		for step_n in 560: # 28.0 seconds at dt = 0.05
			var pose := anim.step(0.05)
			ui.menu_robot_preview._layout_player(pose)
			max_body_disp = maxf(max_body_disp, (pose.body_pos as Vector2).length())
			if anim.current_action != "" and anim.current_action != last_seen_action:
				distinct_actions[anim.current_action] = true
				if anim.current_action == prev_finished_action:
					back_to_back_repeat = true
				prev_finished_action = anim.current_action
				last_seen_action = anim.current_action
			elif anim.current_action == "":
				last_seen_action = ""
		check("idle_diverse_%s" % id, anim.actions_triggered >= 4 and distinct_actions.size() >= 2 and not back_to_back_repeat and (max_body_disp > 1.0 and max_body_disp < 12.0),  # v29: Samurobot uses the shared PNG idle since v27
			"triggered=%d distinct=%d repeat=%s disp=%.1f" % [anim.actions_triggered, distinct_actions.size(), back_to_back_repeat, max_body_disp])

