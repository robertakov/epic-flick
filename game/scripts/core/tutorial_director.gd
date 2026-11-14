class_name TutorialDirector
extends Node
## Tutorial (v33 flow, v34 pacing): learn by PLAYING, one concept at a time, on the practice slope
## (TerrainBuilder.build_training) with the REAL release controls (fixed physics).
##
## v34 FREEZE GATES (v33's x0.65 slow motion failed on phones: the robot kept falling while the player was still
## reading, so success depended on reading + reaction speed). Every teaching step now:
##   1. builds a fair practice setup (setup_step), 2. FREEZES the robot body (RigidBody2D.freeze, velocities stored;
##   no time_scale change, no SceneTree pause -> UI, Skip and input stay live), 3. shows ONE instruction,
##   4. waits indefinitely, 5. resumes on the step's initiating input, 6. observes the REAL gameplay event.
##   Gate input: ROTATE / FEET / CHARGED = a press (hold to steer); CHARGE = a tap that is released (charge only builds
##   while the screen is NOT held). FLICK is gated by the hand itself (it waits at tension for the flick-bar tap).
## Completion is ONLY from authoritative signals / state, never from time:
##   FLICK    GameManager.flicked (tier МИН -> retry the flick)
##   ROTATE   InputRouter.holding while airborne AND the robot really turned counter-clockwise >= ROTATE_GOAL rad
##   FEET     RobotController.landed left / right / both (body / head / poor -> same setup again)
##   REBOUND  the spring of that landing threw the robot back into the air
##   CHARGE   SpinChargeController.ratio() >= CHARGE_GOAL while airborne and not holding
##   CHARGED  RobotController.charge_released on zone "feet" (>= CHARGED_MIN) and that landing is a feet landing
## Practice setups (x on the court, heights above the local ground): see SETUPS. CHARGE gives ~1.9 s of airtime
## (~1.7 automatic turns at the release 0.9 rev/s); the goal needs ~1 turn; the CHARGED gate then re-freezes with
## the earned charge kept and at least CHARGED_CLEARANCE px to the ground for the landing.
## Failures never restart the tutorial: the current setup is rebuilt and frozen again.

enum Step { FLICK, ROTATE, FEET, REBOUND, CHARGE, CHARGED, DONE }

const ROTATE_GOAL := 0.6        # rad of real counter-clockwise turn while holding (~35 deg)
const REBOUND_AIR := 0.12       # s airborne after the feet landing
const CHARGE_GOAL := 0.35       # charge ratio = one automatic turn at the default charge rate
const CHARGED_MIN := 0.1        # charge actually released on the feet
const CHARGED_CLEARANCE := 700.0
const STALL_S := 1.2
const COURT_X := -1300.0
const COURT_END_X := 7000.0
## step -> [height above ground, launch velocity on resume, rotation (rad), angular velocity on resume (rad/s)]
const SETUPS := {
	1: [820.0, Vector2(220, -500), 0.0, 0.0],       # ROTATE: high, upright, plenty of time to see the turn
	2: [900.0, Vector2(220, -450), -1.6, 0.0],      # FEET: feet pointing sideways -> steer them down
	4: [1500.0, Vector2(180, -900), 0.0, 5.65],     # CHARGE: very high + upward kick, spinning clockwise (0.9 rev/s)
}

var gm: GameManager
var destination := &"campaign"
var step := Step.FLICK
var active := true
var gated := false               # gameplay of the robot is frozen, waiting for the initiating input
var ccw := 0.0
var retries := 0
var gates_opened := 0
var completions: Array[String] = []
var hints := {}
var _prev_rot := 0.0
var _air_t := 0.0
var _stall_t := 0.0
var _charged_feet := false
var _busy := false
var _gate_pressed := false       # CHARGE gate: pressed, waiting for the release
var _resume_v := Vector2.ZERO
var _resume_w := 0.0
var _air_gate_pending := false   # freeze the flicked robot in flight for the ROTATE instruction


func _ready() -> void:
	bind_robot()
	set_step(Step.FLICK)
	gm.flicked.connect(_on_flicked)
	gm.input.hold_changed.connect(_on_hold_changed)


func bind_robot() -> void:
	var r := gm.robot
	_prev_rot = r.rotation
	r.landed.connect(func(i: Dictionary) -> void:
		if r == gm.robot:
			_on_landed(i))
	r.touchdown.connect(func(i: Dictionary) -> void:
		if r == gm.robot:
			_on_touchdown(i))
	r.charge_released.connect(func(c: float, _dv: Vector2, i: Dictionary) -> void:
		if r == gm.robot and active and step == Step.CHARGED and StringName(i.get("zone_class", &"")) == &"feet" and c >= CHARGED_MIN:
			_charged_feet = true)
	r.damaged.connect(func(a: float, _z: StringName, _hp: float, _i: Dictionary) -> void:
		if r == gm.robot and active and a > 0.0 and not hints.has("damage"):
			hints.damage = true
			gm.ui.tutorial_overlay.callout(&"health", L.t("TUT_HIT")))
	r.limb_lost.connect(func(_l: StringName, _p: RigidBody2D) -> void:
		if r == gm.robot and active and not hints.has("limb"):
			hints.limb = true
			gm.ui.tutorial_overlay.callout(&"modules", L.t("TUT_PART_LOST")))
	r.rocket_launch_gate = func(_info: Dictionary) -> bool:
		if active:
			retry_step.call_deferred(L.t("TUT_NEW_ROBOT"))
		return active


