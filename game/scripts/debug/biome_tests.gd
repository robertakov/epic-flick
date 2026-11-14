extends Node
## v30 biome tests (debug only, not exported).
##   --scenario=biome_all  : campaign distribution, intro rules / skip / timers, physics modifiers, portals, chasms,
##                           cavern ceiling, anomalies, challenge adjustments, baseline restore
##   --scenario=biome_qa   : visual QA screenshots of every biome (title card + gameplay), needs --shots and -Window
##   --scenario=biome_sim  : calibration: bot runs per biome (distance, chasm deaths, ceiling hits)
## Prints "AT|test biome_<name> PASS|FAIL <details>".
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const SPECIALS := ["moon", "heavy", "chocolate", "jelly", "portal", "chasms", "cavern", "zone"]


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test biome_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run_all(which: String) -> void:
	at.set("max_time", 1.0e9)
	match which:
		"biome_qa":
			await qa()
		"biome_sim":
			await sim()
		"biome_perf":
			await perf()
		_:
			at.set("scenario_running", true)
			campaign_distribution()
			challenges()
			await intro_rules()
			await physics_tests()
			await portals()
			await chasms()
			await cavern()
			await anomalies()
			await ai_in_biomes()
			await baseline_restore()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ---------------- campaign ----------------

func campaign_distribution() -> void:
	var c := gm.campaign
	var seq: Array = []
	for id in c.order:
		seq.append(String(c.node(id).biome))
	var first15 := seq.slice(0, 15).all(func(b: String) -> bool: return b == "green_hills")
	check("r1_r15_green", first15)
	check("r16_moon", seq[15] == "moon", "r16=%s" % seq[15])
	var specials: Array = []
	var gaps: Array = []
	var last := 15
	for i in range(16, seq.size()):
		if seq[i] != "green_hills":
			specials.append(seq[i])
			gaps.append(i - last - 1)
			last = i
	var gaps_ok := gaps.all(func(g: int) -> bool: return g >= 2 and g <= 5)
	var mean := 0.0
	for g in gaps:
		mean += g
	mean /= maxf(gaps.size(), 1)
	check("special_spacing_3_to_4", gaps_ok and mean >= 3.0 and mean <= 4.2, "gaps=%s mean=%.2f" % [gaps, mean])
	var periodic := true
	for i in range(3, gaps.size()):
		periodic = periodic and gaps[i] == gaps[i - 1] and gaps[i - 1] == gaps[i - 2]
	check("spacing_not_periodic", not periodic and not _all_same(gaps))
	var all_seq := ["moon"] + specials
	var rep_ok := true
	for i in range(1, all_seq.size()):
		rep_ok = rep_ok and all_seq[i] != all_seq[i - 1]
		if i >= 2:
			rep_ok = rep_ok and all_seq[i] != all_seq[i - 2]
	check("special_anti_repetition", rep_ok, "%s" % [all_seq])
	var used := {}
	for b in all_seq:
		used[b] = true
	check("all_special_biomes_used", SPECIALS.all(func(b: String) -> bool: return used.has(b)), "%s" % [used.keys()])
	var green := seq.count("green_hills")
	check("green_majority", green >= int(seq.size() * 0.7), "green=%d/%d" % [green, seq.size()])
	var again := CampaignData.load_file(gm.campaign_path)
	var same := true
	for id in c.order:
		same = same and again.node(id).biome == c.node(id).biome and str(again.node(id).stars) == str(c.node(id).stars)
	check("deterministic_reload", same)
	print("AT|biomes %s" % [seq])


static func _all_same(a: Array) -> bool:
	for x in a:
		if x != a[0]:
			return false
	return true


