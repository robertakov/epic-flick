extends Node
## v27 tests (debug only, not exported):
##   --scenario=v27_all : campaign caps, NO_TOUCH_AND_WIN, removed challenge types, Wilhelm trigger, audio bank,
##                        five PNG-modular robots (incl. rebuilt Samurobot) + visual QA captures
##   --scenario=v27_qa  : visual QA captures only (menu / gameplay / airborne / limb loss / head-only for all five)
## Prints "AT|test v27_<name> PASS|FAIL" and "AT|qa <shot> <x> <y>" (robot screen position, for cropping).
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const IDS := ["tin", "hopper", "heavy", "rocket", "samurai"]


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test v27_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run_all(which: String) -> void:
	at.set("scenario_running", true); at.set("max_time", 1.0e9)
	if which != "v27_qa":
		campaign_caps()
		wilhelm_logic()
		audio_bank()
		robots_art()
	await visual_qa()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ---------------- campaign challenge hard caps ----------------
func campaign_caps() -> void:
	var c := gm.campaign
	check("campaign_loaded", c.load_error == "" and c.order.size() == 100, "error='%s' rounds=%d" % [c.load_error, c.order.size()])
	var heights := []
	var speeds := []
	var no_touch := []
	var types := {}
	for id in c.order:
		for ch in c.node(id).get("stars", []):
			var t := String(ch.type)
			types[t] = true
			if t == "MAX_HEIGHT_M":
				heights.append(float(ch.m))
			elif t == "SPEED_TARGET":
				speeds.append(float(ch.kmh))
			elif t == "NO_TOUCH_AND_WIN":
				no_touch.append(float(ch.s))
	var hmax: float = heights.max() if not heights.is_empty() else 0.0
	var smax: float = speeds.max() if not speeds.is_empty() else 0.0
	check("height_cap_30m", not heights.is_empty() and hmax <= 30.0, "MAX_HEIGHT_M values=%s" % [heights])
	check("speed_cap_100", not speeds.is_empty() and smax <= 100.0, "SPEED_TARGET values=%s" % [speeds])
	check("cap_constants", is_equal_approx(StarChallenges.MAX_HEIGHT_CAP_M, 30.0) and is_equal_approx(StarChallenges.SPEED_CAP_KMH, 100.0))
	check("validator_rejects_height_31", StarChallenges.validate({"type": "MAX_HEIGHT_M", "m": 31, "reward": 10}) != ""
		and StarChallenges.validate({"type": "MAX_HEIGHT_M", "m": 30, "reward": 10}) == "")
	check("validator_rejects_speed_101", StarChallenges.validate({"type": "SPEED_TARGET", "kmh": 101, "reward": 10}) != ""
		and StarChallenges.validate({"type": "SPEED_TARGET", "kmh": 100, "reward": 10}) == "")
	check("no_touch_and_win_3_5s", not no_touch.is_empty() and no_touch.all(func(v: float) -> bool: return is_equal_approx(v, 3.5))
		and StarChallenges.validate({"type": "NO_TOUCH_AND_WIN", "s": 4.0, "reward": 10}) != "", "values=%s" % [no_touch])
	for removed in ["FINISH_WITHIN_ENEMY", "KEEP_ENEMY_IN_VIEW"]:
		check("removed_" + removed, not types.has(removed) and not StarChallenges.TYPES.has(removed)
			and StarChallenges.validate({"type": removed, "m": 10, "s": 3, "reward": 10}) != "")
	# a stars.json carrying an over-cap value is refused by the loader (caps cannot sneak back in through data)
	var bad := CampaignData.new()
	bad.from_dict({"start": "r1", "nodes": [{"id": "r1", "type": "race", "next": []}]})
	var path := "user://test/v27_bad_stars.json"
	DirAccess.make_dir_recursive_absolute("user://test")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"r1": [{"type": "DISTANCE", "m": 50, "reward": 5}, {"type": "TOTAL_GOOD_LANDINGS", "n": 3, "reward": 5},
		{"type": "MAX_HEIGHT_M", "m": 40, "reward": 5}]}))
	f.close()
	bad.load_stars(path)
	check("loader_rejects_over_cap", bad.load_error != "", "error='%s'" % bad.load_error)


