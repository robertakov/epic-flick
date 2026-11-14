extends Node
## v32 final gameplay & balance pass tests (debug only, not exported).
##   --scenario=v32_all     : focused suite (momentum, specialisation, record, NO_TOUCH, continue, artifact, profiles)
##                            needs -Window (real taps) and --profiles_root=<test dir> for the profile-isolation parts
##   --scenario=v32_measure : jump / momentum-chain measurements (AT|measure lines)
##   --scenario=v32_probe   : collision shapes vs art per robot
##   --scenario=v32_qa      : screenshots (thrusters, continue card, artifact, artifact toggle)
## Prints "AT|test v32_<name> PASS|FAIL <details>".
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const ROBOTS := ["tin", "hopper", "heavy", "rocket", "samurai"]


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test v32_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run_all(which: String) -> void:
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	match which:
		"v32_thruster":
			# v36 diagnostic: only the thruster checks; --old_floor = the pre-v36 natural rebound floor (300 / 6)
			if (at.get("args") as Dictionary).has("old_floor"):
				gm.contact_config.min_natural_rebound_speed = 300.0
				gm.contact_config.min_natural_extension_comp = 6.0
			await thruster_tests()
		"v32_probe":
			await probe_shapes()
		"v32_nozzle":
			await nozzle_shots()
		"v32_measure":
			await measure_jumps()
			await measure_chains()
		"v32_qa":
			await qa()
		"v32_jellyprobe":
			for mom in [false, true]:
				for biome in ["", "jelly"]:
					gm.debug_track_seed = 424242
					await at.get_node(".").get_tree().process_frame
					var r: RobotController = await start_robot(String(gm.profile.selected), 424242, biome)
					if not mom:
						r.contacts.cfg.momentum_gain = 0.0
					var px := 2600.0
					for k in 200:
						var nx := 2400.0 + k * 40.0
						if absf(gm.terrain.normal_at(nx).x) < 0.12 and gm.terrain.gap_index(nx) < 0:
							px = nx
							break
					r.global_position = Vector2(px, gm.terrain.surface_y(px) - 380.0)
					r.rotation = 0.0
					r.launch(Vector2.ZERO, 0.0)
					var evs := []
					r.landed.connect(func(i: Dictionary) -> void: evs.append("%s/%s vn=%.0f m=%.0f b=%.0f" % [i.type, i.quality, (i.velocity_out as Vector2).dot(i.normal), i.get("momentum", 0.0), i.get("momentum_boost", 0.0)]))
					for i in 240:
						await get_tree().physics_frame
						r.angular_velocity = 0.0
						if evs.size() >= 3:
							break
					print("AT|probe jelly robot=%s momentum=%s biome=%s x=%.0f events=%s" % [gm.profile.selected, mom, biome, px, evs])
		"v32_tune":
			# v34 tuning probe: --tune_ids=a,b --tune_gains=g1,g2 (gain only applies to the listed ids; -1 = definition)
			var ids := ["tin", "heavy", "samurai"]
			var gains := [-1.0]
			var align := Array(OS.get_cmdline_user_args()).has("--tune_aligned")
			var on_slope := Array(OS.get_cmdline_user_args()).has("--tune_slope")
			# cases: real tracks = 8 seeds; practice slope = 4 launch velocities
			var seeds_used: Array = TUNE_SEEDS + TUNE_SEEDS_EXTRA if Array(OS.get_cmdline_user_args()).has("--tune_many") else TUNE_SEEDS
			var cases := seeds_used.map(func(sd: int) -> Array: return [sd, Vector2(700, -350)])
			if on_slope:
				cases = [[4242, Vector2(500, -300)], [4242, Vector2(700, -350)], [4242, Vector2(900, -400)], [4242, Vector2(650, -650)]]
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--tune_ids="):
					ids = Array(a.substr(11).split(","))
				if a.begins_with("--tune_gains="):
					gains = Array(a.substr(13).split(",")).map(func(s: String) -> float: return float(s))
			for secs in [6.0, 12.0]:
				for id in ids:
					var offs := {}
					for ci in cases.size():
						offs[ci] = (await chain(id, secs, false, cases[ci][1], cases[ci][0], -1.0, align, on_slope)).dist
					for g in gains:
						var vals := []
						for ci in cases.size():
							var on: Dictionary = await chain(id, secs, true, cases[ci][1], cases[ci][0], g, align, on_slope)
							vals.append(on.dist / maxf(float(offs[ci]), 0.01) - 1.0)
						var mean := 0.0
						for v in vals:
							mean += v / vals.size()
						var sorted := vals.duplicate()
						sorted.sort()
						print("AT|tune slope=%s aligned=%s secs=%.0f %s gain=%.0f mean=%+.1f%% median=%+.1f%% min=%+.1f%% max=%+.1f%% per_seed=%s" % [on_slope, align, secs, id, g, mean * 100.0,
							(sorted[(sorted.size() - 1) / 2] + sorted[sorted.size() / 2]) * 50.0, sorted[0] * 100.0, sorted[-1] * 100.0, vals.map(func(v: float) -> int: return int(round(v * 100.0)))])
		"v32_chaindetail":
			for sd in [4242, 5151]:
				for id in ["rocket", "tin"]:
					var on: Dictionary = await chain(id, 6.0, true, Vector2(700, -350), sd)
					print("AT|detail seed=%d %s dist=%.1f vx=%.0f landings=%s" % [sd, id, on.dist, on.vx, on.landings])
		"v32_chainprobe":
			# v34 diagnostics: momentum gain per robot over several seeds / longer windows (release physics)
			for secs in [6.0, 12.0]:
				var sums := {}
				for sd in [4242, 5151, 777, 31337]:
					for id in ROBOTS:
						var on: Dictionary = await chain(id, secs, true, Vector2(700, -350), sd)
						var off: Dictionary = await chain(id, secs, false, Vector2(700, -350), sd)
						var gn: float = on.dist / maxf(off.dist, 0.01) - 1.0
						sums[id] = float(sums.get(id, 0.0)) + gn / 4.0
						print("AT|probe chain secs=%.0f seed=%d %s %+.0f%% landings=%d" % [secs, sd, id, gn * 100.0, on.landings.size()])
				print("AT|probe chain secs=%.0f MEAN %s" % [secs, sums])
		_:
			gm.continue_offers_enabled = false   # only the continue tests turn offers on (a paused offer would stall others)
			momentum_rules()
			await momentum_engine()
			await specialisation()
			await record_tests()
			await no_touch_tests()
			await continue_tests()
			await artifact_tests()
			await profile_isolation()
			gm.debug_track_seed = -1
			gm.go_menu()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ======================================================================================================
# 14. momentum
# ======================================================================================================

