extends "res://scripts/debug/v37_audio_tests.gd"
## v39 complete robot sound design tests (debug only, not exported). Prints "AT|test v39_<name> PASS|FAIL".
##   --scenario=v39_audio   five robot sets resolve, personality events, energy build/full/discharge, Chronobot
##                          thruster lifecycle, rival gain, portal cue, loop budget priority, audio RNG isolation


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test v39_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func run_all(_which: String) -> void:
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	sets_tests()
	await landing_identity_tests()
	await takeoff_tests()
	await energy_tests()
	await lifecycle_tests()
	await thruster_tests()
	await rival_gain_tests()
	await portal_tests_v39()
	loop_budget_tests()
	rng_tests()
	GameManager.set_sim_speed(1)
	print("AT|tests passed=%d failed=%d" % [passed, failed])


func sets_tests() -> void:
	var a := gm.audio
	var bank: Dictionary = a.bank.banks
	var missing := []
	var own := {}
	var shared_paths := 0
	for id in IDS:
		var cfg := RobotSoundSet.config_for(id)
		if cfg.is_empty():
			missing.append(id + ":no set"); continue
		var fams := []
		for ev in cfg.events:
			fams.append(String(cfg.events[ev].family))
			for l in cfg.events[ev].get("layers", []):
				fams.append(String(l.family))
		for k in cfg.get("families", {}):
			fams.append(String(cfg.families[k]))
		for fam in fams:
			if not bank.has(fam):
				missing.append(id + ":" + fam); continue
			for clip in bank[fam]:
				if a.stream(clip) == null:
					missing.append(String(clip.path))
		# identity: each robot's own land / body / detach files are its own
		for ev in ["land", "body", "detach"]:
			for clip in bank.get("v39/%s_%s" % [id, ev], []):
				shared_paths += int(own.has(clip.path)); own[clip.path] = id
	check("five_sets_resolve_and_load", missing.is_empty(), "%s" % [missing])
	check("robot_families_not_shared", shared_paths == 0 and own.size() >= 5 * 3 * 4, "%d files" % own.size())
	var long_one_shots := []
	for fam in bank:
		if String(fam).begins_with("v39/"):
			for c in bank[fam]:
				if not bool(c.loop) and float(c.duration) > 1.7:
					long_one_shots.append("%s %.2f" % [c.path, c.duration])
	check("v39_one_shots_bounded", long_one_shots.is_empty(), "%s" % [long_one_shots])
	check("electric_anomaly_untouched", bank.has("common/anomaly_electric") and String(bank["common/anomaly_electric"][0].path).contains("/common/"))
	check("ui_v38_untouched", String(bank["common/click"][0].path).contains("/ui_v38/") and String(bank["common/victory"][0].path).contains("/ui_v38/"))


func landing_identity_tests() -> void:
	var rows := {}
	for id in IDS:
		var before := int(gm.audio.counts.get("v39/%s_land" % id, 0))
		var d: Dictionary = await drop(id, false, 260.0, 0.0)
		rows[id] = {"ev": names(events(gm.robot)), "own_family": int(gm.audio.counts.get("v39/%s_land" % id, 0)) - before, "impact": int(d.impact)}
	var ok := true
	for id in rows:
		# Chronobot's boot thruster puffs on touchdown (visible exhaust), so its land can follow a thrust_burst
		ok = ok and rows[id].ev.count("land") == 1 and int(rows[id].own_family) == 1
	check("each_robot_lands_with_own_sound", ok, JSON.stringify(rows))


func takeoff_tests() -> void:
	var got := {}
	for id in IDS:
		var r: RobotController = await start_robot(id, false)
		r.launch(Vector2(1100, -900), 0.0)
		await frames(4)
		got[id] = names(events(r)).count("takeoff")
	check("takeoff_gesture_once_per_launch", got.values().all(func(n: int) -> bool: return n == 1), "%s" % [got])


func _air_robot(id: String) -> RobotController:
	var r: RobotController = await start_robot(id, false)
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.damage.invulnerable_left = 99.0
	r.global_position += Vector2(0, -1600)
	r.gravity_scale = 0.0          # test only: keep it airborne (no landing may spend the charge / fire a thruster)
	r.linear_velocity = Vector2.ZERO
	return r


