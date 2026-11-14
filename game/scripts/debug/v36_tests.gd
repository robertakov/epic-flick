extends Node
## v36 post-MK2 fix / polish tests (debug only, not exported). Prints "AT|test v36_<name> PASS|FAIL <details>".
##   --scenario=v36_all   focused tests of every v36 change
##   --scenario=v36_ff    fast-forward 1x vs accelerated A/B physics comparison (also part of v36_all, smaller)
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
var trace_ids: Array = []
var traj_log := false
var cm_log := false
const IDS := ["tin", "hopper", "heavy", "rocket", "samurai"]


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test v36_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run_all(which: String) -> void:
	TerrainBuilder.debug_legacy_ceiling = (at.get("args") as Dictionary).has("legacy_ceiling")
	RobotSoundSet.debug_disabled = (at.get("args") as Dictionary).has("legacy_robot_audio")   # v37 audio A/B
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	match which:
		"v36_ff":
			await ff_tests(true)
		"v36_one":
			# one A/B variant per process (fresh engine state): --ff_seed --ff_biome --ff_factor --ff_at --ff_mode --ff_pre --ff_ids
			var args: Dictionary = at.get("args")
			var ids: Array = Array(String(args.get("ff_ids", ",".join(IDS))).split(","))
			if args.has("ff_noise"):
				# noise-floor control: same 1x simulation, only extra per-frame memory churn (no gameplay effect)
				var gd := GDScript.new()
				gd.source_code = "extends Node\nvar keep := []\nfunc _process(_d):\n\tkeep.append(str(randi()).repeat(randi() % 64 + 1))\n\tif keep.size() > 300: keep = keep.slice(150)\n"
				gd.reload()
				var churn := Node.new()
				churn.set_script(gd)
				add_child(churn)
			if args.has("ff_trace"):
				trace_ids = Array(String(args.ff_trace).split(","))
			var r := await ff_case(int(args.get("ff_seed", "101")), String(args.get("ff_biome", "green_hills")), ids,
				float(args.get("ff_at", "5")), int(args.get("ff_factor", "1")), String(args.get("ff_mode", "new")), args.has("ff_pre"))
			var cs := []
			for c in r.c:
				cs.append({"id": c.id, "d": c.d, "reason": c.reason, "hp": c.hp, "limbs": c.limbs, "rocket": c.rocket, "hits": c.hits,
					"x": c.pos.x, "y": c.pos.y})
			print("AT|ffjson " + JSON.stringify({"t": r.t, "steps": r.steps, "dts": r.dts, "rank": r.rank, "c": cs}))
		"v36_traj":
			# airborne corridor statistics: --traj_biome --traj_seeds
			var a2: Dictionary = at.get("args")
			traj_log = true
			for k in int(a2.get("traj_seeds", "6")):
				await ff_case(7000 + k * 31, String(a2.get("traj_biome", "green_hills")), IDS, 999.0, 1, "new", false)
		"v36_spring":
			await spring_probe()
		"v36_chmetrics":
			# per-biome achievable challenge metrics: AI races with a StarTracker per robot (--cm_biome --cm_seeds)
			var a3: Dictionary = at.get("args")
			cm_log = true
			for k in int(a3.get("cm_seeds", "8")):
				await ff_case(9100 + k * 37, String(a3.get("cm_biome", "green_hills")), IDS, 999.0, 1, "new", false)
		"v36_chaudit":
			for id in gm.campaign.order:
				var nd: Dictionary = gm.campaign.node(id)
				var b := String(nd.get("biome", "green_hills"))
				if true:
					print("AT|chaudit %s r%d %s %s" % [id, int(nd.get("round", 0)), b, JSON.stringify(nd.get("stars", []))])
		"v36_cavern":
			var seeds := []
			for k in 40:
				seeds.append(1000 + k * 977)
			print("AT|cavern_summary %s" % [await cavern_report(seeds)])
		"v36_det":
			for spec in [["green_hills", IDS], ["jelly", IDS], ["jelly", ["heavy"]], ["jelly", ["heavy"]], ["jelly", IDS]]:
				var bi: String = spec[0]
				var a := await ff_case(101, bi, spec[1], 5.0, 1, "new", false)
				var b := await ff_case(101, bi, spec[1], 5.0, 1, "new", false)
				var df := ff_diff(a, b)
				print("AT|det biome=%s d=%.4f pos=%.3f state=%s a=%s b=%s" % [bi, df.d, df.pos, df.state,
					a.c.map(func(c: Dictionary) -> String: return "%s:%.2f" % [c.id, c.d]), b.c.map(func(c: Dictionary) -> String: return "%s:%.2f" % [c.id, c.d])])
		"v36_qa":
			await qa_shots()
		"v36_parse":
			pass
		"v36_schemes":
			await scheme_shots()
		_:
			spin_tests()
			wilhelm_tests()
			await sim_speed_tests()
			ccw_tests()
			await last_leg_tests()
			await spring_floor_tests()
			stuck_unit_tests()
			await stuck_world_tests()
			await anomaly_tests()
			await portal_tests()
			await cavern_tests()
			challenge_tests()
			rename_tests()
			await jumper_tests()
			await artifact_tests()
			mk2_visual_tests()
			await skin_tests()
	GameManager.set_sim_speed(1)
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ---------------- helpers ----------------

func _grant(id: String, mk2: bool) -> void:
	var p := gm.profile
	if not p.owned.has(id):
		p.owned.append(id)
	if mk2 and not p.mk2_owned.has(id):
		p.mk2_owned.append(id)
	p.mk2_selected[id] = mk2
	p.selected = id


## Free-run robot (base or MK2) on a fixed seed, flick skipped, not launched yet (frozen, upright).
func start_robot(id: String, mk2 := false, seed := 4242, biome := "") -> RobotController:
	GameManager.set_sim_speed(1)
	gm.go_menu()
	await frames(2)
	_grant(id, mk2)
	gm.mode = &"free"
	gm.debug_track_seed = seed
	gm.debug_biome = biome
	gm.ui.biome_intro.instant = true
	gm.start_run()
	await frames(3)
	gm.hand.playing = false
	gm.hand.visible = false
	gm.ui.flick_bar.hide_immediate()
	gm.state = GameManager.State.RUN
	gm.camera.follow(gm.robot)
	gm.debug_track_seed = -1
	gm.debug_biome = ""
	return gm.robot


func flat_x(x0: float) -> float:
	for k in 400:
		var x := x0 + k * 40.0
		if absf(gm.terrain.normal_at(x).x) < 0.06 and absf(gm.terrain.normal_at(x + 80.0).x) < 0.06 and gm.terrain.gap_index(x) < 0:
			return x
	return x0


## Upright drop: the robot's lowest boot starts `clear` px above the ground. Returns the first valid feet landing's
## release speed along the normal (vn), its type, and the apex height gain (px) before the next contact.
func drop(id: String, mk2: bool, clear: float, charge: float, floor_override := -1.0) -> Dictionary:
	var r: RobotController = await start_robot(id, mk2)
	var saved := [r.contact_config.min_natural_rebound_speed, r.contact_config.min_natural_extension_comp]
	if floor_override > 0.0:
		# pre-v36 floor (300 / 6) on THIS robot's config, for the in-process old/new comparison
		r.contact_config.min_natural_rebound_speed = floor_override
		r.contact_config.min_natural_extension_comp = 6.0
	var x := flat_x(2600.0)
	var stand := r.global_position.y   # spawn height = standing on the ledge
	var foot := 0.0
	for leg in r.contacts.legs:
		foot = maxf(foot, leg.hip.y + leg.cap_len + r.contact_config.coil_rest_length + leg.boot_len)
	r.global_position = Vector2(x, gm.terrain.surface_y(x) - foot - clear)
	r.rotation = 0.0
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.damage.invulnerability_time = 99.0
	r.damage.invulnerable_left = 99.0
	r.spin_charge.charge = charge * r.spin_charge.cfg.max_charge
	var out := {"vn": 0.0, "type": "", "apex": 0.0, "impact": 0.0}
	var phase := [0]
	var cb := func(info: Dictionary) -> void:
		if phase[0] == 0 and String(info.type) not in ["soft"]:
			out.vn = (info.velocity_out as Vector2).dot(info.normal)
			out.type = String(info.type)
			out.impact = float(info.impact)
			phase[0] = 1
	r.landed.connect(cb)
	var released := false
	var y0 := 0.0
	for i in 120 * 5:
		await get_tree().physics_frame
		if not is_instance_valid(r):
			break
		r.angular_velocity = 0.0
		r.rotation = 0.0
		r.linear_velocity.x = 0.0
		if phase[0] == 1:
			if not released:
				y0 = r.global_position.y
			if not r.contacts.any_contact:
				released = true
				out.apex = maxf(out.apex, y0 - r.global_position.y)
			elif released:
				break
	if is_instance_valid(r):
		r.contact_config.min_natural_rebound_speed = saved[0]
		r.contact_config.min_natural_extension_comp = saved[1]
	return out


func spring_probe() -> Dictionary:
	var res := {}
	for id in IDS:
		for mk2 in [false, true]:
			for spec in [["tiny", 12.0, 0.0], ["tiny_c", 12.0, 1.0], ["low", 45.0, 0.0], ["medium", 300.0, 0.0], ["strong", 1100.0, 0.0]]:
				var o := await drop(id, mk2, spec[1], spec[2])
				res["%s%s/%s" % [id, "_mk2" if mk2 else "", spec[0]]] = o
				print("AT|spring %-12s %-7s clear=%5.0f charge=%.0f -> type=%s impact=%.0f vn=%.0f apex=%.0f" % [id + ("_mk2" if mk2 else ""), spec[0], spec[1], spec[2] * 100.0, o.type, o.impact, o.vn, o.apex])
	return res


# ---------------- 11. Cavern clearance ----------------

