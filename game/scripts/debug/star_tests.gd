extends Node
## Debug-only semantic, migration and real-loop integration tests.
var gm: GameManager
var at: Node
var passed := 0
var failed := 0

func check(name: String, ok: bool) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("AT|test star_%s %s" % [name, "PASS" if ok else "FAIL"])

func tracker(type: String, params := {}) -> StarTracker:
	var ch := {"type": type, "reward": 20}
	ch.merge(params)
	return StarTracker.new([ch])

func step(t: StarTracker, d: float, contact := false, robot_phase := true, dt := 0.1, speed := 0.0, pending := false) -> void:
	t.sample(dt, d, d * 100.0, contact, robot_phase, speed, pending)

func land(t: StarTracker, type: String, ratio := 0.0) -> void:
	t.on_landed({"type": type, "charge_ratio": ratio})

func run_all(_which: String) -> void:
	at.set("scenario_running", true)
	if _which == "star_report":
		audit_metrics()
		print("AT|tests passed=%d failed=%d" % [passed, failed])
		return
	if _which == "star_layout":
		await layout()
		print("AT|tests passed=%d failed=%d" % [passed, failed])
		return
	structure()
	semantics()
	persistence()
	await integration()
	print("AT|tests passed=%d failed=%d" % [passed, failed])

func structure() -> void:
	var total := 0
	var seen := {}
	var sets := {}
	var prev := []
	var valid := gm.campaign.load_error == ""
	var descriptions := true
	# v33 unlock rounds (tools/rebalance_stars_v33.py UNLOCK): more types early for variety (r1-r5 used to be forced
	# to a feet-landing challenge every round)
	var minimum := {"DISTANCE": 1, "TOTAL_GOOD_LANDINGS": 1, "CHARGE_TARGET": 1, "CLEAN_START": 2, "AIR_TIME": 2,
		"FLICK_MAX_POWER": 2, "RECOVERY": 2, "GOOD_LANDING_STREAK": 3, "CCW_TURNS": 3, "SPEED_TARGET": 3,
		"BAD_LANDING_LIMIT": 3, "LONG_JUMP": 4, "SURVIVAL_HP": 4, "CHARGED_LANDING": 5, "LIMB_LIMIT": 6,
		"CLEAN_SECTION": 8, "CHARGED_LANDING_STREAK": 18, "ROCKET_HEAD_DISTANCE": 41, "WIN_MARGIN_OVER": 41,
		"HEAD_LANDINGS": 41, "NO_TOUCH_AND_WIN": 41, "MAX_HEIGHT_M": 41, "FLICK_MIN_AND_WIN": 41}
	for id in gm.campaign.order:
		var rows: Array = gm.campaign.node(id).get("stars", [])
		valid = valid and rows.size() == 3
		total += rows.size()
		var types := []
		var cats := []
		for ch in rows:
			valid = valid and StarChallenges.validate(ch) == "" and int(id.substr(1)) >= int(minimum.get(ch.type, 99))
			seen[ch.type] = true
			types.append(ch.type)
			cats.append(StarChallenges.category(ch))
			descriptions = descriptions and StarChallenges.describe(ch) != "?" and StarChallenges.short(ch) != "?"
		cats.sort()
		valid = valid and cats == ["A", "B", "C"]
		for pair in StarChallenges.INCOMPATIBLE:
			valid = valid and not (types.has(pair[0]) and types.has(pair[1]))
		var common := 0
		for type in types:
			common += int(prev.has(type))
		types.sort()
		var key := str(types)
		valid = valid and common <= 1 and not sets.has(key)
		sets[key] = true
		prev = types
	check("40_rounds_120_unique_category_triplets", total == 300 and gm.campaign.order.size() == 100 and seen.size() == 23 and valid)
	check("all_russian_descriptions", descriptions)
	var before := JSON.stringify(gm.campaign.nodes)
	for i in 100:
		gm.adaptive.record({"player_m": 1, "best_enemy_m": 1000, "won": false, "attempts": i + 1, "hp_ratio": 0.0, "difficulty": "boss"})
	check("adaptive_never_changes_objectives", JSON.stringify(gm.campaign.nodes) == before)
	check("reject_nonfinite_fractional_and_zero_streak", StarChallenges.validate({"type": "AIR_TIME", "s": NAN, "reward": 1}) != ""
		and StarChallenges.validate({"type": "RECOVERY", "n": 0, "reward": 1}) != ""
		and StarChallenges.validate({"type": "LIMB_LIMIT", "m": 20, "n": 1.5, "reward": 1}) != "")

