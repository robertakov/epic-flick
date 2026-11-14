class_name RobotController
extends RigidBody2D
## The player robot. Owns the physics body and wires together the single-responsibility parts:
##   RotationController      - one-button spin control
##   SpringContactController - spring legs + landing classification + body hits
##   DamageController        - health, collision events, which module breaks
##   SpinChargeController    - energy from the automatic clockwise air spin, spent by every new contact
##   RobotVisual             - procedural cartoon rig (no physics influence)
## Detached modules become DetachablePart bodies; the final torso hit spawns a RocketHead.

signal touchdown(info: Dictionary)
signal landed(info: Dictionary)
signal body_hit(info: Dictionary)
signal limb_lost(limb: StringName, part: RigidBody2D)
signal rocket_launched(head: RigidBody2D)
signal damaged(amount: float, zone_class: StringName, health: float, info: Dictionary)
signal charge_changed(charge: float)
signal charge_released(charge: float, bonus: Vector2, info: Dictionary)

const LAYER_GROUND := 1
const LAYER_ROBOT := 2
const LAYER_DEBRIS := 4
## Body hits slower than this get no CRASH!/dust effect (purely visual; damage does not use it).
const FX_MIN_IMPACT := 140.0

@export var config: RobotConfig
@export var contact_config: ContactConfig
@export var damage_config: DamageConfig
@export var rocket_config: RocketConfig
@export var spin_config: SpinChargeConfig

var rig: RigData
var input_router: InputRouter
var rotation_ctl: RotationController
var contacts: SpringContactController
var damage: DamageController
var spin_charge: SpinChargeController
var visual: RobotVisual
var fx: Node   # Fx spawner (optional)
## Optional training-only local translation gate. Normal robots never enable it.
var tutorial_air_gate := false
var tutorial_saved_velocity := Vector2.ZERO
var rocket_launch_gate: Callable
var tutorial_pending_rocket := {}
var launched := false
var physics_time := 0.0
var attached := {&"arm_l": true, &"arm_r": true, &"leg_l": true, &"leg_r": true, &"head": true}
var _hips := {}
var _head_center := Vector2.ZERO
var _head_shape: CollisionShape2D
var _arm_shapes := {}
## v36 fast-forward invariance: structural changes requested inside the physics callback (limb detach, jet-head
## launch) used call_deferred, whose flush point depends on the frame cadence (at 1x in the rendered frame, while
## fast-forwarding at the end of the NEXT physics frame, after the visuals had already advanced a step -> a different
## jet-head start transform). They now run at a fixed point: the start of this robot's next physics frame.
var _queued: Array = []
## Tests only: the pre-v36 order (the breaking last leg is removed at once) for before/after measurements.
var debug_immediate_detach := false


func _queue(method: StringName, args: Array) -> void:
	_queued.append([method, args])


func _physics_process(_dt: float) -> void:
	if _queued.is_empty():
		return
	var q := _queued
	_queued = []
	for item in q:
		callv(item[0], item[1])


func setup(p_input: InputRouter, p_fx: Node) -> void:
	input_router = p_input
	fx = p_fx


