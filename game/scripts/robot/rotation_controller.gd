class_name RotationController
extends Node
## One-button spin control. Released: clockwise at `clockwise_rotation_speed` rev/s.
## Held: counter-clockwise at `counterclockwise_rotation_speed` rev/s.
## v0.9.1: the automatic speed grows by RobotConfig.auto_spin_accel per COMPLETED automatic clockwise turn in the air
## (held / counter-clockwise rotation never counts), capped by auto_spin_max_rps; the counter restarts on a new contact.
## Implemented as a controlled angular velocity (exponential approach), weakened while touching the
## ground so contact torques from springs / body hits still matter.

var cfg: RobotConfig
var input: InputRouter
var enabled := false
var spin_charge: SpinChargeController   # optional: (legacy) charge-based speed-up multiplier
## Completed + partial automatic clockwise turns in the air since the last contact.
var auto_turns := 0.0
## Recovery phase (v0.9.2): auto speed saved when a hold starts, and the time since release.
var saved_auto_rps := 0.0
var recovery_t := -1.0          # < 0 = not recovering
var _was_holding := false


func _holding() -> bool:
	return input != null and input.holding


func is_recovering() -> bool:
	return recovery_t >= 0.0 and cfg.recovery_time > 0.0 and recovery_t < cfg.recovery_time


## Speed the automatic spin is actually driven to right now (rev/s). During recovery: smooth ease from
## recovery_start_ratio x saved_auto_rps (speed before the hold) to the current automatic speed
## (= saved_auto_rps unless a contact restarted the turn counter meanwhile).
func effective_auto_rps() -> float:
	var full := auto_rps()
	if not is_recovering():
		return full
	var start := saved_auto_rps * clampf(cfg.recovery_start_ratio, 0.0, 1.0)
	return lerpf(start, full, smoothstep(0.0, 1.0, recovery_t / cfg.recovery_time))


## Current automatic (released) spin speed in rev/s.
func auto_rps() -> float:
	var rps := cfg.clockwise_rotation_speed + cfg.auto_spin_accel * floorf(auto_turns + 0.000001)
	rps *= spin_charge.cw_multiplier() if spin_charge else 1.0
	return minf(rps, maxf(cfg.auto_spin_max_rps, cfg.clockwise_rotation_speed))


func reset_auto_turns() -> void:
	auto_turns = 0.0


func _update_recovery(dt: float) -> void:
	var h := _holding()
	if h and not _was_holding:
		# remember the automatic speed reached before the manual correction (never the reduced recovery speed)
		saved_auto_rps = auto_rps()
		recovery_t = -1.0
	elif not h and _was_holding:
		recovery_t = 0.0
	elif not h and recovery_t >= 0.0:
		recovery_t += dt
		if recovery_t >= cfg.recovery_time:
			recovery_t = -1.0
	_was_holding = h


## Called every physics step with the body's real angular velocity.
## v36: at 100 % charge further clockwise turns no longer count (no extra acceleration); the speed already earned
## stays (auto_turns is kept, not cleared) and counting resumes as soon as the charge is below full again.
func count_turns(dt: float, angular_velocity: float, airborne: bool) -> void:
	if enabled and airborne and angular_velocity > 0.0 and not (input != null and input.holding) and not charge_full():
		auto_turns += angular_velocity * dt / TAU


func charge_full() -> bool:
	return spin_charge != null and spin_charge.is_full()


func target_angular_velocity() -> float:
	# Godot 2D: positive angular velocity = clockwise on screen
	if _holding():
		return -cfg.counterclockwise_rotation_speed * TAU
	return effective_auto_rps() * TAU


func integrate(state: PhysicsDirectBodyState2D, influence: float) -> void:
	if not enabled:
		return
	_update_recovery(state.step)
	var k := 1.0 - exp(-cfg.rotation_response * state.step)
	var w := state.angular_velocity
	var target := target_angular_velocity() * damping_compensation(k, state.total_angular_damp * state.step)
	state.angular_velocity = w + (target - w) * k * (1.0 - clampf(influence, 0.0, 1.0))


## The engine multiplies the angular velocity by (1 - c) every step (angular damping, c = damp * dt) before our
## callback, so the exponential approach alone settles below its target. The velocity we set is the one the body
## turns with:  w = (w (1 - c)) + (T - w (1 - c)) k  ->  w = T k / (k + c - k c).
## Aiming at  T (k + c - k c) / k  makes the real spin equal T (measured within 0.1 %).
static func damping_compensation(k: float, c: float) -> float:
	if k <= 0.0 or c <= 0.0 or c >= 1.0:
		return 1.0
	return (k + c - k * c) / k
