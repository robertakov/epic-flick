class_name EnemyAI
extends Node
## Rule-based opponent driver. It owns NOTHING but a private InputRouter (real input disabled) and decides,
## like a player, when to HOLD (manual counter-clockwise) and when to RELEASE (automatic clockwise spin).
## The robot's normal physics, rotation controller, springs, charge and damage do everything else - the AI never
## writes position, velocity, rotation or distance.
##
## In the air it predicts the touchdown (ballistic + drag vs. the terrain), picks a target landing angle (slope
## normal at the predicted landing point + preferred lean), and simulates the robot's own rotation controller
## (incl. per-turn acceleration and post-hold recovery) for a set of hold plans; it chooses the plan that holds the
## least while landing within its tolerance. Charge-greedy plans keep the screen released early (auto spin
## charges) and correct late; cautious plans correct first.
## Skill (0..1) sets the quality of every step: per-flight angle error, timing error, blunders, naive slope reading,
## reaction delay, replanning rate, tolerance. A per-attempt "form" offset and the RNG make every attempt different.

var robot: RobotController
var control: InputRouter
var terrain: TerrainBuilder
var cfg: AIConfig
## Effective skill = round base skill + hidden adaptive modifier (set by RaceManager).
var skill := 0.5
var lean := 18.0
var greed := 0.5
var rng := RandomNumberGenerator.new()
var form := 0.0
var band_min_m := 0.0
var band_max_m := 0.0
var _start_x := 0.0
var _px_per_meter := 100.0
var _distance_m := 0.0
var _protect := 0.0
var _fatigue := 0.0
## Offline profiling only; false in visible gameplay.
var profile_plans := false
var plan_usec := 0
var plan_calls := 0
## Debug / telemetry snapshot (overlay + simulation tools).
var debug := {}
var flights := 0
var blunders := 0

var _t := 0.0
var _next_plan := 0.0
var _airborne := false
var _air_time := 0.0
var _desired := false
var _queued_state := false
var _queue: Array = []        # [time_due, hold]
var _lean_err := 0.0
var _tau_bias := 0.0
var _greedy := false
var _blunder := false


func setup(p_robot: RobotController, p_control: InputRouter, p_terrain: TerrainBuilder, p_cfg: AIConfig,
		p_skill: float, p_lean: float, p_greed: float, p_seed: int) -> void:
	robot = p_robot
	control = p_control
	terrain = p_terrain
	cfg = p_cfg
	skill = p_skill
	lean = p_lean
	greed = p_greed
	_start_x = robot.global_position.x
	_distance_m = 0.0
	rng.seed = p_seed
	form = _gauss() * cfg.at(cfg.form_spread, skill)
	debug = {"skill": skill, "form": form}


func eff_skill() -> float:
	return clampf(skill + form * lerpf(1.0,cfg.protected_form_scale,_protect) - cfg.long_run_skill_drop * _fatigue, 0.0, 1.0)


func configure_band(min_m: float, max_m: float, px_per_meter: float) -> void:
	var valid := is_finite(min_m) and is_finite(max_m) and min_m > 0 and max_m > min_m and px_per_meter > 0
	band_min_m = min_m if valid else 0.0
	band_max_m = max_m if valid else 0.0
	_px_per_meter = px_per_meter if px_per_meter > 0 else 100.0


## Pure constant-cost curve; no search, simulation, player comparison or desired result.
static func band_weights(distance: float, min_m: float, max_m: float) -> Vector2:
	if not is_finite(distance) or not is_finite(min_m) or not is_finite(max_m) or min_m <= 0 or max_m <= min_m:
		return Vector2.ZERO
	var span := max_m-min_m
	var protect := 1.0 - smoothstep(min_m*0.9,min_m+span*0.25,distance)
	var fatigue := smoothstep(max_m-span*0.2,max_m+span*0.8,distance)
	return Vector2(protect,fatigue)


func error_scale(protected_scale: float) -> float:
	return lerpf(1.0,protected_scale,_protect)


func bounded_noise() -> float:
	var noise := _gauss()
	return lerpf(noise,clampf(noise,-1.7,1.7),_protect)


func _gauss() -> float:
	return rng.randfn(0.0, 1.0)