func momentum_rules() -> void:
	var M := MomentumRules
	var clean := {"type": &"both", "quality": &"flat"}
	var m1 := M.update(0.0, clean, 55.0, 220.0)
	var m2 := M.update(m1, {"type": &"both", "quality": &"sweet"}, 55.0, 220.0)
	check("momentum_clean_landing_increases", is_equal_approx(m1, 55.0), str(m1))
	check("momentum_repeated_clean_increases_further", is_equal_approx(m2, 110.0), str(m2))
	var m := 0.0
	for i in 10:
		m = M.update(m, clean, 55.0, 220.0)
	check("momentum_cap", is_equal_approx(m, 220.0), str(m))
	check("momentum_acceptable_landing_small_gain", is_equal_approx(M.update(100.0, {"type": &"both", "quality": &"normal"}, 55.0, 220.0), 122.0))
	check("momentum_one_foot_preserves", is_equal_approx(M.update(100.0, {"type": &"left"}, 55.0, 220.0), 100.0))
	check("momentum_awkward_loses", is_equal_approx(M.update(100.0, {"type": &"poor"}, 55.0, 220.0), 50.0))
	check("momentum_body_major_loss", is_equal_approx(M.update(100.0, {"type": &"body", "impact": 400.0}, 55.0, 220.0), 20.0))
	check("momentum_head_or_severe_resets", M.update(200.0, {"type": &"body", "charge_zone": &"head", "impact": 100.0}, 55.0, 220.0) == 0.0
		and M.update(200.0, {"type": &"body", "impact": 1200.0}, 55.0, 220.0) == 0.0)
	check("momentum_no_nan", M.update(NAN, clean, 55.0, 220.0) == 55.0 and M.update(INF, {"type": &"left"}, 55.0, 220.0) == 0.0
		and M.boost(NAN, 0.0, 1800.0) == 0.0 and M.boost(100.0, INF, 1800.0) == 0.0)
	check("momentum_boost_forward_fades_to_cap", is_equal_approx(M.boost(200.0, 0.0, 1800.0), 200.0) and M.boost(200.0, 1800.0, 1800.0) == 0.0
		and M.boost(200.0, 2500.0, 1800.0) == 0.0 and is_equal_approx(M.boost(200.0, 900.0, 1800.0), 100.0))
	check("momentum_boost_is_forward_only", M.forward_tangent(Vector2(0, -1)).is_equal_approx(Vector2(1, 0))
		and M.forward_tangent(Vector2(0.4, -0.9165)).x > 0.0)


var chains := {}
const TUNE_SEEDS := [4242, 5151, 777, 31337, 2024, 9001, 1234, 8086]
const TUNE_SEEDS_EXTRA := [11, 222, 3333, 44444, 5050, 606, 7070, 8888]

## Mean momentum gain (distance with / without momentum - 1) of one robot over the identity cases (6 s each).
func _identity_mean(id: String, on_slope: bool) -> float:
	var cases: Array = [[4242, Vector2(500, -300)], [4242, Vector2(700, -350)], [4242, Vector2(900, -400)], [4242, Vector2(650, -650)]] \
		if on_slope else TUNE_SEEDS.map(func(sd: int) -> Array: return [sd, Vector2(700, -350)])
	var total := 0.0
	for c in cases:
		var off: Dictionary = await chain(id, 6.0, false, c[1], c[0], -1.0, false, on_slope)
		var on: Dictionary = await chain(id, 6.0, true, c[1], c[0], -1.0, false, on_slope)
		total += on.dist / maxf(float(off.dist), 0.01) - 1.0
	return total / cases.size()


func momentum_engine() -> void:
	for id in ROBOTS:
		var on: Dictionary = await chain(id)
		var off: Dictionary = await chain(id, 6.0, false)
		chains[id] = {"on": on, "off": off, "gain": on.dist / maxf(off.dist, 0.01) - 1.0}
		print("AT|measure chain %s dist %.1f vs %.1f m (%+.0f%%) vx %.0f vs %.0f max_speed %.0f" % [id, on.dist, off.dist,
			chains[id].gain * 100.0, on.vx, off.vx, on.max_speed])
	# v34 release baseline (200 % springs): the identity is judged on MULTIPLE cases, not one scripted chain -
	# 8 real tracks (upright scripted pilot, chaotic: one-foot landings can stop any chain) + the controlled 6 %
	# practice slope (clean landings, 4 launch velocities). Mean momentum gain over 6 s per robot.
	var real := {}
	var slope := {}
	for id in ROBOTS:
		real[id] = await _identity_mean(id, false)
		slope[id] = await _identity_mean(id, true)
	print("AT|measure identity real8 %s slope4 %s" % [real, slope])
	var others_real := maxf(float(real.tin), float(real.samurai))
	var others_slope := 0.0
	for id in ["tin", "samurai", "heavy", "hopper"]:
		others_slope = maxf(others_slope, float(slope[id]))
	check("chrono_strongest_forward_acceleration", float(real.rocket) >= 1.2 * others_real and float(slope.rocket) >= 1.5 * others_slope,
		"real tracks rocket %+.0f%% vs best other %+.0f%%; slope rocket %+.0f%% vs best other %+.0f%%" % [float(real.rocket) * 100, others_real * 100, float(slope.rocket) * 100, others_slope * 100])
	check("kengurobot_not_speed_specialist", float(real.hopper) < float(real.rocket) * 0.4 and float(slope.hopper) < float(slope.rocket) * 0.4,
		"hopper real %+.0f%% slope %+.0f%%" % [float(real.hopper) * 100, float(slope.hopper) * 100])
	check("sumobot_weak_acceleration", float(real.heavy) < float(real.samurai) and float(real.heavy) < float(real.rocket) * 0.25
		and float(slope.heavy) < float(slope.samurai) and float(slope.heavy) < float(slope.tin) and float(slope.heavy) < float(slope.rocket) * 0.35,
		"heavy real %+.0f%% slope %+.0f%%" % [float(real.heavy) * 100, float(slope.heavy) * 100])
	var finite := true
	var fast := 0.0
	for id in chains:
		finite = finite and bool(chains[id].on.finite)
		fast = maxf(fast, float(chains[id].on.max_speed))
	check("momentum_chains_finite_and_bounded", finite and fast < 2900.0, "max speed %.0f" % fast)
	# a runaway attempt: absurd gain / ceiling must still respect the release-speed guard
	var r: RobotController = await start_robot("rocket", 4242)
	r.contacts.cfg.momentum_gain = 1.0e9
	r.contacts.cfg.momentum_max = 1.0e9
	r.contacts.cfg.momentum_forward_cap = 1.0e9
	r.launch(Vector2(900, -300), 0.0)
	var top := 0.0
	var ok := true
	for i in 120 * 5:
		await get_tree().physics_frame
		if not is_instance_valid(r) or gm.state != GameManager.State.RUN:
			break
		r.angular_velocity = 0.0
		r.rotation = 0.0
		ok = ok and is_finite(r.linear_velocity.x) and is_finite(r.linear_velocity.y)
		top = maxf(top, r.linear_velocity.length())
	check("momentum_safety_limits_hold", ok and top <= r.config.max_speed + 1.0, "top %.0f (robot max_speed %.0f)" % [top, r.config.max_speed])


