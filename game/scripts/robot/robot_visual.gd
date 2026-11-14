class_name RobotVisual
extends Node2D
## Builds the samurai from its six modules and animates it procedurally on top of physics:
## squash & stretch of torso, wobbling head, dangling spring arms, spring legs driven by the
## physical leg state, expressions reacting to landings. Never feeds anything back into physics.

@export var squash_hz := 5.0
@export var squash_damping := 0.28

var rig: RigData
var robot: RigidBody2D
var contacts: SpringContactController
var frame := FrameMotion.new()
var torso: Sprite2D
var art_torso: VideoRobotPart
var art_profile: VisualRigProfile
var identity: RobotIdentityFeedback
var head: HeadVisual
var arms := {}
var legs := {}
var squash := 0.0
var squash_vel := 0.0
var launched := false
var _pivot := Vector2.ZERO
var _neck := Vector2.ZERO
var _sockets := {}
var _hips := {}
var _scare_cooldown := 0.0
var _ray := PhysicsRayQueryParameters2D.new()
## Spin charge 0..1 (set by RobotController). Drives the ChargeAura; full charge adds a golden sparkle trail.
var charge_ratio := 0.0:
	set(v):
		charge_ratio = v
		if aura:
			aura.set_ratio(v if launched else 0.0)
var aura: ChargeAura
var _sparkles: CPUParticles2D


func build(p_robot: RigidBody2D, p_rig: RigData, p_contacts: SpringContactController, hips: Dictionary) -> void:
	robot = p_robot
	rig = p_rig
	art_profile = VisualRigProfile.new(rig)
	contacts = p_contacts
	name = "Visual"
	_neck = rig.torso_point("neck") + Vector2(0, 6)
	_sockets = {&"arm_l": rig.torso_point("shoulder_l"), &"arm_r": rig.torso_point("shoulder_r")}
	_hips = hips
	_pivot = Vector2(0, hips[&"leg_l"].y)
	# draw order: legs behind the torso, arms and head in front
	for side in [&"leg_r", &"leg_l"]:
		var lv := LegVisual.new()
		lv.setup(rig, side, contacts.get_leg(side), contacts.cfg)
		lv.body_rotation_provider = func() -> float: return robot.global_rotation
		add_child(lv)
		legs[side] = lv
	torso = Sprite2D.new()
	torso.name = "Torso"
	torso.texture = rig.tex.torso
	torso.centered = false
	torso.offset = -rig.torso_center / 1.0
	torso.scale = Vector2.ONE * rig.s
	add_child(torso)
	var art := VideoRobotPart.new()
	if art.setup(rig, "torso"):
		art_torso = art
		torso.add_child(art)
		torso.texture = null
	else:
		art.free()
	for side in [&"arm_l", &"arm_r"]:
		var av := ArmVisual.new()
		av.setup(rig, side, _sockets[side])
		add_child(av)
		arms[side] = av
	head = HeadVisual.new()
	head.setup(rig)
	add_child(head)
	_ray.collision_mask = 1
	_sparkles = CPUParticles2D.new()
	_sparkles.name = "ChargeSparkles"
	_sparkles.local_coords = false
	_sparkles.amount = 22
	_sparkles.lifetime = 0.45
	_sparkles.texture = Fx.spark_texture()
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparkles.emission_sphere_radius = 70.0
	_sparkles.direction = Vector2.UP
	_sparkles.spread = 180.0
	_sparkles.gravity = Vector2.ZERO
	_sparkles.initial_velocity_min = 20.0
	_sparkles.initial_velocity_max = 70.0
	_sparkles.scale_amount_min = 0.35
	_sparkles.scale_amount_max = 0.75
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
	sg.set_color(1, Color(1.0, 0.6, 0.1, 0.0))
	_sparkles.color_ramp = sg
	_sparkles.emitting = false
	add_child(_sparkles)
	_apply_squash()
	# per-robot palette swap: one material on the rig root, inherited by every module sprite and coil
	var mat: Material = (robot as RobotController).config.visual_material if robot is RobotController else null
	if mat:
		material = mat
		inherit_material(self)
	aura = ChargeAura.new()
	aura.setup(robot, rig.s / 0.42)
	aura.set_ratio(0.0)
	add_child(aura)
	identity = RobotIdentityFeedback.new()
	identity.setup(self)
	add_child(identity)