func challenges() -> void:
	var c := gm.campaign
	var ok := true
	var bad := []
	var types := {}
	var green_same := true
	var changed := 0
	for id in c.order:
		var n := c.node(id)
		for i in 3:
			var ch: Dictionary = n.stars[i]
			var base: Dictionary = n.stars_base[i]
			types[String(ch.type)] = true
			if StarChallenges.validate(ch) != "":
				bad.append("%s:%s" % [id, StarChallenges.validate(ch)])
			if ch.type == "NO_TOUCH_AND_WIN" and not is_equal_approx(float(ch.s), 3.5):
				bad.append(id + " no_touch")
			if ch.type == "MAX_HEIGHT_M" and float(ch.m) > 30.0:
				bad.append(id + " height")
			if ch.type == "SPEED_TARGET" and float(ch.kmh) > 100.0:
				bad.append(id + " speed")
			if n.biome == "green_hills":
				green_same = green_same and str(ch) == str(base)
			elif str(ch) != str(base):
				changed += 1
	check("adjusted_stars_valid_and_capped", bad.is_empty(), "%s" % [bad])
	check("removed_types_absent", not types.has("FINISH_WITHIN_ENEMY") and not types.has("KEEP_ENEMY_IN_VIEW"))
	check("green_rounds_unchanged", green_same)
	check("special_rounds_adjusted", changed > 0, "changed=%d" % changed)
	# explicit per-rule checks
	var h := BiomeChallenges.adjust({"type": "MAX_HEIGHT_M", "m": 26, "reward": 10}, "moon")
	var hc := BiomeChallenges.adjust({"type": "MAX_HEIGHT_M", "m": 26, "reward": 10}, "cavern")
	var sp := BiomeChallenges.adjust({"type": "SPEED_TARGET", "kmh": 95, "reward": 10}, "heavy")
	var nt := BiomeChallenges.adjust({"type": "NO_TOUCH_AND_WIN", "s": 3.5, "reward": 10}, "moon")
	var air := BiomeChallenges.adjust({"type": "AIR_TIME", "s": 2.0, "reward": 10}, "heavy")
	# v36: data-driven rules - Cavern height capped by the narrowest ceiling section (8 m), Supergravity air x0.6
	check("rule_examples", float(h.m) == 30.0 and float(hc.m) <= 8.0 and float(sp.kmh) == 100.0 and float(nt.s) == 3.5 and is_equal_approx(float(air.s), 1.2),
		"moon height %s cavern height %s heavy speed %s air %s" % [h.m, hc.m, sp.kmh, air.s])


# ---------------- intro ----------------

func _start_free(biome_id: String) -> void:
	gm.go_menu()
	await frames(2)
	gm.mode = &"free"
	gm.debug_biome = biome_id
	gm.start_run()


func intro_rules() -> void:
	var bi := gm.ui.biome_intro
	bi.instant = true
	# campaign r1: Green Hills title; r2: none; r16: Moon title
	var counts := []
	for id in ["r1", "r2", "r16"]:
		gm.go_menu(); await frames(2)
		gm.mode = &"campaign"; gm.node_id = id
		gm.profile.ensure_campaign_start(id)
		var before := gm.biome_intros_shown
		gm.start_run()
		if gm.ui.awareness.visible: gm.ui.awareness.confirm.pressed.emit()
		await frames(3)
		counts.append(gm.biome_intros_shown - before)
	check("green_title_only_r1", counts[0] == 1 and counts[1] == 0, "r1=%d r2=%d" % [counts[0], counts[1]])
	check("special_title_every_time", counts[2] == 1 and gm.biome.id == "moon")
	# replay r16: same biome again
	gm.start_run()
	if gm.ui.awareness.visible: gm.ui.awareness.confirm.pressed.emit()
	await frames(3)
	check("replay_same_biome", gm.biome.id == "moon")
	# real duration + timers frozen
	bi.instant = false
	await _start_free("jelly")
	var secs := 0.0
	var dur0 := gm.attempt.duration_s
	var why := ""
	while bi.active and secs < 4.0:
		await get_tree().process_frame
		secs += get_process_delta_time()      # game time (the harness runs with a fixed 120 Hz step)
		if not bi.active:
			break                             # card over: the flick legitimately starts now
		if gm.state != GameManager.State.INTRO: why = "state"
		if not gm.robot.freeze: why = "robot moving"
		if gm.attempt.duration_s != dur0: why = "attempt timer"
		if gm.ui.flick_bar and gm.ui.flick_bar.active: why = "flick bar running"
		if gm.hand.playing: why = "hand playing"
	check("intro_about_2s", secs > 1.8 and secs < 2.3, "%.2fs" % secs)
	check("intro_freezes_gameplay", why == "", why)
	# tap skip: consumed, never reaches gameplay
	await _start_free("moon")
	await frames(10)
	var taps := [0]
	var cb := func() -> void: taps[0] += 1
	gm.input.tapped.connect(cb)
	var center := get_viewport().get_visible_rect().size * 0.5
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = center; press.global_position = center
	Input.parse_input_event(press)
	await frames(3)
	var during_hold := gm.input.holding
	var rel := press.duplicate(); rel.pressed = false
	Input.parse_input_event(rel)
	await frames(4)
	gm.input.tapped.disconnect(cb)
	var bar_locked := gm.ui.flick_bar != null and gm.ui.flick_bar.locked
	check("tap_skips_intro", not bi.active and not bi.blocking(), "active=%s" % bi.active)
	check("skip_tap_consumed", taps[0] == 0 and not during_hold and not gm.input.holding and not bar_locked,
		"taps=%d hold=%s bar_locked=%s" % [taps[0], during_hold, bar_locked])
	check("gameplay_starts_after_skip", gm.state == GameManager.State.INTRO and gm.ui.flick_bar != null and gm.ui.flick_bar.active)
	bi.instant = true


