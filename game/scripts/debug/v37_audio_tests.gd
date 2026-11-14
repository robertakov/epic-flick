extends "res://scripts/debug/v36_tests.gd"
## v37 Samurobot audio vertical slice tests (debug only, not exported). Prints "AT|test v37_<name> PASS|FAIL".
##   --scenario=v37_audio   event coverage, intensity, anti-spam, rocket loop lifecycle, sound off, other robots untouched
## Determinism A/B (audio on/off must not change physics) uses --scenario=v36_one with/without --legacy_robot_audio.


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test v37_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func run_all(which: String) -> void:
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	await asset_tests()
	await landing_tests()
	await bounce_tests()
	await body_tests()
	await damage_tests()
	await death_rocket_tests()
	await v38_ui_tests()
	await v38_charge_npc_tests()
	await sound_off_tests()
	GameManager.set_sim_speed(1)
	print("AT|tests passed=%d failed=%d" % [passed, failed])


func fb(r: RobotController) -> RobotAudioFeedback:
	return r.get_node_or_null("AudioFeedback") as RobotAudioFeedback if is_instance_valid(r) else null


func events(r: RobotController) -> Array:
	var f := fb(r)
	return f.sound_set.fired.duplicate() if f and f.sound_set else []


func names(ev: Array) -> Array:
	return ev.map(func(e: Array) -> String: return String(e[0]))


# ---------------- assets / architecture ----------------

func asset_tests() -> void:
	var cfg := RobotSoundSet.config_for("samurai")
	var bank: Dictionary = gm.audio.bank.get("banks", {})
	var missing := []
	var clips := 0
	for ev in cfg.get("events", {}):
		var e: Dictionary = cfg.events[ev]
		var fams := [String(e.family)]
		for l in e.get("layers", []):
			fams.append(String(l.family))
		for fam in fams:
			if not bank.has(fam):
				missing.append(fam); continue
			for clip in bank[fam]:
				clips += 1
				if gm.audio.stream(clip) == null:
					missing.append(String(clip.path))
	check("samurai_set_assets_load", missing.is_empty() and clips >= 50, "clips %d missing %s" % [clips, missing])
	var variants := {}
	for fam in ["samurai_v37/spring", "samurai_v37/body", "samurai_v37/limb_lost", "samurai_v37/head_launch", "samurai_v37/launch", "samurai_v37/shout", "samurai_v37/head_impact"]:
		variants[fam] = (bank.get(fam, []) as Array).size()
	check("repeated_events_have_variants", variants.values().all(func(n: int) -> bool: return n >= 4), "%s" % [variants])
	var others := []
	for id in ["tin", "hopper", "heavy", "rocket"]:
		# v39 (legit update): every robot now has its own RobotSoundSet (personality sound design)
		if not RobotSoundSet.config_for(id).is_empty():
			others.append(id)
	check("all_robots_have_sound_sets", others.size() == 4, "%s" % [others])
	# every Samurobot family is a set of takes split from the MasterAudio files (source_s = start in the master)
	var not_master := []
	for fam in bank:
		if String(fam).begins_with("samurai_v37/"):
			for clip in bank[fam]:
				if not (clip as Dictionary).has("source_s"):
					not_master.append(String(clip.path))
	check("samurai_families_from_master", not_master.is_empty(), "%s" % [not_master])
	var fset := RobotSoundSet.config_for("samurai").get("families", {}) as Dictionary
	check("adapter_families_from_master", String(fset.get("launch", "")) == "samurai_v37/launch" and String(fset.get("rolling", "")) == "samurai_v37/head_rolling"
		and String(fset.get("voice", "")) == "samurai_v37/shout" and String(fset.get("energy", "")) == "v40/energy_release", "%s" % [fset])
	var r: RobotController = await start_robot("samurai", true)
	check("mk2_uses_samurai_set", fb(r) != null and fb(r).sound_set != null and fb(r).sound_set.robot_id == "samurai", "MK2 visual id %s" % r.config.visual_id)
	check("adapter_resolves_master_families", fb(r).family("launch") == "samurai_v37/launch" and fb(r).family("rolling") == "samurai_v37/head_rolling"
		and fb(r).family("energy") == "v40/energy_release", "%s %s %s" % [fb(r).family("launch"), fb(r).family("rolling"), fb(r).family("energy")])
	var t: RobotController = await start_robot("heavy", false)
	check("sumobot_own_set", fb(t) != null and fb(t).sound_set != null and fb(t).sound_set.robot_id == "heavy" and fb(t).family("rolling") == "v39/heavy_rolling")