## Every descendant draws with its parent's material (also after it moves to a detached part / rocket head).
static func inherit_material(n: Node) -> void:
	for ch in n.get_children():
		if ch is LegExhaust or ch is RobotIdentityFeedback:
			continue
		if ch is CanvasItem and not (ch is CPUParticles2D):
			(ch as CanvasItem).use_parent_material = true
		inherit_material(ch)


func _sq(p: Vector2) -> Vector2:
	var s := Vector2(1.0 + 0.55 * squash, 1.0 - squash)
	return _pivot + (p - _pivot) * s


var _enemy_idle_t := 0.0

func _apply_squash() -> void:
	var s := Vector2(1.0 + 0.55 * squash, 1.0 - squash)
	torso.position = _sq(Vector2.ZERO)
	torso.rotation = 0.0
	torso.scale = Vector2.ONE * rig.s * s
	if head:
		head.set_neck(_sq(_neck))
		head.scale = Vector2(1.0 + 0.25 * squash, 1.0 - 0.35 * squash)
	for side in arms:
		arms[side].set_socket(_sq(_sockets[side]))
	for side in legs:
		legs[side].set_hip(_sq(_hips[side]))
	_sync_art_joints()


func _sync_art_joints() -> void:
	if not art_profile.enabled():
		return
	if art_torso: art_torso.sync_png_scale()
	if head and head.video_part: head.video_part.sync_png_scale()
	if art_torso is EnemyArtPart:
		(art_torso as EnemyArtPart).sync_scale()
	if head and head.video_part is EnemyArtPart:
		(head.video_part as EnemyArtPart).sync_scale()
	for side in arms:
		var a: ArmVisual = arms[side]
		a.visual_socket_delta = art_profile.anchor("shoulder_l" if side == &"arm_l" else "shoulder_r", art_torso, torso) - a.socket
		a._apply()
	for side in legs:
		var l: LegVisual = legs[side]
		l.visual_hip_delta = art_profile.anchor("hip_l" if side == &"leg_l" else "hip_r", art_torso, torso) - l.hip
		l._apply()
	if head:
		head.set_visual_neck(art_profile.anchor("neck", art_torso, torso))
		if head.video_part:
			head.video_part.position = head.transform.affine_inverse() * head.visual_neck

func _process(_dt: float) -> void:
	# Body response is presentation at render cadence; sockets follow that same displayed transform.
	_sync_art_joints()

func _physics_process(dt: float) -> void:
	if robot == null:
		return
	frame.update_from(robot, dt, BiomeRuntime.gravity())
	# squash target follows the physical compression of the legs
	var load := 0.0
	for side in legs:
		var l: LegVisual = legs[side]
		if l.leg and l.leg.attached and l.leg.in_contact:
			load = maxf(load, l.leg.load_ratio)
	var target := load * 0.32
	var w0 := TAU * squash_hz
	squash_vel += (-w0 * w0 * (squash - target) - 2.0 * squash_damping * w0 * squash_vel) * dt
	squash = clampf(squash + squash_vel * dt, -0.32, 0.42)
	_apply_squash()
	if _sparkles:
		_sparkles.emitting = charge_ratio >= 0.999 and launched
	for side in arms:
		arms[side].step(dt, frame)
	for side in legs:
		legs[side].step(dt, frame)
	if head:
		head.step(dt, frame)
		_idle_expression(dt)
	if not launched and has_meta("enemy_identity"):
		_enemy_idle_t += dt
		var pose := EnemyIdleAnimator.compute_pose(String(get_meta("enemy_identity")), _enemy_idle_t)
		torso.position += (pose.body_pos as Vector2) * 0.65
		torso.rotation = float(pose.body_rot) * 0.75
		for side in arms:
			var a: ArmVisual = arms[side]
			var gain := maxf(float(a.video_part.geometry.get("inertia_gain", 0.28)), 0.05) if a.video_part else 0.28
			var hand_off: Vector2 = pose.arm_l_offset if side == &"arm_l" else pose.arm_r_offset
			a.p = a.exit + a.rest + (hand_off * 0.75) / gain
		if head:
			head.angle = float(pose.head_angle)
			head.rotation = head.angle
			head.want_expression(pose.expression)
		_sync_art_joints()


