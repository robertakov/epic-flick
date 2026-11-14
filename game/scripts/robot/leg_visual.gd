class_name LegVisual
extends Node2D
## Spring leg: cap at the hip, coil, boot. While attached its coil length comes straight from the
## physical SpringLeg (contact compression / free oscillation). Detached it runs the same free
## oscillator itself, so the spring keeps wobbling while the part tumbles.

@export var swing_hz := 3.2
@export var swing_damping := 0.2
@export var max_swing := 0.55

var side: StringName
var leg: SpringLeg               # physics state (null when detached)
var cfg: ContactConfig
var cap: Sprite2D
var boot: Sprite2D
var coil: SpringCoil
var hip := Vector2.ZERO
var cap_len := 13.0
var boot_len := 54.0
var length := 56.0
var length_vel := 0.0
var swing := 0.0                 # rubber-hose lag angle of the whole leg
var swing_vel := 0.0
var boot_tilt := 0.0
var _cap_fix := 0.0
var _boot_fix := 0.0
var video_part: VideoRobotPart
var visual_hip_delta := Vector2.ZERO
var exhaust: LegExhaust
var nozzle: ChronoNozzle


func setup(rig: RigData, p_side: StringName, p_leg: SpringLeg, p_cfg: ContactConfig) -> void:
	side = p_side
	name = String(side)
	leg = p_leg
	cfg = p_cfg
	var part := String(side)
	var ts := rig.s
	coil = SpringCoil.new()
	coil.ring = rig.tex.coil_ring
	coil.ring_scale = rig.s * 1.05
	coil.ring_count = 5
	coil.rest_length = cfg.coil_rest_length
	boot = Sprite2D.new()
	boot.texture = rig.tex[part + "_boot"]
	boot.centered = false
	boot.scale = Vector2.ONE * ts
	cap = Sprite2D.new()
	cap.texture = rig.tex[part + "_cap"]
	cap.centered = false
	cap.scale = Vector2.ONE * ts
	add_child(coil)
	add_child(boot)
	add_child(cap)
	var top := rig.piece_point(part, "cap", "top")
	var bot := rig.piece_point(part, "cap", "bottom")
	cap.offset = -top / ts
	cap_len = (bot - top).length()
	_cap_fix = Vector2.DOWN.angle() - (bot - top).angle()
	var btop := rig.piece_point(part, "boot", "top")
	var sole := rig.piece_point(part, "boot", "sole")
	boot.offset = -btop / ts
	boot_len = sole.y - btop.y
	_boot_fix = 0.0
	length = cfg.coil_rest_length
	if leg:
		leg.cap_len = cap_len
		leg.boot_len = boot_len
	var art := VideoRobotPart.new()
	if art.setup(rig, part):
		video_part = art
		add_child(art)
		cap.visible = false
		boot.visible = false
		coil.visible = false
		if RobotIdentityProfile.for_robot(rig.robot_id).leg_exhaust:
			# v32: the heel nozzle (enlarged pod) and its flame; the flame only flashes (RobotIdentityFeedback)
			if ChronoNozzle.ANCHORS.has(side):
				nozzle = ChronoNozzle.new(side, rig.art.get("nozzle_anchors", {}))
				add_child(nozzle)
			exhaust = LegExhaust.new()
			exhaust.z_index = -1
			add_child(exhaust)
	else:
		art.free()


func set_hip(h: Vector2) -> void:
	hip = h


## local_normal: ground normal in frame-local axes (only meaningful while grounded).
func step(dt: float, frame: FrameMotion) -> void:
	var grounded := leg != null and leg.attached and leg.in_contact
	if leg != null and leg.attached:
		length = leg.length
		length_vel = leg.length_vel
	else:
		_free_length(dt, frame)
	# swing: legs trail behind the spin and whip on impacts (overlapping action)
	var dir := Vector2.DOWN.rotated(swing)
	var foot := hip + dir * (cap_len + length + boot_len * 0.5)
	var pa := frame.pseudo(foot, Vector2.ZERO)
	var lateral := pa.dot(Vector2(-dir.y, dir.x)) / maxf(cap_len + length + boot_len * 0.5, 1.0)
	var w0 := TAU * swing_hz
	if grounded:
		swing = lerpf(swing, 0.0, 1.0 - exp(-30.0 * dt))
		swing_vel = 0.0
		var nl := leg.ground_normal.rotated(-get_parent_body_rotation())
		boot_tilt = lerpf(boot_tilt, clampf(Vector2.UP.angle_to(nl), -0.6, 0.6), 1.0 - exp(-25.0 * dt))
	else:
		swing_vel += (-w0 * w0 * swing - 2.0 * swing_damping * w0 * swing_vel + lateral * 0.35) * dt
		swing = clampf(swing + swing_vel * dt, -max_swing, max_swing)
		boot_tilt = lerpf(boot_tilt, swing * 0.4, 1.0 - exp(-8.0 * dt))
	_apply()


var body_rotation_provider: Callable


func get_parent_body_rotation() -> float:
	return body_rotation_provider.call() if body_rotation_provider.is_valid() else 0.0


func _free_length(dt: float, frame: FrameMotion) -> void:
	var w := TAU * cfg.free_leg_frequency
	var dir := Vector2.DOWN.rotated(swing)
	var axial := -frame.pseudo(hip + dir * (cap_len + length), Vector2.ZERO).dot(dir)
	var a := -w * w * (length - cfg.coil_rest_length) - 2.0 * cfg.free_leg_damping * w * length_vel - axial
	length_vel += a * dt
	length = clampf(length + length_vel * dt, cfg.coil_min_length, cfg.coil_max_length)


func kick(dl: float) -> void:
	length_vel += dl


func _apply() -> void:
	var dir := Vector2.DOWN.rotated(swing)
	cap.position = hip
	cap.rotation = swing + _cap_fix
	var c0 := hip + dir * cap_len
	var c1 := c0 + dir * length
	coil.set_line(c0, c1)
	boot.position = c1
	boot.rotation = swing * 0.5 + boot_tilt
	if video_part:
		var start := hip + visual_hip_delta
		var unit := video_part.art_rig.limb_scale(String(side))
		var source := RigData._v(video_part.geometry.end) - RigData._v(video_part.geometry.pivot)
		var offset := Vector2(source.x * unit, cap_len + length).rotated(swing) + Vector2.DOWN.rotated(boot.rotation) * boot_len
		var finish := start+offset
		if video_part.art_rig.data.get("png_modular",false):
			# Cosmetic endpoint follows the existing physical sole; never writes SpringLeg dimensions.
			finish.y=hip.y+offset.y
		video_part.fit_limb(start, finish, unit, boot.rotation)
	if nozzle and video_part:
		nozzle.sync(video_part)
	if exhaust:
		exhaust.position = nozzle.mouth() if nozzle and video_part else c1 + Vector2.DOWN.rotated(boot.rotation) * boot_len
		exhaust.rotation = boot.rotation
		if leg == null or not leg.attached:
			exhaust.disable()