## Largest distance from the body origin to any part of the robot that can touch geometry, legs at MAX coil
## extension: the body sweeps a circle of this radius while it tumbles.
func envelope_radius(r: RobotController) -> float:
	var rr := 0.0
	var cc := r.contact_config
	for leg in r.contacts.legs:
		rr = maxf(rr, (leg.hip + Vector2.DOWN * (leg.cap_len + cc.coil_max_length + leg.boot_len)).length())
		rr = maxf(rr, (leg.hip + Vector2.DOWN * (leg.cap_len + cc.coil_max_length + leg.boot_len)).length() + cc.foot_half_width)
	for ch in r.get_children():
		if ch is CollisionShape2D:
			var cs := ch as CollisionShape2D
			if cs.shape is CircleShape2D:
				rr = maxf(rr, cs.position.length() + (cs.shape as CircleShape2D).radius)
			elif cs.shape is CapsuleShape2D:
				rr = maxf(rr, cs.position.length() + (cs.shape as CapsuleShape2D).height * 0.5)
	return rr


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Real collision geometry of one generated Cavern track up to x_max: minimum Euclidean ground<->ceiling distance
## (stalactite tips included), plus the clearance distribution (vertical, per 100 px).
func cavern_measure(seed: int, x_max: float) -> Dictionary:
	gm.go_menu()
	await frames(1)
	var def := BiomeCatalog.get_def("cavern")
	gm._apply_biome(def)
	gm.terrain.reset(seed)
	var x := 0.0
	while x < x_max:
		x += 3000.0
		gm.terrain.ensure_ahead(x)
	await frames(1)
	var ceil_pts := PackedVector2Array()
	for chunk in gm.terrain.get_children():
		for b in chunk.get_children():
			if b is StaticBody2D and b.has_meta(&"ceiling"):
				for cp in b.get_children():
					if cp is CollisionPolygon2D:
						var poly: PackedVector2Array = (cp as CollisionPolygon2D).polygon
						for i in poly.size() - 2:
							ceil_pts.append(poly[i])
	var min_d := INF
	var min_at := Vector2.ZERO
	var vert := []
	var g := gm.terrain.points
	var gi := 0
	for p in ceil_pts:
		if p.x < 400.0 or p.x > x_max - 1500.0:
			continue
		while gi < g.size() - 1 and g[gi + 1].x < p.x - 700.0:
			gi += 1
		var j := gi
		while j < g.size() - 1 and g[j].x < p.x + 700.0:
			var d := _seg_dist(p, g[j], g[j + 1])
			if d < min_d:
				min_d = d
				min_at = p
			j += 1
	var xx := 2000.0
	while xx < x_max - 1500.0:
		vert.append(gm.terrain.surface_y(xx) - gm.terrain.ceiling_y(xx))
		xx += 100.0
	vert.sort()
	gm._apply_biome(BiomeCatalog.get_def(BiomeCatalog.GREEN))
	gm.terrain.reset(gm.track_seed)
	return {"min": min_d, "at": min_at, "p05": vert[int(vert.size() * 0.05)], "p50": vert[vert.size() / 2],
		"p95": vert[int(vert.size() * 0.95)], "max": vert[-1], "n": ceil_pts.size()}


func cavern_report(seeds: Array) -> Dictionary:
	var env := 0.0
	var envs := {}
	for id in IDS:
		for mk2 in [false, true]:
			var r: RobotController = await start_robot(id, mk2)
			var e := envelope_radius(r)
			envs[id + ("_mk2" if mk2 else "")] = e
			env = maxf(env, e)
	print("AT|cavern envelope radius per robot %s -> tumbling diameter max %.0f px" % [envs, env * 2.0])
	var worst := INF
	var halls := 0
	var narrow := 0
	for s in seeds:
		var m := await cavern_measure(int(s), 60000.0)
		worst = minf(worst, float(m.min))
		print("AT|cavern seed=%d min_euclid=%.0f at=%s vertical p05=%.0f p50=%.0f p95=%.0f max=%.0f" % [s, m.min, m.at, m.p05, m.p50, m.p95, m.max])
		halls += int(float(m.p95) >= 1800.0)
		narrow += int(float(m.p05) <= 1550.0)
	return {"env_d": env * 2.0, "worst": worst, "halls": halls, "narrow": narrow, "n": seeds.size()}


# ---------------- 3. fast-forward invariance ----------------

## One deterministic race of `robots` (rival AI, terrain-only collisions) on `seed` / `biome_id`. At sim time
## ff_at the speed-up starts: mode "new" = GameManager.set_sim_speed(factor) (the game path), "legacy" = the
## pre-v36 behaviour (Engine.time_scale only), factor 1 = plain 1x. predamage: at ff_at every robot takes 55 % of
## its max HP as an external hit (limbs detach, debris bodies exist while fast-forwarding).
func ff_case(seed: int, biome_id: String, robots: Array, ff_at: float, factor: int, mode: String, predamage: bool) -> Dictionary:
	GameManager.set_sim_speed(1)
	gm.go_menu()
	await frames(2)
	gm.mode = &"campaign"
	var def := BiomeCatalog.get_def(biome_id)
	gm._apply_biome(def)
	gm.track_seed = seed
	gm.terrain.reset(seed)
	gm.hazards.reset(def, gm.terrain, seed)
	gm._spawn_robot()
	gm.robot.visible = false
	gm.hand.visible = false
	var enemies := []
	for i in robots.size():
		enemies.append({"name": "FF%d" % i, "robot": robots[i], "skill": 0.55 + 0.1 * (i % 4), "lean": 18, "greed": 0.6})
	gm.race.deterministic_ai = true
	gm.race.spawn(enemies, 0.0, seed, gm.ai_config)
	gm.race.deterministic_ai = false
	var trackers := []
	var maxh := []
	if cm_log:
		for c in gm.race.competitors:
			var tr := StarTracker.new([])
			tr.attach(c.robot, gm.level_config.px_per_meter)
			trackers.append(tr)
			maxh.append(0.0)
	await get_tree().physics_frame
	gm.race.launch(Vector2.RIGHT.rotated(-deg_to_rad(gm.launch_angle)) * gm.launch_speed * gm.settings.get_value("flick") / 100.0,
		gm.robot_config.clockwise_rotation_speed * TAU)
	var t := 0.0
	var steps := 0
	var switched := false
	var dts := {}
	var fin_pos := {}
	while not gm.race.all_finished() and t < 150.0:
		if not switched and t >= ff_at:
			switched = true
			if predamage:
				for c in gm.race.competitors:
					if is_instance_valid(c.robot) and not c.finished:
						c.robot.damage.apply_external(c.robot.damage.max_health * 0.55, &"electric", {"point": c.robot.global_position, "normal": Vector2.UP}, false)
			if mode == "legacy":
				Engine.time_scale = float(factor)
			else:
				GameManager.set_sim_speed(factor)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		dts[snappedf(dt, 0.000001)] = true
		t += dt
		steps += 1
		var mx := gm.race.max_x()
		if is_finite(mx):
			var mn := gm.race.min_running_x()
			gm.terrain.ensure_ahead(mx, mn if is_finite(mn) else -INF)
		gm.race.step(dt)
		if cm_log:
			for i in trackers.size():
				var cc: RaceManager.Competitor = gm.race.competitors[i]
				var trk: StarTracker = trackers[i]
				if trk.active:
					trk.step(dt, cc.distance)
					if is_instance_valid(cc.robot) and not cc.robot.damage.rocket_fired:
						maxh[i] = maxf(maxh[i], (gm.terrain.surface_y(cc.robot.global_position.x) - cc.robot.global_position.y) / gm.level_config.px_per_meter)
					if cc.finished:
						trk.finalize_contact()
						trk.stop()
		if traj_log and steps % 3 == 0:
			for c in gm.race.competitors:
				var pp := c.piece()
				if not c.finished and pp:
					print("AT|traj %s %d %.0f %.0f" % [c.robot_id, seed, pp.global_position.x, gm.terrain.surface_y(pp.global_position.x) - pp.global_position.y])
		if trace_ids.size() > 0:
			for c in gm.race.competitors:
				if c.robot_id in trace_ids and not c.finished and c.piece():
					var tp := c.piece() as RigidBody2D
					var extra := ""
					if tp is RobotController:
						var rr := tp as RobotController
						extra = "w=%.6f hold=%s ch=%.5f turns=%.5f hp=%.2f lim=%d cont=%s" % [rr.angular_velocity, rr.input_router.holding, rr.spin_charge.charge,
							rr.rotation_ctl.auto_turns, rr.damage.health, rr.damage.limbs_remaining.size(), rr.contacts.any_contact]
					print("AT|tr %s %d %.6f %.6f %.6f %.6f %s" % [c.robot_id, steps, tp.global_position.x, tp.global_position.y, tp.linear_velocity.x, tp.linear_velocity.y, extra])
		for c in gm.race.competitors:
			if c.finished and not fin_pos.has(c.index):
				var fp := c.piece()
				fin_pos[c.index] = fp.global_position if fp else Vector2.ZERO
	if cm_log:
		for i in trackers.size():
			var cc2: RaceManager.Competitor = gm.race.competitors[i]
			var mm: Dictionary = (trackers[i] as StarTracker).metrics()
			print("AT|cm " + JSON.stringify({"biome": biome_id, "seed": seed, "id": cc2.robot_id, "d": cc2.distance, "max_jump": mm.max_jump, "max_air": mm.max_air,
				"height": maxh[i], "ccw": mm.ccw_turns, "speed": mm.max_speed, "charge": mm.peak_charge, "good": mm.total_good, "streak": mm.max_good_streak,
				"head": mm.head_landings, "rec": mm.recoveries, "clean": mm.max_clean, "rocket_m": mm.rocket_head_m, "first_limb": mm.first_limb_m,
				"bad": mm.bad_m.size(), "charged2": StarTracker.charged_streak(mm, 70.0), "charged1_90": StarTracker.charged_streak(mm, 90.0)}))
	GameManager.set_sim_speed(1)
	var out := {"t": t, "steps": steps, "dts": dts.keys(), "c": []}
	for c in gm.race.competitors:
		var r := c.robot
		var alive := is_instance_valid(r)
		var p := c.piece()
		out.c.append({"id": c.robot_id, "d": c.distance, "reason": c.reason,
			"hp": r.damage.health if alive else -1.0, "limbs": r.damage.limbs_remaining.size() if alive else -1,
			"rocket": alive and r.damage.rocket_fired, "hits": r.damage.hits if alive else -1,
			"pos": fin_pos.get(c.index, p.global_position if p else Vector2.ZERO)})
	var ranking := range(out.c.size())
	ranking.sort_custom(func(a: int, b: int) -> bool: return out.c[a].d > out.c[b].d)
	out["rank"] = ranking
	gm.race.clear()
	for n in gm.dynamic.get_children():
		n.queue_free()
	gm.mode = &"free"
	await frames(2)
	return out


