class_name StarTracker
extends RefCounted
## Read-only per-attempt measurements. Runtime and offline validation share evaluate().
## stop() disconnects the source before retry/menu; old robots cannot award new stars.
signal star_completed(index: int)
signal star_failed(index: int)

var challenges: Array = []
var owned: Array = []
var status: Array = [] # pending=0, completed=1, impossible this attempt=-1
var robot: RobotController
var active := true
var distance := 0.0
var px_per_meter := 100.0
var start_x := 0.0
var _seen_contact := false
var _left_launch := false
var _was_contact := false
var _air := 0.0
var _takeoff_x := 0.0
var _clean_start := 0.0
var _bad_pending := false
var _contact_pending := false
var _contact_m := 0.0
var _next_hp := 5.0
var _has_prev_theta := false
var _prev_theta := 0.0
var _ccw_rad := 0.0          # v36: CURRENT continuous counter-clockwise streak (net radians)
var _cw_run := 0.0           # clockwise rotation since the streak last progressed
## v36 CCW_TURNS = ONE continuous counter-clockwise streak. Clockwise rotation beyond this (cumulative since the
## streak last advanced) breaks it; smaller jitter (physics noise, a tiny wobble on a contact) is only subtracted.
const CCW_JITTER_RAD := deg_to_rad(12.0)
var _head_land_cd := 0.0
var _m := {
	"distance": 0.0, "robot_m": 0.0, "rocket_head_m": 0.0,
	"first_touch_m": -1.0, "first_limb_m": -1.0,
	"limb_loss_m": [], "bad_m": [], "landings": [], "hp_changes": [[0.0, 100.0]], "hp_at": {},
	"peak_charge": 0.0, "max_air": 0.0, "max_jump": 0.0, "max_speed": 0.0,
	"recoveries": 0, "max_clean": 0.0, "max_good_streak": 0, "good_streak": 0, "total_good": 0,
	"ccw_turns": 0.0, "ccw_streak": 0.0, "head_landings": 0, "max_height_m": 0.0,
	"no_touch_s": 0.0, "max_no_touch_s": 0.0,
	"flick_tier": "NORMAL", "flick_multiplier": 1.0, "flick_locked": false,
	"race_finished": false, "won": false, "player_final_m": 0.0, "best_enemy_m": 0.0,
	"win_margin_m": 0.0,
}

func _init(data: Array = [], before: Array = []) -> void:
	challenges = data.duplicate(true)
	for i in challenges.size():
		owned.append(bool(before[i]) if i < before.size() else false)
		status.append(0)

func attach(r: RobotController, ppm := 100.0) -> void:
	robot = r
	start_x = r.global_position.x
	px_per_meter = ppm
	_prev_theta = r.global_rotation
	_has_prev_theta = true
	r.landed.connect(on_landed)
	r.touchdown.connect(_touchdown)
	r.body_hit.connect(_body_hit)
	r.limb_lost.connect(_limb)
	r.damaged.connect(_damage)
	r.charge_changed.connect(_charge)

## v32 paid continue: the same attempt goes on with a new robot body; keeps start_x and every measurement.
func reattach(r: RobotController) -> void:
	disconnect_robot()
	robot = r
	_prev_theta = r.global_rotation
	_has_prev_theta = true
	r.landed.connect(on_landed)
	r.touchdown.connect(_touchdown)
	r.body_hit.connect(_body_hit)
	r.limb_lost.connect(_limb)
	r.damaged.connect(_damage)
	r.charge_changed.connect(_charge)


## v32 paid continue at distance at_m. A continue never repairs what the death already broke:
##   SURVIVAL_HP pending -> failed (the robot was destroyed before its checkpoint; restored HP is not recorded)
##   streak / chain objectives (GOOD_LANDING_STREAK, CHARGED_LANDING(_STREAK), CLEAN_SECTION, NO_TOUCH_AND_WIN):
##     the running streak is broken (they can still be achieved fresh after the continue)
##   CLEAN_START / LIMB_LIMIT / BAD_LANDING_LIMIT: their recorded limb losses / bad landings stay counted
##   accumulating / max objectives (DISTANCE, TOTAL_GOOD_LANDINGS, HEAD_LANDINGS, AIR_TIME, LONG_JUMP, SPEED_TARGET,
##     MAX_HEIGHT_M, CCW_TURNS (best streak), CHARGE_TARGET, ROCKET_HEAD_DISTANCE, RECOVERY): keep their progress
##   CCW_TURNS: the best streak is kept, the running streak ends (a new body is not one continuous rotation)
##   race / flick objectives (WIN_MARGIN_OVER, FLICK_*): unchanged (decided by the flick and the race result)
func on_continue(at_m: float) -> void:
	if not active:
		return
	_m.continued = true
	for i in challenges.size():
		if status[i] == 0 and String(challenges[i].type) == "SURVIVAL_HP":
			status[i] = -1
			star_failed.emit(i)
	_m.good_streak = 0
	_ccw_rad = 0.0
	_cw_run = 0.0
	_m.ccw_streak = 0.0
	_bad_pending = false
	_m.landings.append([false, 0.0, at_m])
	_clean_start = at_m
	_m.no_touch_s = 0.0
	_air = 0.0
	_was_contact = true
	_contact_pending = false
	_evaluate()


