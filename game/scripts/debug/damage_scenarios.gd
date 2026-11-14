extends Node
## Debug-only damage + spin-charge tests (not exported). Run with:  -- --autotest --scenario=logic|drops|spin|all
## logic : drives DamageController directly with synthetic zone contacts -> exact rule checks.
## drops : drops the real robot (no spin control) onto the flat-ish launch ledge in fixed poses and
##         checks which zone the physics reports and what damage follows.
## Prints "AT|test <name> PASS|FAIL <details>".

var gm: GameManager
var at: Node
var passed := 0
var failed := 0


func run_all(which: String) -> void:
	if which == "logic" or which == "all":
		_logic_tests()
	if which == "drops" or which == "all":
		await _drop_tests()
	at.set("scenario_running", true)
	if which == "spin_visual":
		await _spin_visual()
	if which == "aura_visual":
		await _aura_visual()
	if which == "spin" or which == "all":
		_spin_logic_tests()
		await _spin_physics_tests()
	if which == "spin" or which == "recovery" or which == "all":
		await _recovery_tests()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


func _check(name: String, ok: bool, details: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("AT|test %s %s %s" % [name, "PASS" if ok else "FAIL", details])


# ---------------- logic (v0.7: invulnerability timer, health-ratio thresholds) ----------------

class Probe:
	var dc: DamageController
	var lost: Array[String] = []
	var dmg: Array = []
	var times: Array = []
	var rockets := 0
	var t := 0.0
	var frame := 0

	func _init(cfg: DamageConfig, parent: Node, max_hp := -1.0, invuln := 0.5) -> void:
		var c := cfg
		if max_hp > 0.0:
			c = cfg.duplicate()
			c.max_health = max_hp
		dc = DamageController.new()
		dc.cfg = c
		parent.add_child(dc)
		dc.invulnerability_time = invuln
		dc.limb_lost.connect(func(l: StringName, _i: Dictionary) -> void: lost.append(String(l)))
		dc.damage_applied.connect(func(a: float, _c: StringName, _h: float, _i: Dictionary) -> void:
			dmg.append(a)
			times.append(t))
		dc.rocket_triggered.connect(func(_i: Dictionary) -> void: rockets += 1)
		step([])   # one airborne step arms the damage (as after the launch)

	## One physics step with these zones touching the ground.
	func step(zones: Array, dt := 1.0 / 120.0) -> void:
		var d := {}
		for z in zones:
			d[StringName(z)] = {"point": Vector2.ZERO, "normal": Vector2.UP, "impact": 0.0}
		frame += 1
		dc.tick(dt, d, frame)
		t += dt

	func hold(zones: Array, seconds: float) -> void:
		for i in int(round(seconds * 120.0)):
			step(zones)

	## A hit followed by a long enough air phase for the invulnerability to run out.
	func hit(zones: Array) -> void:
		step(zones)
		hold([], dc.invulnerability_time + 0.05)

	func dispose() -> void:
		dc.queue_free()


func _logic_tests() -> void:
	var cfg := gm.damage_config
	# first contact damages, even a 0 px/s touch; contact inside the invulnerability does not
	var p := Probe.new(cfg, self)
	p.step(["leg_l"])
	var first := p.dmg.duplicate()
	p.hold(["leg_l"], 0.45)
	_check("first_contact_and_invulnerability", first == [15.0] and p.dmg == [15.0], "first=%s after_0.45s_contact=%s" % [first, p.dmg])
	# continuous contact: damaged again each time the timer runs out (no lift-off needed)
	p.hold(["leg_l"], 1.6)
	var gaps := []
	for i in range(1, p.times.size()):
		gaps.append(snappedf(p.times[i] - p.times[i - 1], 0.001))
	_check("continuous_contact_periodic", p.dmg.size() == 5 and gaps.all(func(g: float) -> bool: return absf(g - 0.5) <= 0.0084),
		"hits=%s gaps=%s (invuln 0.5 s)" % [p.dmg, gaps])
	p.dispose()
	# airborne: nothing; timer also runs out in the air; next touch damages at once
	p = Probe.new(cfg, self)
	p.step(["leg_r"])
	p.hold([], 2.0)
	p.step(["leg_r"])
	_check("airborne_no_damage_then_touch", p.dmg == [15.0, 15.0], "dmg=%s" % [p.dmg])
	p.dispose()
	# several zones touching at once -> only the worst one; one damage per physics frame
	p = Probe.new(cfg, self)
	p.step(["leg_l", "leg_r", "torso", "arm_l"])
	var side := p.dmg.duplicate()
	p.hold([], 0.6)
	p.step(["leg_l", "torso", "head"])
	_check("simultaneous_worst_zone", side == [35.0] and p.dmg == [35.0, 50.0], "torso+legs+arm=%s then +head=%s" % [side, p.dmg])
	var before := p.dmg.size()
	p.hold([], 0.6)
	var d := {&"head": {"point": Vector2.ZERO, "normal": Vector2.UP, "impact": 0.0}}
	p.dc.tick(1.0 / 120.0, d, 999999)
	p.dc.invulnerable_left = 0.0
	p.dc.tick(1.0 / 120.0, d, 999999)       # same frame id: must be ignored
	_check("one_damage_per_frame", p.dmg.size() == before + 1, "applications in one frame=%d" % (p.dmg.size() - before))
	p.dispose()
	# invulnerability setting is respected
	p = Probe.new(cfg, self, -1.0, 1.0)
	p.step(["leg_l"])
	p.hold(["leg_l"], 0.9)
	var n1 := p.dmg.size()
	p.hold(["leg_l"], 0.2)
	_check("invulnerability_setting", n1 == 1 and p.dmg.size() == 2, "hits after 0.9s=%d after 1.1s=%d (invuln 1.0 s)" % [n1, p.dmg.size()])
	p.dispose()
	# thresholds as health ratio: 100 HP (feet hits 15 each)
	p = Probe.new(cfg, self)
	var trace := []
	for i in 7:
		p.hit(["leg_l"])
		trace.append("%d:%s" % [int(p.dc.health), ",".join(p.lost)])
	_check("thresholds_100hp", p.lost == ["arm_l", "arm_r", "leg_l", "leg_r"] and trace[1] == "70:arm_l" and trace[3] == "40:arm_l,arm_r"
		and trace[4] == "25:arm_l,arm_r,leg_l" and trace[6] == "0:arm_l,arm_r,leg_l,leg_r", " ".join(trace))
	p.dispose()
	# 200 HP: arms at 150/100, legs at 50/0 (side hits 35 each)
	p = Probe.new(cfg, self, 200.0)
	trace = []
	for i in 6:
		p.hit(["torso"])
		trace.append("%d:%s" % [int(p.dc.health), ",".join(p.lost)])
	_check("thresholds_200hp", trace[0] == "165:" and trace[1] == "130:arm_l" and trace[2] == "95:arm_l,arm_r" and trace[3] == "60:arm_l,arm_r"
		and trace[4] == "25:arm_l,arm_r,leg_l" and trace[5] == "0:arm_l,arm_r,leg_l,leg_r", " ".join(trace))
	p.dispose()
	# one hit crossing several thresholds (200 HP: 120 -> 85 = 42.5% crosses 75% and 50%)
	p = Probe.new(cfg, self, 200.0)
	p.dc.debug_set_health(120.0)
	p.hit(["torso"])
	_check("multi_threshold_ratio", p.lost == ["arm_l", "arm_r"] and p.dc.health == 85.0, "hp=%.0f lost=%s" % [p.dc.health, p.lost])
	p.dispose()
	# head rule: both arms at once, even at full 200 HP (150 = 75% would only take one)
	p = Probe.new(cfg, self, 200.0)
	p.hit(["head"])
	var after_head := p.lost.duplicate()
	p.hit(["head"])
	_check("head_rule_any_hp", after_head == ["arm_l", "arm_r"] and p.lost == ["arm_l", "arm_r"] and p.dc.health == 100.0,
		"after 1st head=%s after 2nd=%s hp=%.0f (no double removal)" % [after_head, p.lost, p.dc.health])
	p.dispose()
	# final stage: at 0 HP a head-only contact does nothing, a torso contact after the invulnerability fires
	# the jet head exactly once
	p = Probe.new(cfg, self)
	p.dc.debug_set_health(10.0)
	p.dc.limbs_remaining = [&"leg_r"]
	p.step(["torso"])                       # 10 -> 0, starts invulnerability; same contact cannot fire yet
	var at_zero := p.rockets
	p.hold(["head"], 0.7)
	var head_only := p.rockets
	p.hold(["torso"], 1.5)
	_check("rocket_once_after_zero", p.dc.health == 0.0 and at_zero == 0 and head_only == 0 and p.rockets == 1,
		"hp=%.0f at_zero=%d head_only=%d after_torso=%d" % [p.dc.health, at_zero, head_only, p.rockets])
	p.dispose()
	# never armed while still standing on the launch ledge
	p = Probe.new(cfg, self)
	p.dc.armed = false
	p.hold(["leg_l", "leg_r"], 1.0)
	var standing := p.dmg.size()
	p.step([])
	p.step(["leg_l"])
	_check("not_armed_on_launch_ledge", standing == 0 and p.dmg == [15.0], "while standing=%d after first air step=%s" % [standing, p.dmg])
	p.dispose()

# ---------------- physical drops ----------------

func _drop_tests() -> void:
	gm.ui.show_hud()
	await _drop("drop_feet", 0.0, 520.0, &"feet", 15.0, 4.0)
	await _drop("drop_side_right", 90.0, 300.0, &"side", 35.0, 2.5)
	await _drop("drop_side_left", -90.0, 300.0, &"side", 35.0, 2.5)
	await _drop("drop_head", 180.0, 320.0, &"head", 50.0, 2.5)


func _drop(name: String, rot_deg: float, height: float, want_class: StringName, want_amount: float, secs: float) -> void:
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	gm.hand.visible = false
	await get_tree().physics_frame
	var r := gm.robot
	var x := -1300.0
	r.global_position = Vector2(x, gm.terrain.height_at(x) - height)
	r.rotation = deg_to_rad(rot_deg)
	gm.camera.snap_intro(r.global_position + Vector2(0, 150), 0.8)
	var events: Array = []
	var lost: Array = []
	var landings := [0]
	r.damaged.connect(func(a: float, c: StringName, hp: float, i: Dictionary) -> void:
		events.append({"a": a, "c": c, "hp": hp, "zone": i.get("zone"), "lost_at": lost.size(), "t": r.physics_time}))
	r.limb_lost.connect(func(l: StringName, _p: RigidBody2D) -> void: lost.append(String(l)))
	r.touchdown.connect(func(i: Dictionary) -> void:
		if i.impact >= 140.0:
			landings[0] += 1)
	r.launch(Vector2(0, 50), 0.0)
	r.rotation_ctl.enabled = false
	var t := 0.0
	while t < secs:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if at.get("shots_dir") != "" and int(t * 120) % 12 == 0:
			at.call("_shot", "%s_%03d" % [name, int(t * 10)])
	var first: Dictionary = events[0] if not events.is_empty() else {}
	var ok: bool = not first.is_empty() and first.c == want_class and is_equal_approx(first.a, want_amount)
	var details := "first=%s events=%d landings=%d hp=%.0f lost=%s all=%s" % [first, events.size(), landings[0],
		r.damage.health, lost, events.map(func(e: Dictionary) -> String: return "%s:%d" % [e.zone, int(e.a)])]
	if want_class == &"head":
		ok = ok and lost.slice(0, 2) == ["arm_l", "arm_r"]
	if want_class == &"feet":
		# every confirmed landing charged exactly once, each 15
		var all15 := events.all(func(e: Dictionary) -> bool: return e.c == &"feet" and is_equal_approx(e.a, 15.0))
		var spaced := true
		for k in range(1, events.size()):
			spaced = spaced and events[k].t - events[k - 1].t >= r.damage.invulnerability_time - 0.001
		ok = ok and all15 and spaced
	_check(name, ok, details)


# ---------------- spin charge ----------------

func _new_charge() -> SpinChargeController:
	var s := SpinChargeController.new()
	s.cfg = gm.spin_config
	s.base_cw_speed = gm.robot_config.clockwise_rotation_speed
	add_child(s)
	return s


## Integrate `turns` rotations at `rps` (rev/s, + = clockwise).
func _spin(s: SpinChargeController, turns: float, rps: float, airborne := true, holding := false) -> void:
	var dt := 1.0 / 120.0
	var steps := int(round(absf(turns / rps) / dt))
	for i in steps:
		s.step(dt, rps * TAU, airborne, holding)


func _spin_logic_tests() -> void:
	var s := _new_charge()
	s.base_cw_speed = 0.5
	# 1. automatic clockwise spin in the air charges 35% per turn, partial turns proportional
	_spin(s, 1.0, 0.5, true, false)
	_check("auto_one_turn_35pct", absf(s.charge - 0.35) < 0.003, "charge=%.4f" % s.charge)
	_spin(s, 0.5, 0.5, true, false)
	_check("auto_half_turn_proportional", absf(s.charge - 0.525) < 0.003, "charge=%.4f" % s.charge)
	# 2. manual (held, counter-clockwise) neither adds nor drains; ground rotation adds nothing
	var before := s.charge
	_spin(s, -2.0, -1.0, true, true)
	var held := s.charge
	_spin(s, 2.0, 0.5, false, false)
	_check("manual_and_ground_neutral", is_equal_approx(held, before) and is_equal_approx(s.charge, before),
		"before=%.3f after_2_held_turns=%.3f after_ground=%.3f" % [before, held, s.charge])
	# 3. full after ~2.9 turns, never above 100%, one full event
	s.reset()
	var fulls := [0]
	s.charge_full.connect(func() -> void: fulls[0] += 1)
	_spin(s, 2.9, 0.5, true, false)
	var at_29 := s.charge
	_spin(s, 3.0, 0.5, true, false)
	_check("auto_full_cap", at_29 > 0.99 and s.charge <= 1.0 and fulls[0] == 1, "after 2.9 turns=%.3f now=%.3f full_events=%d" % [at_29, s.charge, fulls[0]])
	# 4. slight physical speed-up only: 0.50 -> 0.60 rev/s at 100%
	var speeds := []
	for k in 5:
		s.charge = k * 0.25
		speeds.append(snappedf(s.cw_speed(), 0.001))
	# v0.9.1: the charge no longer changes the spin speed (it accelerates per completed turn instead)
	_check("charge_does_not_change_speed", speeds.all(func(v: float) -> bool: return is_equal_approx(v, 0.5)), "rps at 0/25/50/75/100%%: %s" % [speeds])
	# 5. every contact spends EVERYTHING; effective = charge * zone efficiency
	var eff := {}
	for z in [&"feet", &"arm", &"side", &"head"]:
		s.charge = 1.0
		eff[z] = snappedf(s.consume(z), 0.001)
		eff[String(z) + "_after"] = s.charge
	_check("spend_all_zone_efficiency", is_equal_approx(eff[&"feet"], 1.0) and is_equal_approx(eff[&"arm"], 0.3)
		and is_equal_approx(eff[&"side"], 0.25) and is_equal_approx(eff[&"head"], 0.25)
		and eff.feet_after == 0.0 and eff.side_after == 0.0 and eff.head_after == 0.0 and eff.arm_after == 0.0, "%s" % [eff])
	s.charge = 0.0
	_check("spend_nothing_at_zero", s.consume(&"feet") == 0.0, "")
	# 6. robot multipliers (energy & charge rate)
	s.charge = 0.0
	s.charge_rate = 1.25
	s.energy_multiplier = 1.7
	_spin(s, 1.0, 0.5, true, false)
	var c_rate := s.charge
	var e := s.consume(&"feet")
	_check("robot_multipliers", absf(c_rate - 0.4375) < 0.003 and absf(e - 0.4375 * 1.7) < 0.003, "charge=%.4f eff=%.4f" % [c_rate, e])
	# 7. impulse is bounded
	var cc := gm.contact_config
	var out := s.clamp_out(Vector2(0, -2000) + s.boost_vector(1.0, Vector2.UP, Vector2.UP, Vector2.RIGHT), Vector2.UP, 1.0, cc)
	_check("boost_capped", -out.y <= cc.max_release_normal_speed + s.cfg.bonus_cap_headroom + 0.5, "out=(%.0f,%.0f)" % [out.x, out.y])
	s.queue_free()


func _spin_physics_tests() -> void:
	gm.ui.show_hud()
	var rev0: Dictionary = await _reverse_time(0.0)
	var rev1: Dictionary = await _reverse_time(1.0)
	_check("spin_reverse_responsive", rev0.t_cross > 0.0 and rev1.t_cross > 0.0 and rev1.t_cross < 0.15 and rev1.t_90 > 0.0 and rev1.t_90 < 0.25,
		"charge0: cross=%.3fs ccw90%%=%.3fs | charge100: cw=%.2f rps cross=%.3fs ccw90%%=%.3fs" % [rev0.t_cross, rev0.t_90, rev1.rps, rev1.t_cross, rev1.t_90])
	# real robot floating: measured auto/manual speeds and charging
	gm.reset_settings()
	var f0: Dictionary = await _float_spin(0.0)
	# v34 (legit update): release auto / manual speeds are the fixed 0.9 / 1.1 rev/s (SettingsStore.FIXED)
	var auto0: float = gm.settings.get_value("auto_rps")
	var man0: float = gm.settings.get_value("manual_rps")
	_check("physical_auto_charging", absf(f0.cw0 - auto0) < 0.015 and f0.auto_gain > 0.25 and absf(f0.held_gain) < 0.0001 and absf(f0.ccw - man0) < 0.01,
		"cw at start=%.3f rps, gain 2 s released=%.3f, held 1 s gain=%.4f, ccw=%.3f rps" % [f0.cw0, f0.auto_gain, f0.held_gain, f0.ccw])
	# v0.9.1 per-turn acceleration (default +0.20 rev/s per completed automatic turn), manual turns never count
	var acc: Dictionary = await _accel_float(0.2, 4)
	var want := [auto0, auto0 + 0.2, auto0 + 0.4, auto0 + 0.6]
	var ok_acc := true
	for i in 4:
		ok_acc = ok_acc and absf(acc.rps[i] - want[i]) < 0.02
	_check("auto_accel_per_turn", ok_acc and acc.turns_held_delta == 0.0 and absf(acc.ccw - man0) < 0.01 and acc.after_hold_rps >= 1.09,
		"rps in turns 1..4=%s (want %s) held 1 s: turn counter +%.3f, ccw=%.3f rps, auto after hold=%.3f" % [acc.rps, want, acc.turns_held_delta, acc.ccw, acc.after_hold_rps])
	var acc0: Dictionary = await _accel_float(0.0, 3)
	_check("auto_accel_zero_setting", acc0.rps.all(func(v: float) -> bool: return absf(v - auto0) < 0.01), "rps=%s" % [acc0.rps])
	var cap: Dictionary = await _accel_float(0.5, 9)
	var cap_v: float = gm.robot.config.auto_spin_max_rps
	_check("auto_accel_cap", absf(cap.rps[5] - 3.0) < 0.03 and cap.rps.all(func(v: float) -> bool: return v <= cap_v + 0.01) and absf(cap.rps[4] - (auto0 + 2.0)) < 0.03,
		"max setting 0.50: rps per turn=%s cap=%.2f" % [cap.rps, cap_v])
	gm.reset_settings()
	# a new ground contact restarts the counter
	var rs: Dictionary = await _accel_reset()
	_check("auto_accel_resets_on_contact", rs.before > 1.0 and rs.after_touch < 0.05, "turns before landing=%.2f after touchdown=%.2f" % [rs.before, rs.after_touch])
	# feet landing with / without charge
	for pose in [["flat", 0.0, Vector2(500, 0)], ["forward", 26.0, Vector2(500, 0)]]:
		var a: Dictionary = await _bounce(pose[1], pose[2], 0.0)
		var b: Dictionary = await _bounce(pose[1], pose[2], 1.0)
		var ok: bool = b.used and b.uses == 1 and b.charge_after == 0.0 and b.dmg[0] == 15.0 and a.dmg[0] == 15.0 \
			and (b.flight_x > a.flight_x + 50.0 or b.apex > a.apex + 50.0) and b.zone == &"feet"
		_check("charged_feet_landing_" + pose[0], ok,
			"kind=%s | no charge: apex=%.0f next_x=+%.0f | full: |dv|=%.0f eff=%.2f apex=%.0f next_x=+%.0f uses=%d charge_after=%.2f dmg=%s/%s"
			% [b.kind, a.apex, a.flight_x, b.dv, b.eff, b.apex, b.flight_x, b.uses, b.charge_after, a.dmg, b.dmg])
	# side / head with full charge: spent at 25%, damage unchanged
	for pose in [["side", 90.0, 35.0], ["head", 180.0, 50.0]]:
		var r: Dictionary = await _bounce(pose[1], Vector2(0, 0), 1.0, 300.0)
		_check("charged_" + pose[0] + "_weak", r.used and r.uses == 1 and r.charge_after == 0.0 and r.eff < 0.36 and r.dmg.size() >= 1 and r.dmg[0] == pose[2],
			"zone=%s eff=%.2f |dv|=%.0f uses=%d dmg=%s charge_after=%.2f" % [r.zone, r.eff, r.dv, r.uses, r.dmg, r.charge_after])
	# continuous contact: a robot resting on the ground never spends twice (no new contact event)
	var cont: Dictionary = await _continuous_contact()
	_check("continuous_contact_single_use", cont.uses_first == 1 and cont.uses_after == 1 and is_equal_approx(cont.charge_kept, 0.8),
		"uses after landing=%d, charge set to 0.80 while resting -> after 1.5 s still %.2f, uses=%d" % [cont.uses_first, cont.charge_kept, cont.uses_after])


## Drop with full charge, let it come to rest on the ground, then put charge back while it keeps touching.
func _continuous_contact() -> Dictionary:
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	gm.hand.visible = false
	await get_tree().physics_frame
	var r := gm.robot
	var x := -1500.0
	r.global_position = Vector2(x, gm.terrain.height_at(x) - 260.0)
	var uses := [0]
	r.charge_released.connect(func(_c: float, _dv: Vector2, _i: Dictionary) -> void: uses[0] += 1)
	r.launch(Vector2.ZERO, 0.0)
	r.rotation_ctl.enabled = false
	r.spin_charge.enabled = true
	r.spin_charge.charge = 1.0
	# settle: spring bounces die out on the gentle ledge
	var rest := 0.0
	var t := 0.0
	# v34 (legit update): the approved 200 % springs keep hopping a little longer - "resting" = 1.5 s of contact at
	# low speed (a later hop would be a NEW landing, which correctly spends a charge)
	while t < 14.0 and rest < 1.5:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		rest = rest + 1.0 / 120.0 if (r.contacts.any_contact and r.linear_velocity.length() < 60.0) else 0.0
	var first: int = uses[0]
	r.spin_charge.charge = 0.8
	await _frames_n(180)
	return {"uses_first": first, "uses_after": uses[0], "charge_kept": r.spin_charge.charge}

func _reverse_time(charge: float) -> Dictionary:
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	await get_tree().physics_frame
	var r := gm.robot
	r.global_position = Vector2(-1300, gm.terrain.height_at(-1300) - 4000)
	r.gravity_scale = 0.0
	r.spin_charge.charge = charge
	r.launch(Vector2.ZERO, r.spin_charge.cw_speed() * TAU)
	for i in 30:
		await get_tree().physics_frame
	r.spin_charge.charge = charge   # keep the tested level (air spin would add a little)
	var rps := r.angular_velocity / TAU
	gm.input.set_virtual_hold(true)
	var t := 0.0
	var res := {"rps": rps, "t_cross": -1.0, "t_90": -1.0}
	while t < 0.6:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if res.t_cross < 0.0 and r.angular_velocity < 0.0:
			res.t_cross = t
		if res.t_90 < 0.0 and r.angular_velocity <= -0.9 * r.config.counterclockwise_rotation_speed * TAU:
			res.t_90 = t
	gm.input.set_virtual_hold(false)
	return res


## Drop the robot (rotation control off, so the charge stays as set) and watch one landing.
func _bounce(rot_deg: float, vel: Vector2, charge: float, height := 420.0) -> Dictionary:
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	gm.hand.visible = false
	await get_tree().physics_frame
	var r := gm.robot
	var x := -1900.0
	r.global_position = Vector2(x, gm.terrain.height_at(x) - height)
	r.rotation = deg_to_rad(rot_deg)
	gm.camera.snap_intro(r.global_position + Vector2(300, 150), 0.7)
	var res := {"used": false, "uses": 0, "zone": &"", "eff": 0.0, "dv": 0.0, "dmg": [], "out": 0.0, "apex": 0.0, "flight_x": 0.0, "kind": "", "charge_after": -1.0}
	var state := {"released": false, "x0": 0.0, "y0": 0.0, "done": false}
	r.charge_released.connect(func(_c: float, dv: Vector2, i: Dictionary) -> void:
		res.used = true
		res.uses += 1
		if res.uses == 1:
			res.zone = i.zone_class
			res.eff = i.effective
			res.dv = dv.length())
	r.damaged.connect(func(a: float, _c: StringName, _h: float, _i: Dictionary) -> void: res.dmg.append(a))
	r.landed.connect(func(i: Dictionary) -> void:
		if not state.released and i.type != &"soft":
			state.released = true
			res.kind = "%s/%s" % [i.type, i.quality]
			res.out = (i.velocity_out as Vector2).length()
			state.x0 = r.global_position.x
			state.y0 = r.global_position.y)
	r.touchdown.connect(func(i: Dictionary) -> void:
		if state.released and not state.done and i.impact > 100.0:
			state.done = true
			res.flight_x = i.point.x - state.x0)
	r.launch(vel, 0.0)
	r.rotation_ctl.enabled = false
	r.spin_charge.charge = charge
	r.spin_charge.charge_changed.emit(charge)
	var t := 0.0
	while t < 3.5 and not state.done:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if at.get("shots_dir") != "" and int(t * 120) % 6 == 0:
			at.call("_shot", "bounce_c%d_%03d" % [int(charge * 100), int(t * 20)])
		if state.released:
			res.apex = maxf(res.apex, state.y0 - r.global_position.y)
			if res.charge_after < 0.0:
				res.charge_after = r.spin_charge.charge
	if res.charge_after < 0.0:
		res.charge_after = r.spin_charge.charge
	return res

## Aura look at fixed charge levels (screenshots aura_<pct>_*).
func _aura_visual() -> void:
	gm.ui.show_hud()
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	gm.hand.visible = false
	await get_tree().physics_frame
	var r := gm.robot
	r.global_position = Vector2(-1300, gm.terrain.height_at(-1300) - 900)
	r.gravity_scale = 0.0
	r.launch(Vector2(300, 0), 0.0)
	gm.camera.follow(r)
	for pct in [0, 35, 70, 100]:
		for i in 50:
			r.spin_charge.charge = pct / 100.0
			r.visual.charge_ratio = pct / 100.0
			await get_tree().physics_frame
		at.call("_shot", "aura_%03d" % pct)


func _spin_visual() -> void:
	gm.ui.show_hud()
	await _bounce(0.0, Vector2(500, 0), 1.0)
	await _bounce(0.0, Vector2(500, 0), 0.4)

## Robot floating (no gravity, no ground): measured automatic / manual spin speeds and real auto charging.
func _float_spin(start_charge: float) -> Dictionary:
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	await get_tree().physics_frame
	var r := gm.robot
	var res := {"spawn_charge": r.spin_charge.charge}
	r.global_position = Vector2(-1300, gm.terrain.height_at(-1300) - 5000)
	r.gravity_scale = 0.0
	r.launch(Vector2.ZERO, 0.0)
	r.spin_charge.charge = start_charge
	await _frames_n(24)                           # 0.2 s: spun up, charge still ~0
	res["cw0"] = r.angular_velocity / TAU
	var c0 := r.spin_charge.charge
	await _frames_n(216)                          # 2 s released in total
	res["auto_gain"] = r.spin_charge.charge - c0
	await _frames_n(480)                          # +4 s -> full
	res["cw_full"] = r.angular_velocity / TAU
	res["full"] = r.spin_charge.charge
	gm.input.set_virtual_hold(true)
	var c1 := r.spin_charge.charge
	await _frames_n(120)
	res["held_gain"] = r.spin_charge.charge - c1
	res["ccw"] = -r.angular_velocity / TAU
	gm.input.set_virtual_hold(false)
	return res

## Floating robot (no gravity / ground) at a given acceleration setting: average rps inside each completed turn.
func _accel_float(accel: float, turns: int) -> Dictionary:
	gm.set_setting("spin_accel", accel)
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	await get_tree().physics_frame
	var r := gm.robot
	r.global_position = Vector2(-1300, gm.terrain.height_at(-1300) - 6000)
	r.gravity_scale = 0.0
	r.launch(Vector2.ZERO, 0.5 * TAU)
	# v36 (legit update): turns stop counting at 100 % charge (tested in v36_tests); this measures the per-turn step
	# itself, so the charge is switched off here
	r.spin_charge.enabled = false
	var res := {"rps": []}
	var k := 0
	var guard := 0
	while k < turns and guard < 120 * 60:
		guard += 1
		await get_tree().physics_frame
		var t := r.rotation_ctl.auto_turns
		if t >= k + 0.6:   # sample mid-turn, after the speed step has settled
			res.rps.append(snappedf(r.angular_velocity / TAU, 0.001))
			k += 1
	var t0 := r.rotation_ctl.auto_turns
	gm.input.set_virtual_hold(true)
	await _frames_n(120)
	res["turns_held_delta"] = r.rotation_ctl.auto_turns - t0
	res["ccw"] = -r.angular_velocity / TAU
	gm.input.set_virtual_hold(false)
	await _frames_n(90)   # past the 0.5 s recovery ramp (v0.9.2)
	res["after_hold_rps"] = r.angular_velocity / TAU
	return res


## Drop from high with auto spin: counter grows in the air, touchdown resets it.
func _accel_reset() -> Dictionary:
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	gm.hand.visible = false
	await get_tree().physics_frame
	var r := gm.robot
	var x := -1500.0
	r.global_position = Vector2(x, gm.terrain.height_at(x) - 1800.0)
	var res := {"before": 0.0, "after_touch": -1.0}
	r.touchdown.connect(func(_i: Dictionary) -> void:
		if res.after_touch < 0.0:
			res.before = res.get("last", 0.0)
			res.after_touch = r.rotation_ctl.auto_turns)
	r.launch(Vector2(0, -1400), 0.5 * TAU)   # long flight: > 1 completed turn before landing
	var t := 0.0
	while t < 6.0 and res.after_touch < 0.0:
		res["last"] = r.rotation_ctl.auto_turns
		await get_tree().physics_frame
		t += 1.0 / 120.0
	return res


# ---------------- v0.9.2: auto-spin recovery + bounce spin ----------------

## Floating robot: spin at `auto` rev/s (accel per turn `accel`), hold for hold_s, release; samples after release.
func _recovery_run(auto: float, accel: float, hold_s: float, rec_s := 0.5, rec_pct := 25.0, pre_turns := 0.0) -> Dictionary:
	gm.set_setting("auto_rps", auto)
	gm.set_setting("spin_accel", accel)
	gm.set_setting("recovery_s", rec_s)
	gm.set_setting("recovery_pct", rec_pct)
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	await get_tree().physics_frame
	var r := gm.robot
	r.global_position = Vector2(-1300, gm.terrain.height_at(-1300) - 8000)
	r.gravity_scale = 0.0
	r.launch(Vector2.ZERO, auto * TAU)
	r.rotation_ctl.auto_turns = pre_turns
	await _frames_n(90)
	var res := {}
	res["before_rps"] = r.angular_velocity / TAU
	res["auto_before"] = r.rotation_ctl.auto_rps()
	var c0 := r.spin_charge.charge
	gm.input.set_virtual_hold(true)
	await _frames_n(2)
	res["saved"] = r.rotation_ctl.saved_auto_rps
	await _frames_n(int(hold_s * 120.0))
	res["ccw"] = -r.angular_velocity / TAU
	res["charge_hold_delta"] = r.spin_charge.charge - c0
	var t_before := r.rotation_ctl.auto_turns
	var c1 := r.spin_charge.charge
	gm.input.set_virtual_hold(false)
	await get_tree().physics_frame
	res["start_target"] = r.rotation_ctl.effective_auto_rps()
	var turned := 0.0
	var samples := []
	for i in 120:   # 1.0 s after release
		await get_tree().physics_frame
		if r.angular_velocity > 0.0:
			turned += r.angular_velocity / 120.0 / TAU
		if i % 12 == 11:
			samples.append(snappedf(r.angular_velocity / TAU, 0.01))
	res["samples"] = samples
	res["after_rps"] = r.angular_velocity / TAU
	res["cw_turns_after"] = turned
	res["charge_gain"] = r.spin_charge.charge - c1
	res["charge_rate"] = r.spin_charge.charge_rate
	res["turns_after"] = r.rotation_ctl.auto_turns - t_before
	# keep going: acceleration continues after recovery
	# v36 (legit update): turns stop counting at 100 % charge (tested in v36_tests); the charge was measured above,
	# so it is switched off for this per-turn continuation check
	r.spin_charge.enabled = false
	var t1 := r.rotation_ctl.auto_turns
	var guard := 0
	while r.rotation_ctl.auto_turns < floorf(t1) + 1.6 and guard < 120 * 30:
		guard += 1
		await get_tree().physics_frame
	res["later_rps"] = r.angular_velocity / TAU
	return res


func _recovery_tests() -> void:
	gm.ui.show_hud()
	# 1+2+5: saved speed captured before the hold; start = 25% of it; back to it after 0.5 s
	var a: Dictionary = await _recovery_run(1.2, 0.0, 0.6)
	_check("recovery_saved_and_start_pct", absf(a.saved - 1.2) < 0.001 and absf(a.before_rps - 1.2) < 0.02 and absf(a.start_target - 0.3) < 0.02,
		"before=%.3f rps saved=%.3f release target=%.3f (want 0.30)" % [a.before_rps, a.saved, a.start_target])
	_check("recovery_returns_to_saved", absf(a.samples[5] - 1.2) < 0.03 and a.samples[0] < 0.75 and absf(a.after_rps - 1.2) < 0.02,
		"rps every 0.1 s after release=%s" % [a.samples])
	# 3: manual rotation never adds charge (and never drains it)
	_check("manual_no_charge", absf(a.charge_hold_delta) < 0.0001 and absf(a.ccw - gm.settings.get_value("manual_rps")) < 0.02, "charge change while held=%.4f ccw=%.3f" % [a.charge_hold_delta, a.ccw])
	# 4: charge during recovery = real clockwise rotation (35% per turn x robot rate), less than without recovery
	var want: float = a.cw_turns_after * 0.35 * a.charge_rate
	var nr: Dictionary = await _recovery_run(1.2, 0.0, 0.6, 0.0, 100.0)
	_check("recovery_charge_from_real_rotation", absf(a.charge_gain - want) < 0.01 and a.charge_gain < nr.charge_gain - 0.03,
		"1 s after release: real cw turns=%.3f charge=+%.3f (expect %.3f) | without recovery: turns=%.3f charge=+%.3f" % [a.cw_turns_after, a.charge_gain, want, nr.cw_turns_after, nr.charge_gain])
	# other examples from the brief: 0.80 -> 0.20, 1.40 -> 0.35
	var b: Dictionary = await _recovery_run(0.8, 0.0, 0.4)
	var c: Dictionary = await _recovery_run(1.4, 0.0, 0.4)
	_check("recovery_examples", absf(b.start_target - 0.2) < 0.02 and absf(c.start_target - 0.35) < 0.02,
		"0.80 -> %.3f, 1.40 -> %.3f" % [b.start_target, c.start_target])
	# 6: accelerated speed kept and acceleration continues after recovery (base 0.5 + 0.2/turn, 3 turns done)
	var d: Dictionary = await _recovery_run(0.5, 0.2, 0.5, 0.5, 25.0, 2.15)
	# saved = accelerated speed (not the base 0.5); recovery reaches at least it; the next completed turn adds +0.20
	_check("recovery_keeps_accel_then_continues", d.saved > 0.85 and absf(d.start_target - d.saved * 0.25) < 0.02
		and d.samples[5] >= d.saved - 0.03 and absf(d.later_rps - (d.after_rps + 0.2)) < 0.03,
		"saved=%.3f start=%.3f samples=%s end=%.3f next turn rps=%.3f" % [d.saved, d.start_target, d.samples, d.after_rps, d.later_rps])
	gm.reset_settings()
	# 7: bounce-spin setting never changes the controlled spin speeds
	var speeds := []
	for pct in [0.0, 40.0, 100.0]:
		gm.set_setting("bounce_spin", pct)
		var m: Dictionary = await _float_spin(0.0)
		speeds.append([pct, snappedf(m.cw0, 0.001), snappedf(m.ccw, 0.001)])
	_check("bounce_spin_not_affecting_control", speeds.all(func(v: Array) -> bool: return absf(v[1] - speeds[0][1]) < 0.002 and absf(v[2] - speeds[0][2]) < 0.002),
		"[setting, auto rps, manual rps]=%s" % [speeds])
	# bounce-spin scales the contact torque of a feet landing (linear bounce stays about the same)
	var land := {}
	for pct in [100.0, 40.0, 0.0]:
		gm.set_setting("bounce_spin", pct)
		land[pct] = await _spin_drop(18.0, 0.0)
	var k40: float = land[40.0].dw_spring / land[100.0].dw_spring if land[100.0].dw_spring != 0.0 else 0.0
	_check("bounce_spin_feet_torque", land[100.0].dw_spring < -0.2 and absf(k40 - 0.4) < 0.1 and absf(land[0.0].dw_spring) < 0.01
		and absf(land[40.0].out / land[100.0].out - 1.0) < 0.1,
		"spring dw rev/s: 100%%=%.2f 40%%=%.2f 0%%=%.2f | out speed 100%%=%.0f 40%%=%.0f 0%%=%.0f" % [land[100.0].dw_spring, land[40.0].dw_spring, land[0.0].dw_spring, land[100.0].out, land[40.0].out, land[0.0].out])
	var side := {}
	for pct in [100.0, 40.0]:
		gm.set_setting("bounce_spin", pct)
		side[pct] = await _spin_drop(90.0, 0.0, 300.0)
	_check("bounce_spin_body_scaled_not_off", absf(side[40.0].dw_solver) > 0.02 and absf(side[40.0].dw_solver) < absf(side[100.0].dw_solver),
		"side hit solver dw rev/s: 100%%=%.2f 40%%=%.2f dmg=%s/%s" % [side[100.0].dw_solver, side[40.0].dw_solver, side[100.0].dmg, side[40.0].dmg])
	gm.reset_settings()


## Drop (rotation control off) and return the first landing's angular bookkeeping.
func _spin_drop(rot_deg: float, w0: float, height := 420.0) -> Dictionary:
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	gm.hand.visible = false
	await get_tree().physics_frame
	var r := gm.robot
	var x := -1600.0
	r.global_position = Vector2(x, gm.terrain.height_at(x) - height)
	r.rotation = deg_to_rad(rot_deg)
	var res := {"dw_spring": 0.0, "dw_solver": 0.0, "out": 0.0, "done": false, "dmg": []}
	r.damaged.connect(func(a: float, _c: StringName, _h: float, _i: Dictionary) -> void: res.dmg.append(a))
	r.landed.connect(func(i: Dictionary) -> void:
		if not res.done and i.type != &"soft":
			res.done = true
			res.dw_spring = i.get("dw_spring", 0.0) / TAU
			res.dw_solver = i.get("dw_solver", 0.0) / TAU
			res.out = (i.velocity_out as Vector2).length())
	r.launch(Vector2(300, 0), w0)
	r.rotation_ctl.enabled = false
	var t := 0.0
	while t < 3.0 and not res.done:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	return res


func _frames_n(n: int) -> void:
	for i in n:
		await get_tree().physics_frame