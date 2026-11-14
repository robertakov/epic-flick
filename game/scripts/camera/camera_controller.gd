class_name CameraController
extends Camera2D
## Follows the active piece (robot, then rocket head). Looks ahead along the velocity, zooms out on
## big jumps so the next landing spot stays visible, and adds decaying screen shake.

@export var base_zoom := 0.88
## v34 (tester: "camera a bit too close"): the follow framing shows ~10% more world in every direction. Measured
## near-ground travel zoom was ~0.58 (the downhill look-ahead keeps it below base_zoom), so the cap alone would not
## change real play; this scales the whole follow curve modestly. min_zoom, look-ahead, tutorial framing unchanged.
const FRAMING_SCALE := 0.9
@export var min_zoom := 0.34
@export var look_ahead_time := 0.34
@export var max_look_ahead := 700.0
@export var follow_rate := 7.0
@export var zoom_rate := 2.2

## Player setting Screen Shake (0..1, default 0.6). 0 = no shake at all.
var shake_scale := 0.6
## Logical safe margins from UI, converted with actual canvas scale for readability.
var safe_margins := Vector4.ZERO
var practice_framing := false
## v34: practice framing offset. Ledge / flick: (0, 220) shows hand + ground. Airborne gates: the frozen robot sits
## near the screen centre, clear of the instruction band at the top.
var practice_offset := Vector2(0, 220)
var target: Node2D
var terrain: TerrainBuilder
var intro_focus := Vector2.ZERO
var intro_zoom := 0.5
var mode := &"intro"   # &"intro", &"follow"
var _shake := 0.0
var _shake_time := 0.0
var _shake_dur := 0.0
var _center := Vector2.ZERO
var _look := Vector2.ZERO


func _ready() -> void:
	ignore_rotation = true
	position_smoothing_enabled = false


func snap_intro(focus: Vector2, z: float) -> void:
	mode = &"intro"
	target = null
	_shake = 0.0
	_shake_time = 0.0
	_shake_dur = 0.0
	intro_focus = focus
	intro_zoom = z
	_center = focus
	global_position = focus
	zoom = Vector2.ONE * z
	_look = Vector2.ZERO


func follow(t: Node2D) -> void:
	target = t
	mode = &"follow"


func shake(strength: float, duration: float) -> void:
	strength *= shake_scale
	if strength <= 0.0:
		return
	if strength >= _shake * clampf(1.0 - _shake_time / maxf(_shake_dur, 0.01), 0.0, 1.0):
		_shake = strength
		_shake_dur = duration
		_shake_time = 0.0


func _process(dt: float) -> void:
	var desired := intro_focus
	var desired_zoom := intro_zoom
	if mode == &"follow" and is_instance_valid(target):
		var p := target.global_position
		var v := Vector2.ZERO
		if target is RigidBody2D:
			v = (target as RigidBody2D).linear_velocity
		var la := Vector2(clampf(v.x * look_ahead_time, -250.0, max_look_ahead), clampf(v.y * 0.1, -120.0, 220.0))
		_look = _look.lerp(la, 1.0 - exp(-3.0 * dt))
		var probe_x := p.x + _look.x * 1.4
		var ground := terrain.surface_y(probe_x) if terrain else p.y + 300.0
		var ground_here := terrain.surface_y(p.x) if terrain else p.y + 300.0
		var low := maxf(ground, ground_here)
		var height := maxf(low - p.y, 0.0)
		var vs := usable_size()
		desired_zoom = responsive_zoom(height, vs, Vector2(DisplayServer.window_get_size()))
		desired = Vector2(p.x + _look.x, lerpf(p.y, low - 120.0, 0.45) + _look.y * 0.3)
		if practice_framing:
			desired=p+practice_offset
			desired_zoom=practice_zoom(p)
			_look=Vector2.ZERO
		# never let the followed piece leave the inner part of the frame
		var half := vs / (2.0 * desired_zoom)
		desired.x = clampf(desired.x, p.x - half.x * 0.55, p.x + half.x * 0.55)
		desired.y = clampf(desired.y, p.y - half.y * 0.5, p.y + half.y * 0.5)
	_center = _center.lerp(desired, 1.0 - exp(-follow_rate * dt))
	if mode == &"follow" and is_instance_valid(target):
		# hard limit as well, so very fast pieces (rocket head) cannot outrun the smoothing
		var lim := usable_size() / (2.0 * zoom.x) * 0.8
		var tp := target.global_position
		_center = Vector2(clampf(_center.x, tp.x - lim.x, tp.x + lim.x), clampf(_center.y, tp.y - lim.y, tp.y + lim.y))
	var z := lerpf(zoom.x, desired_zoom, 1.0 - exp(-zoom_rate * dt))
	zoom = Vector2(z, z)
	var off := Vector2.ZERO
	if _shake_time < _shake_dur:
		_shake_time += dt
		var k := 1.0 - _shake_time / _shake_dur
		off = Vector2(sin(_shake_time * 71.0), cos(_shake_time * 57.0)) * _shake * k / z
	# Centre world framing in the safe rectangle, including asymmetric Android cutouts.
	var safe_offset := Vector2(safe_margins.x-safe_margins.z, safe_margins.y-safe_margins.w) * 0.5
	global_position = _center + off - safe_offset / z


func usable_size() -> Vector2:
	return (get_viewport_rect().size - Vector2(safe_margins.x+safe_margins.z,safe_margins.y+safe_margins.w)).max(Vector2(1,1))

## canvas_items/expand hides physical display size: logical height stays >=720 even on an outer screen.
## Restore the rendered robot footprint below 1000 usable display pixels. At >=1000 the legacy fit is exact.
## Bounded compensation preserves high-flight zoom and caps close-up at the original base_zoom.
func responsive_zoom(height: float, usable: Vector2, window_size: Vector2) -> float:
	var viewport_size := get_viewport_rect().size
	var physical_height := usable.y * window_size.y / maxf(viewport_size.y,1.0)
	var correction := clampf(1000.0/maxf(physical_height,1.0),1.0,1.75)
	var legacy := clampf(usable.y*0.82/(height+420.0),min_zoom,base_zoom)
	var framing: float = float(get_meta("qa_framing", FRAMING_SCALE))   # debug QA before/after only
	return maxf(minf(legacy*correction,base_zoom) * framing, min_zoom)


func focus_practice(t: Node2D) -> void:
	snap_intro(t.global_position+practice_offset,practice_zoom(t.global_position))
	follow(t)


func practice_zoom(p: Vector2) -> float:
	var height := terrain.surface_y(p.x)-p.y if terrain else 300.0
	return clampf((usable_size().y-380.0)/maxf(height,200.0),0.6,base_zoom)