func _physics_process(dt: float) -> void:
	if robot == null or not is_instance_valid(robot):
		return
	_t += dt
	var distance := (robot.global_position.x-_start_x)/_px_per_meter
	if is_finite(distance):
		_distance_m = maxf(_distance_m,distance)
	var weights := band_weights(_distance_m,band_min_m,band_max_m)
	_protect = weights.x
	_fatigue = weights.y
	if not robot.launched or not robot.rotation_ctl.enabled:
		control.set_virtual_hold(false)
		debug.state = "idle"
		return
	var air := not robot.contacts.any_contact
	if air:
		_air_time += dt
		if not _airborne and _air_time > 0.05:
			_airborne = true
			_new_flight()
	else:
		_air_time = 0.0
		if _airborne:
			_airborne = false
		_desired = false          # on the ground: let the auto spin run (and roll the robot onward)
		debug.state = "ground"
	if _airborne and _t >= _next_plan:
		var tick := Time.get_ticks_usec() if profile_plans else 0
		_plan()
		if profile_plans:
			plan_usec += Time.get_ticks_usec()-tick
			plan_calls += 1
		_next_plan = _t + cfg.at(cfg.replan_interval, eff_skill()) * rng.randf_range(0.8, 1.2)
	# human-like reaction delay between deciding and pressing / releasing
	if _desired != _queued_state:
		_queued_state = _desired
		_queue.append([_t + cfg.at(cfg.reaction_delay, eff_skill()) * error_scale(cfg.protected_reaction_scale) * rng.randf_range(0.6, 1.4), _desired])
	while not _queue.is_empty() and _queue[0][0] <= _t:
		control.set_virtual_hold(_queue.pop_front()[1])
	debug.hold = control.holding