# ---------------- Wilhelm (pure trigger) ----------------
func wilhelm_logic() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 2727
	var t := WilhelmTrigger.new()
	t.probability = 1.0
	var plays := 0
	for i in 1200:   # 10 s above 30 m: one roll only
		plays += int(t.step(30.0 + 10.0 * sin(i * .05), rng))
	check("wilhelm_one_roll_per_climb", t.rolls == 1 and plays == 1)
	for alt in [28.0, 24.0, 21.0, 33.0]:
		t.step(alt, rng)
	check("wilhelm_no_reroll_above_rearm", t.rolls == 1)
	t.step(19.0, rng); t.step(30.5, rng)
	check("wilhelm_rearms_after_descent", t.rolls == 2)
	check("wilhelm_altitude_formula", is_equal_approx(WilhelmTrigger.altitude_m(1000.0, -2000.0, 100.0), 30.0))
	t.reset(); t.probability = WilhelmTrigger.PROBABILITY
	check("wilhelm_ignores_nan", not t.step(NAN, rng) and t.rolls == 2)


# ---------------- audio bank ----------------
func audio_bank() -> void:
	var a := gm.audio
	var b: Dictionary = a.bank
	check("bank_version", String(b.get("audio_version", "")) == "v27_sourced_physical_redesign")
	var missing := []
	var ogg_refs := 0
	var clips := 0
	var long_transients := []
	for fam in b.banks:
		for c in b.banks[fam]:
			clips += 1
			if not ResourceLoader.exists(String(c.path)):
				missing.append(c.path)
			if String(c.path).ends_with(".ogg"):
				ogg_refs += 1
			# v37: MasterAudio takes keep their natural length (head launch 2-4.7 s, multi-hit crash 2.4-2.9 s)
			if not bool(c.loop) and float(c.duration) > 1.85 and not String(fam).begins_with("samurai_v37/"):
				long_transients.append("%s %.2f" % [c.path, c.duration])
	check("bank_all_resolve", missing.is_empty(), "missing=%s" % [missing])
	check("bank_no_stale_ogg", ogg_refs == 0)
	check("bank_no_long_transients", long_transients.is_empty(), "%s" % [long_transients])
	# v37 (legit update): + 11 Samurobot sound-set families split from MasterAudio (samurai_v37/*, tools/audio/build_robot_sound_sets.py); v38 + common/charge_hum (build_ui_sounds.py); v39 + 46 robot/energy/portal families (build_v39_sound_design.py); v40 + 6 energy discharge families (build_energy_v40.py)
	check("bank_size", b.banks.size() == 125 and clips >= 630, "families=%d clips=%d" % [b.banks.size(), clips])
	# every runtime event resolves to a playable family for every robot
	var unresolved := []
	for id in IDS:
		for ev in ["launch", "spring", "body", "head", "limb", "voice", "head_launch", "rolling", "energy", "flight", "wilhelm"]:
			var fam := a.resolve(id, ev)
			if fam == "" or not b.banks.has(fam) or a.stream(a.choose(fam)) == null:
				unresolved.append(id + ":" + ev)
	for ev in GameAudio.COMMON_EVENTS:
		if a.stream(a.choose("common/" + ev)) == null:
			unresolved.append("common:" + ev)
	check("events_resolve", unresolved.is_empty(), "%s" % [unresolved])
	# robot identities are distinct sample sets (no shared files between robots)
	var shared := 0
	for ev in ["launch", "spring", "body", "head", "limb", "voice", "head_launch"]:
		var seen := {}
		for id in IDS:
			for c in b.banks[id + "/" + ev]:
				shared += int(seen.has(c.path)); seen[c.path] = true
	check("robot_banks_distinct", shared == 0)
	check("wilhelm_bank_constants", is_equal_approx(float(b.get("wilhelm_height_m", 0)), 30.0) and is_equal_approx(float(b.get("wilhelm_probability", 0)), .07))
	var loops_ok := true
	for fam in ["tin/rolling", "samurai/rolling", "common/flight"]:
		var s := a.stream(b.banks[fam][0])
		loops_ok = loops_ok and s is AudioStreamWAV and bool(b.banks[fam][0].loop)
	check("loops_are_wav_flagged", loops_ok)