# ---------------- physics ----------------

func _space_gravity() -> float:
	return float(PhysicsServer2D.area_get_param(get_viewport().world_2d.space, PhysicsServer2D.AREA_PARAM_GRAVITY))


func _fall_accel() -> float:
	var b := RigidBody2D.new()
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new(); sh.radius = 5
	cs.shape = sh; b.add_child(cs)
	b.collision_layer = 0; b.collision_mask = 0
	b.position = Vector2(-5000, -50000)
	gm.add_child(b)
	await physics(4)
	var v0 := b.linear_velocity.y
	await physics(60)
	var a := (b.linear_velocity.y - v0) / 0.5
	b.queue_free()
	return a


func physics_tests() -> void:
	await _start_free("moon")
	var gm_moon := _space_gravity()
	var a_moon := await _fall_accel()
	await _start_free("heavy")
	var gm_heavy := _space_gravity()
	var a_heavy := await _fall_accel()
	await _start_free("")
	var a_green := await _fall_accel()
	# measured on a real falling body (project default damping applies equally in every biome -> compare ratios)
	check("moon_gravity", is_equal_approx(gm_moon, 810.0) and absf(a_moon / a_green - 0.45) < 0.02, "space %.0f measured %.0f (x%.3f)" % [gm_moon, a_moon, a_moon / a_green])
	check("heavy_gravity", is_equal_approx(gm_heavy, 2880.0) and absf(a_heavy / a_green - 1.6) < 0.04, "space %.0f measured %.0f (x%.3f)" % [gm_heavy, a_heavy, a_heavy / a_green])
	check("green_gravity_baseline", a_green > 1700.0 and is_equal_approx(_space_gravity(), 1800.0), "measured %.0f" % a_green)
	# real drop landings: jelly vs green release speed (same robot, same track seed, same height, same spot)
	gm.debug_track_seed = 424242
	# restart explicitly: _drop_release only restarts when the biome differs, which would keep the previous
	# (random-seed) Green Hills track and compare jelly against a different spot
	await _start_free("")
	var g_out := await _drop_release("")
	var j_out := await _drop_release("jelly")
	gm.debug_track_seed = -1
	check("jelly_stronger_rebound", j_out > g_out * 1.25 and j_out < g_out * 2.0 and is_finite(j_out), "green %.0f jelly %.0f" % [g_out, j_out])
	# chocolate: pool contact slows / sticks but always releases, dirt appears and cleans off
	gm.debug_track_seed = 424242
	await _start_free("chocolate")
	gm.terrain.ensure_ahead(20000.0)
	# the flattest pool centre (a steep pool makes the drop slide off before it settles)
	var cx := 0.0
	var best_slope := 9.0
	for pool in gm.terrain.chocolate_pools:
		var px := (float(pool[0]) + float(pool[1])) * 0.5
		var sl := absf(gm.terrain.normal_at(px).x)
		if sl < best_slope:
			best_slope = sl
			cx = px
	# same track, same spot, pools temporarily removed (chocolate pools do not change the terrain geometry)
	var pools: Array = gm.terrain.chocolate_pools
	gm.terrain.chocolate_pools = []
	var g_same := await _drop_release("chocolate", cx)
	gm.terrain.chocolate_pools = pools
	await physics(30)
	var c_out := await _drop_release("chocolate", cx)
	var dirt := gm.hazards.dirt_of(gm.robot)
	check("chocolate_resists_but_releases", c_out > 0.0 and c_out < g_same * 0.9 and c_out >= BiomeRuntime.CHOCO_MIN_EXIT * 0.9,
		"same spot green %.0f chocolate %.0f" % [g_same, c_out])
	check("chocolate_dirt_on_contact", dirt > 0.05, "dirt=%.2f" % dirt)
	var st: Dictionary = gm.hazards._state.get(gm.robot.get_instance_id(), {})
	st["dirt"] = 1.0
	# float the robot in the air (no contact at all) and let the dirt wear off
	gm.robot.gravity_scale = 0.0
	gm.robot.linear_velocity = Vector2.ZERO
	gm.robot.global_position.y -= 2000.0
	await physics(int(120 * 6.5))
	gm.robot.gravity_scale = 1.0
	check("chocolate_dirt_cleans_off", gm.hazards.dirt_of(gm.robot) < 0.05 and gm.robot.visual.modulate.is_equal_approx(gm.robot.get_meta("base_modulate")),
		"dirt=%.2f" % gm.hazards.dirt_of(gm.robot))
	# heavy world: weaker rebound for the same drop
	var h_out := await _drop_release("heavy")
	check("heavy_weaker_rebound_factor", is_equal_approx(BiomeRuntime.current().feet_rebound, 0.86) and h_out > 0.0)
	gm.debug_track_seed = -1