# ======================================================================================================
# 15. specialisation
# ======================================================================================================

func specialisation() -> void:
	var jumps := {}
	for id in ROBOTS:
		jumps[id] = await drop(id)
	var k := float(jumps.hopper.apex)
	var best_other := 0.0
	for id in ROBOTS:
		if id != "hopper":
			best_other = maxf(best_other, float(jumps[id].apex))
	check("kengurobot_jumps_higher", k > best_other * 1.25, "hopper %.0f px vs best other %.0f px (samurai %.0f, rocket %.0f, heavy %.0f)" %
		[k, best_other, jumps.samurai.apex, jumps.rocket.apex, jumps.heavy.apex])
	var k0: Dictionary = await drop("hopper", 380.0, 1.0)
	check("kengurobot_jump_comes_from_rebound_power", k > float(k0.apex) * 1.2, "%.0f vs %.0f" % [k, k0.apex])
	# survivability: real head hits until 0 HP
	var hits := {}
	for id in ["heavy", "samurai", "rocket", "tin"]:
		var r: RobotController = await start_robot(id)
		var n := 0
		while r.damage.health > 0.0 and n < 50:
			r.damage.invulnerable_left = 0.0
			r.damage._apply(&"head", {"point": r.global_position, "normal": Vector2.UP, "impact": 600.0})
			n += 1
		hits[id] = n
	# v34: Sumobot 170 HP (highest base) - still the most hits, no longer a +2 margin over Самуробот (155)
	check("sumobot_survives_far_more", int(hits.heavy) >= int(hits.samurai) and int(hits.heavy) >= 2 * int(hits.rocket) and int(hits.heavy) >= int(hits.tin) + 2,
		"head hits to 0 HP: %s" % hits)
	# Sumobot body collider ~ normal robot, still solid against terrain, limbs still detach
	var sumo: RobotController = await start_robot("heavy")
	var sam_r := 44.0 * 0.42 / 0.42
	var cap: CapsuleShape2D = null
	for c in sumo.get_children():
		if c is CollisionShape2D and c.get_meta(&"zone", &"") == &"torso":
			cap = (c as CollisionShape2D).shape as CapsuleShape2D
	check("sumobot_body_collider_normal_size", cap != null and absf(cap.radius - sam_r) < 0.6 and absf(cap.height - 100.0) < 1.2,
		"r %.1f h %.1f (was r 49.3 h 112)" % [cap.radius if cap else -1.0, cap.height if cap else -1.0])
	var x := flat_x(3000.0)
	sumo.global_position = Vector2(x, gm.terrain.surface_y(x) - 260.0)
	sumo.rotation = PI * 0.5
	sumo.launch(Vector2(0, 300), 0.0)
	var body_contact := false
	var through := false
	var dmg := [0.0]
	sumo.damaged.connect(func(a: float, _z: StringName, _h: float, _i: Dictionary) -> void: dmg[0] += a)
	for i in 120 * 2:
		await get_tree().physics_frame
		if not is_instance_valid(sumo):
			break
		body_contact = body_contact or sumo.contacts.any_body_contact
		through = through or sumo.global_position.y > gm.terrain.surface_y(sumo.global_position.x) + 40.0
	check("sumobot_collider_hits_terrain_and_damages", body_contact and not through and dmg[0] > 0.0, "damage %.0f" % dmg[0])
	sumo = await start_robot("heavy")
	sumo.launch(Vector2(200, -200), 0.0)
	await physics(10)
	var lost := []
	sumo.limb_lost.connect(func(l: StringName, _p: RigidBody2D) -> void: lost.append(l))
	sumo.damage.invulnerable_left = 0.0
	sumo.damage.health = sumo.damage.max_health * 0.55
	sumo.damage._apply(&"side", {"point": sumo.global_position, "normal": Vector2.UP, "impact": 500.0})
	await physics(3)
	check("sumobot_limbs_still_detach", lost.size() >= 2, str(lost))
	var mv: Dictionary = await chain("heavy", 4.0)
	check("sumobot_moves_normally", float(mv.dist) > 8.0 and bool(mv.finite), "%.1f m" % mv.dist)
	await thruster_tests()


func thruster_tests() -> void:
	var r: RobotController = await start_robot("rocket", 4242)
	var nozzles := 0
	for side in r.visual.legs:
		nozzles += int((r.visual.legs[side] as LegVisual).nozzle != null)
	var idf: RobotIdentityFeedback = r.visual.identity
	var levels := []
	r.landed.connect(func(i: Dictionary) -> void:
		if String(i.type) in ["left", "right", "both"]:
			levels.append([float(i.get("momentum", 0.0)), idf._thrust_level]))
	r.launch(Vector2(700, -350), 0.0)
	var on_frames := 0
	var total := 0
	var run := 0.0
	var longest := 0.0
	# physics frames: forcing the rotation from a process frame would re-apply a stale node transform
	for i in 120 * 6:
		await get_tree().physics_frame
		if not is_instance_valid(r) or gm.state != GameManager.State.RUN:
			break
		r.angular_velocity = 0.0
		r.rotation = 0.0
		var lit := false
		for side in r.visual.legs:
			var ex: LegExhaust = (r.visual.legs[side] as LegVisual).exhaust
			lit = lit or (ex != null and ex.visible)
		total += 1
		on_frames += int(lit)
		run = run + get_physics_process_delta_time() if lit else 0.0
		longest = maxf(longest, run)
	print("AT|diag thruster frames=%d state=%s landings=%d pos=%s vel=%s freeze=%s launched=%s same=%s" % [total, GameManager.State.keys()[gm.state], levels.size(),
		r.global_position, r.linear_velocity, r.freeze, r.launched, r == gm.robot])
	check("chrono_has_enlarged_nozzles", nozzles == 2)
	check("chrono_thrust_flashes_on_landings", idf.thrust_flashes >= 3 and levels.size() >= 3, "flashes %d" % idf.thrust_flashes)
	# v36 (legit update): the higher natural rebound floor turns more tiny landings into real hops (19 vs 17 flashes in
	# this run; old floor: lit 34 %, longest 0.36 s / new: 38 %, 0.33 s) - each flash stays short, so the share limit is 42 %
	check("chrono_flame_not_permanent", total > 0 and float(on_frames) / total < 0.42 and longest <= 0.12 + RobotIdentityFeedback.THRUST_MAX_S + 0.05,   # v34: touchdown puff (0.12 s) may chain into the rebound kick with the 200 % springs
		"lit %.0f%% longest %.2fs" % [100.0 * on_frames / maxi(total, 1), longest])
	var low := 1.0
	var high := 0.0
	for e in levels:
		if float(e[0]) < 150.0:
			low = minf(low, float(e[1]))
		if float(e[0]) >= 270.0:
			high = maxf(high, float(e[1]))
	check("chrono_flash_scales_with_momentum", high > low, "low-momentum flash %.2f high-momentum flash %.2f (%s)" % [low, high, levels])
	var other: RobotController = await start_robot("samurai", 4242)
	var any := false
	for side in other.visual.legs:
		any = any or (other.visual.legs[side] as LegVisual).exhaust != null or (other.visual.legs[side] as LegVisual).nozzle != null
	check("thrusters_only_on_chronobot", not any)


