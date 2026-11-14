class_name RobotConfig
extends Resource
## Physical + control parameters of one robot body. Future robots / part sets ship their own .tres.

@export_group("Body")
@export var rig_json := "res://assets/robot/rig.json"
@export var texture_dir := "res://assets/robot/"
## World pixels per exported rig pixel (rig.json coordinates are at 0.5 of the source video).
@export var rig_scale := 0.42
## v32: main-body (torso capsule) hit size multiplier on top of rig_scale (RobotDefinition.body_hit_scale).
@export var torso_hit_scale := 1.0
@export var torso_mass := 1.7
@export var head_mass := 0.5
@export var arm_mass := 0.2
@export var leg_mass := 0.25
## Inertia multiplier over (mass * radius^2); higher = more stable spin.
@export var inertia_radius := 78.0
@export var max_speed := 3400.0
## Quadratic air drag (1/px): decel = air_drag * v^2. Keeps top speed readable on long descents.
@export var air_drag := 0.00008
@export var body_bounce := 0.22
@export var body_friction := 0.32

@export_group("Per-robot (filled from RobotDefinition)")
## Which RobotDefinition produced this copy (telemetry / UI).
@export var robot_id := "samurai"
## Decoupled visual character identity (e.g. rasta, kenguru, sumo, chronos, samurai).
@export var visual_id := ""
## Spin-charge gain multiplier and impulse multiplier.
@export var charge_rate := 1.0
@export var energy_boost_multiplier := 1.0
## Palette-swap material for the module sprites (null = original art). Set from the equipped SkinDefinition.
@export var visual_material: Material
@export var skin_id := ""

@export_group("Rotation control")
## Rotations per second while the screen is NOT touched (clockwise).
@export var clockwise_rotation_speed := 2.0
## Rotations per second while the screen IS held (counter-clockwise).
@export var counterclockwise_rotation_speed := 1.0
## v0.9.1: the automatic clockwise spin gets faster by this much (rev/s) per COMPLETED automatic turn in the air
## (player setting "Ускорение вращения", default 0.20). Manual counter-clockwise turns never count.
@export var auto_spin_accel := 0.2
## Safety cap for the accelerated automatic spin (rev/s). 3.0 leaves 5 turns at the max setting (0.50) untouched.
@export var auto_spin_max_rps := 3.0
## The turn counter restarts on every new ground contact (each jump starts at the base speed again).
@export var auto_spin_reset_on_contact := true
## v0.9.2 Auto-spin recovery after a manual correction: on release the automatic spin restarts at
## recovery_start_ratio x the auto speed reached BEFORE the hold, and eases back to it over recovery_time (s).
## Player settings "Восстановление вращения" (default 0.5 s) and "Скорость после управления" (default 25%).
@export var recovery_time := 0.5
@export var recovery_start_ratio := 0.25
## How fast angular velocity converges to the target (1/s). Higher = snappier.
@export var rotation_response := 24.0
## 0..1: how much of the rotation control is suppressed while/just after touching ground,
## so contact torques (one-foot landings, body hits) stay visible.
@export_range(0.0, 1.0) var collision_angular_influence := 0.95
## Influence during long (resting / rolling) contact, so spin input can roll the robot back into play.
@export_range(0.0, 1.0) var resting_contact_influence := 0.35
## Seconds the influence fades out after the last contact.
@export var collision_influence_time := 0.22