func energy_tests() -> void:
	# v40 (APK v36.7): sparse electrical discharges, no loop; one completion event per fill
	var r: RobotController = await _air_robot("tin")
	var f := fb(r)
	var fams: Array = RobotAudioFeedback.SPARK_FAMILIES
	var count := func() -> int:
		var n := 0
		for fam in fams:
			n += int(gm.audio.counts.get(fam, 0))
		return n
	# curves: silent below 20 % and at 100 %, interval shortens, level rises strongly non-linearly
	var iv := []
	var lv := []
	for c in [0.1, 0.3, 0.5, 0.75, 0.9, 0.98, 1.0]:
		iv.append(snappedf(RobotAudioFeedback.spark_interval(c), 0.01))
		lv.append(snappedf(RobotAudioFeedback.spark_level(c), 0.001))
	var mono_i := true
	for k in range(2, 6):
		mono_i = mono_i and float(iv[k]) < float(iv[k - 1])
	var mono_l := true
	for k in range(2, 6):
		mono_l = mono_l and float(lv[k]) > float(lv[k - 1])
	check("spark_curves", iv[0] == INF and iv[6] == INF and mono_i and mono_l and float(lv[1]) < 0.06 and float(lv[2]) < 0.2 and float(lv[5]) > 0.7,
		"interval %s level %s" % [iv, lv])
	check("spark_tiers", RobotAudioFeedback.spark_family(0.3, 0.5) == "v40/charge_micro" and RobotAudioFeedback.spark_family(0.6, 0.5) == "v40/charge_crackle"
		and RobotAudioFeedback.spark_family(0.85, 0.5) == "v40/charge_snap" and RobotAudioFeedback.spark_family(0.97, 0.5) == "v40/charge_nearfull")
	# real scheduler, 20 simulated seconds per charge level (direct steps: deterministic, private audio RNG)
	var rate := {}
	for c in [0.1, 0.3, 0.6, 0.9, 0.98, 1.0]:
		f.spark_t = -1.0
		var n0: int = count.call()
		for i in 120 * 20:
			f.spark_step(c, true, 1.0 / 120.0, r.global_position)
		rate[c] = count.call() - n0
	check("low_charge_silent", int(rate[0.1]) == 0 and int(rate[0.3]) <= 6, "%s" % [rate])
	check("frequency_rises_with_charge", int(rate[0.3]) < int(rate[0.6]) and int(rate[0.6]) < int(rate[0.9]) and int(rate[0.9]) < int(rate[0.98]), "%s" % [rate])
	check("full_charge_no_spam", int(rate[1.0]) == 0, "%s" % [rate])
	f.spark_t = -1.0
	var n1: int = count.call()
	for i in 120 * 20:
		f.spark_step(0.9, false, 1.0 / 120.0, r.global_position)     # on the ground / not eligible
	check("no_sparks_when_not_eligible", count.call() == n1)
	# never a fixed rhythm: intervals of one level vary
	f.spark_t = -1.0
	var times := []
	var tt := 0.0
	for i in 120 * 30:
		tt += 1.0 / 120.0
		if f.spark_step(0.8, true, 1.0 / 120.0, r.global_position):
			times.append(tt)
	var gaps := []
	for k in range(1, times.size()):
		gaps.append(times[k] - times[k - 1])
	var spread: float = (gaps.max() - gaps.min()) if gaps.size() > 2 else 0.0
	check("spark_timing_random", gaps.size() >= 8 and spread > 0.5, "%d gaps, spread %.2f s" % [gaps.size(), spread])
	# full cue: once per fill; a repeated full signal without the charge falling below 90 % gives nothing;
	# the real way out of 100 % (consume on landing) re-arms it
	var full0 := int(gm.audio.counts.get("v40/energy_full", 0))
	r.spin_charge.fill()
	await physics(4)
	f.full_charge()                       # same fill, signal again (e.g. anomaly while already full)
	r.spin_charge.fill()
	await physics(4)
	var once := int(gm.audio.counts.get("v40/energy_full", 0)) - full0
	r.spin_charge.consume(&"feet")        # charge spent -> below 90 % -> re-armed by the feedback
	await physics(4)
	gm.audio.cooldowns.erase(f.owner_key + "charge_full")
	r.spin_charge.fill()
	await physics(4)
	var twice := int(gm.audio.counts.get("v40/energy_full", 0)) - full0
	check("full_cue_once_per_fill", once == 1 and twice == 2, "same fill: %d, after consume + refill: %d" % [once, twice])
	# no loop of any kind for the charge, at any level
	var loops := 0
	for k in gm.audio.loops:
		loops += int(String(k).begins_with(f.owner_key + "charge"))
	check("no_charge_loop", loops == 0 and not gm.audio.bank.banks.has("v40/charge_loop"))
	# release scales with stored charge
	var rel := "v40/energy_release"
	var c0 := int(gm.audio.counts.get(rel, 0))
	f.discharge(0.25)
	gm.audio.cooldowns.erase(f.owner_key + "discharge")
	f.discharge(0.95)
	check("discharge_v40_family", f.family("energy") == rel and int(gm.audio.counts.get(rel, 0)) >= c0 + 2)
	check("electric_anomaly_unchanged", String(gm.audio.bank.banks["common/anomaly_electric"][0].path) == "res://assets/audio/common/anomaly_electric_01.wav")