# ======================================================================================================
# 16. global record
# ======================================================================================================

func record_tests() -> void:
	gm.go_menu()
	await frames(2)
	gm.stats.data = StatsStore.defaults()
	gm.stats.save()
	gm.best_m = 0.0
	# Free Run establishes the record
	var res := gm.stats.record_attempt({"id": "rec1", "distance_m": 120.0})
	check("record_free_run", res.record and is_equal_approx(gm.stats.best_m(), 120.0))
	# Campaign establishes it too (real _finish of a campaign attempt)
	await _campaign_finish_at("r1", 300.0)
	check("record_campaign_updates_global", is_equal_approx(gm.stats.best_m(), 300.0) and is_equal_approx(gm.best_m, 300.0) and gm.campaign_record)
	gm.go_menu()
	await frames(2)
	check("record_shown_in_menu", gm.ui.best_label_menu.text == "РЕКОРД: 300 м", gm.ui.best_label_menu.text)
	# worse results never overwrite
	gm.stats.record_attempt({"id": "rec2", "distance_m": 90.0})
	await _campaign_finish_at("r1", 50.0)
	check("record_worse_never_overwrites", is_equal_approx(gm.stats.best_m(), 300.0) and not gm.campaign_record)
	var reload := StatsStore.new(gm.stats.path)
	reload.load_data()
	check("record_persists", is_equal_approx(reload.best_m(), 300.0))
	check("record_campaign_keeps_level_progress", gm.campaign.nodes.has("r1") and gm.profile.attempts_on("r1") >= 0)
	gm.go_menu()
	await frames(2)


## A campaign attempt on node id ends at `meters` through the real GameManager._finish path.
func _campaign_finish_at(id: String, meters: float) -> void:
	gm.go_menu()
	await frames(2)
	gm.mode = &"campaign"
	gm.node_id = id
	gm.profile.ensure_campaign_start(id)
	gm.ui.biome_intro.instant = true
	gm.start_run()
	if gm.ui.awareness.visible:
		gm.ui.awareness.confirm.pressed.emit()
	await frames(3)
	gm.hand.playing = false
	gm.state = GameManager.State.RUN
	gm.robot.launch(Vector2(300, -200), 0.0)
	await physics(2)
	gm.distance_m = meters
	var offers := gm.continue_offers_enabled
	gm.continue_offers_enabled = false
	gm._finish("test")
	gm.continue_offers_enabled = offers
	await frames(2)


# ======================================================================================================
# 17. NO_TOUCH_AND_WIN + rocket head
# ======================================================================================================

func no_touch_tests() -> void:
	var all35 := true
	for id in gm.campaign.order:
		for ch in gm.campaign.node(id).get("stars", []):
			if String(ch.type) == "NO_TOUCH_AND_WIN":
				all35 = all35 and is_equal_approx(float(ch.s), 3.5)
	check("no_touch_stays_3_5s", all35)
	var st := StarTracker.new([{"type": "NO_TOUCH_AND_WIN", "s": 3.5}])
	st.sample_no_touch(3.4, false)
	st.sample_no_touch(1.0, false, true)   # jet-head flight
	st.on_race_result(true, 120.0, 100.0)
	check("no_touch_3_4_plus_rocket_fails", st.status[0] != 1 and is_equal_approx(float(st._m.max_no_touch_s), 3.4), "max %.2f" % st._m.max_no_touch_s)
	st = StarTracker.new([{"type": "NO_TOUCH_AND_WIN", "s": 3.5}])
	st.sample_no_touch(3.6, false)
	st.sample_no_touch(2.0, false, true)
	st.on_race_result(true, 120.0, 100.0)
	check("no_touch_pre_head_completion_kept", st.status[0] == 1)
	# real robot: a fired jet head stops accumulation even without the explicit flag
	var r: RobotController = await start_robot("samurai")
	st = StarTracker.new([{"type": "NO_TOUCH_AND_WIN", "s": 3.5}])
	st.attach(r)
	st.sample_no_touch(3.0, false)
	r.damage.rocket_fired = true
	st.sample_no_touch(2.0, false)
	check("no_touch_robot_rocket_flag_stops_time", is_equal_approx(float(st._m.max_no_touch_s), 3.0))
	st.stop()


# ======================================================================================================
# 18. paid continue
# ======================================================================================================

## Free run with the given coins, launched and moving; returns the robot.
func _run_with_coins(coins: int, biome := "", id := "samurai") -> RobotController:
	gm.go_menu()
	await frames(2)
	gm.profile.coins = coins
	gm.profile.save()
	var r: RobotController = await start_robot(id, 777, biome)
	gm.robot.launch(Vector2(700, -300), 0.0)
	return r


## v34 two-stage purchase: ПРОДОЛЖИТЬ opens the confirmation, ПОДТВЕРДИТЬ (armed after CONFIRM_ARM_S) spends.
func _confirm_continue() -> void:
	var card := gm.ui.continue_card
	card.yes.pressed.emit()
	await _wait_unpaused_s(ContinueCard.CONFIRM_ARM_S + 0.1)
	card.confirm_yes.pressed.emit()