## Drops the player robot upright from 380 px onto the track and returns the release speed of the first landing.
func _drop_release(biome_id: String, x := -1.0) -> float:
	if gm.biome.id != (biome_id if biome_id != "" else "green_hills"):
		await _start_free(biome_id)
	await frames(2)
	var r := gm.robot
	gm.state = GameManager.State.RUN
	gm.hand.playing = false
	var px := x if x > 0.0 else 2600.0
	# a flat-ish place: search for a small slope
	if x <= 0.0:
		for k in 200:
			var nx := 2400.0 + k * 40.0
			if absf(gm.terrain.normal_at(nx).x) < 0.12 and gm.terrain.gap_index(nx) < 0:
				px = nx
				break
	r.global_position = Vector2(px, gm.terrain.surface_y(px) - 380.0)
	r.rotation = 0.0
	r.launch(Vector2.ZERO, 0.0)
	r.angular_velocity = 0.0
	var out := [0.0]
	var cb := func(info: Dictionary) -> void:
		if out[0] == 0.0 and String(info.type) in ["left", "right", "both"]:
			out[0] = (info.velocity_out as Vector2).dot(info.normal)
	r.landed.connect(cb)
	for i in 240:
		await get_tree().physics_frame
		r.angular_velocity = 0.0
		if out[0] != 0.0:
			break
	if r.landed.is_connected(cb):
		r.landed.disconnect(cb)
	return out[0]


# ---------------- portals ----------------

func portals() -> void:
	await _start_free("portal")
	await physics(10)
	gm.terrain.ensure_ahead(30000.0)
	await physics(4)
	var hz := gm.hazards
	check("portals_generated", hz.portals.size() >= 6, "n=%d" % hz.portals.size())
	var self_exit := false
	for i in hz.portals.size():
		for k in 30:
			var d := hz.choose_destination(i)
			self_exit = self_exit or d == i
	check("never_exit_from_entrance", not self_exit)
	var clearance_ok := true
	for p in hz.portals:
		for o in [-90.0, 0.0, 90.0]:
			clearance_ok = clearance_ok and gm.terrain.surface_y(float(p.pos.x) + o) - float(p.pos.y) >= 229.0
	check("portal_exits_clear_of_terrain", clearance_ok)
	# real teleport of the robot through the first portal
	var r := gm.robot
	gm.state = GameManager.State.RUN
	r.launch(Vector2(900, -100), 0.0)
	# v36: portals are one-way pairs - use the first ENTRY portal (exits never capture)
	var ein := 0
	while ein < hz.portals.size() and int(hz.portals[ein].partner) < 0:
		ein += 1
	var entry: Vector2 = hz.portals[ein].pos
	r.global_position = entry
	r.linear_velocity = Vector2(1100, 200)
	var n0 := hz.teleports
	await physics(2)
	var tp := hz.last_teleport
	var moved := hz.teleports == n0 + 1 and int(tp.get("from", -1)) == ein and int(tp.get("to", -1)) != ein
	var speed_ok := absf((tp.get("vel", Vector2.ZERO) as Vector2).length() - Vector2(1100, 200).length()) < 1.0
	check("teleport_moves_body", moved and r.global_position.distance_to(hz.portals[int(tp.get("to", 0))].pos) < 120.0, "%s" % [tp])
	check("teleport_keeps_speed_aims_exit", speed_ok and (tp.vel as Vector2).normalized().dot(hz.portals[int(tp.to)].dir) > 0.99)
	# no loop: the robot sits in the exit portal for several steps, nothing fires
	var n1 := hz.teleports
	for i in 30:
		r.global_position = hz.portals[int(tp.to)].pos
		await get_tree().physics_frame
	check("no_teleport_loop", hz.teleports == n1, "extra=%d" % (hz.teleports - n1))
	check("robot_not_duplicated", gm.dynamic.get_children().filter(func(c: Node) -> bool: return c is RobotController).size() == 1)