## A new flight: sample this jump's mistakes.
func _new_flight() -> void:
	flights += 1
	var s := eff_skill()
	_lean_err = bounded_noise() * cfg.at(cfg.angle_error_deg, s) * error_scale(cfg.protected_angle_scale) * lerpf(1.0,cfg.long_run_angle_scale,_fatigue)
	_tau_bias = bounded_noise() * cfg.at(cfg.timing_error, s) * error_scale(cfg.protected_timing_scale) * lerpf(1.0,cfg.long_run_timing_scale,_fatigue)
	_blunder = rng.randf() < cfg.at(cfg.blunder_chance, s) * error_scale(cfg.protected_blunder_scale)
	if _blunder:
		blunders += 1
		_lean_err += (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(80.0, 160.0) * error_scale(0.25)
	_greedy = rng.randf() < greed
	debug.merge({"flight": flights, "lean_err": _lean_err, "tau_bias": _tau_bias, "blunder": _blunder,
		"greedy": _greedy}, true)


func _plan() -> void:
	var s := eff_skill()
	var pred := _predict_impact()
	if pred.is_empty():
		_desired = false
		debug.state = "air: no touchdown in sight"
		return
	var tau: float = maxf(pred.t * (1.0 + _tau_bias + bounded_noise() * cfg.at(cfg.timing_error, s) * error_scale(cfg.protected_timing_scale) * lerpf(1.0,cfg.long_run_timing_scale,_fatigue) * 0.3), 0.05)
	# slope judgement: good players read the landing spot, weak ones partly the ground under them
	var n_land: Vector2 = pred.normal
	var n_here := terrain.normal_at(robot.global_position.x)
	var mix := cfg.at(cfg.naive_slope_mix, s) * error_scale(cfg.protected_slope_scale)
	var n := n_land.lerp(n_here, mix).normalized()
	var target := atan2(n.x, -n.y) + deg_to_rad(lean + _lean_err)
	var tol := cfg.at(cfg.plan_tolerance, s) * error_scale(cfg.protected_tolerance_scale)
	var greedy := _greedy and tau > 0.35
	var best := _choose(tau, target, tol, greedy)
	var h: float = best.h
	if greedy:
		# start holding when the remaining time reaches the planned hold, early by the expected press latency
		# (a skilled player anticipates their own reaction; a weak one only partly)
		var latency := cfg.at(cfg.replan_interval, s) * 0.5 + cfg.at(cfg.reaction_delay, s) * error_scale(cfg.protected_reaction_scale) * s
		_desired = h > 0.001 and h >= tau - latency
	else:
		_desired = h > 0.03
	debug.merge({"state": ("air: greedy" if greedy else "air: careful") + (" BLUNDER" if _blunder else ""),
		"tau": tau, "tau_true": pred.t, "target_deg": rad_to_deg(target), "plan_err_deg": rad_to_deg(best.err),
		"hold_plan": h, "land_x": pred.x}, true)


## Simulates the robot's own rotation controller for hold plans of length h (0..tau) and picks the least-hold
## plan within tolerance (else the most accurate). greedy: release first, hold at the end; careful: hold first.
func _choose(tau: float, target: float, tol: float, greedy: bool) -> Dictionary:
	# coarse scan, then a fine 0.01 s refinement around the pick (cheap and precise)
	var best_h := -1.0
	var best_err := INF
	var fb_h := 0.0
	var h := 0.0
	while h <= tau + 0.0001:
		var err := absf(wrapf(_simulate(tau, h, greedy) - target, -PI, PI))
		if err < tol and best_h < 0.0:
			best_h = h
		if err < best_err:
			best_err = err
			fb_h = h
		h += cfg.hold_step
	var center := best_h if best_h >= 0.0 else fb_h
	var lo := maxf(center - cfg.hold_step, 0.0)
	var hi := minf(center + cfg.hold_step, tau)
	var pick := center
	var pick_err := INF
	h = lo
	while h <= hi + 0.0001:
		var err := absf(wrapf(_simulate(tau, h, greedy) - target, -PI, PI))
		if best_h >= 0.0:
			# least hold within tolerance
			if err < tol:
				pick = h
				pick_err = err
				break
		elif err < pick_err:
			pick = h
			pick_err = err
		h += 0.01
	if pick_err == INF:
		pick_err = absf(wrapf(_simulate(tau, pick, greedy) - target, -PI, PI))
	return {"h": pick, "err": pick_err}


## Mirror of RotationController (auto speed + per-turn acceleration + cap + recovery after a hold).
func _simulate(tau: float, h: float, greedy: bool) -> float:
	var rc := robot.rotation_ctl
	var c := robot.config
	var dt := cfg.plan_dt
	var theta := robot.global_rotation
	var w := robot.angular_velocity
	var turns := rc.auto_turns
	var rec := rc.recovery_t
	var saved := rc.saved_auto_rps
	var was_hold := control.holding
	# v36: turns stop counting while the charge is full (mirror of RotationController.count_turns)
	var sc := robot.spin_charge
	var counting := sc != null and sc.enabled and sc.cfg.enabled
	var ch := sc.charge if counting else 0.0
	var ch_max := sc.cfg.max_charge - 0.0001 if counting else INF
	var ch_rate := sc.cfg.charge_per_rotation * sc.charge_rate if counting else 0.0
	var resp := 1.0 - exp(-c.rotation_response * dt)
	var t := 0.0
	while t < tau:
		var hold := (t >= tau - h) if greedy else (t < h)
		if hold and not was_hold:
			saved = minf(c.clockwise_rotation_speed + c.auto_spin_accel * floorf(turns + 0.000001), c.auto_spin_max_rps)
			rec = -1.0
		elif not hold and was_hold:
			rec = 0.0
		elif not hold and rec >= 0.0:
			rec += dt
			if rec >= c.recovery_time:
				rec = -1.0
		was_hold = hold
		var target: float
		if hold:
			target = -c.counterclockwise_rotation_speed * TAU
		else:
			var full := minf(c.clockwise_rotation_speed + c.auto_spin_accel * floorf(turns + 0.000001), c.auto_spin_max_rps)
			if rec >= 0.0 and c.recovery_time > 0.0:
				full = lerpf(saved * c.recovery_start_ratio, full, smoothstep(0.0, 1.0, rec / c.recovery_time))
			target = full * TAU
		w += (target - w) * resp
		theta += w * dt
		if not hold and w > 0.0 and ch < ch_max:
			turns += w * dt / TAU
			ch += w * dt / TAU * ch_rate
		t += dt
	return theta


## Ballistic touchdown prediction (gravity + quadratic drag) against the terrain. Cheap: <= 60 steps.
func _predict_impact() -> Dictionary:
	var p := robot.global_position
	var v := robot.linear_velocity
	var g := BiomeRuntime.gravity() * robot.gravity_scale   # v30: biome gravity (Moon / Heavy World)
	var drag := robot.config.air_drag
	var dt := 1.0 / 20.0
	var t := 0.0
	var reach := 150.0 * robot.config.rig_scale / 0.42
	while t < cfg.max_lookahead:
		if p.y + reach >= terrain.height_at(p.x):
			return {"t": t, "normal": terrain.normal_at(p.x), "x": p.x}
		v.y += g * dt
		v -= v * v.length() * drag * dt
		p += v * dt
		t += dt
	return {}
