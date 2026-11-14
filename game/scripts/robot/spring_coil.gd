class_name SpringCoil
extends Node2D
## Draws a coil spring as a stack of ring sprites along a (optionally curved) axis.
## Ring spacing follows the real length, so compression/extension reads as an actual spring
## instead of a squashed bitmap. Purely visual: whoever owns the coil feeds it its endpoints.

var ring: Texture2D
var ring_count := 5
var ring_scale := 0.42
var rest_length := 50.0
var helix_tilt := 0.14

var _p0 := Vector2.ZERO
var _p1 := Vector2(0, 50)
var _c := Vector2(0, 25)


func set_line(a: Vector2, b: Vector2) -> void:
	_p0 = a
	_p1 = b
	_c = (a + b) * 0.5
	queue_redraw()


func set_curve(a: Vector2, ctrl: Vector2, b: Vector2) -> void:
	_p0 = a
	_c = ctrl
	_p1 = b
	queue_redraw()


func _bez(t: float) -> Vector2:
	var u := 1.0 - t
	return _p0 * u * u + _c * 2.0 * u * t + _p1 * t * t


func _bez_tan(t: float) -> Vector2:
	return (_c - _p0) * 2.0 * (1.0 - t) + (_p1 - _c) * 2.0 * t


func _draw() -> void:
	if ring == null:
		return
	var length := _p0.distance_to(_c) + _c.distance_to(_p1)
	var stretch := length / maxf(rest_length, 1.0)
	# stretched coils get thinner, compressed ones bulge a little (squash & stretch on the spring itself)
	var wscale := clampf(1.18 - 0.22 * stretch, 0.78, 1.22)
	# dark core so a stretched coil never shows gaps
	var pts := PackedVector2Array()
	for i in 9:
		pts.append(_bez(i / 8.0))
	draw_polyline(pts, Color(0.07, 0.06, 0.06), 7.0 * ring_scale / 0.42, true)
	var half := ring.get_size() * 0.5
	for i in ring_count:
		var t := (i + 0.5) / ring_count
		var tan := _bez_tan(t)
		if tan.length_squared() < 0.0001:
			tan = Vector2.DOWN
		var ang := tan.angle() - PI * 0.5 + (helix_tilt if i % 2 == 0 else -helix_tilt * 0.4)
		draw_set_transform(_bez(t), ang, Vector2(ring_scale * wscale, ring_scale))
		draw_texture(ring, -half)
	draw_set_transform_matrix(Transform2D.IDENTITY)
