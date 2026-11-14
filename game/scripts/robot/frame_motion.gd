class_name FrameMotion
extends RefCounted
## Motion of the rigid frame (robot body or detached part) a dangling spring lives in.
## Springs are simulated in that local frame with the proper inertial pseudo-forces, so arms fling out
## while spinning, float in free fall and whip on impacts - physics drives the cartoon motion.

var accel_local := Vector2.ZERO   # frame linear acceleration, in frame-local axes
var gravity_local := Vector2.ZERO
var w := 0.0                      # angular velocity (rad/s, + = clockwise)
var alpha := 0.0                  # angular acceleration

var _prev_v := Vector2.ZERO
var _prev_w := 0.0
var _primed := false

const MAX_ACCEL := 60000.0
const MAX_ALPHA := 900.0


func update_from(body: RigidBody2D, dt: float, gravity: float) -> void:
	var v := body.linear_velocity
	var ww := body.angular_velocity
	if not _primed:
		_prev_v = v
		_prev_w = ww
		_primed = true
	var a := (v - _prev_v) / dt
	if a.length() > MAX_ACCEL:
		a = a.normalized() * MAX_ACCEL
	var rot := -body.global_rotation
	accel_local = a.rotated(rot)
	gravity_local = Vector2(0, gravity * body.gravity_scale).rotated(rot)
	w = ww
	alpha = clampf((ww - _prev_w) / dt, -MAX_ALPHA, MAX_ALPHA)
	_prev_v = v
	_prev_w = ww


## Pseudo acceleration felt by a point at local position p moving with local velocity v.
func pseudo(p: Vector2, v: Vector2) -> Vector2:
	# -a_frame + g  - alpha x p  - w x (w x p) - 2 w x v      (2D cross: w x p = (-w p.y, w p.x))
	var euler := Vector2(alpha * p.y, -alpha * p.x)
	var centrifugal := p * (w * w)
	var coriolis := Vector2(2.0 * w * v.y, -2.0 * w * v.x)
	return -accel_local + gravity_local + euler + centrifugal + coriolis