## A wreck can remain in contact forever. Resolve its last robot landing once,
## then stop consulting corpse contacts during the independently measured jet flight.
func finalize_contact() -> void:
	if active and _contact_pending and is_instance_valid(robot):
		on_landed(robot.contacts._event.duplicate())

func disconnect_robot() -> void:
	if is_instance_valid(robot):
		for pair in [[robot.touchdown, _touchdown], [robot.landed, on_landed], [robot.body_hit, _body_hit], [robot.limb_lost, _limb], [robot.damaged, _damage], [robot.charge_changed, _charge]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
	robot = null

func stop() -> void:
	active = false
	disconnect_robot()

func _source_m() -> float:
	if not is_instance_valid(robot):
		return distance
	var x := robot.global_position.x
	var d := (x - start_x) / px_per_meter
	return maxf(distance, d) if is_finite(d) and d < distance + 100.0 else distance

func _limb(_id: StringName, _part: RigidBody2D) -> void:
	if active and robot.launched:
		on_limb(_source_m())

func on_limb(at_m: float) -> void:
	if not active:
		return
	if _m.first_limb_m < 0.0:
		_m.first_limb_m = at_m
	_m.limb_loss_m.append(at_m)
	_evaluate()

func _damage(_amount: float, _zone: StringName, hp: float, _info: Dictionary) -> void:
	if active and robot.launched:
		on_health(_source_m(), hp / robot.damage.max_health * 100.0)

func on_health(at_m: float, hp: float) -> void:
	if active:
		_m.hp_changes.append([at_m, hp])
		_evaluate()

func _charge(c: float) -> void:
	if active and robot.launched and not robot.damage.rocket_fired:
		on_charge(c / maxf(robot.spin_config.max_charge, 0.0001))

func on_charge(ratio: float) -> void:
	if active and is_finite(ratio):
		_m.peak_charge = maxf(_m.peak_charge, clampf(ratio, 0.0, 1.0))
		_evaluate()

func _body_hit(info: Dictionary) -> void:
	if not active or not is_instance_valid(robot) or not robot.launched or robot.damage.rocket_fired:
		return
	if StringName(info.get("kind", &"")) == &"head" and float(info.get("impact", 0.0)) >= 25.0:
		on_head_landing()

func on_head_landing() -> void:
	if not active or _head_land_cd > 0.0:
		return
	_head_land_cd = 0.25
	_m.head_landings = int(_m.head_landings) + 1
	_evaluate()

func on_flick(tier_name: String, multiplier := 1.0) -> void:
	if not active:
		return
	_m.flick_tier = tier_name
	_m.flick_multiplier = multiplier
	_m.flick_locked = true
	_evaluate()

func sample_rotation(dtheta_rad: float) -> void:
	if not active or not is_finite(dtheta_rad):
		return
	if _rotate(dtheta_rad):
		_evaluate()


## One rotation sample (Godot 2D: negative = counter-clockwise). Returns true when the best streak grew.
func _rotate(dtheta: float) -> bool:
	if dtheta < 0.0:
		_ccw_rad += -dtheta
		_cw_run = 0.0
	elif dtheta > 0.0:
		_cw_run += dtheta
		if _cw_run > CCW_JITTER_RAD:
			_ccw_rad = 0.0          # meaningful clockwise rotation: the streak is broken
		else:
			_ccw_rad = maxf(0.0, _ccw_rad - dtheta)
	_m.ccw_streak = _ccw_rad / TAU
	if _m.ccw_streak > float(_m.ccw_turns):
		_m.ccw_turns = _m.ccw_streak
		return true
	return false

## v30 portals: a teleport is neither a jump nor a flight; the next airborne frame starts a fresh flight at the exit.
func on_teleport() -> void:
	_air = 0.0
	_was_contact = true


func sample_height(height_m: float) -> void:
	if not active or not is_finite(height_m):
		return
	if height_m > float(_m.max_height_m):
		_m.max_height_m = height_m
		_evaluate()

## NO_TOUCH_AND_WIN (3.5 s): only robot-phase time counts. v32: once the head launches into rocket mode the streak
## stops accumulating for good (a legit max reached before the launch is kept in max_no_touch_s).
func sample_no_touch(dt: float, holding: bool, rocket_phase := false) -> void:
	if not active or not is_finite(dt) or dt < 0.0:
		return
	if rocket_phase or (is_instance_valid(robot) and robot.damage.rocket_fired):
		_m.no_touch_s = 0.0
		return
	if not holding:
		_m.no_touch_s = float(_m.no_touch_s) + dt
		_m.max_no_touch_s = maxf(float(_m.max_no_touch_s), float(_m.no_touch_s))
	else:
		_m.no_touch_s = 0.0

func on_race_result(won: bool, player_m: float, best_enemy_m: float) -> void:
	if not active:
		return
	_m.race_finished = true
	_m.won = won
	_m.player_final_m = player_m
	_m.best_enemy_m = best_enemy_m
	_m.win_margin_m = player_m - best_enemy_m
	_evaluate(false)

func _touchdown(info: Dictionary) -> void:
	if not active or not robot.launched or robot.damage.rocket_fired:
		return
	if StringName(info.get("charge_zone", &"")) == &"head" and StringName(info.get("type", &"")) != &"soft":
		on_head_landing()
	if _contact_pending:
		return
	_contact_pending = true
	_contact_m = maxf(distance, (float(info.get("contact_x", robot.global_position.x)) - start_x) / px_per_meter)

func on_landed(info: Dictionary) -> void:
	if not active or (is_instance_valid(robot) and (not robot.launched or (robot.damage.rocket_fired and not _contact_pending))):
		return
	var had_contact := _contact_pending
	_contact_pending = false
	var type := String(info.get("type", ""))
	if type not in ["left", "right", "both", "poor", "body"]:
		return # Soft contacts do not break either streak or a recovery.
	var at_m := distance
	if info.has("contact_x"):
		at_m = maxf(0.0, (float(info.contact_x) - start_x) / px_per_meter)
	if had_contact:
		at_m = _contact_m # Furthest distance at touchdown, even after moving backwards.
	var good := type in ["left", "right", "both"]
	var charge := float(info.get("charge_ratio", 0.0))
	# A body-first contact that later becomes feet did not spend its charge on feet.
	if info.has("charge_zone") and String(info.charge_zone) != "feet":
		charge = 0.0
	_m.landings.append([good, charge, at_m])
	if good:
		_m.total_good += 1
		_m.good_streak += 1
		_m.max_good_streak = maxi(_m.max_good_streak, _m.good_streak)
		if _bad_pending:
			_m.recoveries += 1
		_bad_pending = false
	else:
		_m.bad_m.append(at_m)
		_m.good_streak = 0
		_bad_pending = true
		_clean_start = at_m
	_evaluate()

func step(dt: float, distance_m: float) -> void:
	if not active:
		return
	if _head_land_cd > 0.0 and dt > 0.0:
		_head_land_cd = maxf(0.0, _head_land_cd - dt)
	if not is_instance_valid(robot) or not robot.launched:
		return
	var pre_rocket := not robot.damage.rocket_fired
	if not pre_rocket:
		finalize_contact()
	else:
		var theta := robot.global_rotation
		if _has_prev_theta:
			_rotate(wrapf(theta - _prev_theta, -PI, PI))
		_prev_theta = theta
		_has_prev_theta = true
	var contact := robot.contacts.any_contact
	var x := robot.global_position.x
	var sane := is_finite(x) and absf((x - start_x) / px_per_meter - distance_m) < 1000.0
	var speed := robot.linear_velocity.length()
	if not is_finite(speed) or speed > robot.config.max_speed * 1.25:
		speed = 0.0
	sample(dt, distance_m, x, contact, pre_rocket and sane, speed / px_per_meter * 3.6,
		pre_rocket and robot.contacts._event_active)

## Public deterministic sampling seam for tests; no dependency on AI or adaptive difficulty.
func sample(dt: float, d: float, x: float, contact: bool, robot_phase: bool, kmh: float, event_active := false) -> void:
	if not active or not is_finite(d):
		return
	distance = maxf(distance, d)
	_m.distance = distance
	if robot_phase:
		_m.robot_m = distance
		if not contact:
			_left_launch = true
		if contact and _left_launch and not _seen_contact:
			_seen_contact = true
			_m.first_touch_m = distance
		if _seen_contact:
			_m.max_speed = maxf(_m.max_speed, kmh)
			if not contact:
				if _was_contact:
					_takeoff_x = x
					_air = 0.0
				_air += dt
				_m.max_air = maxf(_m.max_air, _air)
			elif not _was_contact and _air > 0.0:
				_m.max_jump = maxf(_m.max_jump, maxf(0.0, (x - _takeoff_x) / px_per_meter))
				_air = 0.0
		# Wait for contact classification before committing a section across that contact.
		if not event_active:
			_m.max_clean = maxf(_m.max_clean, distance - _clean_start)
		_was_contact = contact
	else:
		_air = 0.0 # Never bridge robot flight and jet-head flight.
		_m.rocket_head_m = maxf(float(_m.rocket_head_m), maxf(0.0, distance - float(_m.robot_m)))
	while _next_hp <= distance:
		_m.hp_at[str(int(_next_hp))] = hp_at(_m, _next_hp)
		_next_hp += 5.0
	_evaluate(event_active)

static func hp_at(m: Dictionary, checkpoint: float) -> float:
	var hp := 100.0
	for e in m.hp_changes:
		if float(e[0]) <= checkpoint:
			hp = float(e[1])
	return hp

static func count_before(events: Array, checkpoint: float) -> int:
	var n := 0
	for d in events:
		if float(d) <= checkpoint:
			n += 1
	return n

static func charged_streak(m: Dictionary, pct: float) -> int:
	var best := 0
	var current := 0
	for e in m.landings:
		current = current + 1 if bool(e[0]) and float(e[1]) * 100.0 + 0.00001 >= pct else 0
		best = maxi(best, current)
	return best

## All objectives use this exact evaluator in live runs and simulation reports.
static func evaluate(ch: Dictionary, m: Dictionary) -> bool:
	var x := float(ch.get("m", 0.0))
	var n := int(ch.get("n", 0))
	var pct := float(ch.get("pct", 0.0))
	match String(ch.type):
		"DISTANCE": return m.distance >= x
		"CLEAN_START": return m.distance >= x and count_before(m.limb_loss_m, x) == 0
		"LIMB_LIMIT": return m.distance >= x and count_before(m.limb_loss_m, x) <= n
		"BAD_LANDING_LIMIT": return m.distance >= x and count_before(m.bad_m, x) <= n
		"SURVIVAL_HP": return m.distance >= x and hp_at(m, x) >= float(ch.hp)
		"ROCKET_HEAD_DISTANCE": return float(m.get("rocket_head_m", 0.0)) >= x
		"WIN_MARGIN_OVER": return bool(m.get("race_finished", false)) and bool(m.get("won", false)) and float(m.get("win_margin_m", 0.0)) > x
		"GOOD_LANDING_STREAK": return m.max_good_streak >= n
		"TOTAL_GOOD_LANDINGS": return m.total_good >= n
		"HEAD_LANDINGS": return int(m.get("head_landings", 0)) >= n
		"NO_TOUCH_AND_WIN": return bool(m.get("race_finished", false)) and bool(m.get("won", false)) and float(m.get("max_no_touch_s", 0.0)) + 0.000001 >= float(ch.s)
		"CHARGE_TARGET": return m.peak_charge * 100.0 + 0.00001 >= pct
		"CHARGED_LANDING": return charged_streak(m, pct) >= 1
		"CHARGED_LANDING_STREAK": return charged_streak(m, pct) >= n
		"AIR_TIME": return m.max_air + 0.000001 >= float(ch.s) # Fixed-step accumulation roundoff, not extra gameplay time.
		"LONG_JUMP": return m.max_jump >= x
		"SPEED_TARGET": return m.max_speed >= float(ch.kmh)
		"CCW_TURNS": return float(m.get("ccw_turns", 0.0)) + 0.0001 >= float(n)
		"MAX_HEIGHT_M": return float(m.get("max_height_m", 0.0)) >= x
		"FLICK_MAX_POWER": return String(m.get("flick_tier", "")) == "MAXIMUM" and bool(m.get("flick_locked", true))
		"FLICK_MIN_AND_WIN": return bool(m.get("race_finished", false)) and bool(m.get("won", false)) and String(m.get("flick_tier", "")) == "MINIMUM"
		"RECOVERY": return m.recoveries >= n
		"CLEAN_SECTION": return m.max_clean >= x
	return false

func _evaluate(event_active := false) -> void:
	if not active:
		return
	if is_instance_valid(robot):
		event_active = event_active or _contact_pending or (robot.contacts._event_active and not robot.damage.rocket_fired)
	for i in challenges.size():
		if status[i] != 0:
			continue
		var ch: Dictionary = challenges[i]
		var type := String(ch.type)
		if event_active and type in ["BAD_LANDING_LIMIT", "CLEAN_SECTION"]:
			continue
		if evaluate(ch, _m):
			status[i] = 1
			star_completed.emit(i)
			continue
		var checkpoint := float(ch.get("m", 0.0))
		var fail := false
		if type == "CLEAN_START": fail = count_before(_m.limb_loss_m, checkpoint) > 0
		if type == "LIMB_LIMIT": fail = count_before(_m.limb_loss_m, checkpoint) > int(ch.n)
		if type == "BAD_LANDING_LIMIT": fail = count_before(_m.bad_m, checkpoint) > int(ch.n)
		if type == "SURVIVAL_HP": fail = hp_at(_m, minf(distance, checkpoint)) < float(ch.hp)
		if type == "FLICK_MAX_POWER" and bool(_m.get("flick_locked", false)) and String(_m.get("flick_tier", "")) != "MAXIMUM":
			fail = true
		if type == "FLICK_MIN_AND_WIN":
			if bool(_m.get("flick_locked", false)) and String(_m.get("flick_tier", "")) != "MINIMUM":
				fail = true
			elif bool(_m.get("race_finished", false)) and not bool(_m.get("won", false)):
				fail = true
		if type in ["WIN_MARGIN_OVER", "NO_TOUCH_AND_WIN"] and bool(_m.get("race_finished", false)):
			fail = true
		if fail:
			status[i] = -1
			star_failed.emit(i)

func metrics() -> Dictionary:
	return _m.duplicate(true)

func progress(i: int) -> String:
	var ch: Dictionary = challenges[i]
	match String(ch.type):
		"ROCKET_HEAD_DISTANCE": return L.f("TRK_M", {"a": int(_m.rocket_head_m), "b": int(ch.m)})
		"WIN_MARGIN_OVER": return L.f("CHS_WIN_MARGIN", {"m": int(ch.m)})
		"GOOD_LANDING_STREAK": return "%d/%d" % [_m.good_streak, int(ch.n)]
		"TOTAL_GOOD_LANDINGS": return "%d/%d" % [_m.total_good, int(ch.n)]
		"HEAD_LANDINGS": return "%d/%d" % [int(_m.head_landings), int(ch.n)]
		"NO_TOUCH_AND_WIN": return L.f("TRK_S", {"a": L.dec(float(_m.max_no_touch_s)), "b": L.dec(float(ch.s))})
		"RECOVERY": return "%d/%d" % [_m.recoveries, int(ch.n)]
		"CHARGED_LANDING_STREAK": return "%d/%d" % [charged_streak(_m, float(ch.pct)), int(ch.n)]
		"CHARGED_LANDING": return "%d/1" % mini(1, charged_streak(_m, float(ch.pct)))
		"CHARGE_TARGET": return "%d%%" % int(_m.peak_charge * 100.0)
		"AIR_TIME": return L.f("TRK_S", {"a": L.dec(float(_m.max_air)), "b": L.dec(float(ch.s))})
		"SPEED_TARGET": return "%d/%d" % [int(_m.max_speed), int(ch.kmh)]
		"LONG_JUMP": return L.f("TRK_M", {"a": int(_m.max_jump), "b": int(ch.m)})
		"CCW_TURNS": return "%d/%d" % [int(floor(float(_m.ccw_turns) + 0.0001)), int(ch.n)]
		"MAX_HEIGHT_M": return L.f("TRK_M", {"a": int(_m.max_height_m), "b": int(ch.m)})
		"FLICK_MAX_POWER": return "1/1" if String(_m.flick_tier) == "MAXIMUM" and bool(_m.flick_locked) else "0/1"
		"FLICK_MIN_AND_WIN": return L.t("TRK_MIN_OK") if String(_m.flick_tier) == "MINIMUM" and bool(_m.flick_locked) else "0/1"
		"CLEAN_SECTION": return L.f("TRK_M", {"a": int(maxf(0.0, float(_m.robot_m) - _clean_start)), "b": int(ch.m)})
	return L.f("TRK_M", {"a": int(distance), "b": int(ch.get("m", 0))})
