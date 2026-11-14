class_name HeadVisual
extends Node2D
## Head on a wobbly neck: angular + positional lag springs (follow-through) and swappable faces.
## Expressions have priorities and hold times so reactions are readable, not flickering.

@export var wobble_hz := 3.0
@export var wobble_damping := 0.18
@export var bob_hz := 4.5
@export var bob_damping := 0.22

var sprite: Sprite2D
var faces := {}
var expression := &"neutral"
var _expr_until := 0.0
var _expr_priority := 0
var angle := 0.0
var angle_vel := 0.0
var offset_pos := Vector2.ZERO
var offset_vel := Vector2.ZERO
var neck := Vector2.ZERO
var center_local := Vector2.ZERO   # head centre relative to the neck pivot
var _time := 0.0
var video_part: VideoRobotPart
var visual_neck := Vector2.ZERO
var visual_anchor_enabled := false

func set_visual_neck(p: Vector2) -> void:
	visual_neck = p
	visual_anchor_enabled = true

func release_visual_anchor() -> void:
	visual_anchor_enabled = false
	scale = Vector2.ONE
	if video_part:
		video_part.position = Vector2.ZERO


func setup(rig: RigData) -> void:
	name = "Head"
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.scale = Vector2.ONE * rig.s
	for e in rig.expressions:
		faces[StringName(e)] = rig.tex["head_" + e]
	sprite.texture = faces[&"neutral"]
	var nk := rig.head_point("neck")
	sprite.offset = -nk / rig.s
	center_local = rig.head_point("center") - nk
	add_child(sprite)
	var art := VideoRobotPart.new()
	if art.setup(rig, "head"):
		video_part = art
		add_child(art)
		sprite.visible = false
	else:
		art.free()


func set_neck(p: Vector2) -> void:
	neck = p


func set_expression(e: StringName, hold := 0.6, priority := 1) -> void:
	if not faces.has(e):
		return
	if _time < _expr_until and priority < _expr_priority:
		return
	expression = e
	_expr_until = _time + hold
	_expr_priority = priority
	sprite.texture = faces[e]
	if video_part:
		video_part.select(String(e))


## Expression the idle logic would like; only applied when no reaction is being held.
func want_expression(e: StringName) -> void:
	if _time >= _expr_until and expression != e:
		expression = e
		_expr_priority = 0
		sprite.texture = faces[e]
		if video_part:
			video_part.select(String(e))


func step(dt: float, frame: FrameMotion) -> void:
	_time += dt
	var c := neck + center_local
	var pa := frame.pseudo(c, Vector2.ZERO)
	# torque on the head about the neck from the felt acceleration
	var torque := (center_local.x * pa.y - center_local.y * pa.x) / maxf(center_local.length_squared(), 1.0)
	var w0 := TAU * wobble_hz
	angle_vel += (-w0 * w0 * angle - 2.0 * wobble_damping * w0 * angle_vel + torque * 0.5) * dt
	angle = clampf(angle + angle_vel * dt, -0.7, 0.7)
	var b0 := TAU * bob_hz
	offset_vel += (-offset_pos * b0 * b0 - offset_vel * 2.0 * bob_damping * b0 + pa * 0.012) * dt
	offset_pos += offset_vel * dt
	offset_pos = offset_pos.limit_length(14.0)
	position = neck + offset_pos
	rotation = angle
	if video_part and visual_anchor_enabled:
		# Compensate the old visual bob on the child only: physical rocket transform is unchanged.
		video_part.position = transform.affine_inverse() * visual_neck


func kick(spin: float, push: Vector2) -> void:
	angle_vel += spin
	offset_vel += push