static func ff_diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var dmax := 0.0
	var hpmax := 0.0
	var posmax := 0.0
	var same_state := true
	for i in a.c.size():
		var x: Dictionary = a.c[i]
		var y: Dictionary = b.c[i]
		dmax = maxf(dmax, absf(float(x.d) - float(y.d)))
		hpmax = maxf(hpmax, absf(float(x.hp) - float(y.hp)))
		posmax = maxf(posmax, (x.pos as Vector2).distance_to(y.pos))
		same_state = same_state and x.reason == y.reason and x.limbs == y.limbs and x.rocket == y.rocket and x.hits == y.hits
	return {"d": dmax, "hp": hpmax, "pos": posmax, "state": same_state, "rank": a.rank == b.rank}


func ff_tests(full: bool) -> void:
	var seeds := [101, 202, 303, 404] if full else [101, 303]
	var biomes := ["green_hills", "jelly", "heavy", "portal", "zone", "cavern", "chasms", "moon", "chocolate"] if full else ["green_hills", "jelly", "portal"]
	var worst_new := {"d": 0.0, "hp": 0.0, "pos": 0.0}
	var worst_legacy := 0.0
	var all_state := true
	var all_rank := true
	var cases := 0
	var legacy_cases := 0
	var step_ok := true
	var k := 0
	for seed in seeds:
		for bi in biomes:
			k += 1
			var ff_at: float = [2.0, 5.0, 9.0][k % 3]
			var predamage := k % 2 == 0
			var base := await ff_case(seed, bi, IDS, ff_at, 1, "new", predamage)
			for factor in ([2, 3, 16] if full else [3]):
				var fast := await ff_case(seed, bi, IDS, ff_at, factor, "new", predamage)
				var df := ff_diff(base, fast)
				cases += 1
				step_ok = step_ok and fast.dts.size() == 1 and absf(float(fast.dts[0]) - 1.0 / 120.0) < 1e-6 and fast.steps == base.steps
				worst_new.d = maxf(worst_new.d, df.d)
				worst_new.hp = maxf(worst_new.hp, df.hp)
				worst_new.pos = maxf(worst_new.pos, df.pos)
				all_state = all_state and df.state
				all_rank = all_rank and df.rank
				print("AT|ff seed=%d biome=%s ff_at=%.0f pre=%s x%d  d_max=%.4fm hp=%.3f pos=%.3fpx state=%s rank=%s steps %d/%d dists=%s" % [
					seed, bi, ff_at, predamage, factor, df.d, df.hp, df.pos, df.state, df.rank, base.steps, fast.steps,
					base.c.map(func(c: Dictionary) -> String: return "%s:%.1f" % [c.id, c.d])])
			if full or k <= 2:
				var leg := await ff_case(seed, bi, IDS, ff_at, 3, "legacy", predamage)
				var dl := ff_diff(base, leg)
				legacy_cases += 1
				worst_legacy = maxf(worst_legacy, dl.d)
				print("AT|ff_legacy seed=%d biome=%s x3 (time_scale only) d_max=%.2fm rank_same=%s dists=%s" % [seed, bi, dl.d, dl.rank,
					leg.c.map(func(c: Dictionary) -> String: return "%s:%.1f" % [c.id, c.d])])
	check("ff_fixed_step", step_ok, "every accelerated step is 1/120 s and the step count equals the 1x run")
	check("ff_distance_identical", worst_new.d < 0.01, "%d cases, worst |d| %.4f m (tolerance 0.01 m)" % [cases, worst_new.d])
	check("ff_state_identical", all_state and worst_new.hp < 0.001 and worst_new.pos < 0.5,
		"finish reason / limbs / jet head / hits identical, worst hp %.4f, worst resting pos %.3f px" % [worst_new.hp, worst_new.pos])
	check("ff_ranking_identical", all_rank, "")
	print("AT|ff_summary cases=%d worst_new_d=%.5f worst_legacy_d=%.2f (legacy cases %d)" % [cases, worst_new.d, worst_legacy, legacy_cases])


# ======================================================================================================
# v36 focused tests
# ======================================================================================================

# ---------------- 1. spin acceleration ----------------

## Feeds `turns` revolutions of automatic clockwise air spin (1 rev/s) into the controllers, 120 steps per turn.
static func _turns(rc: RotationController, sc: SpinChargeController, turns: float, charge_follows := false) -> void:
	for i in int(round(turns * 120.0)):
		rc.count_turns(1.0 / 120.0, TAU, true)
		if charge_follows:
			sc.step(1.0 / 120.0, TAU, true, false)


func _spin_pair() -> Array:
	var cfg: RobotConfig = gm.robot_config.duplicate()
	cfg.auto_spin_accel = gm.settings.get_value("spin_accel")
	var sc := SpinChargeController.new()
	sc.cfg = gm.spin_config.duplicate()
	sc.charge_rate = 1.0
	var rc := RotationController.new()
	rc.cfg = cfg
	rc.spin_charge = sc
	rc.enabled = true
	return [rc, sc, cfg]


func spin_tests() -> void:
	check("spin_accel_is_0_30", is_equal_approx(float(SettingsStore.FIXED.spin_accel), 0.3) and is_equal_approx(gm.settings.get_value("spin_accel"), 0.3)
		and is_equal_approx(gm.robot_config.auto_spin_accel, 0.3), "fixed %.2f live %.2f" % [SettingsStore.FIXED.spin_accel, gm.robot_config.auto_spin_accel])
	var p := _spin_pair()
	var rc: RotationController = p[0]
	var sc: SpinChargeController = p[1]
	var base: float = (p[2] as RobotConfig).clockwise_rotation_speed
	sc.charge = 0.2
	_turns(rc, sc, 1.0)
	var one := rc.auto_rps()
	check("spin_one_turn_plus_0_30", is_equal_approx(one, base + 0.3), "%.3f -> %.3f rev/s" % [base, one])
	_turns(rc, sc, 2.0)
	var three := rc.auto_rps()
	check("spin_turns_accumulate", is_equal_approx(three, base + 0.9), "after 3 turns %.3f rev/s" % three)
	sc.charge = sc.cfg.max_charge
	var turns_at_full := rc.auto_turns
	_turns(rc, sc, 3.0)
	check("spin_no_accel_at_full_charge", is_equal_approx(rc.auto_turns, turns_at_full) and is_equal_approx(rc.auto_rps(), three),
		"3 more turns at 100 %%: %.3f rev/s (turns %.2f)" % [rc.auto_rps(), rc.auto_turns])
	check("spin_earned_speed_kept_at_full", rc.auto_rps() >= base + 0.9 - 0.0001, "%.3f" % rc.auto_rps())
	sc.charge = sc.cfg.max_charge * 0.5
	_turns(rc, sc, 1.0)
	check("spin_resumes_below_full", is_equal_approx(rc.auto_rps(), base + 1.2), "%.3f" % rc.auto_rps())
	# charge reaching 100 % by the spin itself stops the acceleration at that very turn (natural sequence)
	var q := _spin_pair()
	var rc2: RotationController = q[0]
	var sc2: SpinChargeController = q[1]
	_turns(rc2, sc2, 6.0, true)
	var full_turns := sc2.cfg.max_charge / (sc2.cfg.charge_per_rotation * sc2.charge_rate)
	check("spin_natural_charge_caps_accel", sc2.is_full() and rc2.auto_turns <= full_turns + 0.02 and is_equal_approx(rc2.auto_rps(), base + 0.3 * floorf(full_turns)),
		"full after %.2f turns -> %.2f counted, %.2f rev/s" % [full_turns, rc2.auto_turns, rc2.auto_rps()])
	var q2 := _spin_pair()
	_turns(q2[0], q2[1], 6.0, true)
	check("spin_deterministic", is_equal_approx((q2[0] as RotationController).auto_turns, rc2.auto_turns) and is_equal_approx((q2[0] as RotationController).auto_rps(), rc2.auto_rps()))
	rc.free(); sc.free(); rc2.free(); sc2.free(); (q2[0] as Node).free(); (q2[1] as Node).free()


# ---------------- 2. Wilhelm ----------------

func wilhelm_tests() -> void:
	var t := WilhelmTrigger.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 36
	for i in 20000:
		t.step(31.0, rng)
		t.step(5.0, rng)
	var rate := float(t.screams) / float(t.rolls)
	check("wilhelm_probability_7pct", is_equal_approx(WilhelmTrigger.PROBABILITY, 0.07) and absf(rate - 0.07) < 0.006 and t.rolls == 20000,
		"constant %.2f, measured %.4f over %d separate high jumps" % [WilhelmTrigger.PROBABILITY, rate, t.rolls])
	check("wilhelm_rules_unchanged", is_equal_approx(WilhelmTrigger.HEIGHT_M, 30.0) and is_equal_approx(WilhelmTrigger.REARM_M, 20.0))


# ---------------- 3. fast-forward (in-process part; the cross-process A/B matrix is tools-driven) ----------------

