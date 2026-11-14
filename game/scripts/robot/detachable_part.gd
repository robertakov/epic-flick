class_name DetachablePart
extends RigidBody2D
## A module that broke off the robot. Keeps the exact visual node (and its spring state), becomes an
## independent rigid body and keeps its coil wobbling from the inertial forces of its own tumbling.

const LIFETIME := 14.0

var limb: Node2D
var frame := FrameMotion.new()
var _life := 0.0
var _gravity := 1800.0


func setup_from(node: Node2D, robot: RigidBody2D, vel: Vector2, spin: float) -> void:
	limb = node
	var center := _limb_center(node)
	var xf := robot.global_transform
	global_position = xf * center
	global_rotation = xf.get_rotation()
	add_child(node)
	node.position = -center
	node.rotation = 0.0
	linear_velocity = vel
	angular_velocity = spin
	collision_layer = RobotController.LAYER_DEBRIS
	collision_mask = RobotController.LAYER_GROUND
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	mass = 0.3
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.35
	mat.friction = 0.7
	physics_material_override = mat
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 26.0 if node is ArmVisual else 30.0
	cs.shape = sh
	add_child(cs)
	z_index = 4
	# twang the spring as it rips off
	if node is ArmVisual:
		(node as ArmVisual).kick(Vector2(-spin * 30.0, -260.0))
	elif node is LegVisual:
		(node as LegVisual).kick(520.0)
	_gravity = ProjectSettings.get_setting("physics/2d/default_gravity")


func _limb_center(node: Node2D) -> Vector2:
	if node is ArmVisual:
		var a := node as ArmVisual
		return (a.socket + a.p) * 0.5
	if node is LegVisual:
		var l := node as LegVisual
		return l.hip + Vector2.DOWN * (l.cap_len + l.length + l.boot_len * 0.5) * 0.6
	return Vector2.ZERO


func _physics_process(dt: float) -> void:
	_life += dt
	frame.update_from(self, dt, BiomeRuntime.gravity())
	if limb and limb.has_method("step"):
		limb.call("step", dt, frame)
	if _life > LIFETIME:
		modulate.a = maxf(0.0, modulate.a - dt)
		if modulate.a <= 0.0:
			queue_free()