# ---------------- chasms ----------------

func chasms() -> void:
	await _start_free("chasms")
	gm.terrain.ensure_ahead(40000.0)
	var t := gm.terrain
	check("gaps_generated", t.gaps.size() >= 6, "n=%d" % t.gaps.size())
	var worst := 99.0
	for g in t.gaps:
		var w := float(g[1]) - float(g[0])
		var drop := float(g[3]) - float(g[2])
		# slowest considered approach 550 px/s, robot half-width 90 px, real gravity
		var reach := 550.0 * sqrt(2.0 * maxf(drop, 0.0) / 1800.0) + 90.0
		worst = minf(worst, reach / w)
	check("gaps_traversable", worst >= 1.0, "worst reach/width=%.2f" % worst)
	var solid_in_gap := false
	await physics(2)    # newly built chunks must be in the physics space before ray queries
	for g in t.gaps:
		var q := PhysicsRayQueryParameters2D.create(Vector2((float(g[0]) + float(g[1])) * 0.5, float(g[2]) - 50.0),
			Vector2((float(g[0]) + float(g[1])) * 0.5, float(g[3]) + 3000.0), 1)
		var hit := get_viewport().world_2d.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			solid_in_gap = true
			print("AT|gaphit gap=%s hit=%s collider=%s" % [g, hit.position, (hit.collider as Node).get_path()])
			for c in (hit.collider as Node).get_children():
				if c is CollisionPolygon2D:
					var pp: PackedVector2Array = (c as CollisionPolygon2D).polygon
					print("AT|gappoly n=%d %s" % [pp.size(), pp])
	await physics(2)
	check("gaps_have_no_collision", not solid_in_gap)
	# falling deep into a gap ends the run as a failure
	var g0: Array = t.gaps[0]
	var r := gm.robot
	gm.state = GameManager.State.RUN
	r.launch(Vector2.ZERO, 0.0)
	r.global_position = Vector2((float(g0[0]) + float(g0[1])) * 0.5, maxf(float(g0[2]), float(g0[3])) + TerrainBuilder.GAP_FALL + 40.0)
	await physics(3)
	check("chasm_fall_ends_run", gm.state == GameManager.State.RESULT and gm._end_reason == "Упал в пропасть", "state=%d reason=%s" % [gm.state, gm._end_reason])


# ---------------- cavern ----------------

func cavern() -> void:
	await _start_free("cavern")
	gm.terrain.ensure_ahead(30000.0)
	await physics(3)
	var t := gm.terrain
	var min_clear := INF
	var x := -500.0
	while x < 30000.0:
		min_clear = minf(min_clear, t.surface_y(x) - t.ceiling_y(x))
		x += 37.0
	check("ceiling_above_terrain", min_clear >= TerrainBuilder.CEIL_MIN - 1.0, "min clearance %.0f" % min_clear)
	# the ceiling is real geometry in the ground group
	var probe := Vector2(5000.0, t.surface_y(5000.0) - 200.0)
	var q := PhysicsRayQueryParameters2D.create(probe, probe + Vector2(0, -4000), 1)
	var hit := get_viewport().world_2d.direct_space_state.intersect_ray(q)
	var grp := not hit.is_empty() and (hit.collider as Node).is_in_group(&"ground")
	check("ceiling_is_collision", grp and absf(float(hit.position.y) - t.ceiling_y(5000.0)) < 130.0, "%s" % [hit.get("position", "none")])
	# a robot thrown hard upward hits it and takes NORMAL collision damage
	var r := gm.robot
	gm.state = GameManager.State.RUN
	r.launch(Vector2.ZERO, 0.0)
	r.damage.armed = true
	# v36.5: the old ground-relative throw cannot reach some v36 ceiling halls.
	# Checkpoint/current 20-seed comparison: identical misses in 10/20; ceiling-relative hits 20/20.
	r.global_position = Vector2(5000.0, t.ceiling_y(5000.0) + 400.0)
	r.rotation = PI     # head first
	r.linear_velocity = Vector2(0, -2600)
	var hp0 := r.damage.health
	for i in 120:
		await get_tree().physics_frame
		if r.damage.health < hp0:
			break
	check("ceiling_hit_normal_damage", r.damage.health < hp0, "hp %.0f -> %.0f" % [hp0, r.damage.health])