func sim_speed_tests() -> void:
	gm.go_menu()
	await frames(2)
	var ok := true
	var info := []
	for f in [2, 3, 16]:
		GameManager.set_sim_speed(f)
		await frames(3)
		var dts := {}
		for i in 8:
			await get_tree().physics_frame
			dts[snappedf(get_physics_process_delta_time(), 0.000001)] = true
		var good: bool = dts.size() == 1 and absf(float(dts.keys()[0]) - 1.0 / 120.0) < 1e-6 and Engine.physics_ticks_per_second == 120 * f and is_equal_approx(Engine.time_scale, f)
		ok = ok and good
		info.append("x%d: dt %s ticks %d" % [f, dts.keys(), Engine.physics_ticks_per_second])
	GameManager.set_sim_speed(1)
	await frames(2)
	check("ff_step_is_always_1_120", ok, ", ".join(info))
	gm.ui.race_hud.speed_up_requested.emit()
	var btn := GameManager.sim_speed == GameManager.SPEED_UP_FACTOR and Engine.physics_ticks_per_second == 120 * GameManager.SPEED_UP_FACTOR
	gm.go_menu()
	await frames(2)
	check("ff_speed_button_and_reset", btn and GameManager.sim_speed == 1 and Engine.physics_ticks_per_second == 120 and is_equal_approx(Engine.time_scale, 1.0))
	var src := FileAccess.get_file_as_string("res://scripts/core/game_manager.gd")
	var raw_scale := 0
	for line in src.split("\n"):
		if line.contains("Engine.time_scale =") and not line.strip_edges().begins_with("#") and not line.contains("float(factor)"):
			raw_scale += 1
	check("ff_no_raw_time_scale_writes", raw_scale == 0, "%d direct Engine.time_scale writes outside set_sim_speed" % raw_scale)


# ---------------- 4. CCW streak ----------------

static func _ccw(seq: Array) -> StarTracker:
	var st := StarTracker.new([{"type": "CCW_TURNS", "n": 2, "reward": 0}])
	for d in seq:
		st.sample_rotation(deg_to_rad(float(d)))
	return st


func ccw_tests() -> void:
	var cont := []
	for i in 144:
		cont.append(-5.0)
	check("ccw_continuous_720_completes", _ccw(cont).status[0] == 1)
	var split := []
	for i in 72:
		split.append(-5.0)
	split.append(30.0)                 # meaningful clockwise rotation
	for i in 72:
		split.append(-5.0)
	var s2 := _ccw(split)
	check("ccw_360_cw_360_not_complete", s2.status[0] == 0, "best streak %.2f turns" % float(s2.metrics().ccw_turns))
	var scattered := []
	for i in 12:
		scattered.append(-120.0)
		scattered.append(20.0)
	var s3 := _ccw(scattered)
	check("ccw_scattered_not_complete", s3.status[0] == 0, "1440 deg CCW in total, best streak %.2f turns" % float(s3.metrics().ccw_turns))
	var jitter := []
	for i in 156:
		jitter.append(-5.0)
		if i % 10 == 0:
			jitter.append(2.0)           # physics noise
	check("ccw_tiny_jitter_does_not_reset", _ccw(jitter).status[0] == 1)
	check("ccw_deterministic", str(_ccw(scattered).metrics().ccw_turns) == str(s3.metrics().ccw_turns))


# ---------------- 5. last-leg charged landing ----------------

## One remaining leg (right), charge 100 %, feet landing from ~1.2 m: kill = the landing damage removes that last
## leg; legacy = the pre-v36 order (leg removed at once). Returns the bounce and the leg state.
func _last_leg(kill: bool, legacy := false) -> Dictionary:
	var r: RobotController = await start_robot("tin", false)
	var x := flat_x(2600.0)
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.debug_immediate_detach = legacy
	r.damage.armed = true
	r.damage.invulnerable_left = 99.0      # no ledge-contact damage while the test sets the robot up
	r.global_position += Vector2(0, -400)
	# both arms + the left leg go through the normal threshold rules (12 HP of 95 -> 13 %)
	r.damage.apply_external(r.damage.max_health - 12.0, &"electric", {"point": r.global_position, "normal": Vector2.UP}, false)
	await physics(3)
	var foot := 0.0
	for leg in r.contacts.legs:
		foot = maxf(foot, leg.hip.y + leg.cap_len + r.contact_config.coil_rest_length + leg.boot_len)
	r.global_position = Vector2(x, gm.terrain.surface_y(x) - foot - 120.0)
	r.rotation = 0.0
	r.linear_velocity = Vector2(0, 250)
	r.angular_velocity = 0.0
	r.damage.invulnerable_left = 0.0 if kill else 99.0
	r.spin_charge.charge = r.spin_charge.cfg.max_charge
	var out := {"released": 0.0, "zone": "", "up": 0.0, "lost": [], "legs_before": r.damage.limbs_remaining.duplicate(), "type": ""}
	r.charge_released.connect(func(c: float, _b: Vector2, info: Dictionary) -> void:
		out.released = c
		out.zone = String(info.zone_class))
	r.touchdown.connect(func(info: Dictionary) -> void:
		if out.type == "": out.type = String(info.type))
	r.limb_lost.connect(func(l: StringName, _p: RigidBody2D) -> void: out.lost.append(String(l)))
	var landed := false
	for i in 120 * 2:
		await get_tree().physics_frame
		if not is_instance_valid(r):
			break
		if not landed:
			r.rotation = 0.0
			r.angular_velocity = 0.0
			landed = r.contacts.any_contact
		out.up = maxf(out.up, -r.linear_velocity.y)
	out["attached_leg_r"] = is_instance_valid(r) and bool(r.attached[&"leg_r"])
	out["debris"] = gm.dynamic.get_children().filter(func(n: Node) -> bool: return n is DetachablePart).size()
	return out


func last_leg_tests() -> void:
	var ctrl := await _last_leg(false)
	var hit := await _last_leg(true)
	var legacy := await _last_leg(true, true)
	check("last_leg_setup_one_leg", ctrl.legs_before == [&"leg_r"] and hit.legs_before == [&"leg_r"], "%s" % [hit.legs_before])
	check("last_leg_detaches_honestly", hit.lost.has("leg_r") and not bool(hit.attached_leg_r), "lost %s" % [hit.lost])
	check("last_leg_full_charged_bounce", float(hit.released) >= 0.99 and hit.zone == "feet" and float(hit.up) >= float(ctrl.up) * 0.9,
		"bounce up %.0f px/s vs intact-leg control %.0f (pre-v36 order: %.0f, charge released %.2f)" % [hit.up, ctrl.up, legacy.up, legacy.released])
	check("last_leg_was_broken_before", float(legacy.up) < float(ctrl.up) * 0.6, "pre-v36 order bounce %.0f px/s" % legacy.up)


# ---------------- 6. spring floor ----------------

func spring_floor_tests() -> void:
	var rows := []
	var tiny_ok := true
	var other_ok := true
	for id in IDS:
		for mk2 in [false, true]:
			var nt := await drop(id, mk2, 12.0, 0.0)
			var ot := await drop(id, mk2, 12.0, 0.0, 300.0)
			var nm := await drop(id, mk2, 300.0, 0.0)
			var om := await drop(id, mk2, 300.0, 0.0, 300.0)
			var ns := await drop(id, mk2, 1100.0, 0.0)
			var os := await drop(id, mk2, 1100.0, 0.0, 300.0)
			tiny_ok = tiny_ok and float(nt.vn) >= float(ot.vn) * 1.12 and float(nt.vn) <= float(ot.vn) * 1.3
			other_ok = other_ok and absf(float(nm.vn) - float(om.vn)) <= maxf(2.0, float(om.vn) * 0.01) and absf(float(ns.vn) - float(os.vn)) <= maxf(2.0, float(os.vn) * 0.01)
			rows.append("%s%s tiny %.0f->%.0f medium %.0f->%.0f strong %.0f->%.0f" % [id, "_mk2" if mk2 else "", ot.vn, nt.vn, om.vn, nm.vn, os.vn, ns.vn])
	for c in [["rocket", false], ["heavy", true]]:
		var nc := await drop(c[0], c[1], 12.0, 1.0)
		var oc := await drop(c[0], c[1], 12.0, 1.0, 300.0)
		other_ok = other_ok and absf(float(nc.vn) - float(oc.vn)) <= 2.0
		rows.append("%s%s tiny 100%% charge %.0f->%.0f" % [c[0], "_mk2" if c[1] else "", oc.vn, nc.vn])
	print("AT|spring_floor " + " | ".join(rows))
	check("spring_floor_tiny_landings_stronger", tiny_ok, "min natural rebound 300 -> %.0f (x sqrt(spring power))" % gm.contact_config.min_natural_rebound_speed)
	check("spring_floor_medium_strong_charged_unchanged", other_ok)


# ---------------- 7. stuck detector ----------------

func stuck_unit_tests() -> void:
	var dt := 1.0 / 120.0
	var w := MotionWatch.new(7.0)
	w.reset(Vector2(5000, 0))
	var stuck := false
	var stopped := 0.0
	for i in 120 * 16:
		var t := i * dt
		var p := Vector2(5000.0 - 430.0 * t, -absf(sin(t * 3.0)) * 300.0)
		stuck = stuck or w.step(dt, p)
		stopped = maxf(stopped, w.stopped(dt, 430.0, 0.5, 55.0))
	check("stuck_backward_bouncing_never_stuck", not stuck and stopped < 2.5, "69 m backward over 16 s while bouncing")
	w = MotionWatch.new(7.0)
	w.reset(Vector2.ZERO)
	stuck = false
	for i in 120 * 20:
		var t2 := i * dt
		stuck = stuck or w.step(dt, Vector2(-900.0 * t2, -1500.0 * sin(t2)))   # flying backward
	check("stuck_flying_backward_never_stuck", not stuck)
	w = MotionWatch.new(7.0)
	w.reset(Vector2.ZERO)
	var at_s := -1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 120 * 12:
		if w.step(dt, Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))) and at_s < 0.0:
			at_s = i * dt
	check("stuck_wedged_jitter_is_stuck", at_s > 7.0 and at_s < 9.6, "detected after %.2f s" % at_s)
	w = MotionWatch.new(7.0)
	w.reset(Vector2.ZERO)
	var loop_at := -1.0
	for i in 120 * 70:
		var t3 := i * dt
		if w.step(dt, Vector2(0, -absf(sin(t3 * 2.0)) * 400.0)) and loop_at < 0.0:
			loop_at = t3
	check("stuck_endless_pogo_guard", loop_at >= MotionWatch.LOOP_NO_RECORD_S - 0.05 and loop_at < MotionWatch.LOOP_NO_RECORD_S + 5.0, "pogo in place (400 px hops) ended after %.1f s" % loop_at)
	var s2 := MotionWatch.new(7.0)
	s2.reset(Vector2.ZERO)
	var spin_stop := 0.0
	var still_stop := 0.0
	for i in 120 * 4:
		spin_stop = s2.stopped(dt, 10.0, 6.0, 55.0)
	var s3 := MotionWatch.new(7.0)
	s3.reset(Vector2.ZERO)
	for i in 120 * 4:
		still_stop = s3.stopped(dt, 10.0, 0.1, 55.0)
	check("stuck_rotation_counts_as_movement", spin_stop == 0.0 and still_stop > 2.5)


