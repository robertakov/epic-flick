class_name LaunchHand
extends Node2D
## The giant gloved hand. Plays the cleaned video frames on a timeline with procedural anticipation
## (pull-back + tremble), the flick, follow-through and retreat. `flicked` fires on the exact frame the
## finger is fully extended - the robot is launched from that signal, never earlier.

signal flicked(tip_global: Vector2)
signal finished

const FLICK_FRAME := 19          # first fully extended finger frame
const TENSION_FRAME := 17        # last frame before the flick (the pause is here)
const WORLD_SCALE := 2.3

## [frame_index, seconds]
const TIMELINE := [[0, 0.16], [1, 0.08], [2, 0.08], [3, 0.08], [4, 0.06], [5, 0.06], [6, 0.06], [7, 0.05],
	[8, 0.05], [9, 0.05], [10, 0.05], [11, 0.06], [12, 0.08], [13, 0.1], [14, 0.1], [15, 0.1], [16, 0.12],
	[17, 0.5], [18, 0.035], [19, 0.08], [20, 0.07], [21, 0.07], [22, 0.08], [23, 0.12], [24, 0.08], [25, 0.06],
	[26, 0.06], [27, 0.06], [28, 0.06], [29, 0.25]]

var frames: Array[Texture2D] = []
var sprite: Sprite2D
var sleeve: Polygon2D
var speed := 1.0
var playing := false
var _step := 0
var _t := 0.0
var _flick_done := false
var _base_pos := Vector2.ZERO
var _time := 0.0
var _retreat := 0.0
var _rush := false
var hold_at_tension := false
var meta: Dictionary


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hand/hand.json"))
	for i in meta.frames.size():
		frames.append(load("res://assets/hand/hand_%02d.png" % i))
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = frames[0]
	sprite.scale = Vector2.ONE * WORLD_SCALE
	var sy: Array = meta.sleeve_y
	sleeve = Polygon2D.new()
	sleeve.color = Color(0.02, 0.02, 0.02)
	sleeve.polygon = PackedVector2Array([Vector2(-6000, sy[0]), Vector2(4, sy[0]), Vector2(4, sy[1]), Vector2(-6000, sy[1])])
	sprite.add_child(sleeve)
	add_child(sprite)
	z_index = 5


## Fingertip of the extended frame, in this node's local space.
func tip_local() -> Vector2:
	return Vector2(924, 174) * WORLD_SCALE


## Places the hand so the extended fingertip lands on `contact_global`.
func aim_at(contact_global: Vector2) -> void:
	_base_pos = contact_global - tip_local()
	global_position = _base_pos


func play(p_speed := 1.0) -> void:
	speed = p_speed
	playing = true
	_step = 0
	_t = 0.0
	_time = 0.0
	_flick_done = false
	_retreat = 0.0
	_rush = false
	modulate.a = 1.0
	visible = true
	_show(0)


## Player tapped during the wind-up: hurry to the flick (retry-friendly).
func rush() -> void:
	hold_at_tension = false
	if playing and not _flick_done:
		_rush = true


## Player locked the flick power bar: release tension and execute the flick immediately.
func release_flick() -> void:
	hold_at_tension = false
	if not playing:
		play(1.6)
	if not _flick_done:
		_rush = true
		if _step < 17:
			_step = 17
			_show(_step)
			_t = TIMELINE[17][1] * 0.85


func _show(i: int) -> void:
	sprite.texture = frames[TIMELINE[i][0]]


func _process(dt: float) -> void:
	if not playing:
		return
	var sp := speed * (4.0 if _rush and not _flick_done else 1.0)
	_t += dt * sp
	_time += dt
	if hold_at_tension and not _rush and _step < TIMELINE.size() and TIMELINE[_step][0] == TENSION_FRAME:
		_t = minf(_t, TIMELINE[_step][1] * 0.85)
	while _step < TIMELINE.size() and _t >= TIMELINE[_step][1]:
		if hold_at_tension and not _rush and TIMELINE[_step][0] == TENSION_FRAME:
			_t = TIMELINE[_step][1] * 0.85
			break
		_t -= TIMELINE[_step][1]
		_step += 1
		if _step >= TIMELINE.size():
			break
		_show(_step)
		if TIMELINE[_step][0] == FLICK_FRAME and not _flick_done:
			_flick_done = true
			# snap: the drawn fingertip and the physical launch coincide on this frame
			global_position = _base_pos + Vector2(50.0, -4.0)
			flicked.emit(_base_pos + tip_local())
	# procedural layer: anticipation pull-back and tremble, then follow-through lunge and retreat
	var f: int = TIMELINE[mini(_step, TIMELINE.size() - 1)][0]
	var off := Vector2.ZERO
	var sq := Vector2.ONE
	if f >= 12 and f <= TENSION_FRAME:
		var k := clampf((f - 12) / 5.0 + _t * 0.5, 0.0, 1.0)
		off = Vector2(-60.0 * k, 10.0 * k)
		if f == TENSION_FRAME:
			off += Vector2(sin(_time * 70.0), cos(_time * 53.0)) * 5.0
			sq = Vector2(0.97, 1.03)
	elif f >= 18 and f <= 22:
		off = Vector2(50.0, -4.0)
		sq = Vector2(1.06, 0.95)
	if _step >= TIMELINE.size():
		_retreat += dt
		off += Vector2(-900.0, -250.0) * clampf(_retreat / 0.9, 0.0, 1.0) ** 2
		modulate.a = clampf(1.0 - (_retreat - 0.5) / 0.5, 0.0, 1.0)
		if _retreat > 1.0:
			playing = false
			visible = false
			finished.emit()
	global_position = global_position.lerp(_base_pos + off, 1.0 - exp(-30.0 * dt))
	sprite.scale = Vector2.ONE * WORLD_SCALE * sq