func _ready() -> void:
	rig = RigData.new(config)
	collision_layer = LAYER_ROBOT
	collision_mask = LAYER_GROUND
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	custom_integrator = false
	var mat := PhysicsMaterial.new()
	mat.bounce = config.body_bounce
	mat.friction = config.body_friction
	physics_material_override = mat

	# hit zones: every CollisionShape2D carries a "zone" meta that SpringContactController reads
	var torso_shape := CollisionShape2D.new()
	torso_shape.set_meta(&"zone", &"torso")
	var cap := CapsuleShape2D.new()
	# v32: torso_hit_scale shrinks ONLY the main body capsule (Sumobot's huge art keeps a normal-size body hit)
	cap.radius = 44.0 * config.rig_scale / 0.42 * config.torso_hit_scale
	cap.height = 100.0 * config.rig_scale / 0.42 * config.torso_hit_scale
	torso_shape.shape = cap
	add_child(torso_shape)
	var nk := rig.torso_point("neck")
	_head_center = nk + Vector2(0, 6) + (rig.head_point("center") - rig.head_point("neck"))
	var head_shape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 50.0 * config.rig_scale / 0.42
	head_shape.shape = circ
	head_shape.position = _head_center
	head_shape.set_meta(&"zone", &"head")
	add_child(head_shape)
	_head_shape = head_shape
	# arm hit zones: the fists at their rest pose (side hits taken by an arm)
	for side in [&"arm_l", &"arm_r"]:
		var part := String(side)
		var socket := rig.torso_point("shoulder_l" if side == &"arm_l" else "shoulder_r")
		var fist := socket + rig.piece_point(part, "shoulder", "exit") - rig.piece_point(part, "shoulder", "disc") + rig.coil_rest_vec(part)
		var arm_shape := CollisionShape2D.new()
		var ac := CircleShape2D.new()
		ac.radius = 24.0 * config.rig_scale / 0.42
		arm_shape.shape = ac
		arm_shape.position = fist
		arm_shape.set_meta(&"zone", side)
		add_child(arm_shape)
		_arm_shapes[side] = arm_shape

	rotation_ctl = RotationController.new()
	rotation_ctl.name = "RotationController"
	rotation_ctl.cfg = config
	rotation_ctl.input = input_router
	add_child(rotation_ctl)

	spin_charge = SpinChargeController.new()
	spin_charge.name = "SpinChargeController"
	spin_charge.cfg = spin_config if spin_config else SpinChargeConfig.new()
	spin_charge.base_cw_speed = config.clockwise_rotation_speed
	spin_charge.charge_rate = config.charge_rate
	spin_charge.energy_multiplier = config.energy_boost_multiplier
	add_child(spin_charge)
	rotation_ctl.spin_charge = spin_charge

	contacts = SpringContactController.new()
	contacts.name = "SpringContactController"
	contacts.setup(self, contact_config, config)
	contacts.spin_charge = spin_charge
	add_child(contacts)
	var hip_y := rig.torso_point("hip_l").y
	var hip_x := 27.0 * config.rig_scale / 0.42
	_hips = {&"leg_l": Vector2(-hip_x, hip_y), &"leg_r": Vector2(hip_x, hip_y)}
	for side in [&"leg_l", &"leg_r"]:
		var leg := SpringLeg.new()
		leg.side = side
		leg.hip = _hips[side]
		contacts.add_leg(leg)

	damage = DamageController.new()
	damage.name = "DamageController"
	damage.cfg = damage_config
	add_child(damage)

	visual = RobotVisual.new()
	visual.build(self, rig, contacts, _hips)
	add_child(visual)

	contacts.touchdown.connect(_on_touchdown)
	contacts.landing.connect(_on_landing)
	contacts.body_hit.connect(_on_body_hit)
	contacts.deferred_detach.connect(_detach_now)
	damage.limb_lost.connect(_on_limb_lost)
	damage.rocket_triggered.connect(_on_rocket_triggered)
	damage.damage_applied.connect(_on_damage_applied)
	spin_charge.charge_changed.connect(func(c: float) -> void:
		visual.charge_ratio = spin_charge.ratio()
		charge_changed.emit(c))
	spin_charge.charge_released.connect(_on_charge_released)

	_update_mass()
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = true


## Called by the launch hand at the exact frame the finger connects.
func launch(velocity: Vector2, spin: float) -> void:
	freeze = false
	linear_velocity = velocity
	angular_velocity = spin
	launched = true
	rotation_ctl.enabled = true
	visual.launched = true
	visual.head.set_expression(&"scared", 0.5, 3)
	visual.squash_vel -= 6.0


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not launched:
		return
	# v34: a frozen body (tutorial instruction gate) runs NO gameplay integration: no charge, no turns, no damage
	if freeze:
		return
	physics_time += state.step
	contacts.integrate(state)
	damage.tick(state.step, contacts.touching, Engine.get_physics_frames())
	var w_c := state.angular_velocity
	rotation_ctl.integrate(state, contacts.angular_influence())
	contacts.dw_ctrl_step = state.angular_velocity - w_c
	rotation_ctl.count_turns(state.step, state.angular_velocity, not contacts.any_contact)
	if rotation_ctl.enabled:
		spin_charge.step(state.step, state.angular_velocity, not contacts.any_contact,
			input_router != null and input_router.holding)
	var v := state.linear_velocity
	state.linear_velocity = v - v * v.length() * config.air_drag * state.step
	if state.linear_velocity.length() > config.max_speed:
		state.linear_velocity = state.linear_velocity.normalized() * config.max_speed
	if tutorial_air_gate:
		state.linear_velocity=Vector2.ZERO
	contacts.post_step(state)


func _update_mass() -> void:
	var m := config.torso_mass
	var com := Vector2.ZERO
	var parts := {&"head": [config.head_mass, _head_center],
		&"arm_l": [config.arm_mass, rig.torso_point("shoulder_l") + Vector2(-20, 25)],
		&"arm_r": [config.arm_mass, rig.torso_point("shoulder_r") + Vector2(20, 25)],
		&"leg_l": [config.leg_mass, _hips[&"leg_l"] + Vector2(0, 60)],
		&"leg_r": [config.leg_mass, _hips[&"leg_r"] + Vector2(0, 60)]}
	for k in parts:
		if attached[k]:
			m += parts[k][0]
			com += parts[k][1] * parts[k][0]
	mass = m
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com / m
	inertia = m * config.inertia_radius * config.inertia_radius


# ---------------- contact events ----------------

