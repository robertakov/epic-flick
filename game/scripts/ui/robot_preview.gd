class_name RobotPreview
extends Node2D
## Animated menu preview of a robot: the real module art (+ the robot's palette swap) standing on its springs,
## bobbing up and down with compressing coils, dangling spring arms and a wobbling head. Reuses the in-game
## ArmVisual / HeadVisual / SpringCoil with a synthetic frame motion, so it moves like the real rig.

var def: RobotDefinition
var rig: RigData
var torso: Sprite2D
var head: HeadVisual
var arms := {}
var legs := {}         # side -> {cap, coil, boot, hip, cap_len, boot_len}
var frame := FrameMotion.new()
var _t := 0.0
var _rest := 56.0
var _prev_y := 0.0
var _prev_vy := 0.0
var _neck := Vector2.ZERO
var art_torso: VideoRobotPart
var art_profile: VisualRigProfile
var enemy_id := ""
var phase_offset := 0.0
var player_animator := PlayerIdleAnimator.new()

## v34: presentation-only size correction of the menu / robot-select previews (applied after their fit, scaled
## around the feet). Самуробот's art reads ~12% larger than the other normal-sized robots. Gameplay never uses this.
const PRESENTATION_SCALE := {"samurai": 0.88}


static func presentation_scale(robot_id: String) -> float:
	return float(PRESENTATION_SCALE.get(robot_id, 1.0))


var mk2 := false


## mk2 = show the archetype's MK2 art (same rig). v36: the colour scheme applies to the shown version.
func show_robot(p_def: RobotDefinition, base_cfg: RobotConfig, skin: SkinDefinition = null, p_mk2 := false) -> void:
	for ch in get_children():
		ch.queue_free()
	arms.clear()
	legs.clear()
	enemy_id = ""
	if has_meta("enemy_identity"):
		remove_meta("enemy_identity")
	def = p_def
	mk2 = p_mk2 and def.has_mk2()
	var cfg: RobotConfig = base_cfg.duplicate()
	if skin == null:
		skin = SkinDefinition.from_robot_default(def)
	skin.apply_visual(cfg, def, mk2)
	cfg.robot_id = def.id
	cfg.rig_scale = 0.42
	rig = RigData.new(cfg)
	art_profile = VisualRigProfile.new(rig)
	var hip_y := rig.torso_point("hip_l").y
	for side in [&"leg_r", &"leg_l"]:
		var part := String(side)
		var coil := SpringCoil.new()
		coil.ring = rig.tex.coil_ring
		coil.ring_scale = rig.s * 1.05
		coil.ring_count = 5
		coil.rest_length = _rest
		var boot := _sprite(rig.tex[part + "_boot"], rig.piece_point(part, "boot", "top"))
		var cap := _sprite(rig.tex[part + "_cap"], rig.piece_point(part, "cap", "top"))
		var top := rig.piece_point(part, "cap", "top")
		var bot := rig.piece_point(part, "cap", "bottom")
		cap.rotation = Vector2.DOWN.angle() - (bot - top).angle()
		add_child(coil)
		add_child(boot)
		add_child(cap)
		var sole := rig.piece_point(part, "boot", "sole")
		legs[side] = {"cap": cap, "coil": coil, "boot": boot, "hip": Vector2(-27.0 if side == &"leg_l" else 27.0, hip_y),
			"cap_len": (bot - top).length(), "boot_len": sole.y - rig.piece_point(part, "boot", "top").y}
		var art := VideoRobotPart.new()
		if art.setup(rig, part):
			add_child(art)
			legs[side]["art"] = art
			cap.visible = false
			boot.visible = false
			coil.visible = false
		else:
			art.free()
	torso = Sprite2D.new()
	torso.texture = rig.tex.torso
	torso.centered = false
	torso.offset = -rig.torso_center
	torso.scale = Vector2.ONE * rig.s
	add_child(torso)
	art_torso = null
	var body_art := VideoRobotPart.new()
	if body_art.setup(rig, "torso"):
		art_torso = body_art
		torso.add_child(body_art)
		torso.texture = null
	else:
		body_art.free()
	for side in [&"arm_l", &"arm_r"]:
		var av := ArmVisual.new()
		av.setup(rig, side, rig.torso_point("shoulder_l" if side == &"arm_l" else "shoulder_r"))
		add_child(av)
		arms[side] = av
	head = HeadVisual.new()
	head.setup(rig)
	_neck = rig.torso_point("neck") + Vector2(0, 6)
	head.set_neck(_neck)
	add_child(head)
	head.set_expression(&"neutral", 0.0, 0)
	material = cfg.visual_material
	RobotVisual.inherit_material(self)
	scale = Vector2.ONE * def.size
	_t = 0.0
	player_animator.setup(cfg.visual_id)
	_layout_player(player_animator.step(0.0))
	head.step(0.0, frame)