# ---------------- robot art ----------------
func robots_art() -> void:
	for id in IDS:
		var prof := RobotArtLibrary.visual_profile(id)
		var mf := RobotArtLibrary.manifest(id)
		var parts_ok := true
		for p in ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]:
			parts_ok = parts_ok and mf.get("parts", {}).has(p) and RobotArtLibrary.atlas(id, p) != null
		check(id + "_png_modular_parts", prof.get("png_modular", false) and parts_ok)
		check(id + "_seven_faces", int(mf.parts.head.count) == 7)
		var def := gm.catalog.get_by_id(id)
		check(id + "_display_name", def != null and def.display_name == {"tin": "Растабот", "hopper": "Кенгуробот", "heavy": "Сумобот",
			"rocket": "Хронобот", "samurai": "Самуробот"}[id], def.display_name if def else "")
	# gameplay numbers of every archetype unchanged by the art pass (physics signature of the base configs)
	var samurai := gm.catalog.get_by_id("samurai")
	var cfgs := samurai.make_configs(gm.robot_config, gm.contact_config, gm.damage_config)
	check("samurai_stats_unchanged", is_equal_approx(cfgs.damage.max_health, 155.0), "max_health=%s" % cfgs.damage.max_health)


# ---------------- visual QA ----------------
func _qa_shot(name: String, node: Node) -> void:
	await frames(2)
	var p := Vector2.ZERO
	if node is Node2D and is_instance_valid(node):
		p = (node as Node2D).get_global_transform_with_canvas().origin
	elif node is Control and is_instance_valid(node):
		p = (node as Control).get_global_rect().get_center()
	print("AT|qa %s %d %d" % [name, int(p.x), int(p.y)])
	at.call("_shot", name)


func visual_qa() -> void:
	for id in IDS:
		if not gm.profile.owned.has(id):
			gm.profile.owned.append(id)
		gm.profile.select(id)
		gm.go_menu(); gm._refresh_menu_robot(); await frames(40)
		await _qa_shot("v27_menu_" + id, gm.ui.menu_robot_preview)
		gm.open_robot_select(); await frames(40)
		await _qa_shot("v27_select_" + id, gm.ui.robot_select)
		gm._close_select(); await frames(2)
		gm.mode = &"free"
		at.call("start_seen_run"); await frames(5)
		gm.hand.playing = false
		var r := gm.robot
		r.freeze = true; await frames(3)
		await _qa_shot("v27_stand_" + id, r)
		r.freeze = false
		gm._on_flick(Vector2.ZERO)
		for k in 60:
			await get_tree().physics_frame
		r.freeze = true
		await _qa_shot("v27_air_" + id, r)
		r.rotation += 2.2; await frames(2)
		await _qa_shot("v27_spin_" + id, r)
		var info := {"event": 2727, "impact": 1000.0, "point": r.global_position, "normal": Vector2.UP}
		r._on_limb_lost(&"arm_r", info); await frames(6)
		r._on_limb_lost(&"leg_l", info); await frames(6)
		await _qa_shot("v27_damaged_" + id, r)
		r._launch_rocket(info); await frames(75)   # past the launch BOOM effect: the flying head itself
		await _qa_shot("v27_head_" + id, gm.rocket if is_instance_valid(gm.rocket) else r)
		gm.go_menu(); await frames(3)
