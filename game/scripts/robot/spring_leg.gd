class_name SpringLeg
extends RefCounted
## State of one physical spring leg. The coil length here IS the visual length (no fake animation):
## grounded -> length = rest - compression from the ground ray; airborne -> damped free oscillator.

var side: StringName          # &"leg_l" / &"leg_r"
var hip := Vector2.ZERO        # body-local hip position
var cap_len := 13.0            # hip -> top of coil
var boot_len := 54.0           # bottom of coil -> sole
var attached := true

var length := 56.0             # current coil length (px)
var length_vel := 0.0          # d(length)/dt
var in_contact := false
var compression := 0.0
var compression_vel := 0.0     # > 0 while compressing
var load_ratio := 0.0          # 0..1 of the usable compression
var ground_normal := Vector2.UP
var ground_point := Vector2.ZERO
var bottomed := false
var peak_load := 0.0           # max load_ratio during the current contact
var contact_time := 0.0


func reach(cfg: ContactConfig) -> float:
	return cap_len + cfg.coil_rest_length + boot_len


## Free oscillation while airborne (semi-implicit Euler, stable at 120 Hz).
func step_free(cfg: ContactConfig, dt: float, axial_accel: float) -> void:
	var w := TAU * cfg.free_leg_frequency
	var a := -w * w * (length - cfg.coil_rest_length) - 2.0 * cfg.free_leg_damping * w * length_vel - axial_accel
	length_vel += a * dt
	length += length_vel * dt
	if length > cfg.coil_max_length:
		length = cfg.coil_max_length
		length_vel = minf(length_vel, 0.0)
	elif length < cfg.coil_min_length:
		length = cfg.coil_min_length
		length_vel = maxf(length_vel, 0.0)