func lifecycle_tests() -> void:
	# energy audio leaves nothing behind across restart / menu (one-shots only; no owner loops survive)
	var r: RobotController = await _air_robot("samurai")
	var f := fb(r)
	r.spin_charge.charge = 0.9 * r.spin_charge.cfg.max_charge
	for i in 240:
		await get_tree().physics_frame
	var key := f.owner_key
	gm.go_menu()
	await frames(10)
	var left := 0
	for k in gm.audio.loops:
		left += int(String(k).begins_with(key))
	check("energy_nothing_after_menu", left == 0, "%d owner loops" % left)
	var r2: RobotController = await start_robot("samurai", false)
	check("energy_fresh_after_restart", fb(r2).spark_t == -1.0 and fb(r2).full_armed)
	var sparks := func() -> int:
		var n := 0
		for fam in RobotAudioFeedback.SPARK_FAMILIES:
			n += int(gm.audio.counts.get(fam, 0))
		return n
	# discharge: charge spent on landing -> scheduler resets, nothing more fires
	var r3: RobotController = await _air_robot("tin")
	var f3 := fb(r3)
	r3.spin_charge.charge = 0.9 * r3.spin_charge.cfg.max_charge
	await physics(240)
	var armed_before := f3.spark_t >= 0.0
	r3.spin_charge.consume(&"feet")
	await physics(4)
	var s0: int = sparks.call()
	await physics(360)
	check("energy_reset_on_discharge", armed_before and f3.spark_t == -1.0 and sparks.call() == s0, "armed %s, t %.2f" % [armed_before, f3.spark_t])
	# death: rocket-head phase -> no charge sparks at all (even with a charge value forced back in)
	r3.damage.armed = true
	r3.damage.apply_external(r3.damage.max_health * 3.0, &"electric", {"point": r3.global_position, "normal": Vector2.UP}, false)
	await physics(30)
	r3.spin_charge.charge = 0.95 * r3.spin_charge.cfg.max_charge
	var s1: int = sparks.call()
	await physics(360)
	check("energy_silent_after_death", sparks.call() == s1, "%d sparks in rocket phase" % (sparks.call() - s1))
	# Continue: a NEW body is built; the old feedback dies with the old body, the new one starts fresh
	var r4: RobotController = await _air_robot("hopper")
	var f4 := fb(r4)
	r4.spin_charge.charge = 0.9 * r4.spin_charge.cfg.max_charge
	await physics(120)
	var old_key := f4.owner_key
	gm._respawn_after_continue()
	await frames(6)
	var left4 := 0
	for k in gm.audio.loops:
		left4 += int(String(k).begins_with(old_key))
	var nf := fb(gm.robot)
	check("energy_fresh_after_continue", not is_instance_valid(f4) and left4 == 0 and nf != null and nf.spark_t == -1.0 and nf.full_armed and gm.robot != r4,
		"old alive %s, loops %d" % [is_instance_valid(f4), left4])