func semantics() -> void:
	var t := tracker("DISTANCE", {"m": 30})
	step(t, 29)
	var pending: bool = t.status[0] == 0
	step(t, 30, false, false)
	check("distance_includes_jet_head", pending and t.status[0] == 1)
	t = tracker("CLEAN_START", {"m": 30})
	step(t, 30)
	t.on_limb(31)
	check("clean_start_locked_at_checkpoint", t.status[0] == 1)
	t = tracker("CLEAN_START", {"m": 30})
	t.on_limb(29)
	step(t, 40)
	check("clean_start_early_failure", t.status[0] == -1)
	t = tracker("LIMB_LIMIT", {"m": 30, "n": 1})
	t.on_limb(20)
	step(t, 30)
	t.on_limb(31)
	check("limb_limit_checkpoint", t.status[0] == 1)
	t = tracker("LIMB_LIMIT", {"m": 30, "n": 1})
	t.on_limb(20)
	t.on_limb(25)
	step(t, 30)
	check("limb_limit_failure", t.status[0] == -1)
	t = tracker("BAD_LANDING_LIMIT", {"m": 30, "n": 1})
	step(t, 20)
	land(t, "body")
	step(t, 30)
	land(t, "body")
	check("bad_limit_lock_after_checkpoint", t.status[0] == 1)
	t = tracker("BAD_LANDING_LIMIT", {"m": 30, "n": 0})
	step(t, 31, true, true, .1, 0, true)
	var delayed: bool = t.status[0] == 0
	t.on_landed({"type": "body", "contact_x": 2900})
	check("bad_limit_waits_for_contact_classification", delayed and t.status[0] == -1)
	t = tracker("GOOD_LANDING_STREAK", {"n": 2})
	land(t, "left")
	land(t, "body")
	land(t, "right")
	pending = t.status[0] == 0
	land(t, "soft")
	land(t, "both")
	check("good_streak_resets_soft_ignored", pending and t.status[0] == 1)
	t = tracker("TOTAL_GOOD_LANDINGS", {"n": 2})
	land(t, "left")
	land(t, "poor")
	land(t, "right")
	check("total_good_survives_bad", t.status[0] == 1)
	t = tracker("CHARGE_TARGET", {"pct": 50})
	t.on_charge(.49)
	pending = t.status[0] == 0
	t.on_charge(.5)
	t.on_charge(0)
	check("charge_peak_retained", pending and t.status[0] == 1)
	t = tracker("CHARGED_LANDING", {"pct": 50})
	land(t, "body", 1)
	land(t, "left", .49)
	pending = t.status[0] == 0
	t.on_charge(0)
	land(t, "both", .5)
	check("charged_landing_uses_contact_not_current_charge", pending and t.status[0] == 1)
	t = tracker("CHARGED_LANDING", {"pct": 50})
	t.on_landed({"type": "both", "charge_ratio": .9, "charge_zone": "side"})
	check("body_first_charge_not_a_feet_boost", t.status[0] == 0)
	t = tracker("CHARGED_LANDING_STREAK", {"pct": 50, "n": 2})
	land(t, "left", .6)
	land(t, "right", .4)
	land(t, "left", .6)
	pending = t.status[0] == 0
	land(t, "poor", .9)
	land(t, "left", .6)
	land(t, "soft", 0)
	land(t, "right", .6)
	check("charged_streak_resets_low_charge_and_bad", pending and t.status[0] == 1)
	t = tracker("AIR_TIME", {"s": 1.0})
	step(t, 0, true) # launch ledge contact
	step(t, 10, false, true, 2.0)
	pending = t.status[0] == 0
	step(t, 15, true)
	step(t, 20, false, true, .5)
	step(t, 25, true)
	step(t, 30, false, true, .5)
	pending = pending and t.status[0] == 0
	step(t, 40, false, true, .5)
	check("air_excludes_flick_and_requires_continuous_flight", pending and t.status[0] == 1)
	t = tracker("AIR_TIME", {"s": 1.9})
	step(t, 10)
	step(t, 15, true)
	for i in 228:
		step(t, 20 + i * .1, false, true, 1.0 / 120.0)
	check("air_exact_physics_tick_boundary", t.status[0] == 1)
	t = tracker("LONG_JUMP", {"m": 10})
	step(t, 10)
	step(t, 15, true)
	step(t, 20)
	step(t, 35)
	pending = t.status[0] == 0
	step(t, 36, true)
	check("jump_only_awarded_on_next_contact", pending and t.status[0] == 1)
	t = tracker("LONG_JUMP", {"m": 10})
	step(t, 10)
	step(t, 15, true)
	step(t, 20)
	step(t, 100, true, false, 10.0)
	check("jump_jet_transition_discarded", t.status[0] == 0)
	t = tracker("SPEED_TARGET", {"kmh": 80})
	step(t, 0, true, true, .1, 120)
	step(t, 10, false, true, .1, 120)
	pending = t.status[0] == 0
	step(t, 15, true, true, .1, 79)
	step(t, 100, false, false, .1, 200)
	pending = pending and t.status[0] == 0
	step(t, 101, false, true, .1, 80)
	check("speed_excludes_flick_jet", pending and t.status[0] == 1)
	t = tracker("SURVIVAL_HP", {"m": 30, "hp": 60})
	t.on_health(20, 60)
	step(t, 30)
	t.on_health(35, 0)
	check("hp_checkpoint_later_damage_irrelevant", t.status[0] == 1)
	t = tracker("SURVIVAL_HP", {"m": 30, "hp": 60})
	step(t, 10)
	t.on_health(10, 59)
	check("hp_fails_early", t.status[0] == -1)
	t = tracker("RECOVERY", {"n": 2})
	land(t, "body")
	land(t, "poor")
	land(t, "both")
	land(t, "left")
	pending = t.status[0] == 0
	land(t, "body")
	land(t, "soft")
	land(t, "right")
	check("recovery_next_landing_only", pending and t.status[0] == 1)
	t = tracker("CLEAN_SECTION", {"m": 30})
	step(t, 20)
	land(t, "body")
	step(t, 40)
	pending = t.status[0] == 0
	step(t, 50)
	land(t, "body")
	check("clean_section_restarts_anywhere_locks", pending and t.status[0] == 1)
	t = tracker("CLEAN_SECTION", {"m": 30})
	step(t, 20)
	step(t, 100, false, false)
	check("clean_section_excludes_jet", t.status[0] == 0)
	t = tracker("DISTANCE", {"m": 30})
	t.stop()
	step(t, 100)
	land(t, "left", 1)
	t.on_charge(1)
	check("stopped_tracker_ignores_late_events", t.status[0] == 0 and t.metrics().total_good == 0)

