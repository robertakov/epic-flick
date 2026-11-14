class_name SpinChargeController
extends Node
## Spin charge (v0.9).
##   step()        - every physics step: real AUTOMATIC clockwise rotation in the air adds charge
##                   (+charge_per_rotation per turn, scaled by the robot's charge rate); holding adds/drains nothing
##   consume()     - SpringContactController calls it once per NEW contact event: the whole charge is spent,
##                   effective boost = charge * zone efficiency (feet 100 %, arm 30, torso 25, head 25)
##                   * the robot's energy multiplier
##   boost_vector()/clamp_out() - turn the effective boost into a bounded velocity change
## Independent of damage: never reads or writes HP.

signal charge_changed(charge: float)
signal charge_full
## Emitted when the impulse is actually applied. charge = what was stored (0..1), bonus = velocity change,
## info: zone_class, effective (0..energy_multiplier), point, normal.
signal charge_released(charge: float, bonus: Vector2, info: Dictionary)
signal charge_lost(amount: float, reason: StringName)

var cfg: SpinChargeConfig
var base_cw_speed := 0.5
## Per-robot tuning (RobotDefinition): faster/slower charging and stronger/weaker impulse.
var charge_rate := 1.0
var energy_multiplier := 1.0
var charge := 0.0
var enabled := true
var total_charged_angle := 0.0  # telemetry: radians of counted (automatic, clockwise, airborne) rotation
var releases := 0               # telemetry: number of consume() calls that spent a charge
var _was_full := false


func step(dt: float, angular_velocity: float, airborne: bool, holding: bool) -> void:
	if not enabled or not cfg.enabled:
		return
	var before := charge
	var d := angular_velocity * dt   # Godot 2D: + = clockwise
	# only the automatic spin: screen released, clockwise, in the air
	if d > 0.0 and not holding and (airborne or not cfg.count_only_airborne):
		total_charged_angle += d
		charge = minf(charge + d / TAU * cfg.charge_per_rotation * charge_rate, cfg.max_charge)
	if charge != before:
		charge_changed.emit(charge)
	var full := charge >= cfg.max_charge - 0.0001
	if full and not _was_full:
		charge_full.emit()
	_was_full = full


## v36 electric anomaly: the charge jumps to 100 % at once (same signals as charging normally).
func fill() -> void:
	if not enabled or cfg == null or not cfg.enabled:
		return
	var was := charge
	charge = cfg.max_charge
	if charge != was:
		charge_changed.emit(charge)
	if not _was_full:
		charge_full.emit()
	_was_full = true


## Charge at 100 % (an active controller only).
func is_full() -> bool:
	return enabled and cfg != null and cfg.enabled and charge >= cfg.max_charge - 0.0001


## 0..1 share of the charge.
func ratio() -> float:
	return clampf(charge / maxf(cfg.max_charge, 0.0001), 0.0, 1.0)


## Physical automatic spin multiplier (very slight speed-up with charge).
func cw_multiplier() -> float:
	if not enabled or not cfg.enabled:
		return 1.0
	return 1.0 + cfg.spin_speedup_at_full * ratio()


func cw_speed() -> float:
	return base_cw_speed * cw_multiplier()


func efficiency(zone_class: StringName) -> float:
	return float(cfg.zone_efficiency.get(String(zone_class), 0.25))


## A new contact started: spend EVERYTHING. Returns the effective boost (0 = nothing to apply).
func consume(zone_class: StringName) -> float:
	if not enabled or not cfg.enabled or charge <= 0.0:
		return 0.0
	var c := ratio()
	charge = 0.0
	_was_full = false
	charge_changed.emit(charge)
	if c < cfg.min_charge_to_use:
		charge_lost.emit(c, &"tiny")
		return 0.0
	releases += 1
	return c * efficiency(zone_class) * energy_multiplier


## Velocity change for an effective boost. n = surface normal, up = robot up axis, fwd = down-track tangent.
func boost_vector(effective: float, n: Vector2, up: Vector2, fwd: Vector2) -> Vector2:
	var dir := (n + up).normalized() if (n + up).length_squared() > 0.01 else n
	return (dir * cfg.boost_up + fwd * cfg.boost_forward) * effective


## Keeps the landing caps, with bounded headroom proportional to the effective boost.
func clamp_out(v: Vector2, n: Vector2, effective: float, contact_cfg: ContactConfig, spring_speed_scale := 1.0) -> Vector2:
	var head := cfg.bonus_cap_headroom * clampf(effective, 0.0, 2.0)
	var vn := v.dot(n)
	if vn > contact_cfg.max_release_normal_speed * spring_speed_scale + head:
		v -= n * (vn - contact_cfg.max_release_normal_speed * spring_speed_scale - head)
	if v.length() > contact_cfg.max_release_speed * spring_speed_scale + head:
		v = v.normalized() * (contact_cfg.max_release_speed * spring_speed_scale + head)
	return v


func notify_applied(stored: float, bonus: Vector2, info: Dictionary) -> void:
	charge_released.emit(stored, bonus, info)


func reset() -> void:
	charge = 0.0
	_was_full = false
	charge_changed.emit(charge)