func set_step(value: Step) -> void:
	step = value
	ccw = 0.0
	_air_t = 0.0
	_charged_feet = false
	if is_instance_valid(gm.robot):
		_prev_rot = gm.robot.rotation
	GameManager.set_sim_speed(1)   # v34: never slow motion - the gates give the reading time
	gm.ui.tutorial_overlay.show_step(step, gated)


func _learned(next: Step, word: String) -> void:
	var from := step
	completions.append(Step.keys()[step])
	gm.ui.tutorial_overlay.pop(word, true)
	set_step(next)
	if next == Step.ROTATE and from == Step.FLICK:
		_air_gate_pending = true   # the flicked robot itself freezes in flight (natural continuation)
	elif next in [Step.ROTATE, Step.FEET, Step.CHARGE]:
		setup_step.call_deferred()
	elif next == Step.CHARGED:
		_gate_charged.call_deferred()


# ---------------- practice setups + freeze gates ----------------

## A fresh robot (full HP, no charge) in the step's practice pose, frozen behind the instruction gate.
func setup_step() -> void:
	if not active or not SETUPS.has(step):
		return
	_busy = true
	var cfg: Array = SETUPS[step]
	gm._spawn_robot()
	gm.hand.playing = false
	gm.hand.visible = false
	gm.ui.flick_bar.hide_immediate()
	gm.state = GameManager.State.RUN
	var r := gm.robot
	r.global_position = Vector2(COURT_X, gm.terrain.height_at(COURT_X) - float(cfg[0]))
	r.rotation = float(cfg[2])
	r.launch(Vector2.ZERO, 0.0)
	bind_robot()
	gm.camera.follow(r)
	gm.camera.practice_offset = Vector2(0, 40)
	gm.camera.focus_practice(r)
	gm.ui.set_health(r.damage.max_health, r.damage.max_health, true)
	gm.ui.reset_modules()
	_freeze(cfg[1], float(cfg[3]))
	_busy = false


## CHARGED: keep the robot, its rotation and the REAL earned charge; give it room to land and freeze again.
func _gate_charged() -> void:
	if not active or step != Step.CHARGED or not is_instance_valid(gm.robot):
		return
	var r := gm.robot
	var ground := gm.terrain.height_at(r.global_position.x)
	if ground - r.global_position.y < CHARGED_CLEARANCE:
		r.global_position.y = ground - CHARGED_CLEARANCE
	_freeze(Vector2(r.linear_velocity.x, minf(r.linear_velocity.y, 0.0)), r.angular_velocity)


func _freeze(resume_v: Vector2, resume_w: float) -> void:
	var r := gm.robot
	_resume_v = resume_v
	_resume_w = resume_w
	r.linear_velocity = Vector2.ZERO
	r.angular_velocity = 0.0
	r.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	r.freeze = true
	gated = true
	_gate_pressed = false
	gm.camera.practice_offset = Vector2(0, 220) if step == Step.FLICK else Vector2(0, 40)
	gm.input.reset()
	gm.ui.tutorial_overlay.show_step(step, true)


func _release_gate() -> void:
	if not gated or not is_instance_valid(gm.robot):
		return
	var r := gm.robot
	gated = false
	gates_opened += 1
	r.freeze = false
	r.linear_velocity = _resume_v
	r.angular_velocity = _resume_w
	_prev_rot = r.rotation
	gm.ui.tutorial_overlay.show_step(step, false)


func _on_hold_changed(holding: bool) -> void:
	if not active or not gated or _busy:
		return
	if step == Step.CHARGE:
		# the charge only builds while NOT holding: the gate opens when the tap is released
		if holding:
			_gate_pressed = true
		elif _gate_pressed:
			_release_gate()
	elif holding and step in [Step.ROTATE, Step.FEET, Step.CHARGED]:
		_release_gate()   # the press starts the action (hold to steer)


# ---------------- authoritative events ----------------

func _on_flicked(tier: String, _mult: float) -> void:
	if not active or step != Step.FLICK:
		return
	if tier == "MINIMUM":
		gm.ui.tutorial_overlay.pop(L.t("TUT_WEAK"), false)
		retries += 1
		restart_flick.call_deferred()
		return
	_learned(Step.ROTATE, L.t("TUT_YES"))


func _on_touchdown(i: Dictionary) -> void:
	if not active or gated:
		return
	var zone := StringName(i.get("charge_zone", &""))
	if step == Step.CHARGED and zone != &"feet" and zone != &"" and String(i.get("type", "")) != "soft":
		_fail(L.t("TUT_NOT_BODY_AGAIN"), Step.CHARGE)