func persistence() -> void:
	var path := "user://test/stars_profile.json"
	var p := ProfileStore.new(path, gm.catalog, gm.skins)
	p.coins = 777
	p.owned.append("hopper")
	p.selected = "hopper"
	p.ensure_campaign_start("r1")
	p.complete("r1", ["r2"])
	p.claim_first_clear("r1", 45)
	p.grant_skin("tin_copper")
	p.equip_skin("tin", "tin_copper")
	p.adaptive = {"ema": .12, "samples": 5}
	p.campaign.attempts["r2"] = 7
	p.campaign.replay_wins["r1"] = 3
	p.save()
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	old.version = 2
	old.campaign.erase("stars")
	old.campaign.erase("star_claimed")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var q := ProfileStore.new(path, gm.catalog, gm.skins)
	q.load_data()
	check("v2_migration_preserves_every_profile_field", q.coins == 822 and q.owned.has("hopper") and q.selected == "hopper"
		and q.is_completed("r1") and q.is_unlocked("r2") and q.campaign.claimed.has("r1") and q.attempts_on("r2") == 7
		and q.replay_wins("r1") == 3 and q.owns_skin("tin_copper") and q.equipped_skin("tin") == "tin_copper"
		and int(q.adaptive.samples) == 5 and q.total_stars() == 0)
	var paid := q.earn_star("r1", 0, 20)
	q = ProfileStore.new(path, gm.catalog, gm.skins)
	q.load_data()
	check("immediate_persistence_and_current_version", paid.new and paid.paid == 20 and q.has_star("r1", 0) and q.loaded_version == ProfileStore.VERSION)
	q.earn_star("r1", 1, 25)
	q.earn_star("r1", 0, 999)
	check("separate_attempts_no_farming", q.stars_of("r1") == [true, true, false] and q.coins == 867 and q.total_stars() == 2)
	var copy := q.stars_of("r1")
	copy[0] = false
	check("ownership_accessor_cannot_remove_stars", q.has_star("r1", 0))
	check("invalid_ids_indices_refused", not q.earn_star("r101", 0, 20).new and not q.earn_star("r1", 3, 20).new and not q.earn_star("r01", 0, 20).new)
	q.earn_star("r2", 0, 20)
	check("stars_do_not_unlock_or_complete_campaign", not q.is_completed("r2") and not q.is_unlocked("r3"))
	q.complete("r3", ["r4"])
	check("victory_unlocks_without_stars", q.is_unlocked("r4") and q.stars_of("r3") == [false, false, false])
	old.campaign["stars"] = {"r1": [true, "bad", false]}
	old.campaign["star_claimed"] = {"r1": [false, false, true]}
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	q.load_data()
	check("repair_keeps_ownership_prevents_double_pay", q.stars_of("r1") == [true, false, true] and not q.earn_star("r1", 2, 999).new and q.coins == 822)
	var disk_fail := ProfileStore.new("res://not_a_directory/missing/profile.json", gm.catalog)
	# A directory occupying the save filename deterministically forces rename failure.
	disk_fail.path = "user://test/star_save_directory"
	DirAccess.make_dir_recursive_absolute(disk_fail.path)
	var result := disk_fail.earn_star("r1", 0, 20)
	check("failed_save_rolls_back_payment", not result.saved and disk_fail.coins == 0 and disk_fail.total_stars() == 0)