func _on_touchdown(info: Dictionary) -> void:
	if config.auto_spin_reset_on_contact:
		rotation_ctl.reset_auto_turns()
	visual.on_touchdown(info)
	touchdown.emit(info)
	if fx and info.impact > 250.0 and info.type != &"body":
		fx.call_deferred("spring_touchdown", info)


func _on_landing(info: Dictionary) -> void:
	visual.on_landing(info)
	landed.emit(info)
	if fx and info.impact > 250.0 and info.type != &"body":
		fx.call_deferred("landing_burst", info)


func _on_body_hit(info: Dictionary) -> void:
	visual.on_body_hit(info)
	body_hit.emit(info)
	if fx and info.impact >= FX_MIN_IMPACT:
		fx.call_deferred("body_hit", info)


func _on_charge_released(c: float, bonus: Vector2, info: Dictionary) -> void:
	visual.on_charge_released(info.effective)
	charge_released.emit(c, bonus, info)
	if fx:
		fx.call_deferred("charged_impact", info.point, info.normal, info.effective, info.zone_class)


func _on_damage_applied(amount: float, zone_class: StringName, health: float, info: Dictionary) -> void:
	info["time"] = physics_time
	damaged.emit(amount, zone_class, health, info)
	if fx and amount > 0.0:
		fx.call_deferred("damage_number", info.get("point", global_position), amount, zone_class)


## Robot lies on its torso, limbs gone, 0 HP, and cannot bounce any more: final hit (see DamageConfig).
func notify_resting() -> void:
	if contacts.is_zone_in_contact(&"torso"):
		damage.on_resting_torso({"point": global_position, "normal": Vector2.UP, "zone": &"torso"})


func _on_limb_lost(limb: StringName, info: Dictionary) -> void:
	# v36: a final leg breaking in its own charged landing first gives the bounce, then detaches (see contacts)
	if not debug_immediate_detach and contacts.defer_last_leg_detach(limb, info):
		return
	_detach_now(limb, info)


func _detach_now(limb: StringName, info: Dictionary) -> void:
	attached[limb] = false
	var leg := contacts.get_leg(limb)
	if leg:
		leg.attached = false   # its contact rays stop immediately
	if _arm_shapes.has(limb):
		(_arm_shapes[limb] as CollisionShape2D).set_deferred("disabled", true)
	_queue(&"_detach_limb", [limb, info])


func _detach_limb(limb: StringName, info: Dictionary) -> void:
	if is_queued_for_deletion() or not is_inside_tree():
		return   # attempt was restarted: never drop this robot's debris into the next attempt
	var node := visual.take_limb(limb)
	_update_mass()
	visual.on_limb_lost(limb)
	if node == null:
		return
	var part := DetachablePart.new()
	part.material = visual.material
	var n: Vector2 = info.get("normal", Vector2.UP)
	var away: Vector2 = (global_transform * (node as Node2D).get("socket" if node is ArmVisual else "hip") - global_position).normalized()
	part.setup_from(node, self, linear_velocity + (n * 0.6 + away).normalized() * damage_config.detach_impulse,
		angular_velocity + signf(away.x + 0.01) * damage_config.detach_spin)
	get_parent().add_child(part)
	if fx:
		fx.limb_pop(part.global_position)
	limb_lost.emit(limb, part)


func _on_rocket_triggered(info: Dictionary) -> void:
	if rocket_launch_gate.is_valid() and rocket_launch_gate.call(info):
		tutorial_pending_rocket=info.duplicate()
		return
	_queue(&"_launch_rocket", [info])


func set_tutorial_air_gate(on: bool) -> void:
	if on == tutorial_air_gate:
		return
	if on:
		tutorial_saved_velocity=linear_velocity
	else:
		linear_velocity=tutorial_saved_velocity
	tutorial_air_gate=on

func release_tutorial_rocket() -> void:
	if tutorial_pending_rocket.is_empty():
		return
	var info := tutorial_pending_rocket
	tutorial_pending_rocket={}
	_queue(&"_launch_rocket", [info])

func _launch_rocket(info: Dictionary) -> void:
	if is_queued_for_deletion() or not is_inside_tree():
		return   # attempt was restarted before the deferred launch ran
	if not attached[&"head"]:
		return
	attached[&"head"] = false
	rotation_ctl.enabled = false
	spin_charge.reset()
	spin_charge.enabled = false
	var head_xf := visual.head_global_transform()
	var head := visual.take_head()
	_update_mass()
	# the head shape leaves the body too
	_head_shape.set_deferred("disabled", true)
	var rh := RocketHead.new()
	rh.cfg = rocket_config
	rh.material = visual.material
	get_parent().add_child(rh)
	rh.start(head, head_xf, linear_velocity, angular_velocity)
	if fx:
		fx.rocket_ignite(rh.global_position, info)
	rocket_launched.emit(rh)