## Real robots launched backward in each biome: may lose a lot of distance, must never get "stuck".
func stuck_world_tests() -> void:
	var rows := []
	var ok := true
	for bi in ["jelly", "cavern", "chasms", "portal", "green_hills"]:
		for v in [Vector2(-1300, -900), Vector2(-700, -1600)]:
			var r: RobotController = await start_robot("samurai", false, 515, bi)
			gm.profile.coins = 0          # no Continue offer: any end shows up in _end_reason
			var x := flat_x(9000.0)
			r.global_position = Vector2(x, gm.terrain.surface_y(x) - 600.0)
			r.launch(v, 2.0)
			gm._watch.reset(r.global_position)
			gm._max_x = maxf(gm._max_x, r.global_position.x)
			var x0 := r.global_position.x
			var min_x := x0
			var old_rule := 0.0
			var old_fired := false
			var mark := gm._max_x
			for i in 120 * 12:
				await get_tree().physics_frame
				if gm.state != GameManager.State.RUN or not is_instance_valid(r):
					break
				min_x = minf(min_x, r.global_position.x)
				if gm._max_x > mark + 150.0:
					mark = gm._max_x
					old_rule = 0.0
				else:
					old_rule += 1.0 / 120.0
				old_fired = old_fired or old_rule > gm.no_progress_time
			var reason := gm._end_reason if gm.state != GameManager.State.RUN else "running"
			var bad := reason == "Робот застрял"
			ok = ok and not bad
			rows.append("%s v=%s back %.0f m, pre-v36 rule would end it: %s, now: %s" % [bi, v, (x0 - min_x) / 100.0, old_fired, reason])
	print("AT|stuck_world " + " | ".join(rows))
	check("stuck_backward_motion_never_stuck_in_biomes", ok, "%d runs (jelly, cavern, chasms, portal, green)" % rows.size())


# ---------------- 8/9. anomalies ----------------

func anomaly_tests() -> void:
	var r: RobotController = await start_robot("tin", false, 4242, "zone")
	gm.terrain.ensure_ahead(60000.0)
	await physics(4)
	var hz := gm.hazards
	check("anomaly_trigger_sizes", is_equal_approx(BiomeHazards.ELECTRIC_R, 200.0) and is_equal_approx(BiomeHazards.GRAV_R, 210.0)
		and is_equal_approx(BiomeHazards.RAD_RX, 280.0) and is_equal_approx(BiomeHazards.RAD_RY, 160.0), "electric 80->200, gravity 90->210, radiation 170x105->280x160")
	var bands := {}
	var bad_alt := []
	for a in hz.anomalies:
		bands[String(a.band)] = int(bands.get(String(a.band), 0)) + 1
		var alt: float = gm.terrain.surface_y(float(a.pos.x)) - float(a.pos.y)
		var rad := BiomeHazards.ELECTRIC_R if a.kind == "electric" else BiomeHazards.GRAV_R
		if a.kind != "radiation" and alt < rad + 60.0:
			bad_alt.append("%s@%.0f" % [a.kind, alt])
	var n := hz.anomalies.size()
	var air := n - int(bands.get("ground", 0))
	var mid_high := int(bands.get("medium", 0)) + int(bands.get("high", 0))
	check("anomaly_height_distribution", n >= 20 and float(air) / n >= 0.7 and float(mid_high) / n >= 0.5 and bands.has("low") and bands.has("high") and bad_alt.is_empty(),
		"n=%d %s (airborne %.0f %%, medium+high %.0f %%) %s" % [n, bands, 100.0 * air / maxf(n, 1), 100.0 * mid_high / maxf(n, 1), bad_alt])
	var find := func(k: String) -> Dictionary:
		for a in hz.anomalies:
			if a.kind == k:
				return a
		return {}
	gm.state = GameManager.State.RUN
	r.launch(Vector2.ZERO, 0.0)
	r.damage.armed = true
	r.freeze = true
	gm.camera.shake_scale = 1.0
	var fresh := func() -> Dictionary: return {"cool": 0.0, "exit": -1, "inside": {}, "rad": 0.0, "rad_tick": 0.0, "dirt": 0.0, "was_contact": true}
	# electric: damage + 100 % charge + feedback (player only)
	var e: Dictionary = find.call("electric")
	r.spin_charge.charge = 0.1
	var hp0 := r.damage.health
	var c0 := int(gm.audio.counts.get("common/anomaly_electric", 0))
	var f0 := gm.anomaly_flash.electric_count
	gm.camera._shake = 0.0
	r.global_position = e.pos
	hz.step_anomalies(r, fresh.call(), 1.0 / 120.0)
	check("electric_damage_and_full_charge", is_equal_approx(hp0 - r.damage.health, BiomeHazards.ELECTRIC_DMG) and r.spin_charge.is_full(),
		"-%.0f HP (configurable, balance TODO), charge %.0f %%" % [hp0 - r.damage.health, r.spin_charge.ratio() * 100.0])
	check("electric_feedback", int(gm.audio.counts.get("common/anomaly_electric", 0)) == c0 + 1 and gm.anomaly_flash.electric_count == f0 + 1
		and gm.camera._shake >= 50.0 and gm.haptics._pending >= 0.99, "shake %.0f vibration %.2f" % [gm.camera._shake, gm.haptics._pending])
	# invulnerable: no HP loss, charge still filled
	r.spin_charge.charge = 0.0
	r.damage.invulnerable_left = 1.0
	var hp1 := r.damage.health
	hz.step_anomalies(r, fresh.call(), 1.0 / 120.0)
	check("electric_respects_invulnerability", is_equal_approx(r.damage.health, hp1) and r.spin_charge.is_full())
	r.damage.invulnerable_left = 0.0
	# opponents never trigger player feedback
	var other := RigidBody2D.new()
	gm.dynamic.add_child(other)
	var c1 := int(gm.audio.counts.get("common/anomaly_electric", 0))
	gm._on_anomaly_hit(other, "electric", e.pos)
	check("anomaly_feedback_player_only", int(gm.audio.counts.get("common/anomaly_electric", 0)) == c1)
	other.queue_free()
	# radiation: Geiger + full-screen noise
	var rd: Dictionary = find.call("radiation")
	var g0 := int(gm.audio.counts.get("common/anomaly_geiger", 0))
	var rf0 := gm.anomaly_flash.radiation_count
	gm.camera._shake = 0.0
	r.global_position = rd.pos
	hz.step_anomalies(r, fresh.call(), 1.0 / 120.0)
	check("radiation_feedback", int(gm.audio.counts.get("common/anomaly_geiger", 0)) == g0 + 1 and gm.anomaly_flash.radiation_count == rf0 + 1 and gm.camera._shake >= 35.0)
	# gravity: unmistakable throw, weaker feedback
	r.freeze = false
	var gv: Dictionary = find.call("gravity")
	gm.camera._shake = 0.0
	r.global_position = gv.pos + Vector2(0, 40)
	r.linear_velocity = Vector2(500, -300)
	hz.step_anomalies(r, fresh.call(), 1.0 / 120.0)
	var up := r.linear_velocity.y
	var shake_g := gm.camera._shake
	r.global_position = gv.pos + Vector2(0, -40)
	r.linear_velocity = Vector2(500, 300)
	hz.step_anomalies(r, fresh.call(), 1.0 / 120.0)
	check("gravity_throw_and_weaker_feedback", is_equal_approx(up, -BiomeHazards.GRAV_SPEED) and is_equal_approx(r.linear_velocity.y, BiomeHazards.GRAV_SPEED)
		and shake_g > 0.0 and shake_g < 30.0, "vy up %.0f / down %.0f, shake %.0f" % [up, r.linear_velocity.y, shake_g])
	# the player's settings apply
	gm.camera.shake_scale = 0.0
	gm.camera._shake = 0.0
	gm._on_anomaly_hit(r, "electric", e.pos)
	var shake_off := gm.camera._shake
	gm.camera.shake_scale = gm.settings.get_value("shake") / 100.0
	check("anomaly_feedback_respects_settings", shake_off == 0.0 and HapticFeedback.recipe(1.0, 0.0).amplitude == 0.0 and HapticFeedback.recipe(1.0, 1.0).amplitude == 1.0)


# ---------------- 10. portals ----------------