# ---------------- landings ----------------

func landing_tests() -> void:
	var rows := {}
	for c in [["tiny", 6.0, 0.0], ["small", 60.0, 0.0], ["normal", 260.0, 0.0], ["hard", 1500.0, 0.0], ["charged", 260.0, 1.0]]:
		var d: Dictionary = await drop("samurai", false, c[1], c[2])
		var ev := events(gm.robot)
		rows[c[0]] = {"impact": snappedf(float(d.impact), 1), "type": d.type, "ev": names(ev), "level": ev[0][2] if ev.size() > 0 else 0.0}
	print("AT|v37 landings %s" % JSON.stringify(rows))
	check("tiny_landing_quiet_or_silent", rows.tiny.ev.is_empty() or (rows.tiny.ev[0] == "step" and float(rows.tiny.level) < 0.6), "%s" % [rows.tiny])
	check("small_landing_step", rows.small.ev.size() >= 1 and rows.small.ev[0] == "step", "%s" % [rows.small])
	check("normal_landing_land", rows.normal.ev.size() >= 1 and rows.normal.ev[0] == "land", "%s" % [rows.normal])
	check("hard_landing_louder", rows.hard.ev.size() >= 1 and rows.hard.ev[0] == "land" and float(rows.hard.level) > float(rows.normal.level), "%s" % [rows.hard])
	check("charged_landing_own_sound", rows.charged.ev.size() >= 1 and rows.charged.ev[0] == "charged", "%s" % [rows.charged])
	# step / land / charged all play the SpringBounce takes (same loudness): the level carries the impact
	check("intensity_rises_with_impact", float(rows.small.level) < float(rows.normal.level) and float(rows.normal.level) < float(rows.hard.level),
		"levels small %.2f normal %.2f hard %.2f" % [rows.small.level, rows.normal.level, rows.hard.level])


# ---------------- repeated bouncing / anti-spam ----------------

func bounce_tests() -> void:
	var r: RobotController = await start_robot("samurai", false)
	var x := flat_x(2600.0)
	r.global_position = Vector2(x, gm.terrain.surface_y(x) - 700.0)
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.damage.invulnerable_left = 99.0
	var landings := [0]
	r.landed.connect(func(_i: Dictionary) -> void: landings[0] += 1)
	var t0 := gm.audio.clock
	for i in 120 * 6:
		await get_tree().physics_frame
		if not is_instance_valid(r):
			break
		r.angular_velocity = 0.0
		r.rotation = 0.0
		r.linear_velocity.x = 0.0
	var f := fb(r)
	var ev := f.sound_set.fired if f and f.sound_set else []
	var dt := gm.audio.clock - t0
	var levels := ev.map(func(e: Array) -> float: return float(e[2]))
	print("AT|v37 bounce landings=%d sounds=%d suppressed=%d over %.1fs %s" % [landings[0], ev.size(), f.sound_set.suppressed, dt, ev])
	check("repeated_bounce_no_spam", ev.size() <= maxi(landings[0], 1) and ev.size() / maxf(dt, 0.1) <= 4.0,
		"%d sounds for %d landings in %.1f s (%d suppressed)" % [ev.size(), landings[0], dt, f.sound_set.suppressed])
	var ints := ev.map(func(e: Array) -> float: return float(e[1]))
	var follows := true
	for k in range(1, ev.size()):
		follows = follows and (float(levels[k]) > float(levels[k - 1])) == (float(ints[k]) > float(ints[k - 1]))
	check("repeated_bounce_level_follows_impact", follows, "intensity %s -> level %s" % [ints, levels])
	# unit: anti-spam channel (same key, within cooldown, not stronger) and break-through of a clearly stronger hit
	var s := f.sound_set
	s._last.clear(); s._repeat.clear(); s.fired.clear()
	var p := r.global_position
	var a := s.trigger("step", 300.0, p)
	var b := s.trigger("step", 320.0, p)          # same strength inside the 0.12 s window: dropped
	var c := s.trigger("land", 1700.0, p)         # much stronger on the same channel: plays
	check("cooldown_and_break_through", a and not b and c, "step %s, repeat %s, strong %s" % [a, b, c])
	# unit: the same hit repeated every 0.2 s (rapid chatter) gets quieter, then recovers after a pause
	s._last.clear(); s._repeat.clear(); s.fired.clear()
	var saved_clock := gm.audio.clock
	for k in 6:
		s.trigger("land", 1000.0, p)
		gm.audio.clock += 0.2
	gm.audio.clock += 1.0
	s.trigger("land", 1000.0, p)
	gm.audio.clock = saved_clock
	var lv := s.fired.map(func(e: Array) -> float: return float(e[2]))
	check("rapid_repeats_duck_then_recover", lv.size() == 7 and float(lv[4]) < float(lv[0]) * 0.6 and is_equal_approx(float(lv[6]), float(lv[0])),
		"levels %s" % [lv])