func integration() -> void:
	gm.go_menu()
	gm.profile.campaign = ProfileStore.default_campaign()
	gm.profile.ensure_campaign_start("r1")
	gm.node_id = "r1"
	gm.mode = &"campaign"
	at.call("start_seen_run")
	var corpse_test := tracker("BAD_LANDING_LIMIT", {"m": 30, "n": 1})
	corpse_test.attach(gm.robot)
	gm.robot.launched = true
	gm.robot.damage.rocket_fired = true
	gm.robot.contacts._event_active = true
	gm.robot.contacts._event = {"type": "body", "charge_ratio": 0.0}
	corpse_test._contact_pending = true
	corpse_test._contact_m = 20
	corpse_test.step(0.0, 30)
	check("jet_checkpoint_not_blocked_by_corpse_contact", corpse_test.status[0] == 1 and corpse_test.metrics().bad_m.size() == 1)
	corpse_test.stop()
	at.call("start_seen_run")
	var old_tracker := gm.star_tracker
	check("intro_shows_full_objectives", gm.ui.star_hud.visible and not gm.ui.star_hud.compact and gm.ui.star_hud.rows[0].text.contains(StarChallenges.describe(old_tracker.challenges[0])))
	# Drive the production completion signal, including its immediate disk write.
	old_tracker.sample(.1, 1000, 100000, false, false, 0)
	var reload := ProfileStore.new(gm.profile.path, gm.catalog)
	reload.load_data()
	check("live_completion_saved_before_result", reload.has_star("r1", 0) and gm.stars_new.has(0))
	var coins := gm.profile.coins
	at.call("start_seen_run")
	old_tracker.sample(.1, 2000, 200000, false, false, 0)
	check("retry_owned_and_old_source_disconnected", gm.star_tracker.owned[0] and not old_tracker.active and gm.profile.coins == coins and gm.stars_new.is_empty())
	gm._on_flick(Vector2.ZERO)
	gm.robot.spin_charge.charge = gm.spin_config.max_charge
	var captured: Array = []
	gm.robot.landed.connect(func(info: Dictionary) -> void: captured.append(info))
	var elapsed := 0.0
	while captured.is_empty() and elapsed < 8.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 120.0
	check("real_contact_carries_preconsumption_ratio", not captured.is_empty() and captured[0].has("charge_ratio") and float(captured[0].charge_ratio) > 0.0)
	check("flick_switches_to_compact_hud", gm.ui.star_hud.compact)
	gm.go_menu()
	gm.mode = &"free"
	at.call("start_seen_run")
	check("free_run_shared_optional_tracker_and_hud", gm.star_tracker != null and gm.ui.star_hud.visible and gm.ui.star_hud.free_mode and gm.star_tracker.challenges.size() == 3)
	gm.go_menu()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func layout() -> void:
	for width in [1280, 1680]:
		DisplayServer.window_set_size(Vector2i(width, 720))
		gm.ui.debug_safe_margins = Vector4(90, 0, 34, 0)
		gm.ui.apply_safe_area()
		await frames(8)
		gm.profile.ensure_campaign_start("r40")
		gm.open_campaign_map()
		await frames(8)
		var map := gm.ui.campaign_map
		var fits := true
		for id in gm.campaign.order:
			map.select_node(id)
			await frames(3)
			fits = fits and get_viewport().get_visible_rect().encloses(map._star_info.get_global_rect())
			fits = fits and not map._star_info.get_global_rect().intersects(map._start.get_global_rect())
		check("map_all_40_texts_fit_%d" % width, fits)
		if at.get("shots_dir") != "": at.call("_shot", "star_map_%d" % width)
		gm.node_id = "r40"
		gm.mode = &"campaign"
		at.call("start_seen_run")
		gm.hand.playing = false
		await frames(8)
		var hud := gm.ui.star_hud
		var screen := get_viewport().get_visible_rect()
		check("intro_star_hud_safe_area_%d" % width, screen.encloses(hud.get_global_rect()) and hud.position.y >= 206)
		if at.get("shots_dir") != "": at.call("_shot", "star_intro_%d" % width)
		hud.compact = true
		await frames(4)
		gm.ui.set_charge(1.0, true)
		gm.ui.set_charge(0.0)
		gm.ui.charge_bar.scale = Vector2(1.18, 1.18)
		check("charge_pulse_keeps_safe_margin_%d" % width, gm.ui.charge_bar.get_global_rect().position.x >= gm.ui.safe_margins.x)
		check("compact_hud_does_not_overlap_race_%d" % width, not hud.get_global_rect().intersects(gm.ui.race_hud._rows.get_global_rect()) and hud.size.y < 150)
		var result := gm.ui.campaign_result
		result.show_result({"won": true, "title": "Босс: Сёгун Судьбы", "player_m": 500,
			"enemies": [{"name": "Генерал Чугун", "m": 450, "color": Color.BLUE}, {"name": "Капитан Комета", "m": 400, "color": Color.RED}],
			"coins": 1500, "coins_kind": "first", "skin_name": "Сёгун", "has_next": true,
			"stars_before": [true, false, false], "stars_new": [1, 2], "star_coins": 200, "stars_total": 120})
		await get_tree().create_timer(.5).timeout
		check("largest_campaign_result_fits_%d" % width, screen.encloses(result._panel.get_global_rect()) and result._panel.get_global_rect().encloses(result._stars.get_global_rect()))
		if at.get("shots_dir") != "": at.call("_shot", "star_result_%d" % width)
		gm.go_menu()
	gm.ui.debug_safe_margins = Vector4(-1, -1, -1, -1)
	gm.ui.apply_safe_area()