func thruster_tests() -> void:
	var r: RobotController = await _air_robot("rocket")
	var f := fb(r)
	f.sound_set.fired.clear()
	r.visual.identity.thrust_flash(0.9, 0.6)
	var loop_seen := false
	for i in 30:
		await get_tree().process_frame
		for side in r.visual.legs:
			loop_seen = loop_seen or gm.audio.loops.has(f.owner_key + "leg:" + String(side))
	var bursts := names(f.sound_set.fired).count("thrust_burst")
	await physics(150)
	var alive := 0
	for side in r.visual.legs:
		alive += int(gm.audio.loops.has(f.owner_key + "leg:" + String(side)))
	check("chrono_thruster_burst_once", bursts == 1, "%d bursts" % bursts)
	check("chrono_thruster_loop_follows_exhaust", loop_seen and alive == 0, "seen %s, alive after %d" % [loop_seen, alive])
	var s: RobotController = await _air_robot("samurai")
	check("no_thruster_sound_without_exhaust", names(events(s)).count("thrust_burst") == 0)


func rival_gain_tests() -> void:
	var r: RobotController = await start_robot("heavy", false)
	var mine := fb(r)
	var rival := RobotAudioFeedback.new()
	rival.setup(r, gm.audio, gm.terrain)
	rival.is_player = false
	rival.owner_key = "rival_test:"
	rival.sound_set.owner_key = "rival_test:"
	r.add_child(rival)
	await frames(1)
	mine.sound_set._last.clear(); rival.sound_set._last.clear()
	mine.sound_set.trigger("land", 1200.0, r.global_position)
	rival.sound_set.trigger("land", 1200.0, r.global_position)
	var lp: float = mine.sound_set.fired[-1][2]
	var lr: float = rival.sound_set.fired[-1][2]
	check("rival_one_shots_quieter", lr <= lp * 0.35 and lr > 0.0, "player %.3f rival %.3f" % [lp, lr])
	var full0 := int(gm.audio.counts.get("v39/energy_full", 0))
	rival.full_charge()
	check("rival_no_full_charge_cue", int(gm.audio.counts.get("v39/energy_full", 0)) == full0)
	rival.queue_free()


func portal_tests_v39() -> void:
	var r: RobotController = await start_robot("tin", false)
	gm.audio.cooldowns.erase("portal_warp")
	var c0 := int(gm.audio.counts.get("v39/portal_warp", 0))
	gm.hazards.teleported.emit(r)
	var c1 := int(gm.audio.counts.get("v39/portal_warp", 0))
	var other := RigidBody2D.new()
	gm.dynamic.add_child(other)
	gm.audio.cooldowns.erase("portal_warp")
	gm.hazards.teleported.emit(other)
	var c2 := int(gm.audio.counts.get("v39/portal_warp", 0))
	other.queue_free()
	check("portal_cue_player_only", c1 == c0 + 1 and c2 == c1, "%d %d %d" % [c0, c1, c2])


func loop_budget_tests() -> void:
	var a := gm.audio
	for k in a.loops.keys():
		a.loops[k].player.queue_free()
	a.loops.clear()
	for i in 8:
		a.loop_target("npc_test_%d" % i, "v39/tin_rolling", 0.5, Vector2.INF, RobotAudioFeedback.NPC_LOOP_GAIN)
	var npc := a.loops.size()
	a.loop_target("player_test_charge", "v39/tin_rolling", 0.6, Vector2.INF, 1.0)
	check("loop_budget_reserves_player", npc == GameAudio.MAX_LOOPS - 3 and a.loops.has("player_test_charge"), "npc loops %d" % npc)
	for k in a.loops.keys():
		a.loops[k].player.queue_free()
	a.loops.clear()


func rng_tests() -> void:
	seed(777)
	var expect := randi()
	seed(777)
	var s: RobotSoundSet = RobotSoundSet.for_robot("rocket", gm.audio, "rng_test:")
	for i in 30:
		s._last.clear()
		s.trigger("land", 900.0 + i * 20.0, Vector2.INF)
	check("audio_rng_isolated", randi() == expect and s.fired.size() == 30, "%d sounds" % s.fired.size())