# ---------------- body ----------------

func _side_hit(speed: float) -> Array:
	var r: RobotController = await start_robot("samurai", false)
	var x := flat_x(2600.0)
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.damage.invulnerable_left = 99.0
	r.global_position = Vector2(x, gm.terrain.surface_y(x) - 140.0)
	r.rotation = PI * 0.5
	r.linear_velocity = Vector2(0, speed)
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(r):
			break
		if i < 30:
			r.rotation = PI * 0.5
			r.angular_velocity = 0.0
	return names(events(r))


func body_tests() -> void:
	var light := await _side_hit(700.0)
	var hard := await _side_hit(2600.0)
	print("AT|v37 body light=%s hard=%s" % [light, hard])
	check("body_collision_sound", light.has("body") or light.has("crash"), "%s" % [light])
	check("hard_body_escalates_to_crash", hard.has("crash"), "%s" % [hard])
	check("body_hit_single_response", light.count("body") + light.count("crash") <= 2, "%s" % [light])


# ---------------- limb damage / detach ----------------

func damage_tests() -> void:
	var r: RobotController = await start_robot("samurai", false)
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.damage.armed = true
	r.global_position += Vector2(0, -600)
	var lost := []
	r.limb_lost.connect(func(l: StringName, _p: RigidBody2D) -> void: lost.append(String(l)))
	var mh := r.damage.max_health
	r.damage.apply_external(mh * 0.2, &"feet", {"point": r.global_position, "normal": Vector2.UP}, false)
	await physics(4)
	var ev1 := names(events(r))
	r.damage.apply_external(mh * 0.45, &"feet", {"point": r.global_position, "normal": Vector2.UP}, false)
	await physics(6)
	var ev2 := names(events(r))
	print("AT|v37 damage first=%s then=%s lost=%s" % [ev1, ev2, lost])
	# no MasterAudio source exists for plain limb damage: the contact sound covers it, nothing is invented
	check("limb_damage_no_invented_sound", ev1.is_empty(), "%s" % [ev1])
	# one snap per detach moment: limbs breaking in the same step share one sound (no stacked identical hits)
	check("limb_detach_sound_no_stacking", lost.size() >= 1 and ev2.count("detach") >= 1 and ev2.count("detach") <= lost.size(),
		"detach sounds %d for lost %s" % [ev2.count("detach"), lost])
	check("no_death_while_alive", not ev2.has("death") and not ev2.has("ignite"), "%s" % [ev2])
	check("detach_uses_v39_armor_break", int(gm.audio.counts.get("v39/samurai_detach", 0)) >= 1)


# ---------------- death / head detach / rocket ----------------