## Re-evaluate archived physical runs with the final data. The last changed checkpoint
## is also replayed through a fresh StarTracker using its exact bad-contact sequence.
## Unchanged objectives retain and check the original live 120-objective tracker flags.
func audit_metrics() -> void:
	var args: Dictionary = at.get("args")
	var folder := String(args.get("audit_dir", ""))
	var historical: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("G:/Godot/EpicShalban/reports/v15_campaign_stars_before.json"))
	var errors := 0
	var runs := 0
	for file in DirAccess.get_files_at(folder):
		if not file.begins_with("shipped_") or not file.ends_with(".log"):
			continue
		for line in FileAccess.get_file_as_string(folder.path_join(file)).split("\n"):
			if not line.begins_with("AT|simrun "):
				continue
			var row: Dictionary = JSON.parse_string(line.substr(10))
			var metrics: Dictionary = row.metrics
			var ch: Dictionary = historical.r39[1]
			var replay := StarTracker.new([ch])
			for d in metrics.bad_m:
				replay.sample(0.0, float(d), 0.0, false, false, 0.0, true)
				replay.on_landed({"type": "body"})
			replay.sample(0.0, float(metrics.distance), 0.0, false, false, 0.0)
			var replayed: bool = replay.status[0] == 1
			if replayed != StarTracker.evaluate(ch, metrics):
				errors += 1
			var live: Array = row.live_status
			live[115] = replay.status[0]
			row["live_replayed"] = ["r39#2: m 220 -> 210, original physical bad-contact sequence"]
			var index := 0
			for id in gm.campaign.order:
				var outcomes := []
				for objective in historical[id]:
					var done := StarTracker.evaluate(objective, metrics)
					outcomes.append(done)
					if done != (live[index] == 1):
						errors += 1
					index += 1
				row.achieved[id] = outcomes
			print("AT|simrun " + JSON.stringify(row))
			runs += 1
	check("final_data_runtime_and_live_replay_agreement", runs == 160 and errors == 0)
	print("AT|audit runs=%d objective_comparisons=%d errors=%d" % [runs, runs * 120, errors])