# ---------------- anomalies ----------------

func anomalies() -> void:
	await _start_free("zone")
	gm.terrain.ensure_ahead(40000.0)
	await physics(4)
	var hz := gm.hazards
	var kinds := {}
	for a in hz.anomalies:
		kinds[String(a.kind)] = true
	check("three_anomaly_kinds", kinds.size() == 3, "%s n=%d" % [kinds.keys(), hz.anomalies.size()])
	var r := gm.robot
	gm.state = GameManager.State.RUN
	r.launch(Vector2.ZERO, 0.0)
	r.damage.armed = true
	r.freeze = true
	var find := func(k: String) -> Dictionary:
		for a in hz.anomalies:
			if a.kind == k:
				return a
		return {}
	# electric
	var e: Dictionary = find.call("electric")
	var hp0 := r.damage.health
	var st: Dictionary = {"cool": 0.0, "exit": -1, "inside": {}, "rad": 0.0, "rad_tick": 0.0, "dirt": 0.0, "was_contact": true}
	r.global_position = e.pos
	hz.step_anomalies(r, st, 1.0 / 120.0)
	var dmg_e := hp0 - r.damage.health
	hz.step_anomalies(r, st, 1.0 / 120.0)
	check("electric_damages_once_per_entry", is_equal_approx(dmg_e, BiomeHazards.ELECTRIC_DMG) and is_equal_approx(hp0 - r.damage.health, dmg_e),
		"damage %.0f" % dmg_e)
	# radiation: entry dose, damage over time inside and for 1.5 s after leaving, then nothing
	var rd: Dictionary = find.call("radiation")
	st = {"cool": 0.0, "exit": -1, "inside": {}, "rad": 0.0, "rad_tick": 0.0, "dirt": 0.0, "was_contact": true}
	r.damage.debug_set_health(r.damage.max_health)
	var h1 := r.damage.health
	r.global_position = rd.pos
	for i in 120:
		hz.step_anomalies(r, st, 1.0 / 120.0)
	var inside_dmg := h1 - r.damage.health
	r.global_position = rd.pos + Vector2(0, -2000)
	var h2 := r.damage.health
	for i in 240:
		hz.step_anomalies(r, st, 1.0 / 120.0)
	var after := h2 - r.damage.health
	check("radiation_dose_and_linger", absf(inside_dmg - (BiomeHazards.RAD_ENTRY + BiomeHazards.RAD_DPS)) < 3.5 and after > 5.0 and after < 12.0,
		"inside 1s %.1f, after-exposure %.1f" % [inside_dmg, after])
	# gravity: from below -> up, from above -> down
	var gv: Dictionary = find.call("gravity")
	r.freeze = false
	st = {"cool": 0.0, "exit": -1, "inside": {}, "rad": 0.0, "rad_tick": 0.0, "dirt": 0.0, "was_contact": true}
	r.global_position = gv.pos + Vector2(0, 40)
	r.linear_velocity = Vector2(500, -300)
	hz.step_anomalies(r, st, 1.0 / 120.0)
	var up := r.linear_velocity.y
	st = {"cool": 0.0, "exit": -1, "inside": {}, "rad": 0.0, "rad_tick": 0.0, "dirt": 0.0, "was_contact": true}
	r.global_position = gv.pos + Vector2(0, -40)
	r.linear_velocity = Vector2(500, 300)
	hz.step_anomalies(r, st, 1.0 / 120.0)
	var down := r.linear_velocity.y
	check("gravity_anomaly_from_below_up", is_equal_approx(up, -BiomeHazards.GRAV_SPEED), "vy=%.0f" % up)
	check("gravity_anomaly_from_above_down", is_equal_approx(down, BiomeHazards.GRAV_SPEED), "vy=%.0f" % down)


# ---------------- baseline ----------------

