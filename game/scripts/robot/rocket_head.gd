class_name RocketHead
extends RigidBody2D
## Final phase: the head blasts off along the direction it faces at separation (its local up axis
## in world space). No steering - the player's choice was the robot's angle before the last hit.

signal finished(head: RocketHead)

var cfg: RocketConfig
var head: HeadVisual
var frame := FrameMotion.new()
var burning := true
var done := false
var time := 0.0
var _burn_left := 0.0
var _rest_time := 0.0
var _gravity := 1800.0
var _flame: Polygon2D
var _flame_core: Polygon2D
var _smoke: CPUParticles2D
var _launch_dir := Vector2.RIGHT
var _center_local := Vector2.ZERO
var _last_good := Transform2D.IDENTITY
var recovered := 0   # telemetry: how often the safety net had to act


func start(p_head: HeadVisual, head_xf: Transform2D, inherit_vel: Vector2, inherit_spin: float) -> void:
	head = p_head
	_center_local = head.center_local
	global_position = _clear_of_ground(head_xf * _center_local, cfg.radius)
	global_rotation = head_xf.get_rotation()
	_last_good = global_transform
	add_child(head)
	head.set_neck(-_center_local)
	head.angle = 0.0
	head.angle_vel = 0.0
	head.offset_pos = Vector2.ZERO
	head.set_expression(&"determined", 1.4, 5)
	_gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

	collision_layer = RobotController.LAYER_DEBRIS
	collision_mask = RobotController.LAYER_GROUND
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	mass = cfg.mass
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = cfg.linear_damp
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = cfg.angular_damp
	var mat := PhysicsMaterial.new()
	mat.bounce = cfg.bounce
	mat.friction = cfg.friction
	physics_material_override = mat
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = cfg.radius
	cs.shape = sh
	add_child(cs)
	z_index = 6

	_launch_dir = -global_transform.y.normalized()
	linear_velocity = inherit_vel * cfg.inherit_velocity + _launch_dir * cfg.launch_impulse
	angular_velocity = inherit_spin * 0.08
	_burn_left = cfg.thrust_time
	_build_jet()


## The head separates at the moment the torso hits the ground, so its circle can start inside the slope.
## A body that starts overlapping the ground breaks the continuous-collision cast (seen as a teleport to
## ~1e20 on the steep track), so the spawn point is pushed up until the circle is clear.
func _clear_of_ground(p: Vector2, r: float) -> Vector2:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.new()
	q.collision_mask = RobotController.LAYER_GROUND
	# ground under the head (cast from well above), checked at the centre and both sides of the circle
	for dx in [0.0, -r, r]:
		q.from = p + Vector2(dx, -600.0)
		q.to = p + Vector2(dx, r + 4.0)
		var hit := space.intersect_ray(q)
		if hit and hit.position.y < p.y + r + 4.0:
			p.y = hit.position.y - r - 4.0
	return p
func launch_direction() -> Vector2:
	return _launch_dir


func _build_jet() -> void:
	# cartoon flame under the neck, pointing away from the facing direction
	var base := -_center_local + Vector2(0, -6)
	_flame = Polygon2D.new()
	_flame.color = Color(1.0, 0.55, 0.1)
	_flame_core = Polygon2D.new()
	_flame_core.color = Color(1.0, 0.95, 0.45)
	var outline := Line2D.new()
	outline.name = "FlameOutline"
	outline.width = 4.0
	outline.default_color = Color(0.12, 0.05, 0.02)
	outline.closed = true
	_flame.add_child(outline)
	_flame.position = base
	_flame_core.position = base
	add_child(_flame)
	add_child(_flame_core)
	move_child(_flame, 0)
	move_child(_flame_core, 1)
	_smoke = CPUParticles2D.new()
	_smoke.amount = 48
	_smoke.lifetime = 1.1
	_smoke.local_coords = false
	_smoke.texture = Fx.puff_texture()
	_smoke.direction = Vector2(0, 1)
	_smoke.spread = 18.0
	_smoke.initial_velocity_min = 120.0
	_smoke.initial_velocity_max = 220.0
	_smoke.gravity = Vector2(0, -60)
	_smoke.damping_min = 80.0
	_smoke.damping_max = 140.0
	_smoke.scale_amount_min = 0.35
	_smoke.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.6))
	_smoke.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.9, 0.6, 0.95))
	grad.set_color(1, Color(0.55, 0.55, 0.6, 0.0))
	_smoke.color_ramp = grad
	_smoke.position = base + Vector2(0, 30)
	add_child(_smoke)
	move_child(_smoke, 0)
	_smoke.emitting = true


func _update_flame() -> void:
	var s := clampf(_burn_left / maxf(cfg.thrust_time, 0.01), 0.0, 1.0)
	var flick := 0.8 + 0.2 * sin(time * 60.0) + 0.1 * sin(time * 23.0)
	var L := (70.0 + 50.0 * s) * flick * (1.0 if burning else 0.0)
	var w := 26.0 * (0.6 + 0.4 * s)
	var outer := PackedVector2Array([Vector2(-w, 0), Vector2(-w * 0.6, L * 0.45), Vector2(-w * 0.25, L * 0.7),
		Vector2(0, L), Vector2(w * 0.25, L * 0.7), Vector2(w * 0.6, L * 0.45), Vector2(w, 0)])
	_flame.polygon = outer
	(_flame.get_node("FlameOutline") as Line2D).points = outer
	var inner := PackedVector2Array()
	for p in outer:
		inner.append(Vector2(p.x * 0.5, p.y * 0.6))
	_flame_core.polygon = inner


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# safety net: never let a broken solver step leave the head at a non-finite / absurd position
	var o := state.transform.origin
	if not (is_finite(o.x) and is_finite(o.y)) or absf(o.x) > 1.0e7 or absf(o.y) > 1.0e7:
		push_warning("RocketHead: invalid transform %s restored" % [o])
		state.transform = _last_good
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		recovered += 1
		return
	_last_good = state.transform
	if burning:
		var dir := -state.transform.y.normalized()
		state.linear_velocity += dir * cfg.thrust * state.step


func _physics_process(dt: float) -> void:
	if done:
		return
	time += dt
	frame.update_from(self, dt, BiomeRuntime.gravity())
	head.step(dt, frame)
	if burning:
		_burn_left -= dt
		if _burn_left <= 0.0:
			burning = false
			_smoke.emitting = false
			head.set_expression(&"happy", 1.0, 5)
	_update_flame()
	if not burning:
		var on_ground := get_contact_count() > 0
		if on_ground:
			head.want_expression(&"dizzy")
		if linear_velocity.length() < cfg.end_speed and on_ground:
			_rest_time += dt
		else:
			_rest_time = 0.0
		if _rest_time >= cfg.end_rest_time or time >= cfg.max_time:
			done = true
			finished.emit(self)