func death_rocket_tests() -> void:
	var r: RobotController = await start_robot("samurai", false)
	var f := fb(r)
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.damage.armed = true
	r.global_position += Vector2(0, -500)
	var heads := []
	r.rocket_launched.connect(func(h: RigidBody2D) -> void: heads.append(h))
	r.damage.apply_external(r.damage.max_health * 3.0, &"electric", {"point": r.global_position, "normal": Vector2.UP}, false)
	var loop_key := f.owner_key + "flight"
	var burn_frames := 0
	var loop_while_burning := 0
	var loop_after := -1.0
	var burn_end := -1.0
	for i in 120 * 12:
		await get_tree().physics_frame
		if heads.is_empty():
			if i > 240: break
			continue
		var h := heads[0] as RocketHead
		if not is_instance_valid(h):
			break
		if h.burning and not h.done:
			burn_frames += 1
			loop_while_burning += int(gm.audio.loops.has(loop_key))
		elif burn_end < 0.0:
			burn_end = gm.audio.clock
		if burn_end >= 0.0 and gm.audio.loops.has(loop_key):
			loop_after = gm.audio.clock - burn_end
		if h.done and burn_end >= 0.0 and gm.audio.clock - burn_end > 1.0:
			break
	var ev := names(f.sound_set.fired) if is_instance_valid(f) else []
	print("AT|v37 death events=%s burn_frames=%d loop_frames=%d loop_tail=%.2fs" % [ev, burn_frames, loop_while_burning, loop_after])
	check("death_sound_once", ev.count("death") == 1, "%s" % [ev])
	check("head_detach_ignite_once", heads.size() == 1 and ev.count("ignite") == 1 and ev.find("death") < ev.find("ignite"), "%s" % [ev])
	check("destruction_detach_collapsed", ev.count("detach") == 1, "%d detach sounds for 4 limbs in one step" % ev.count("detach"))
	check("thrust_loop_follows_burn", burn_frames > 30 and loop_while_burning >= burn_frames - 2, "loop on %d of %d burning frames" % [loop_while_burning, burn_frames])
	check("thrust_stops_after_burn", burn_end >= 0.0 and loop_after < 0.5 and not gm.audio.loops.has(loop_key), "loop alive %.2f s after burn-out" % loop_after)
	check("no_burnout_one_shot", not ev.has("burnout"), "HeadFlight loop just fades (no master source for a burn-out sound)")
	check("thrust_and_ignite_from_master", int(gm.audio.counts.get("v39/samurai_ignite", 0)) >= 1 and gm.audio.bank.banks.has("samurai_v37/head_flight"))
	check("no_v27_samurai_shouts", int(gm.audio.counts.get("samurai/voice", 0)) == 0 and is_instance_valid(f) and f.family("voice") == "samurai_v37/shout",
		"v27 voice %d, voice family %s" % [int(gm.audio.counts.get("samurai/voice", 0)), f.family("voice") if is_instance_valid(f) else "?"])


# ---------------- v38 global UI / result / charge / NPC loudness ----------------

func v38_ui_tests() -> void:
	var a := gm.audio
	var bad := []
	var long_ui := []
	for ev in GameAudio.COMMON_EVENTS:
		if ev in ["energy", "flight", "wilhelm"]:
			continue
		var clips: Array = a.bank.banks.get("common/" + ev, [])
		if clips.is_empty():
			bad.append(ev); continue
		for c in clips:
			if not String(c.path).contains("/ui_v38/") or a.stream(c) == null:
				bad.append(String(c.path))
			if ev in ["click", "browse", "confirm", "back", "module_install", "module_remove", "countdown", "coin"] and float(c.duration) > 0.2:
				long_ui.append("%s %.2f" % [c.path, c.duration])
	check("v38_ui_events_resolve_new_set", bad.is_empty(), "%s" % [bad])
	check("v38_frequent_ui_very_short", long_ui.is_empty(), "%s" % [long_ui])
	var res_ok := true
	for ev in ["victory", "defeat", "record"]:
		var c: Array = a.bank.banks.get("common/" + ev, [])
		res_ok = res_ok and c.size() >= 1 and float(c[0].duration) <= 0.8
	check("v38_result_cues_short", res_ok)
	# real trigger paths still call the result cues
	var src := FileAccess.get_file_as_string("res://scripts/core/game_manager.gd")
	check("v38_result_trigger_paths", src.contains("audio.common(\"victory\" if won else \"defeat\")") and src.contains("audio.common(\"record\")"))
	var before := int(a.counts.get("common/victory", 0))
	a.cooldowns.erase("ui:victory")
	a.common("victory")
	check("v38_result_plays", int(a.counts.get("common/victory", 0)) == before + 1)
	# button presses: 50 rapid clicks never reuse the same variant twice in a row and never touch gameplay RNG
	seed(4242)
	var expect := randi()
	seed(4242)
	var last := -1
	var repeats := 0
	for i in 50:
		a.cooldowns.erase("ui:click")
		a.common("click")
		var idx := int(a.pools.get("common/click", -1))
		repeats += int(idx == last)
		last = idx
	check("v38_click_no_immediate_repeat", repeats == 0, "%d immediate repeats" % repeats)
	check("v38_audio_rng_private", randi() == expect, "global RNG untouched by 50 UI sounds")