func _idle_expression(dt: float) -> void:
	_scare_cooldown -= dt
	if not launched:
		head.want_expression(&"neutral")
		return
	if contacts.any_leg_contact or contacts.any_body_contact:
		return
	# anticipation: look scared when about to hit the ground badly
	var v := robot.linear_velocity
	if v.length() > 200.0 and _scare_cooldown <= 0.0:
		_ray.from = robot.global_position
		_ray.to = robot.global_position + v * 0.28
		_ray.exclude = [robot.get_rid()]
		var hit := robot.get_world_2d().direct_space_state.intersect_ray(_ray)
		if hit:
			var up := -robot.global_transform.y.normalized()
			if up.dot(hit.normal) < 0.55:
				head.set_expression(&"scared", 0.3, 1)
				_scare_cooldown = 0.25
				return
	head.want_expression(&"determined")


# ---------------- reactions (called by RobotController) ----------------

func on_touchdown(info: Dictionary) -> void:
	var impact: float = info.impact
	squash_vel += clampf(impact * 0.0016, 0.0, 4.5)
	for side in arms:
		arms[side].kick((info.normal as Vector2).rotated(-robot.global_rotation) * -impact * 0.25)
	if head:
		head.kick(clampf(impact * 0.002, 0.0, 3.0) * signf(robot.angular_velocity + 0.01), Vector2(0, impact * 0.18))


func on_landing(info: Dictionary) -> void:
	if head == null:
		return
	var t: StringName = info.type
	var q: StringName = info.quality
	if t == &"both" and (q == &"sweet" or q == &"flat"):
		squash_vel -= 5.5   # big stretch on a power release
		head.set_expression(&"happy", 0.9, 2)
	elif t == &"both":
		squash_vel -= 3.5
		head.set_expression(&"happy", 0.6, 2)
	elif t == &"right":
		squash_vel -= 3.0
		head.set_expression(&"determined", 0.7, 2)
	elif t == &"left":
		squash_vel -= 2.0
		head.set_expression(&"neutral", 0.5, 1)
	elif t == &"poor":
		head.set_expression(&"scared", 0.5, 2)


func on_body_hit(info: Dictionary) -> void:
	squash_vel += clampf(info.impact * 0.003, 1.0, 7.0)
	if head == null:
		return
	head.set_expression(&"angry", 1.1, 3)
	head.kick(clampf(info.impact * 0.004, 0.5, 5.0), Vector2.ZERO)


## Stored spin energy released by a good landing: extra-big stretch, delighted face.
func on_charge_released(c: float) -> void:
	squash_vel -= 4.0 * c
	if head:
		head.set_expression(&"happy", 1.2, 4)


func on_limb_lost(_side: StringName) -> void:
	if head:
		head.set_expression(&"dizzy", 1.0, 4)
	squash_vel += 3.0


func take_limb(side: StringName) -> Node2D:
	var n: Node2D = arms.get(side, legs.get(side))
	if n == null:
		return null
	arms.erase(side)
	legs.erase(side)
	remove_child(n)
	if n is LegVisual:
		(n as LegVisual).leg = null
		if (n as LegVisual).exhaust:
			(n as LegVisual).exhaust.disable()
	return n


func take_head() -> HeadVisual:
	var h := head
	h.release_visual_anchor()
	head = null
	remove_child(h)
	return h


func head_global_transform() -> Transform2D:
	return head.global_transform if head else global_transform