func _wait_unpaused_s(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func continue_tests() -> void:
	gm.continue_offers_enabled = true
	await _continue_tests()
	gm.continue_offers_enabled = false
	get_tree().paused = false


func _continue_tests() -> void:
	var price := gm.continue_price()
	check("continue_price_is_high_and_central", price == int(gm.economy.continue_price) and price >= 500, str(price))
	# insufficient coins: no offer, nothing spent
	await _run_with_coins(price - 1)
	await physics(60)
	gm._finish("Робот остановился")
	check("continue_insufficient_coins_rejected", gm.state == GameManager.State.RESULT and gm.profile.coins == price - 1 + gm._coins_earned
		and not gm.ui.continue_card.visible and not gm.accept_continue())
	# affordable: paused offer with price + balance, nothing spent until the explicit press
	await _run_with_coins(price + 400)
	await physics(240)
	var d_before := gm.distance_m
	var max_x := gm._max_x
	gm._finish("Робот остановился")
	var card := gm.ui.continue_card
	check("continue_offer_shown_paused", gm.state == GameManager.State.OFFER and get_tree().paused and card.visible
		and card.price_label.text.contains(str(price)) and card.price_label.text.contains(str(price + 400)))
	card.yes.pressed.emit()   # too early: not armed yet
	check("continue_never_auto_spends", gm.profile.coins == price + 400 and gm.state == GameManager.State.OFFER)
	await _wait_unpaused_s(ContinueCard.ARM_S + 0.15)
	await _confirm_continue()   # v34: ПРОДОЛЖИТЬ -> ПОДТВЕРДИТЬ
	var r := gm.robot
	var rx := r.global_position.x
	await physics(2)
	check("continue_cost_deducted_once", gm.profile.coins == 400 and gm._continue_used and gm.state == GameManager.State.RUN and not get_tree().paused)
	var reload := ProfileStore.new(gm.profile.path, gm.catalog)
	reload.load_data()
	check("continue_payment_saved", reload.coins == 400)
	check("continue_distance_preserved", gm.distance_m >= d_before and gm._max_x >= max_x, "%.1f -> %.1f" % [d_before, gm.distance_m])
	check("continue_safe_respawn", gm.respawn_ok(rx) and r.global_position.y < gm.terrain.surface_y(r.global_position.x) and rx <= max_x + 1.0,
		"x %.0f (max %.0f)" % [rx, max_x])
	check("continue_hp_restored_partially", is_equal_approx(r.damage.health, r.damage.max_health * gm.economy.continue_hp_ratio)
		and r.damage.health < r.damage.max_health and r.damage.limbs_remaining.size() == 4)
	r.damage.armed = true
	var hp := r.damage.health
	r.damage.tick(1.0 / 120.0, {&"head": {"point": r.global_position, "normal": Vector2.UP, "impact": 900.0}})
	check("continue_spawn_protection", is_equal_approx(r.damage.health, hp) and r.damage.invulnerable_left > 1.5)
	await physics(120)
	check("continue_no_instant_death", is_instance_valid(r) and gm.state == GameManager.State.RUN and r.damage.health > 0.0)
	# second end: no second offer, the attempt ends normally, no more coins taken
	gm._finish("Робот остановился")
	check("continue_only_once_per_attempt", gm.state == GameManager.State.RESULT and not card.visible and gm.profile.coins == 400 + gm._coins_earned)
	# declining ends normally and keeps the coins
	await _run_with_coins(price + 1)
	await physics(60)
	gm._finish("Робот остановился")
	await _wait_unpaused_s(ContinueCard.ARM_S + 0.15)
	card.no.pressed.emit()
	await frames(2)
	check("continue_decline_ends_normally", gm.state == GameManager.State.RESULT and gm.profile.coins == price + 1 + gm._coins_earned and not get_tree().paused)
	challenge_after_continue()
	await chasm_continue()


func challenge_after_continue() -> void:
	var st := StarTracker.new([{"type": "SURVIVAL_HP", "m": 500, "hp": 40}, {"type": "DISTANCE", "m": 100},
		{"type": "GOOD_LANDING_STREAK", "n": 3}, {"type": "LIMB_LIMIT", "m": 300, "n": 0}, {"type": "TOTAL_GOOD_LANDINGS", "n": 3}])
	st.sample(0.1, 10.0, 1000.0, false, true, 0.0)
	st.on_landed({"type": "both", "quality": "flat"})
	st.on_landed({"type": "both", "quality": "flat"})
	st.on_limb(40.0)
	st.on_health(45.0, 0.0)
	st.on_continue(50.0)
	st.on_landed({"type": "both", "quality": "flat"})
	st.sample(0.1, 120.0, 13000.0, false, true, 0.0)
	check("continue_damage_challenge_stays_failed", st.status[0] == -1)
	check("continue_distance_challenge_continues", st.status[1] == 1)
	check("continue_streak_broken_by_death", st.status[2] == 0 and int(st._m.good_streak) == 1)
	check("continue_limb_loss_still_counted", st.status[3] == -1)
	check("continue_accumulating_goal_continues", st.status[4] == 1)


func chasm_continue() -> void:
	# no payment -> no rescue: a chasm fall ends the attempt (offer declined)
	await _run_with_coins(gm.continue_price() + 50, "chasms")
	gm.terrain.ensure_ahead(30000.0)
	await physics(60)
	var g0: Array = gm.terrain.gaps[0]
	var r := gm.robot
	r.global_position = Vector2((float(g0[0]) + float(g0[1])) * 0.5, maxf(float(g0[2]), float(g0[3])) + TerrainBuilder.GAP_FALL + 40.0)
	r.linear_velocity = Vector2(0, 600)
	await physics(4)
	check("chasm_fall_offers_paid_continue_only", gm.state == GameManager.State.OFFER and gm._offer_reason == "Упал в пропасть")
	await _wait_unpaused_s(ContinueCard.ARM_S + 0.15)
	gm.ui.continue_card.no.pressed.emit()
	await frames(2)
	check("chasm_no_free_rescue", gm.state == GameManager.State.RESULT and gm._end_reason == "Упал в пропасть")
	# paid: back on safe ground BEFORE the gap
	await _run_with_coins(gm.continue_price() + 50, "chasms")
	gm.terrain.ensure_ahead(30000.0)
	r = gm.robot
	var x0 := r.global_position.x
	for i in 120 * 4:
		await get_tree().physics_frame
		r.angular_velocity = 0.0
		r.rotation = 0.0
		if gm.terrain.gap_index(r.global_position.x) >= 0 or gm.state != GameManager.State.RUN:
			break
	g0 = gm.terrain.gaps[0]
	for g in gm.terrain.gaps:
		if float(g[1]) > r.global_position.x:
			g0 = g
			break
	r.global_position = Vector2((float(g0[0]) + float(g0[1])) * 0.5, maxf(float(g0[2]), float(g0[3])) + TerrainBuilder.GAP_FALL + 40.0)
	r.linear_velocity = Vector2(0, 600)
	await physics(4)
	await _wait_unpaused_s(ContinueCard.ARM_S + 0.15)
	await _confirm_continue()   # v34: ПРОДОЛЖИТЬ -> ПОДТВЕРДИТЬ
	await physics(2)
	var nr := gm.robot
	var nx := nr.global_position.x
	check("chasm_paid_continue_safe_terrain", gm.state == GameManager.State.RUN and gm.terrain.gap_index(nx) < 0 and nx < float(g0[0]) - 500.0
		and nr.global_position.y < gm.terrain.surface_y(nx) and nx >= x0 - 1.0, "x %.0f gap lip %.0f" % [nx, g0[0]])


# ======================================================================================================
# 19. artifact
# ======================================================================================================

func _start_campaign(id: String, seed := 999) -> void:
	gm.go_menu()
	await frames(2)
	gm.mode = &"campaign"
	gm.node_id = id
	gm.profile.ensure_campaign_start(id)
	gm.ui.biome_intro.instant = true
	gm.debug_track_seed = seed
	gm.start_run()
	gm.debug_track_seed = -1
	if gm.ui.awareness.visible:
		gm.ui.awareness.confirm.pressed.emit()
	await frames(3)
	gm.hand.playing = false
	gm.hand.visible = false
	gm.ui.flick_bar.hide_immediate()
	gm.state = GameManager.State.RUN


func _stream_artifact() -> void:
	gm.terrain.ensure_ahead(SecretArtifact.X_M * gm.level_config.px_per_meter + 3000.0)
	await physics(4)


func _press(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await frames(2)
	var u := e.duplicate() as InputEventMouseButton
	u.pressed = false
	Input.parse_input_event(u)
	await frames(2)


func artifact_tests() -> void:
	gm.profile.artifact = ProfileStore.default_artifact()
	gm.profile.save()
	gm._bind_profile_ui()
	check("artifact_level_is_exclusion_zone", String(gm.campaign.node(SecretArtifact.NODE_ID).biome) == "zone", SecretArtifact.NODE_ID)
	check("artifact_ui_hidden_before_discovery", not gm.ui.artifact_button.visible)
	var elsewhere := true
	for id in ["r21", "r23", "r79"]:
		await _start_campaign(id)
		await _stream_artifact()
		elsewhere = elsewhere and gm.artifact_node == null
	check("artifact_only_on_its_level", elsewhere)
	await _start_campaign(SecretArtifact.NODE_ID, 999)
	await _stream_artifact()
	var p1: Vector2 = gm.artifact_node.global_position if gm.artifact_node else Vector2.INF
	await _start_campaign(SecretArtifact.NODE_ID, 999)
	await _stream_artifact()
	var node := gm.artifact_node
	check("artifact_present_and_deterministic", node != null and p1.is_equal_approx(node.global_position)
		and p1.x >= SecretArtifact.X_M * 100.0 and p1.x < SecretArtifact.X_M * 100.0 + 120.0 * 40 + 1.0, str(p1))
	# robot collision does not collect
	var r := gm.robot
	r.launch(Vector2.ZERO, 0.0)
	for i in 30:
		r.global_position = node.global_position
		r.linear_velocity = Vector2.ZERO
		await get_tree().physics_frame
	check("artifact_robot_collision_does_not_collect", is_instance_valid(node) and not bool(gm.profile.artifact.discovered))
	# a tap elsewhere does not; a tap on it does
	r.global_position = node.global_position + Vector2(-600, 0)
	gm.camera.follow(null)
	gm.camera.snap_intro(node.global_position, 0.6)
	await frames(6)
	var sp := node.get_global_transform_with_canvas().origin
	await _press(sp + Vector2(150, 90))
	check("artifact_unrelated_tap_ignored", is_instance_valid(node) and not bool(gm.profile.artifact.discovered), "screen %s" % sp)
	await _press(sp + Vector2(10, -8))
	check("artifact_tap_collects", not is_instance_valid(node) and bool(gm.profile.artifact.discovered))
	var reload := ProfileStore.new(gm.profile.path, gm.catalog)
	reload.load_data()
	check("artifact_discovery_persists", bool(reload.artifact.discovered) and not bool(reload.artifact.equipped))
	await _start_campaign(SecretArtifact.NODE_ID, 999)
	await _stream_artifact()
	check("artifact_not_offered_again", gm.artifact_node == null)
	gm.go_menu()
	await frames(2)
	check("artifact_ui_after_discovery", gm.ui.artifact_button.visible and gm.ui.artifact_button.text.ends_with("ВЫКЛ"))
	gm.ui.artifact_button.pressed.emit()
	reload = ProfileStore.new(gm.profile.path, gm.catalog)
	reload.load_data()
	check("artifact_equip_persists", gm.artifact_active() and bool(reload.artifact.equipped) and gm.ui.artifact_button.text.ends_with("ВКЛ"))
	whitelist_tests()
	gm.ui.artifact_button.pressed.emit()
	reload = ProfileStore.new(gm.profile.path, gm.catalog)
	reload.load_data()
	check("artifact_unequip_works", not gm.artifact_active() and not bool(reload.artifact.equipped) and bool(reload.artifact.discovered))


func whitelist_tests() -> void:
	var def := gm.catalog.get_by_id("samurai")
	var base := def.base_stats()
	gm.profile.artifact.equipped = true
	var on := gm.build_robot(def, gm.input, gm.fx)
	gm.profile.artifact.equipped = false
	var off := gm.build_robot(def, gm.input, gm.fx)
	gm.profile.artifact.equipped = true
	# v36 (owner decision): exactly +15 displayed points (0..100 scale, HP +15 HP) - see v36_tests artifact checks
	var p_on := SecretArtifact.points(ModuleDefinition.apply_all(base, [SecretArtifact.module(base, gm.catalog)]), gm.catalog)
	var p_off := SecretArtifact.points(base, gm.catalog)
	var ok := is_equal_approx(on.damage_config.max_health, off.damage_config.max_health + 15.0) \
		and is_equal_approx(on.config.rotation_response, off.config.rotation_response * (base.air_control + 0.15 * gm.catalog.stat_max("air_control")) / base.air_control)
	for key in p_on:
		ok = ok and is_equal_approx(float(p_on[key]) - float(p_off[key]), 15.0)
	check("artifact_whitelist_plus_15", ok, "%s" % [p_on])
	var same := is_equal_approx(on.config.torso_mass, off.config.torso_mass) and is_equal_approx(on.config.rig_scale, off.config.rig_scale) \
		and is_equal_approx(on.contact_config.spring_stiffness, off.contact_config.spring_stiffness) \
		and is_equal_approx(on.contact_config.momentum_forward_cap, off.contact_config.momentum_forward_cap) \
		and is_equal_approx(on.contact_config.gain_both_flat, off.contact_config.gain_both_flat) \
		and is_equal_approx(on.config.torso_hit_scale, off.config.torso_hit_scale)
	check("artifact_non_whitelisted_untouched", same)
	check("artifact_base_stats_not_mutated", def.base_stats() == base and is_equal_approx(def.max_health, 155.0))
	var ai := gm.build_robot(def, InputRouter.new(), gm.fx)
	check("artifact_never_on_opponents", is_equal_approx(ai.damage_config.max_health, off.damage_config.max_health))
	gm.competitive_mode = true
	var comp := gm.build_robot(def, gm.input, gm.fx)
	check("artifact_ignored_in_competitive_mode_pref_kept", is_equal_approx(comp.damage_config.max_health, off.damage_config.max_health)
		and bool(gm.profile.artifact.equipped))
	gm.competitive_mode = false
	# a robot bought later gets it too
	gm.profile.owned.erase("heavy")
	gm.profile.coins += 5000
	gm.profile.buy(gm.catalog.get_by_id("heavy"))
	var hv := gm.build_robot(gm.catalog.get_by_id("heavy"), gm.input, gm.fx)
	check("artifact_applies_to_new_robots", is_equal_approx(hv.damage_config.max_health, 170.0 + 15.0), "%.1f" % hv.damage_config.max_health)
	for n in [on, off, ai, comp, hv]:
		n.free()


# ======================================================================================================
# 13. profile isolation (record, coins, artifact) with the real profile system
# ======================================================================================================

func profile_isolation() -> void:
	var base := "user://test/v32/profiles/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profiles_root="):
			base = a.substr(16)
	var root := base.path_join("iso") + "/"
	_wipe(root)
	gm.go_menu()
	await frames(2)
	gm.profiles = ProfileManager.new(root)
	gm.profiles.migrate_legacy()
	gm._use_placeholder_profile()
	gm.activate_slot(1)
	await frames(2)
	# PLAYER 1: campaign record, coins, artifact found + equipped
	await _campaign_finish_at("r1", 420.0)
	gm.go_menu()
	await frames(2)
	gm.profile.coins = 2000
	gm.profile.discover_artifact()
	gm.toggle_artifact()
	var p1_best := gm.stats.best_m()
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[1].pressed.emit()
	await frames(2)
	check("profile_record_isolated", gm.active_slot == 2 and gm.stats.best_m() == 0.0 and is_equal_approx(p1_best, 420.0))
	check("profile_artifact_isolated", not bool(gm.profile.artifact.discovered) and not gm.artifact_active() and not gm.ui.artifact_button.visible)
	var hp2 := gm.build_robot(gm.catalog.get_by_id("samurai"), gm.input, gm.fx)
	check("profile_no_artifact_bonus_for_p2", is_equal_approx(hp2.damage_config.max_health, 155.0))
	hp2.free()
	# PLAYER 2 pays a continue: PLAYER 1's coins stay
	gm.continue_offers_enabled = true
	await _run_with_coins(gm.continue_price() + 10)
	await physics(30)
	gm._finish("Робот остановился")
	await _wait_unpaused_s(ContinueCard.ARM_S + 0.15)
	await _confirm_continue()   # v34: ПРОДОЛЖИТЬ -> ПОДТВЕРДИТЬ
	await physics(2)
	gm.continue_offers_enabled = false
	gm.go_menu()
	await frames(2)
	var p2_coins := gm.profile.coins
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(2)
	check("profile_coins_isolated", gm.profile.coins == 2000 and p2_coins < gm.continue_price(), "p1 %d p2 %d" % [gm.profile.coins, p2_coins])
	check("profile_p1_keeps_artifact_and_record", gm.artifact_active() and gm.ui.artifact_button.visible and is_equal_approx(gm.stats.best_m(), 420.0))
	gm.profiles = null
	gm.active_slot = 0
	gm._open_stats()
	gm._open_profile()


func _wipe(dir_path: String) -> void:
	var abs := ProjectSettings.globalize_path(dir_path)
	var d := DirAccess.open(abs)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_wipe(dir_path.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(abs)


# ======================================================================================================
# 21. visual QA
# ======================================================================================================

func qa() -> void:
	await nozzle_shots()
	# continue card
	gm.continue_offers_enabled = true
	await _run_with_coins(1500)
	await physics(90)
	gm._finish("Голова приземлилась")
	await _wait_unpaused_s(ContinueCard.ARM_S + 0.2)
	at.call("_shot", "v32_continue_card")
	gm.ui.continue_card.no.pressed.emit()
	await frames(2)
	gm.continue_offers_enabled = false
	# artifact in its level (camera on it) and the menu toggle
	gm.profile.artifact = ProfileStore.default_artifact()
	await _start_campaign(SecretArtifact.NODE_ID, 999)
	await _stream_artifact()
	if gm.artifact_node:
		gm.robot.launch(Vector2.ZERO, 0.0)
		gm.robot.global_position = gm.artifact_node.global_position + Vector2(-380, 120)
		gm.camera.follow(null)
		gm.camera.snap_intro(gm.artifact_node.global_position + Vector2(-200, 80), 0.55)
		await frames(10)
		at.call("_shot", "v32_artifact_in_level")
		gm.artifact_node.take()
		await frames(10)
		at.call("_shot", "v32_artifact_collected")
	gm.go_menu()
	await frames(10)
	at.call("_shot", "v32_menu_artifact_off")
	gm.toggle_artifact()
	await frames(5)
	at.call("_shot", "v32_menu_artifact_on")
	# Chronobot chain in flight (momentum + flashes)
	var r: RobotController = await start_robot("rocket", 4242)
	r.launch(Vector2(700, -350), 0.0)
	var pending := []
	r.landed.connect(func(i: Dictionary) -> void:
		if String(i.type) in ["left", "right", "both"]:
			pending.append(int(i.get("momentum", 0.0))))
	var taken := 0
	for i in 120 * 6:
		await get_tree().physics_frame
		if not is_instance_valid(r):
			break
		r.angular_velocity = 0.0
		r.rotation = 0.0
		if not pending.is_empty() and taken < 5:
			# a few frames after the release: the flash is on screen
			await frames(4)
			taken += 1
			at.call("_shot", "v32_chrono_flash_%d_m%d" % [taken, pending.pop_front()])
			pending.clear()
	check("qa_done", true)


## Local-space bounds of one art part (torso / head ...) of a built robot.
func part_bounds(r: RobotController, part_name: String) -> Rect2:
	var out := Rect2()
	var init := false
	var pending: Array[Node] = [r.visual]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if n is VideoRobotPart and String(n.name).to_lower().contains(part_name):
			var p := n as VideoRobotPart
			var rect := p.visual_bounds()
			var xf := r.global_transform.affine_inverse() * p.global_transform
			for c in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
				var q: Vector2 = xf * c
				if not init:
					out = Rect2(q, Vector2.ZERO)
					init = true
				else:
					out = out.expand(q)
	return out


# ---------------- measurement helpers (real physics, fixed track seed) ----------------

## Starts a free run with robot `id` on a fixed track and returns the robot already in RUN state (not launched).
func start_robot(id: String, seed := 31337, biome := "") -> RobotController:
	gm.go_menu()
	await frames(2)
	if not gm.profile.owned.has(id):
		gm.profile.owned.append(id)
	gm.profile.selected = id
	gm.mode = &"free"
	gm.debug_biome = biome
	gm.debug_track_seed = seed
	gm.ui.biome_intro.instant = true
	gm.start_run()
	await frames(3)
	gm.hand.playing = false
	gm.hand.visible = false
	gm.ui.flick_bar.hide_immediate()   # the real flick hides these; the helper skips the flick
	gm.state = GameManager.State.RUN
	gm.camera.follow(gm.robot)
	gm.debug_track_seed = -1
	gm.debug_biome = ""
	return gm.robot


## Flat-ish track spot (small slope) at or after x0.
func flat_x(x0: float) -> float:
	for k in 400:
		var x := x0 + k * 40.0
		if absf(gm.terrain.normal_at(x).x) < 0.1 and gm.terrain.gap_index(x) < 0:
			return x
	return x0


## Drop upright from `h` px above the ground: first valid feet landing -> release speed along the normal and the
## apex height (px above the ground below the robot) reached before the next contact.
func drop(id: String, h := 380.0, rebound_override := -1.0) -> Dictionary:
	var r: RobotController = await start_robot(id)
	if rebound_override >= 0.0:
		r.contacts.cfg.rebound_power = rebound_override
	var x := flat_x(2600.0)
	r.global_position = Vector2(x, gm.terrain.surface_y(x) - h)
	r.rotation = 0.0
	r.launch(Vector2.ZERO, 0.0)
	var out := {"vn": 0.0, "apex": 0.0}
	var phase := [0]
	var cb := func(info: Dictionary) -> void:
		if phase[0] == 0 and String(info.type) in ["left", "right", "both"]:
			out.vn = (info.velocity_out as Vector2).dot(info.normal)
			phase[0] = 1
	r.landed.connect(cb)
	var released := false
	for i in 120 * 5:
		await get_tree().physics_frame
		if not is_instance_valid(r):
			break
		r.angular_velocity = 0.0
		r.rotation = 0.0
		r.linear_velocity.x = 0.0
		if phase[0] == 1:
			if not r.contacts.any_contact:
				released = true
				out.apex = maxf(out.apex, gm.terrain.surface_y(r.global_position.x) - r.global_position.y)
			elif released:
				break
	return out


## Clean-landing chain: launched forward at v0, kept upright (every landing is a clean / acceptable feet landing) for
## `seconds`. Returns distance (m), mean forward speed (px/s), landings with their momentum, max momentum.
## aligned = "competent pilot": the robot is kept perpendicular to the terrain under it (feet parallel to the slope)
## instead of upright, so landings are clean two-foot landings the way a player lands them.
func chain(id: String, seconds := 6.0, momentum_on := true, v0 := Vector2(700, -350), seed := 4242, gain_override := -1.0, aligned := false, slope := false) -> Dictionary:
	var r: RobotController = await start_robot(id, seed)
	if slope:
		# controlled case: the endless gentle 6 % practice slope (no track chaos), launched from a fixed spot
		gm.terrain.build_training()
		await physics(2)
		r.global_position = Vector2(-1300.0, gm.terrain.height_at(-1300.0) - 300.0)
		r.rotation = 0.0
	if gain_override >= 0.0:
		r.contacts.cfg.momentum_gain = gain_override   # tuning probe only
	if not momentum_on:
		r.contacts.cfg.momentum_gain = 0.0
	var x0 := r.global_position.x
	r.launch(v0, 0.0)
	var log := []
	var cb := func(info: Dictionary) -> void:
		if String(info.type) != "soft":
			log.append([String(info.type), String(info.quality), int(info.get("momentum", 0.0)), int(info.get("momentum_boost", 0.0))])
	r.landed.connect(cb)
	var vsum := 0.0
	var n := 0
	var max_speed := 0.0
	var bad := false
	for i in int(120 * seconds):
		await get_tree().physics_frame
		if not is_instance_valid(r) or gm.state != GameManager.State.RUN:
			break
		r.angular_velocity = 0.0
		r.rotation = (gm.terrain.normal_at(r.global_position.x).angle() + PI * 0.5) if aligned else 0.0
		var v := r.linear_velocity
		bad = bad or not (is_finite(v.x) and is_finite(v.y))
		vsum += v.x
		n += 1
		max_speed = maxf(max_speed, v.length())
	var dist := ((r.global_position.x - x0) / gm.level_config.px_per_meter) if is_instance_valid(r) else 0.0
	return {"dist": dist, "vx": vsum / maxi(n, 1), "max_speed": max_speed, "landings": log, "finite": not bad,
		"m": r.contacts.momentum if is_instance_valid(r) else 0.0}


func measure_jumps() -> void:
	for id in ROBOTS:
		var d: Dictionary = await drop(id)
		print("AT|measure jump %-8s release_vn=%.0f apex=%.0f px" % [id, d.vn, d.apex])
	var k0: Dictionary = await drop("hopper", 380.0, 1.0)
	print("AT|measure jump hopper_without_rebound_power release_vn=%.0f apex=%.0f px" % [k0.vn, k0.apex])


func measure_chains() -> void:
	for id in ROBOTS:
		var on: Dictionary = await chain(id)
		var off: Dictionary = await chain(id, 6.0, false)
		print("AT|measure chain %-8s dist=%.1fm (no momentum %.1fm, %+.0f%%) vx=%.0f (off %.0f) max_speed=%.0f m_end=%.0f finite=%s landings=%s" %
			[id, on.dist, off.dist, (on.dist / maxf(off.dist, 0.01) - 1.0) * 100.0, on.vx, off.vx, on.max_speed, on.m, on.finite, on.landings])


func nozzle_shots() -> void:
	for zoom in [1.5, 0.75]:
		var r: RobotController = await start_robot("rocket")
		gm.state = GameManager.State.INTRO
		gm.ui.menu.visible = false
		gm.ui.hud.visible = false
		gm.camera.snap_intro(r.global_position + Vector2(0, 40), zoom)
		await frames(20)
		at.call("_shot", "nz_idle_%d" % int(zoom * 100))
		r.visual.identity.thrust_flash(1.0, 0.26)
		await frames(3)
		at.call("_shot", "nz_flash_%d" % int(zoom * 100))
		r.visual.identity.thrust_flash(0.4, 0.12)
		await frames(14)
		at.call("_shot", "nz_after_%d" % int(zoom * 100))
	check("nozzle_shots", true)


func probe_shapes() -> void:
	for id in ROBOTS:
		var def := gm.catalog.get_by_id(id)
		var r := gm.build_robot(def, InputRouter.new(), gm.fx)
		r.position = Vector2(0, -3000)
		gm.dynamic.add_child(r)
		await frames(3)
		var line := "AT|probe shapes %s rig_scale=%.3f mass=%.2f hp=%.0f" % [id, r.config.rig_scale, r.mass, r.damage.max_health]
		for c in r.get_children():
			if c is CollisionShape2D:
				var cs := c as CollisionShape2D
				if cs.shape is CapsuleShape2D:
					line += " %s=cap(r%.1f,h%.1f)@%s" % [cs.get_meta(&"zone"), (cs.shape as CapsuleShape2D).radius, (cs.shape as CapsuleShape2D).height, cs.position]
				elif cs.shape is CircleShape2D:
					line += " %s=circ(r%.1f)@%s" % [cs.get_meta(&"zone"), (cs.shape as CircleShape2D).radius, cs.position.round()]
		line += " torso_art=%s" % part_bounds(r, "torso")
		print(line)
		r.queue_free()
		await frames(2)
	check("probe_done", true)