func v38_charge_npc_tests() -> void:
	# player: charge hum loop while airborne + charging; follows the charge; no crackle ticks any more
	var r: RobotController = await start_robot("samurai", false)
	var f := fb(r)
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.damage.invulnerable_left = 99.0
	r.global_position += Vector2(0, -900)
	var energy_before := int(gm.audio.counts.get(f.family("energy"), 0))
	r.spin_charge.charge = 0.2 * r.spin_charge.cfg.max_charge
	await physics(30)
	# v40 (legit update): charge accumulation has NO loop any more (sparse discharges, see v39_audio_tests)
	var key := f.owner_key + "charge"
	var loop_low := gm.audio.loops.has(key) or gm.audio.loops.has(f.owner_key + "charge_hi")
	r.spin_charge.charge = r.spin_charge.cfg.max_charge
	await physics(30)
	var loop_high := gm.audio.loops.has(key) or gm.audio.loops.has(f.owner_key + "charge_hi")
	var hum_family := ""
	check("v38_charge_no_loop", not loop_low and not loop_high, "loop at 20 %% %s, at 100 %% %s" % [loop_low, loop_high])
	check("v38_charge_no_ticks", int(gm.audio.counts.get(f.family("energy"), 0)) == energy_before, "energy one-shots while charging: %d" % (int(gm.audio.counts.get(f.family("energy"), 0)) - energy_before))
	var played: bool = gm.audio.bank.banks.has("common/charge_hum")
	check("v38_charge_hum_asset", played and gm.audio.stream(gm.audio.bank.banks["common/charge_hum"][0]) != null, hum_family)
	# NPC: the same flight loop is ~-22 dB under the player's
	var p_target := await _head_flight_target(true)
	var n_target := await _head_flight_target(false)
	check("v38_npc_flight_much_quieter", p_target > 0.0 and n_target > 0.0 and n_target <= p_target * 0.1,
		"player %.3f npc %.4f (%.1f dB)" % [p_target, n_target, 20.0 * log(maxf(n_target, 1e-6) / maxf(p_target, 1e-6)) / log(10.0)])
	var nr: RobotController = await start_robot("samurai", false)
	fb(nr).is_player = false
	nr.spin_charge.charge = nr.spin_charge.cfg.max_charge
	nr.launch(Vector2.ZERO, 0.0)
	nr.global_position += Vector2(0, -900)
	await physics(30)
	check("v38_npc_no_charge_hum", not gm.audio.loops.has(fb(nr).owner_key + "charge"))


func _head_flight_target(player: bool) -> float:
	var r: RobotController = await start_robot("samurai", false)
	var f := fb(r)
	f.is_player = player
	gm.audio.listener = null       # no distance attenuation: compare the gain alone
	r.launch(Vector2.ZERO, 0.0)
	r.damage.armed = true
	r.global_position += Vector2(0, -500)
	r.damage.apply_external(r.damage.max_health * 3.0, &"electric", {"point": r.global_position, "normal": Vector2.UP}, false)
	var best := 0.0
	for i in 120 * 2:
		await get_tree().physics_frame
		if gm.audio.loops.has(f.owner_key + "flight"):
			best = maxf(best, float(gm.audio.loops[f.owner_key + "flight"].target))
	return best


# ---------------- sound off ----------------

func sound_off_tests() -> void:
	gm.ui.sfx_volume_changed.emit(0.0)
	var sfx := AudioServer.get_bus_index("SFX")
	var robot_bus := AudioServer.get_bus_index("Robot")
	var routed := AudioServer.get_bus_send(robot_bus) == &"SFX"
	check("sound_off_mutes_robot_audio", AudioServer.is_bus_mute(sfx) and routed, "SFX muted %s, Robot -> %s" % [AudioServer.is_bus_mute(sfx), AudioServer.get_bus_send(robot_bus)])
	gm.ui.sfx_volume_changed.emit(75.0)
	check("sound_on_restores", not AudioServer.is_bus_mute(sfx))