func baseline_restore() -> void:
	await _start_free("jelly")
	await physics(5)
	gm.go_menu()
	await physics(5)
	var mat_ok := true
	for ch in gm.terrain.get_children():
		for b in ch.get_children():
			if b is StaticBody2D and (b as StaticBody2D).physics_material_override:
				mat_ok = mat_ok and is_zero_approx((b as StaticBody2D).physics_material_override.bounce)
	check("menu_restores_baseline", BiomeRuntime.id() == "green_hills" and gm.terrain.biome.id == "green_hills" and is_equal_approx(_space_gravity(), 1800.0)
		and mat_ok and gm.hazards.portals.is_empty() and gm.hazards.anomalies.is_empty() and gm.terrain.gaps.is_empty())
	check("baseline_modifiers_neutral", is_equal_approx(BiomeRuntime.feet_release(1000.0), 1.0) and BiomeRuntime.surface_at(1000.0) == &"normal")
	gm.debug_biome = ""


# ---------------- AI opponents ----------------

## A real campaign race in every special biome: the opponents launch, stay finite, make progress and are subject to
## the same biome (gravity / hazards act on their pieces through GameManager._active_bodies()).
func ai_in_biomes() -> void:
	gm.ui.biome_intro.instant = true
	var report := []
	var ok := true
	for b in SPECIALS:
		var node_id := ""
		for id in gm.campaign.order:
			if String(gm.campaign.node(id).biome) == b:
				node_id = id
				break
		if node_id == "":
			ok = false
			report.append("%s:no-node" % b)
			continue
		gm.go_menu(); await frames(2)
		gm.mode = &"campaign"; gm.node_id = node_id
		gm.profile.ensure_campaign_start(node_id)
		gm.start_run()
		if gm.ui.awareness.visible: gm.ui.awareness.confirm.pressed.emit()
		await frames(3)
		gm.hand.rush()
		var in_hazards := false
		for i in 120 * 14:
			await get_tree().physics_frame
			if not in_hazards:
				for c in gm.race.competitors:
					if c.piece() in gm._active_bodies():
						in_hazards = true
		var best := 0.0
		var finite := true
		for c in gm.race.competitors:
			best = maxf(best, c.distance)
			var p := c.piece() as Node2D
			if p != null and is_instance_valid(p):
				finite = finite and is_finite(p.global_position.x) and is_finite(p.global_position.y)
		var good: bool = gm.race.competitors.size() > 0 and best > 15.0 and finite and in_hazards and BiomeRuntime.id() == b
		ok = ok and good
		report.append("%s(%s):%dm%s" % [b, node_id, int(best), "" if good else "!"])
	check("ai_opponents_run_in_every_biome", ok, str(report))
	gm.go_menu(); await frames(2)


# ---------------- visual QA ----------------

func _shot(n: String) -> void:
	at.call("_shot", n)


func qa() -> void:
	at.set("scenario_running", false)
	for id in ["green_hills"] + SPECIALS:
		gm.ui.biome_intro.instant = false
		await _start_free("" if id == "green_hills" else id)
		if id != "green_hills":
			await get_tree().create_timer(0.75).timeout
			_shot("bq_title_" + id)
			gm.ui.biome_intro._end(true)
		await get_tree().create_timer(0.6).timeout
		gm.hand.rush()
		await get_tree().create_timer(1.6).timeout
		_shot("bq_start_" + id)
		for k in 3:
			await get_tree().create_timer(2.2).timeout
			if gm.state == GameManager.State.RESULT:
				break
			_shot("bq_run%d_%s" % [k, id])
		# feature close-ups: camera on a portal / anomaly / gap / pool
		var target := Vector2.INF
		match id:
			"portal":
				if gm.hazards.portals.size() > 1: target = gm.hazards.portals[1].pos
			"zone":
				if gm.hazards.anomalies.size() > 2: target = gm.hazards.anomalies[2].pos
			"chasms":
				if gm.terrain.gaps.size() > 0: target = Vector2(gm.terrain.gaps[0][0], gm.terrain.gaps[0][2])
			"chocolate":
				if gm.terrain.chocolate_pools.size() > 0: target = Vector2(gm.terrain.chocolate_pools[0][0], gm.terrain.surface_y(gm.terrain.chocolate_pools[0][0]))
		if target != Vector2.INF:
			at.set("scenario_running", true)
			gm.camera.target = null
			gm.camera.global_position = target
			gm.camera.zoom = Vector2(0.55, 0.55)
			await frames(6)
			_shot("bq_feature_" + id)
			at.set("scenario_running", false)
	gm.ui.biome_intro.instant = true