func show_enemy(p_enemy_id: String, p_def: RobotDefinition, base_cfg: RobotConfig) -> void:
	show_robot(p_def, base_cfg, null)
	enemy_id = p_enemy_id
	set_meta("enemy_identity", p_enemy_id)
	material = null
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemies/%s/rig.json" % p_enemy_id))
	var profile := VisualRigProfile.new(rig)
	profile.data = data
	art_profile = profile
	if art_torso:
		art_torso.hide()
		art_torso.set_process(false)
		art_torso.queue_free()
	var body := EnemyArtPart.new()
	body.configure(rig, profile, "torso", p_enemy_id)
	torso.texture = null
	torso.add_child(body)
	art_torso = body
	for side in arms:
		var arm: ArmVisual = arms[side]
		if arm.video_part:
			arm.video_part.hide()
			arm.video_part.set_process(false)
			arm.video_part.queue_free()
		arm.shoulder.hide()
		arm.fist.hide()
		arm.coil.hide()
		var part := EnemyArtPart.new()
		part.configure(rig, profile, String(side), p_enemy_id)
		arm.add_child(part)
		arm.video_part = part
	for side in legs:
		var L: Dictionary = legs[side]
		if L.has("art") and is_instance_valid(L.art):
			var old_art: VideoRobotPart = L.art
			old_art.hide()
			old_art.set_process(false)
			old_art.queue_free()
		L.cap.visible = false
		L.boot.visible = false
		L.coil.visible = false
		var part := EnemyArtPart.new()
		part.configure(rig, profile, String(side), p_enemy_id)
		add_child(part)
		move_child(part, 0)
		L["art"] = part
	if head.video_part:
		head.video_part.hide()
		head.video_part.set_process(false)
		head.video_part.queue_free()
	head.sprite.hide()
	var face := EnemyArtPart.new()
	face.configure(rig, profile, "head", p_enemy_id)
	head.add_child(face)
	head.video_part = face
	head.set_expression(&"neutral", 0.0, 0)
	_layout_enemy(EnemyIdleAnimator.compute_pose(enemy_id, _t + phase_offset))