func portal_tests() -> void:
	var r: RobotController = await start_robot("tin", false, 4242, "portal")
	gm.terrain.ensure_ahead(60000.0)
	await physics(4)
	var hz := gm.hazards
	var kinds := {}
	var bands := {}
	var pair_ok := true
	var arrow_ok := true
	var clear_ok := true
	var entries := 0
	for i in hz.portals.size():
		var p: Dictionary = hz.portals[i]
		for o in [-300.0, -150.0, 0.0, 150.0, 300.0]:
			clear_ok = clear_ok and gm.terrain.surface_y(float(p.pos.x) + o) - float(p.pos.y) >= BiomeHazards.EXIT_CLEAR - 1.0
		var partner := int(p.partner)
		if partner < 0:
			continue
		entries += 1
		bands[String(p.band)] = int(bands.get(String(p.band), 0)) + 1
		var x: Dictionary = hz.portals[partner]
		pair_ok = pair_ok and partner == i + 1 and int(x.partner) == -1 and float(x.pos.x) > float(p.pos.x) + 1000.0
		kinds[String(x.band)] = int(kinds.get(String(x.band), 0)) + 1
		var dy: float = float(x.pos.y) - float(p.pos.y)
		var arrow: Vector2 = p.arrow
		arrow_ok = arrow_ok and ((dy < -200.0 and arrow.y < -0.3) or (dy > 200.0 and arrow.y > 0.3) or (absf(dy) <= 200.0 and absf(arrow.y) < 0.05))
	check("portal_sizes", is_equal_approx(BiomeHazards.PORTAL_RX, 150.0) and is_equal_approx(BiomeHazards.PORTAL_RY, 240.0), "70x115 -> 150x240")
	check("portal_pairs_one_way_forward", pair_ok and entries >= 8, "%d pairs" % entries)
	check("portal_pair_kinds", kinds.has("helpful") and kinds.has("harmful") and int(kinds.get("helpful", 0)) >= int(kinds.get("harmful", 0)), "%s" % [kinds])
	check("portal_arrow_tells_outcome", arrow_ok)
	check("portal_exits_safe_clearance", clear_ok, ">= %.0f px above the highest ground within +-300 px" % BiomeHazards.EXIT_CLEAR)
	var mid_high := int(bands.get("medium", 0)) + int(bands.get("high", 0))
	check("portal_entry_heights_mostly_airborne", float(mid_high) / maxf(entries, 1) >= 0.6, "%s" % [bands])
	# real teleport through an entry; the exit does not capture
	gm.state = GameManager.State.RUN
	r.launch(Vector2(900, -100), 0.0)
	var ei := -1
	for i in hz.portals.size():
		if int(hz.portals[i].partner) >= 0:
			ei = i
			break
	r.global_position = hz.portals[ei].pos
	r.linear_velocity = Vector2(1100, 200)
	var n0 := hz.teleports
	await physics(2)
	var tp := hz.last_teleport
	check("portal_teleports_to_partner", hz.teleports == n0 + 1 and int(tp.get("to", -1)) == ei + 1, "%s" % [tp])
	var n1 := hz.teleports
	for i in 40:
		r.global_position = hz.portals[ei + 1].pos
		await get_tree().physics_frame
	check("portal_exit_never_captures", hz.teleports == n1)


# ---------------- 11. Cavern ----------------

func cavern_tests() -> void:
	var seeds := []
	for k in 12:
		seeds.append(5000 + k * 613)
	var rep := await cavern_report(seeds)
	check("cavern_min_clearance_2x_tumbling_robot", float(rep.worst) >= 2.0 * float(rep.env_d) and float(rep.worst) >= 1000.0,
		"worst Euclidean ground<->ceiling %.0f px over %d seeds x 600 m (largest tumbling diameter %.0f px)" % [rep.worst, rep.n, rep.env_d])
	check("cavern_has_halls_and_narrows", int(rep.halls) >= int(rep.n) * 0.8 and int(rep.narrow) >= 1, "halls in %d/%d seeds, narrow sections in %d" % [rep.halls, rep.n, rep.narrow])
	gm.go_menu()
	await frames(1)
	gm._apply_biome(BiomeCatalog.get_def("cavern"))
	gm.terrain.reset(777)
	var kinds := {}
	var x := 5000.0
	while x < 80000.0:
		kinds[gm.terrain.ceiling_kind(x)] = true
		x += 500.0
	var a := gm.terrain.ceiling_clearance(33333.0)
	gm.terrain.reset(777)
	var b := gm.terrain.ceiling_clearance(33333.0)
	gm._apply_biome(BiomeCatalog.get_def(BiomeCatalog.GREEN))
	gm.terrain.reset(gm.track_seed)
	check("cavern_sections_deterministic", kinds.size() == 3 and is_equal_approx(a, b), "%s" % [kinds.keys()])


# ---------------- 12. biome / challenge compatibility ----------------

func challenge_tests() -> void:
	var bad := []
	var replaced := []
	var matrix := {}
	for id in gm.campaign.order:
		var nd: Dictionary = gm.campaign.node(id)
		var b := String(nd.get("biome", BiomeCatalog.GREEN))
		var cats := []
		var types := []
		for ch in nd.stars:
			types.append(String(ch.type))
			cats.append(StarChallenges.category(ch))
			if StarChallenges.validate(ch) != "":
				bad.append("%s %s" % [id, StarChallenges.validate(ch)])
			if not BiomeChallenges.is_allowed(String(ch.type), b):
				bad.append("%s excluded %s in %s" % [id, ch.type, b])
			if ch.has("replaced"):
				replaced.append("%s %s: %s -> %s" % [id, b, ch.replaced, ch.type])
			if b == "cavern" and ch.type == "MAX_HEIGHT_M" and float(ch.m) > 8.0:
				bad.append(id + " cavern height above the ceiling-safe cap")
		cats.sort()
		if cats != ["A", "B", "C"]:
			bad.append(id + " categories " + str(cats))
		for pair in StarChallenges.INCOMPATIBLE:
			if types.has(pair[0]) and types.has(pair[1]):
				bad.append(id + " incompatible " + str(pair))
	check("challenges_biome_eligibility", bad.is_empty(), "%s" % [bad])
	check("jelly_never_height", gm.campaign.order.all(func(id: String) -> bool:
		var nd: Dictionary = gm.campaign.node(id)
		return String(nd.get("biome", "")) != "jelly" or not nd.stars.any(func(c: Dictionary) -> bool: return c.type == "MAX_HEIGHT_M")))
	print("AT|challenge_replacements " + " | ".join(replaced))
	var again := CampaignData.load_file(gm.campaign_path)
	var same := true
	for id in gm.campaign.order:
		same = same and JSON.stringify(again.node(id).stars) == JSON.stringify(gm.campaign.node(id).stars)
	check("challenges_deterministic", same and replaced.size() >= 2, "%d replacements" % replaced.size())
	# compatibility matrix (type x biome): allowed / adjusted / excluded
	var lines := []
	for t in StarChallenges.TYPES:
		var cells := []
		for b in BiomeCatalog.SPECIALS:
			cells.append("excluded" if not BiomeChallenges.is_allowed(t, b) else ("adjusted" if BiomeChallenges.RULES.get(b, {}).has(t) else "allowed"))
		lines.append("%s=%s" % [t, ",".join(cells)])
	print("AT|challenge_matrix biomes=%s %s" % [",".join(BiomeCatalog.SPECIALS), " ".join(lines)])


# ---------------- 13. Supergravity name ----------------