# ---------------- performance ----------------

## Per biome: a real bot run of ~10 s (game time), sampling CPU frame cost, draw calls, rendered objects, node count
## and the worst chunk build time (the streaming hitch). Relative numbers: compare specials against Green Hills.
func perf() -> void:
	at.set("scenario_running", false)
	gm.ui.biome_intro.instant = true
	for id in ["green_hills"] + SPECIALS:
		gm.debug_track_seed = 777
		await _start_free("" if id == "green_hills" else id)
		gm.hand.rush()
		var n := 0
		var cpu := 0.0
		var cpu_max := 0.0
		var draws := 0.0
		var draws_max := 0.0
		var objs := 0.0
		var nodes_max := 0.0
		var chunk_max := 0.0
		for i in 600:
			await get_tree().process_frame
			if i < 60:
				continue
			var c := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
			var d := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			n += 1
			cpu += c
			cpu_max = maxf(cpu_max, c)
			draws += d
			draws_max = maxf(draws_max, d)
			objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			nodes_max = maxf(nodes_max, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			chunk_max = maxf(chunk_max, gm.terrain.last_chunk_usec / 1000.0)
		print("AT|bperf %-12s cpu_ms avg=%.2f max=%.2f draws avg=%.0f max=%.0f objects=%.0f nodes_max=%.0f chunk_build_max_ms=%.2f" %
			[id, cpu / n, cpu_max, draws / n, draws_max, objs / n, nodes_max, chunk_max])
	gm.debug_track_seed = -1
	check("perf_done", true)


# ---------------- calibration sim ----------------

func sim() -> void:
	at.set("scenario_running", false)
	var ids := ["green_hills", "chasms", "cavern", "moon", "heavy", "jelly", "chocolate", "portal", "zone"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim_biomes="):
			ids = Array(a.substr(13).split(","))
	for id in ids:
		var dists: Array[float] = []
		var reasons := {}
		var ceiling_hits := 0
		var apexes := 0
		for robot_id in ["tin", "hopper", "heavy", "rocket", "samurai"]:
			for s in 2:
				if not gm.profile.owned.has(robot_id):
					gm.profile.owned.append(robot_id)
				gm.profile.select(robot_id)
				await _start_free("" if id == "green_hills" else id)
				gm.hand.rush()
				var t := 0.0
				var was_up := false
				var hit_log := [0, 0, -1.0]   # all damage hits, hits near the ceiling, distance of the first ceiling hit
				if is_instance_valid(gm.robot):
					var rb := gm.robot
					rb.damage.damage_applied.connect(func(_amt: float, _c: StringName, _hp: float, _info: Dictionary) -> void:
						hit_log[0] += 1
						if gm.biome.ceiling and rb.global_position.y - gm.terrain.ceiling_y(rb.global_position.x) < 260.0:
							hit_log[1] += 1
							if hit_log[2] < 0.0: hit_log[2] = gm.distance_m)
				while gm.state != GameManager.State.RESULT and t < 60.0:
					await get_tree().physics_frame
					t += 1.0 / 120.0
					if id == "cavern" and gm.state == GameManager.State.RUN and is_instance_valid(gm.robot):
						var r := gm.robot
						var top := r.global_position.y - 120.0
						var near := top - gm.terrain.ceiling_y(r.global_position.x) < 30.0
						if near and not was_up:
							ceiling_hits += 1
						was_up = near
						if r.contacts.any_contact and r.linear_velocity.y < -200.0:
							apexes += 1
				dists.append(gm.distance_m)
				print("AT|bsimrun %s %s d=%.0f hits=%d ceil_hits=%d first_ceil_m=%.0f" % [id, robot_id, gm.distance_m, hit_log[0], hit_log[1], hit_log[2]])
				reasons[gm._end_reason] = int(reasons.get(gm._end_reason, 0)) + 1
		dists.sort()
		var mean := 0.0
		for d in dists:
			mean += d
		mean /= dists.size()
		print("AT|bsim %s mean=%.0f median=%.0f min=%.0f max=%.0f reasons=%s ceiling_hits=%d" % [id, mean, dists[dists.size() / 2], dists[0], dists[-1], reasons, ceiling_hits])
	check("sim_done", true)