func _sprite(tex: Texture2D, anchor: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = -anchor / rig.s
	s.scale = Vector2.ONE * rig.s
	return s


## body_y < 0 = body lifted (coils long), > 0 = squashed onto the coils. Boots stay on the floor.
func _layout(body_y: float) -> void:
	torso.position = Vector2(0, body_y)
	torso.rotation = 0.0
	torso.scale = Vector2.ONE * rig.s
	var floor_y := 0.0
	for side in legs:
		var L: Dictionary = legs[side]
		floor_y = maxf(floor_y, L.hip.y + L.cap_len + _rest + L.boot_len)
	for side in legs:
		var L: Dictionary = legs[side]
		var hip: Vector2 = L.hip + Vector2(0, body_y)
		var c0: Vector2 = hip + Vector2(0, L.cap_len)
		var c1 := Vector2(hip.x, floor_y - L.boot_len)
		L.cap.position = hip
		L.coil.set_line(c0, c1)
		L.boot.position = c1
		if L.has("art"):
			var art: VideoRobotPart = L.art
			var socket := art_profile.anchor("hip_l" if side == &"leg_l" else "hip_r", art_torso, torso)
			var unit := art_profile.limb_scale(String(side))
			var source := RigData._v(art.geometry.end) - RigData._v(art.geometry.pivot)
			art.fit_limb(socket, Vector2(socket.x + source.x * unit, floor_y), unit)
	torso.position = Vector2(0, body_y)
	for side in arms:
		arms[side].set_socket(rig.torso_point("shoulder_l" if side == &"arm_l" else "shoulder_r") + Vector2(0, body_y))
	head.set_neck(_neck + Vector2(0, body_y))
	if art_profile.enabled():
		for side in arms:
			var a: ArmVisual = arms[side]
			a.visual_socket_delta = art_profile.anchor("shoulder_l" if side == &"arm_l" else "shoulder_r", art_torso, torso) - a.socket
		head.set_visual_neck(art_profile.anchor("neck", art_torso, torso))


func floor_offset() -> float:
	var floor_y := 0.0
	for side in legs:
		var L: Dictionary = legs[side]
		floor_y = maxf(floor_y, L.hip.y + L.cap_len + _rest + L.boot_len)
	return floor_y if floor_y > 0.0 else 155.0


func _layout_player(pose: Dictionary) -> void:
	var body_pos: Vector2 = pose.body_pos
	torso.position = body_pos
	torso.rotation = float(pose.body_rot)
	torso.scale = Vector2.ONE * rig.s * (pose.body_scale as Vector2)
	if art_torso: art_torso.sync_png_scale()
	if head and head.video_part: head.video_part.sync_png_scale()
	var floor_y := 0.0
	for side in legs:
		var L: Dictionary = legs[side]
		floor_y = maxf(floor_y, L.hip.y + L.cap_len + _rest + L.boot_len)
	var rest_hip_l := Vector2.ZERO
	var rest_hip_r := Vector2.ZERO
	if art_profile.enabled():
		var saved_pos := torso.position
		var saved_rot := torso.rotation
		torso.position = Vector2.ZERO
		torso.rotation = 0.0
		rest_hip_l = art_profile.anchor("hip_l", art_torso, torso)
		rest_hip_r = art_profile.anchor("hip_r", art_torso, torso)
		torso.position = saved_pos
		torso.rotation = saved_rot
	for side in legs:
		var L: Dictionary = legs[side]
		var foot_off: Vector2 = pose.foot_l_offset if side == &"leg_l" else pose.foot_r_offset
		var foot_rot: float = float(pose.foot_l_rot if side == &"leg_l" else pose.foot_r_rot)
		var hip: Vector2 = body_pos + L.hip.rotated(torso.rotation)
		var c0: Vector2 = hip + Vector2(0, L.cap_len).rotated(torso.rotation * 0.5)
		var c1 := Vector2(L.hip.x, floor_y - L.boot_len) + foot_off
		L.cap.position = hip
		L.coil.set_line(c0, c1)
		L.boot.position = c1
		L.boot.rotation = foot_rot
		if L.has("art"):
			var art: VideoRobotPart = L.art
			var socket := art_profile.anchor("hip_l" if side == &"leg_l" else "hip_r", art_torso, torso)
			var rest_socket := rest_hip_l if side == &"leg_l" else rest_hip_r
			var unit := art_profile.limb_scale(String(side))
			var source := RigData._v(art.geometry.end) - RigData._v(art.geometry.pivot)
			var finish := Vector2(rest_socket.x + source.x * unit, floor_y) + foot_off
			art.fit_limb(socket, finish, unit, foot_rot)
	for side in arms:
		var a: ArmVisual = arms[side]
		var sh_pt := rig.torso_point("shoulder_l" if side == &"arm_l" else "shoulder_r").rotated(torso.rotation)
		a.set_socket(sh_pt + body_pos)
		if art_profile.enabled():
			a.visual_socket_delta = art_profile.anchor("shoulder_l" if side == &"arm_l" else "shoulder_r", art_torso, torso) - a.socket
		else:
			a.visual_socket_delta = Vector2.ZERO
		var gain := maxf(float(a.video_part.geometry.get("inertia_gain", 0.28)), 0.05) if a.video_part else 0.72
		var hand_off: Vector2 = pose.arm_l_offset if side == &"arm_l" else pose.arm_r_offset
		a.p = a.exit + a.rest + hand_off / gain
		a._apply()
	head.set_neck(_neck.rotated(torso.rotation) + body_pos + (pose.head_bob as Vector2))
	head.angle = float(pose.head_angle)
	head.offset_pos = Vector2.ZERO
	head.position = head.neck
	head.rotation = head.angle
	if art_profile.enabled():
		var neck_anchor := art_profile.anchor("neck", art_torso, torso) + (pose.head_bob as Vector2)
		head.set_visual_neck(neck_anchor)
		if head.video_part:
			head.video_part.position = head.transform.affine_inverse() * head.visual_neck
	head.want_expression(pose.expression)
	rotation = float(pose.rig_rot)


func _layout_enemy(pose: Dictionary) -> void:
	var body_pos: Vector2 = pose.body_pos
	torso.position = body_pos
	torso.rotation = float(pose.body_rot)
	torso.scale = Vector2.ONE * rig.s * (pose.body_scale as Vector2)
	if art_torso is EnemyArtPart:
		(art_torso as EnemyArtPart).sync_scale()
	var floor_y := 0.0
	for side in legs:
		var L: Dictionary = legs[side]
		floor_y = maxf(floor_y, L.hip.y + L.cap_len + _rest + L.boot_len)
	var saved_pos := torso.position
	var saved_rot := torso.rotation
	torso.position = Vector2.ZERO
	torso.rotation = 0.0
	var rest_hip_l := art_profile.anchor("hip_l", art_torso, torso)
	var rest_hip_r := art_profile.anchor("hip_r", art_torso, torso)
	torso.position = saved_pos
	torso.rotation = saved_rot
	for side in legs:
		var L: Dictionary = legs[side]
		if L.has("art"):
			var art: VideoRobotPart = L.art
			var socket := art_profile.anchor("hip_l" if side == &"leg_l" else "hip_r", art_torso, torso)
			var rest_socket := rest_hip_l if side == &"leg_l" else rest_hip_r
			var unit := art_profile.limb_scale(String(side))
			var source := RigData._v(art.geometry.end) - RigData._v(art.geometry.pivot)
			var foot_off: Vector2 = pose.foot_l_offset if side == &"leg_l" else pose.foot_r_offset
			var foot_rot: float = float(pose.foot_l_rot if side == &"leg_l" else pose.foot_r_rot)
			var finish := Vector2(rest_socket.x + source.x * unit, floor_y) + foot_off
			art.fit_limb(socket, finish, unit, foot_rot)
	for side in arms:
		var a: ArmVisual = arms[side]
		a.set_socket(rig.torso_point("shoulder_l" if side == &"arm_l" else "shoulder_r") + body_pos)
		a.visual_socket_delta = art_profile.anchor("shoulder_l" if side == &"arm_l" else "shoulder_r", art_torso, torso) - a.socket
		var gain := maxf(float(a.video_part.geometry.get("inertia_gain", 0.28)), 0.05) if a.video_part else 0.28
		var hand_off: Vector2 = pose.arm_l_offset if side == &"arm_l" else pose.arm_r_offset
		a.p = a.exit + a.rest + hand_off / gain
		a._apply()
	head.set_neck(_neck + body_pos)
	head.angle = float(pose.head_angle)
	head.offset_pos = Vector2.ZERO
	head.position = head.neck
	head.rotation = head.angle
	if head.video_part is EnemyArtPart:
		(head.video_part as EnemyArtPart).sync_scale()
	var neck_anchor := art_profile.anchor("neck", art_torso, torso) + (pose.head_bob as Vector2)
	head.set_visual_neck(neck_anchor)
	if head.video_part:
		head.video_part.position = head.transform.affine_inverse() * head.visual_neck
	head.want_expression(pose.expression)
	rotation = float(pose.rig_rot)


func _process(dt: float) -> void:
	if rig == null:
		return
	dt = minf(dt, 0.05)
	_t += dt
	if enemy_id != "":
		_layout_enemy(EnemyIdleAnimator.compute_pose(enemy_id, _t + phase_offset))
		return
	_layout_player(player_animator.step(dt))


## The new silhouettes have different extents. Reserve the skin row and fit all visual children.
func art_bounds() -> Rect2:
	var result := Rect2()
	var initialized := false
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.is_queued_for_deletion():
			continue
		pending.append_array(node.get_children())
		var rect := Rect2()
		var transform := Transform2D.IDENTITY
		if node is VideoRobotPart:
			var part := node as VideoRobotPart
			rect = part.visual_bounds()
			transform = global_transform.affine_inverse() * part.global_transform
		elif node is Sprite2D and node.name == "SourceTail" and (node as Sprite2D).texture:
			# v28: Kengurobot's tail is a plain sprite on the torso and must count for fitting / cropping
			var tail := node as Sprite2D
			rect = tail.get_rect()
			transform = global_transform.affine_inverse() * tail.global_transform
		if rect.size != Vector2.ZERO:
			for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
				var point: Vector2 = transform * corner
				if not initialized:
					result = Rect2(point, Vector2.ZERO)
					initialized = true
				else:
					result = result.expand(point)
	if not initialized:
		return Rect2(Vector2(-120.0, -165.0), Vector2(240.0, 330.0))
	return result.grow(18.0)