func rename_tests() -> void:
	var js = JSON.parse_string(FileAccess.get_file_as_string("res://locale/strings.json"))
	var row: Dictionary = {}
	if typeof(js) == TYPE_DICTIONARY:
		row = (js.get("strings", js) as Dictionary).get("D_BIOME_HEAVY", {}) if typeof(js.get("strings", js)) == TYPE_DICTIONARY else {}
	var all13 := row.size() >= 13 and row.values().all(func(v) -> bool: return typeof(v) == TYPE_STRING and String(v) != "")
	check("supergravity_name_13_languages", all13 and String(row.get("ru", "")) == "СВЕРХГРАВИТАЦИЯ" and String(row.get("en", "")) == "SUPERGRAVITY"
		and BiomeCatalog.get_def("heavy").display_name == "СВЕРХГРАВИТАЦИЯ" and BiomeCatalog.get_def("heavy").id == "heavy", "%s" % [row])
	var font: Font = gm.ui.biome_intro._font
	var worst := 0.0
	for code in row:
		var text := String(row[code])
		var fs := int(clampf(1280.0 * 0.88 / maxf(text.length() * 0.62, 1.0), 60.0, 190.0))
		var w := 0.0
		for chr in text:
			w += font.get_string_size(chr, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		worst = maxf(worst, w / 1280.0)
	check("supergravity_title_fits", worst <= 0.98, "widest title %.0f %% of 1280 px" % (worst * 100.0))


# ---------------- 14. menu physics robot ----------------

func jumper_tests() -> void:
	gm.go_menu()
	await frames(6)
	var j := gm.ui.menu_jumper
	var big_before := [gm.ui.menu_robot_preview.position, gm.ui.menu_robot_preview.scale]
	# free fall obeys gravity (far above everything: no contacts)
	j.position = Vector2(0, -100000)
	j.vel = Vector2.ZERO
	j.spin = 0.0
	for i in 12:
		j._step(1.0 / 120.0)
	var g := MenuJumper.GRAVITY_PER_H * j._h
	check("jumper_gravity", absf(j.vel.y - g * 0.1) < g * 0.01, "vy %.1f after 0.1 s (g %.0f px/s^2)" % [j.vel.y, g])
	# off-centre drop onto a button: bounces up, picks up spin (torque from the contact)
	var c: Vector2 = gm.ui._menu_button_centers[0]
	var r := gm.ui.menu_circle_diameter() * 0.5
	j.position = c + Vector2(r * 0.35, -r - j._h * 0.6)
	j.rotation = 0.0
	j.vel = Vector2(0, j._h * 3.0)
	j.spin = 0.0
	var b0 := j.jumps
	var min_vy := 0.0
	for i in 60:
		j._step(1.0 / 120.0)
		min_vy = minf(min_vy, j.vel.y)
	check("jumper_bounces_on_button_proxy", j.jumps > b0 and min_vy < 0.0 and absf(j.spin) > 0.2, "bounces %d, vy %.0f, spin %.2f" % [j.jumps - b0, min_vy, j.spin])
	# live: falls, tumbles, respawns from above
	var f0 := j.falls
	var rot := {}
	var t := 0.0
	while t < 14.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		rot[int(j.rotation * 4.0)] = true
	check("jumper_live_physics_loop", j.falls > f0 and rot.size() >= 4, "falls %d, distinct orientations %d" % [j.falls - f0, rot.size()])
	check("jumper_original_robot_untouched", big_before == [gm.ui.menu_robot_preview.position, gm.ui.menu_robot_preview.scale])
	check("jumper_no_input_no_focus", j is Node2D and not (j as Node).has_method("_gui_input") and j.get_children().all(func(n: Node) -> bool: return not n is Control or (n as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE))


# ---------------- 15/16. secret artifact ----------------

func artifact_tests() -> void:
	gm.go_menu()
	await frames(2)
	gm.profile.artifact.discovered = false
	gm.mode = &"campaign"
	gm.node_id = SecretArtifact.NODE_ID
	gm.profile.ensure_campaign_start(SecretArtifact.NODE_ID)
	gm.debug_track_seed = 2222
	gm.start_run()
	await frames(3)
	gm.debug_track_seed = -1
	var x := 0.0
	while gm.artifact_node == null and x < 40000.0:
		x += 2000.0
		gm.terrain.ensure_ahead(x)
		gm.hazards.generate_now()
		gm._step_artifact()
	var a := gm.artifact_node
	var ok := a != null and is_instance_valid(a.host)
	var detail := "none"
	if ok:
		var hp: Vector2 = a.host.global_position
		var kind := String(a.host.get("kind"))
		var rad := BiomeHazards.GRAV_R if kind == "gravity" else BiomeHazards.ELECTRIC_R
		var inside := a.global_position.distance_to(hp) < rad * 1.2
		var behind := a.z_index < SecretArtifact._abs_z(a.host)
		ok = inside and behind and kind in ["gravity", "electric"]
		detail = "host %s at %.0f m, offset %.0f px of r %.0f, z %d behind %d" % [kind, hp.x / 100.0, a.global_position.distance_to(hp), rad, a.z_index, SecretArtifact._abs_z(a.host)]
	check("artifact_inside_anomaly", ok, detail)
	# v36 exact whitelist: +15 displayed points on HP / acceleration / spring / control / energy, nothing else
	var all_ok := true
	var rows := []
	for id in IDS:
		var d := gm.catalog.get_by_id(id)
		for mk2 in [false, true]:
			var pre := ModuleDefinition.apply_all(d.base_stats(), [d.mk2_module()] if mk2 else [])
			var post := ModuleDefinition.apply_all(pre, [SecretArtifact.module(pre, gm.catalog)])
			var p0 := SecretArtifact.points(pre, gm.catalog)
			var p1 := SecretArtifact.points(post, gm.catalog)
			var good := true
			for key in p0:
				good = good and absf(float(p1[key]) - float(p0[key]) - 15.0) < 0.001
			for key in pre:
				if not String(key) in SecretArtifact.WHITELIST:
					good = good and is_equal_approx(float(pre[key]), float(post[key]))
			all_ok = all_ok and good
			if id == "heavy":
				rows.append("%s%s %s" % [id, " MK2" if mk2 else "", p1])
	check("artifact_exactly_plus_15_points", all_ok, "; ".join(rows))
	var m := SecretArtifact.module(gm.catalog.get_by_id("tin").base_stats(), gm.catalog)
	var forbidden := ["mass_multiplier", "size", "body_hit_scale", "spring_strength", "bounce", "momentum_forward_cap"]
	var leak := m.stat_multipliers.keys().filter(func(k) -> bool: return String(k) in forbidden)
	check("artifact_no_physical_stats", leak.is_empty() and m.stat_offsets.keys().all(func(k) -> bool: return not String(k) in forbidden), "%s" % [m.stat_multipliers])
	gm.go_menu()
	await frames(2)


# ---------------- 17. MK2 visual cleanup ----------------

static func _alpha_at(img: Image, p: Vector2i) -> float:
	if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
		return 0.0
	return img.get_pixelv(p).a


func mk2_visual_tests() -> void:
	# Samurobot MK2: no gold left on the dome top (master x 586..660, y 96..113) in any face frame
	var sh: Image = (load("res://assets/robots/samurai_mk2/head.png") as Texture2D).get_image()
	var smf: Dictionary = RobotArtLibrary.manifest("samurai_mk2")
	var fw := int(smf.parts.head.frame_size[0])
	var so: Array = smf.parts.head.source_origin
	var gold := 0
	for f in 7:
		for my in range(97, 113):
			for mx in range(588, 660):
				var c := sh.get_pixel(f * fw + int((mx - float(so[0])) * 0.5), int((my - float(so[1])) * 0.5))
				if c.a > 0.5 and c.r > 0.6 and c.g > 0.45 and c.b < 0.45 and c.r > c.b + 0.25:
					gold += 1
	check("mk2_samurai_dome_no_gold_remnant", gold == 0, "%d gold px" % gold)
	# Rastabot MK2: the right-shoulder dread tips belong to the head (not cut off)
	var th: Image = (load("res://assets/robots/tin_mk2/head.png") as Texture2D).get_image()
	var tmf: Dictionary = RobotArtLibrary.manifest("tin_mk2")
	var to: Array = tmf.parts.head.source_origin
	var tips := 0
	for mp in [Vector2(860, 340), Vector2(800, 336), Vector2(845, 330)]:
		tips += int(_alpha_at(th, Vector2i(int((mp.x - float(to[0])) * 0.5), int((mp.y - float(to[1])) * 0.5))) > 0.5)
	check("mk2_rastabot_dread_tips_whole", tips == 3, "%d/3 tip points in the head" % tips)
	# Kengurobot MK2: the tail root continues under the left thigh to the pelvis (tail box origin 178,531)
	var tl: Image = (load("res://assets/robots/hopper_mk2/tail.png") as Texture2D).get_image()
	var root := 0
	for mp in [Vector2(545, 780), Vector2(570, 760), Vector2(590, 735)]:
		root += int(_alpha_at(tl, Vector2i(int((mp.x - 178.0) * 0.5), int((mp.y - 531.0) * 0.5))) > 0.5)
	check("mk2_kengurobot_tail_root_covered", root == 3, "%d/3 root points" % root)


# ---------------- visual QA (1280x720, -Window --shots=DIR) ----------------

func qa_shots() -> void:
	at.set("scenario_running", true)
	# main menu physics robot
	gm.go_menu()
	await get_tree().create_timer(1.2).timeout
	for k in 3:
		at.call("_shot", "v36_menu_robot_%d" % k)
		await get_tree().create_timer(0.45).timeout
	# Exclusion Zone anomalies low / medium / high + feedback
	var r: RobotController = await start_robot("tin", false, 4242, "zone")
	gm.terrain.ensure_ahead(40000.0)
	await physics(4)
	var shown := {}
	for a in gm.hazards.anomalies:
		var key := "%s_%s" % [a.kind, a.band]
		if shown.has(key) or float(a.pos.x) < 3000.0:
			continue
		shown[key] = true
		r.freeze = true
		r.global_position = (a.pos as Vector2) + Vector2(-520, 0)
		gm.camera.snap_intro(r.global_position + Vector2(260, -40), 0.55)
		gm.camera.follow(r)
		await get_tree().create_timer(0.5).timeout
		at.call("_shot", "v36_anomaly_%s" % key)
	gm.state = GameManager.State.RUN
	r.launch(Vector2.ZERO, 0.0)
	r.damage.armed = true
	r.freeze = true
	for k in ["electric", "radiation", "gravity"]:
		for a in gm.hazards.anomalies:
			if a.kind == k and float(a.pos.x) > 3000.0:
				r.global_position = a.pos
				gm.camera.snap_intro(a.pos, 0.55)
				gm.camera.follow(r)
				await get_tree().create_timer(0.3).timeout
				gm.hazards.step_anomalies(r, {"cool": 0.0, "exit": -1, "inside": {}, "rad": 0.0, "rad_tick": 0.0, "dirt": 0.0, "was_contact": true}, 1.0 / 120.0)
				await get_tree().create_timer(0.06).timeout
				at.call("_shot", "v36_feedback_%s" % k)
				break
	# portals at varied heights
	r = await start_robot("tin", false, 4242, "portal")
	gm.terrain.ensure_ahead(40000.0)
	await physics(4)
	var pn := 0
	for i in gm.hazards.portals.size():
		var p: Dictionary = gm.hazards.portals[i]
		if int(p.partner) < 0 or pn >= 3:
			continue
		pn += 1
		var mid: Vector2 = ((p.pos as Vector2) + (gm.hazards.portals[i + 1].pos as Vector2)) * 0.5
		r.freeze = true
		r.global_position = mid + Vector2(0, 300)
		gm.camera.snap_intro(mid, 0.4)
		gm.camera.follow(r)
		await get_tree().create_timer(0.5).timeout
		at.call("_shot", "v36_portal_pair_%d_%s" % [pn, gm.hazards.portals[i + 1].band])
	# Cavern, several seeds
	for sd in [101, 202, 303]:
		r = await start_robot("samurai", false, sd, "cavern")
		await physics(2)
		r.launch(Vector2(1700, -1500), 2.0)
		await get_tree().create_timer(2.8).timeout
		at.call("_shot", "v36_cavern_%d" % sd)
	# secret artifact inside its anomaly
	gm.go_menu()
	await frames(2)
	gm.profile.artifact.discovered = false
	gm.mode = &"campaign"
	gm.node_id = SecretArtifact.NODE_ID
	gm.profile.ensure_campaign_start(SecretArtifact.NODE_ID)
	gm.debug_track_seed = 2222
	gm.start_run()
	await frames(3)
	gm.debug_track_seed = -1
	var x := 0.0
	while gm.artifact_node == null and x < 40000.0:
		x += 2000.0
		gm.terrain.ensure_ahead(x)
		gm.hazards.generate_now()
		gm._step_artifact()
	if gm.artifact_node:
		gm.ui.awareness.visible = false
		gm.robot.freeze = true
		gm.robot.global_position = gm.artifact_node.global_position + Vector2(-480, 120)
		gm.camera.snap_intro(gm.artifact_node.global_position, 0.75)
		gm.camera.mode = &"intro"
		await get_tree().create_timer(0.6).timeout
		at.call("_shot", "v36_artifact_in_anomaly")
	# Supergravity name (biome intro) + challenge cards of affected rounds
	for loc in ["ru", "en", "de", "ja"]:
		L.apply(loc)
		gm.go_menu()
		await frames(2)
		gm.ui.biome_intro.instant = false
		gm.ui.biome_intro.show_biome(BiomeCatalog.get_def("heavy"))
		await get_tree().create_timer(0.9).timeout
		at.call("_shot", "v36_supergravity_title_%s" % loc)
		gm.ui.biome_intro.cancel()
	L.apply("ru")
	for id in ["r45", "r79", "r36", "r31"]:
		gm.go_menu()
		await frames(2)
		gm.profile.ensure_campaign_start(id)
		gm.open_campaign_map()
		await frames(3)
		gm.ui.campaign_map.select_node(id)
		await get_tree().create_timer(0.5).timeout
		at.call("_shot", "v36_challenges_%s" % id)
	gm.go_menu()
	await frames(2)


# ---------------- 1. colour schemes (cosmetic only) ----------------

## Every gameplay-relevant number of a built robot (configs) - must not depend on the colour scheme.
static func _phys_sig(r: RobotController) -> Dictionary:
	var rc := r.config
	var cc := r.contact_config
	var out := {"hp": r.damage_config.max_health}
	for k in ["torso_mass", "head_mass", "arm_mass", "leg_mass", "rotation_response", "rig_scale", "inertia_radius", "charge_rate",
			"energy_boost_multiplier", "torso_hit_scale", "clockwise_rotation_speed", "counterclockwise_rotation_speed", "air_drag", "max_speed", "rig_json"]:
		out["r." + k] = rc.get(k)
	for k in ["spring_stiffness", "bottom_out_stiffness", "coil_rest_length", "coil_min_length", "coil_max_length", "foot_half_width",
			"gain_left", "gain_right", "gain_both_normal", "gain_both_flat", "gain_both_sweet", "gain_poor", "momentum_gain", "momentum_max",
			"momentum_forward_cap", "rebound_power", "min_natural_rebound_speed", "spring_power_scale"]:
		out["c." + k] = cc.get(k)
	out["c.max_speed_ratio"] = str(cc.max_speed_ratio)
	return out


func _shape_sig2(r: RobotController) -> Array:
	var out := []
	for c in r.get_children():
		if c is CollisionShape2D:
			var cs := c as CollisionShape2D
			var row := [c.get_index(), cs.position.snapped(Vector2(0.001, 0.001)), cs.shape.get_class()]
			for prop in ["radius", "height"]:
				if prop in cs.shape:
					row.append(snappedf(float(cs.shape.get(prop)), 0.001))
			out.append(row)
	out.append(["body", r.mass, r.center_of_mass.snapped(Vector2(0.001, 0.001)), r.inertia, r.collision_layer, r.collision_mask])
	return out


func skin_tests() -> void:
	gm.go_menu()
	await frames(2)
	var stat_bad := []
	var art_bad := []
	var count := 0
	for id in IDS:
		var d := gm.catalog.get_by_id(id)
		var list := gm.skins.for_robot(id)
		var alt := list.filter(func(s: SkinDefinition) -> bool: return s.source != "default")
		if alt.is_empty():
			art_bad.append(id + ": no alternate scheme")
		for mk2 in [false, true]:
			var ref: Dictionary = {}
			var ref_shapes: Array = []
			for s in list:
				var r := gm.build_robot(d, InputRouter.new(), null, s.id, mk2)
				gm.dynamic.add_child(r)
				await get_tree().physics_frame
				var sig := _phys_sig(r)
				var shp := _shape_sig2(r)
				count += 1
				if ref.is_empty():
					ref = sig
					ref_shapes = shp
				elif str(sig) != str(ref) or str(shp) != str(ref_shapes):
					stat_bad.append("%s%s %s" % [id, " MK2" if mk2 else "", s.id])
				var want := (d.mk2_visual_id if mk2 else d.effective_visual_id()) + ("__" + s.scheme if s.scheme != "" else "")
				if r.config.visual_id != want or r.config.visual_material != null:
					art_bad.append("%s%s %s visual %s (want %s) shader %s" % [id, " MK2" if mk2 else "", s.id, r.config.visual_id, want, r.config.visual_material != null])
				r.queue_free()
			await frames(1)
	check("schemes_cover_all_10_versions", art_bad.is_empty(), "%s" % [art_bad])
	check("schemes_never_change_stats_or_collision", stat_bad.is_empty() and count >= 20, "%d robot builds compared %s" % [count, stat_bad])
	# repainted art: same parts / sizes / geometry as the version it belongs to
	var geo_bad := []
	for s in gm.skins.skins:
		if s.scheme == "":
			continue
		var d := gm.catalog.get_by_id(s.robot_id)
		for mk2 in [false, true]:
			var src := RobotArtLibrary.manifest(d.mk2_visual_id if mk2 else d.effective_visual_id())
			var dst := RobotArtLibrary.manifest(s.art_visual_id(d, mk2))
			var a := (src.duplicate(true) as Dictionary)
			var b := (dst.duplicate(true) as Dictionary)
			for k in ["visual_id", "scheme"]:
				a.erase(k); b.erase(k)
			if JSON.stringify(a) != JSON.stringify(b):
				geo_bad.append(s.id + (" MK2" if mk2 else ""))
			for part in (src.get("parts", {}) as Dictionary).keys() + (["tail"] if FileAccess.file_exists("res://assets/robots/%s/tail.png" % RobotArtLibrary.resolve_asset_id(d.mk2_visual_id if mk2 else d.effective_visual_id())) else []):
				var t0 := RobotArtLibrary.atlas(d.mk2_visual_id if mk2 else d.effective_visual_id(), part)
				var t1 := RobotArtLibrary.atlas(s.art_visual_id(d, mk2), part)
				if t0 == null or t1 == null or t0.get_size() != t1.get_size():
					geo_bad.append("%s%s %s size" % [s.id, " MK2" if mk2 else "", part])
	check("scheme_art_same_geometry", geo_bad.is_empty(), "%s" % [geo_bad])
	# per-version save / restore, old saves
	var path := "user://test/v36_skins/profile.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var p := ProfileStore.new(path, gm.catalog, gm.skins)
	p.reset()
	p.owned.append("samurai")
	p.grant_skin("samurai_shogun")
	p.equip_skin("samurai", "samurai_shogun", true)
	var q := ProfileStore.new(path, gm.catalog, gm.skins)
	q.load_data()
	check("scheme_saved_per_version", q.equipped_skin("samurai", true) == "samurai_shogun" and q.equipped_skin("samurai", false) == "samurai_default")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "coins": 5, "owned": ["tin", "samurai"], "selected": "samurai", "owned_skins": ["samurai_shogun"],
		"equipped_skins": {"samurai": "samurai_shogun"}}))
	f.close()
	var old := ProfileStore.new(path, gm.catalog, gm.skins)
	old.load_data()
	check("scheme_old_save_compatible", old.equipped_skin("samurai") == "samurai_shogun" and old.equipped_skin("samurai", true) == "samurai_default" and old.coins == 5,
		"status %s" % old.last_load_status)
	# Robot Select: robot -> robot, BASE <-> MK2, scheme -> scheme always show the right art
	gm.profile.owned.append("samurai")
	if not gm.profile.mk2_owned.has("samurai"):
		gm.profile.mk2_owned.append("samurai")
	gm.profile.grant_skin("samurai_shogun")
	gm.profile.equip_skin("samurai", "samurai_shogun", false)
	gm.profile.equip_skin("samurai", "samurai_default", true)
	gm.open_robot_select()
	await frames(3)
	var rs := gm.ui.robot_select
	while rs.current().id != "samurai":
		rs.step(1)
	await frames(2)
	rs.set_view_mk2(false)
	await frames(2)
	var v_base: String = rs.preview.rig.visual_id
	rs.set_view_mk2(true)
	await frames(2)
	var v_mk2: String = rs.preview.rig.visual_id
	rs.step_skin(1)
	await frames(2)
	var v_mk2_alt: String = rs.preview.rig.visual_id
	var eq_after := gm.profile.equipped_skin("samurai", true)
	rs.set_view_mk2(false)
	await frames(2)
	var v_base_again: String = rs.preview.rig.visual_id
	rs.step(1)
	await frames(2)
	var other: String = rs.preview.rig.visual_id
	check("select_shows_right_scheme_per_version", v_base == "samurai__shogun" and v_mk2 == "samurai_mk2" and v_mk2_alt == "samurai_mk2__shogun"
		and eq_after == "samurai_shogun" and v_base_again == "samurai__shogun" and not other.begins_with("samurai"),
		"base %s / mk2 %s -> %s (equipped %s) / base %s / next robot %s" % [v_base, v_mk2, v_mk2_alt, eq_after, v_base_again, other])
	var names_ok := true
	for s in gm.skins.skins:
		names_ok = names_ok and L.has_key(String(L.data_keys().get(s.display_name, ""))) if s.source != "default" else names_ok
	check("scheme_names_localized", names_ok)
	gm.go_menu()
	await frames(2)


## 1280x720 Robot Select captures of every robot x version x scheme (owner review sheet: reports/v36/schemes/).
func scheme_shots() -> void:
	for id in IDS:
		if not gm.profile.owned.has(id):
			gm.profile.owned.append(id)
		if not gm.profile.mk2_owned.has(id):
			gm.profile.mk2_owned.append(id)
	for s in gm.skins.skins:
		gm.profile.grant_skin(s.id)
	gm.profile.save()
	gm.open_robot_select()
	await frames(4)
	var rs := gm.ui.robot_select
	for id in IDS:
		while rs.current().id != id:
			rs.step(1)
			await frames(1)
		for mk2 in [false, true]:
			rs.set_view_mk2(mk2)
			var list := gm.skins.for_robot(id)
			for i in list.size():
				gm.profile.equip_skin(id, list[i].id, mk2)
				rs.set_view_mk2(mk2)
				await get_tree().create_timer(0.35).timeout
				at.call("_shot", "scheme_%s_%s_%s" % [id, "mk2" if mk2 else "base", "default" if list[i].source == "default" else list[i].scheme])
	gm.go_menu()
	await frames(2)
