class_name ArmVisual
extends Node2D
## Rubber-hose spring arm: shoulder sprite fixed in the socket, fist = point mass on a damped spring,
## coil drawn along a curve between them. Works attached to the robot or on a detached part.

@export var stiffness_hz := 5.0
@export var damping := 0.16
@export var min_stretch := 0.45
@export var max_stretch := 1.65

var side: StringName
var shoulder: Sprite2D
var fist: Sprite2D
var coil: SpringCoil
var socket := Vector2.ZERO     # where the shoulder disc sits (frame-local)
var exit := Vector2.ZERO       # coil start (frame-local)
var rest := Vector2.ZERO       # exit -> cuff at rest
var exit_dir := Vector2.RIGHT  # shoulder tube direction
var p := Vector2.ZERO          # cuff position
var v := Vector2.ZERO
var _fist_rest_angle := 0.0
var video_part: VideoRobotPart
var visual_socket_delta := Vector2.ZERO


func setup(rig: RigData, p_side: StringName, p_socket: Vector2) -> void:
	side = p_side
	name = String(side)
	socket = p_socket
	var part := String(side)
	coil = SpringCoil.new()
	coil.ring = rig.tex.coil_ring
	coil.ring_scale = rig.s
	coil.ring_count = 7
	add_child(coil)
	shoulder = Sprite2D.new()
	shoulder.texture = rig.tex[part + "_shoulder"]
	shoulder.centered = false
	add_child(shoulder)
	fist = Sprite2D.new()
	fist.texture = rig.tex[part + "_fist"]
	fist.centered = false
	add_child(fist)
	# anchors in rig.json are in exported-texture px; RigData multiplies them by s -> sprite scale = s
	var tex_scale := rig.s
	shoulder.scale = Vector2.ONE * tex_scale
	fist.scale = Vector2.ONE * tex_scale
	var disc := rig.piece_point(part, "shoulder", "disc")
	var ex := rig.piece_point(part, "shoulder", "exit")
	shoulder.offset = -disc / tex_scale
	shoulder.position = socket
	exit = socket + (ex - disc)
	exit_dir = (ex - disc).normalized()
	rest = rig.coil_rest_vec(part)
	var cuff := rig.piece_point(part, "fist", "cuff")
	fist.offset = -cuff / tex_scale
	coil.rest_length = rest.length()
	p = exit + rest
	_fist_rest_angle = rest.angle()
	var art := VideoRobotPart.new()
	if art.setup(rig, part):
		video_part = art
		add_child(art)
		shoulder.visible = false
		fist.visible = false
		coil.visible = false
	else:
		art.free()
	_apply()


## Move the socket (squash & stretch of the torso moves the shoulders).
func set_socket(s: Vector2) -> void:
	var d := s - socket
	socket = s
	exit += d
	shoulder.position = socket


func step(dt: float, frame: FrameMotion) -> void:
	var target := exit + rest
	var w0 := TAU * stiffness_hz
	var a := (target - p) * w0 * w0 - v * 2.0 * damping * w0 + frame.pseudo(p, v)
	v += a * dt
	p += v * dt
	# keep the coil inside its elastic limits
	var d := p - exit
	var L := d.length()
	var rl := rest.length()
	if L > rl * max_stretch:
		p = exit + d / L * rl * max_stretch
		v -= d / L * maxf(v.dot(d / L), 0.0)
	elif L < rl * min_stretch and L > 0.001:
		p = exit + d / L * rl * min_stretch
		v -= d / L * minf(v.dot(d / L), 0.0)
	_apply()


func kick(impulse: Vector2) -> void:
	v += impulse


func _apply() -> void:
	var d := p - exit
	fist.position = p
	fist.rotation = wrapf(d.angle() - _fist_rest_angle, -PI, PI) * 0.85
	var ctrl := exit + exit_dir * d.length() * 0.45
	coil.set_curve(exit, ctrl, p)
	if video_part:
		var start := socket + visual_socket_delta
		var unit := video_part.art_rig.limb_scale(String(side))
		var source := RigData._v(video_part.geometry.end) - RigData._v(video_part.geometry.pivot)
		var lag := (p - exit - rest) * float(video_part.geometry.inertia_gain)
		video_part.fit_limb(start, start + source * unit + lag, unit, fist.rotation * 0.35)