func _on_landed(i: Dictionary) -> void:
	if not active or gated:
		return
	var t := String(i.get("type", ""))
	var feet := t in ["left", "right", "both"]
	match step:
		Step.ROTATE:
			if t != "soft":
				_fail(L.t("TUT_AGAIN_HOLD"), Step.ROTATE)
		Step.FEET:
			if feet:
				_learned(Step.REBOUND, L.t("TUT_FEET_YES"))
			elif t in ["body", "poor"]:
				var head := StringName(i.get("charge_zone", &"")) == &"head" or StringName(i.get("first", &"")) == &"head"
				_fail(L.t("TUT_NOT_HEAD") if head else L.t("TUT_NOT_BODY"), Step.FEET)
		Step.CHARGE:
			if t != "soft":
				_fail(L.t("TUT_DONT_HOLD"), Step.CHARGE)
		Step.CHARGED:
			if feet and _charged_feet:
				_learned(Step.DONE, L.t("TUT_POWERFUL"))
				gm.ui.tutorial_overlay.show_done()
			elif t != "soft":
				_fail(L.t("TUT_CHARGE_LOST"), Step.CHARGE)


## A failed teaching attempt: short feedback, then the same concept's setup again (frozen).
func _fail(word: String, back_to: Step) -> void:
	if _busy:
		return
	retries += 1
	gm.ui.tutorial_overlay.pop(word, false)
	_busy = true
	await gm.get_tree().create_timer(0.8).timeout
	_busy = false
	if not active:
		return
	set_step(back_to)
	setup_step()


# ---------------- per step ----------------

func _physics_process(dt: float) -> void:
	if not active or _busy or gated or not is_instance_valid(gm.robot) or step == Step.DONE:
		return
	var r := gm.robot
	var d := wrapf(r.rotation - _prev_rot, -PI, PI)
	_prev_rot = r.rotation
	var airborne := r.launched and not r.contacts.any_contact
	_air_t = _air_t + dt if airborne else 0.0
	if _air_gate_pending and step == Step.ROTATE:
		if airborne and _air_t >= 0.3:
			_air_gate_pending = false
			_freeze(r.linear_velocity, r.angular_velocity)
		return
	match step:
		Step.ROTATE:
			if airborne and gm.input.holding and d < 0.0:
				ccw += -d
			if ccw >= ROTATE_GOAL:
				_learned(Step.FEET, L.t("TUT_YES"))
		Step.REBOUND:
			if _air_t >= REBOUND_AIR:
				_learned(Step.CHARGE, L.t("TUT_SPRING"))
		Step.CHARGE:
			if airborne and not gm.input.holding and r.spin_charge.ratio() >= CHARGE_GOAL:
				_learned(Step.CHARGED, L.t("TUT_CHARGE"))
	if gm.state == GameManager.State.RUN and step != Step.FLICK:
		_stall_t = _stall_t + dt if r.contacts.any_contact and r.linear_velocity.length() < 60.0 else 0.0
		if _stall_t > STALL_S or r.global_position.x > COURT_END_X:
			_stall_t = 0.0
			retry_step.call_deferred(L.t("TUT_AGAIN"))


# ---------------- retries ----------------

## Rebuild the current concept's practice setup (CHARGED retries from CHARGE: the charge must be earned again).
func retry_step(word := "") -> void:
	if not active or _busy:
		return
	if word == "":
		word = L.t("TUT_AGAIN")
	retries += 1
	gm.ui.tutorial_overlay.pop(word, false)
	match step:
		Step.FLICK:
			restart_flick()
		Step.REBOUND:
			set_step(Step.FEET)
			setup_step()
		Step.CHARGED:
			set_step(Step.CHARGE)
			setup_step()
		_:
			setup_step()


## Back on the ledge with the hand at tension and the real flick bar (flick retry).
func restart_flick() -> void:
	if not active:
		return
	_busy = true
	await gm.get_tree().create_timer(0.9, true, false, true).timeout
	if not active:
		return
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	gm._frame_intro()
	gm.camera.practice_framing = true
	gm.camera.practice_offset = Vector2(0, 220)
	bind_robot()
	gm.hand.hold_at_tension = true
	gm.ui.flick_bar.begin(true)
	gm.hand.play(1.6)
	gm.ui.set_health(gm.robot.damage.max_health, gm.robot.damage.max_health, true)
	set_step(Step.FLICK)
	_busy = false


## Kept for the old test API: a new practice throw of the current step.
func practice_throw(word := "") -> void:
	retry_step(word)


func on_run_end() -> void:
	if active and step != Step.DONE:
		retry_step.call_deferred(L.t("TUT_AGAIN"))


func stop() -> void:
	active = false
	if is_instance_valid(gm.robot) and gm.robot.freeze and gated:
		gm.robot.freeze = false
	gated = false
	GameManager.set_sim_speed(1)
	gm.input.reset()
	gm.ui.tutorial_overlay.visible = false
