class_name ContactConfig
extends Resource
## Spring-leg physics and landing classification. All lengths in world px, angles in degrees.

@export_group("Leg spring (physical)")
@export var coil_rest_length := 56.0
@export var coil_min_length := 10.0
@export var coil_max_length := 84.0
## N per px per leg.
@export var spring_stiffness := 3300.0
## Multiplies extension force/returned energy, not compression, hard stop or body contacts.
@export var spring_power_scale := 1.0
## Damping ratio while compressing / extending (fraction of critical).
@export var damping_ratio_compress := 0.12
@export var damping_ratio_extend := 0.04
## Hard stop when the coil is fully compressed (bottom-out).
@export var bottom_out_stiffness := 42000.0
## Ground friction coefficient at the boot: limits tangential spring push (slip when legs are too tilted).
@export var foot_friction := 0.85
## Scales torque from off-centre spring forces (1 = fully physical).
@export var spring_torque_scale := 0.9
## v0.9.2 "Вращение от отскока" (player setting, default 0.4): scales ONLY the angular response caused by ground
## contact - spring torque on feet landings, solver angular change and spin kick on body/head hits.
## 1 = previous physics, 0 = contacts add no rotation. Linear bounce, springs, boost, spin control: untouched.
@export var bounce_spin_scale := 1.0
## Per-zone balance on top of bounce_spin_scale (feet = spring torque, body = torso/arm hits, head = head hits).
@export var bounce_spin_feet := 1.0
@export var bounce_spin_body := 1.0
@export var bounce_spin_head := 1.0
## Boot half width used for the three contact rays (heel / centre / toe).
@export var foot_half_width := 30.0
## Free (airborne) leg oscillator: natural frequency (Hz) and damping ratio.
@export var free_leg_frequency := 8.0
@export var free_leg_damping := 0.12

@export_group("Landing classification")
## Both feet count as a two-foot landing if the second touches within this window (s).
@export var both_feet_window := 0.085
## Contact ends after this long with no leg/body contact (s).
@export var contact_release_time := 0.05
## Minimum normal speed for a contact to be a "landing" (otherwise it is rolling contact).
@export var min_landing_speed := 160.0
## Robot up-axis vs. surface normal: |angle| below this = flat two-foot landing.
@export var flat_angle := 8.0
## Forward lean window (relative to the surface normal) for the power bounce.
@export var sweet_angle_min := 10.0
@export var sweet_angle_max := 34.0
## Legs more tilted than this vs. the normal = poor contact.
@export var poor_angle := 58.0

@export_group("Landing effects")
## Extension stiffness multipliers (energy returned by the spring per landing type).
@export var gain_left := 0.9
@export var gain_right := 0.95
@export var gain_both_normal := 1.0
@export var gain_both_flat := 1.22
@export var gain_both_sweet := 1.1
@export var gain_poor := 0.7
## Left foot: tangential deceleration while the left spring is loaded (px/s^2 at full compression).
@export var left_brake_accel := 2600.0
## Right foot: forward acceleration along the surface while loaded.
@export var right_boost_accel := 3000.0
## Flat two-foot bounce keeps only this fraction of tangential speed (big height, poor distance).
@export var flat_tangent_keep := 0.72
## Sweet two-foot bounce: extra impulse along the robot's up axis = factor * impact speed (capped).
@export var sweet_impulse_factor := 0.42
@export var sweet_impulse_max := 760.0
## Hard cap on speed right after a release (prevents energy pumping).
@export var max_release_speed := 2900.0
## Cap on the bounce speed along the surface normal (limits bounce height, no runaway pogo).
@export var max_release_normal_speed := 2050.0
## Minimum natural rebound speed along the surface normal for an uncharged valid feet landing (px/s at 100% power).
@export var min_natural_rebound_speed := 360.0   # v36: 300 -> 360 (tiny landings felt dead; medium/strong unaffected)
## Minimum effective coil extension compression (px) on very weak uncharged feet landings so boots lift off cleanly.
@export var min_natural_extension_comp := 7.0   # v36: 6 -> 7
## v32 momentum (see MomentumRules): gain per clean landing, ceiling, forward speed where the boost fades out (px/s).
## Per robot from RobotDefinition.momentum_*; 0 gain = no momentum.
@export var momentum_gain := 0.0
@export var momentum_max := 0.0
@export var momentum_forward_cap := 1800.0
## v32 natural-jump specialisation: scales the natural rebound floor and the release-normal cap of THIS robot's feet
## landings (1.0 = shared tuning). Only Kengurobot uses it.
@export var rebound_power := 1.0
## Energy guard: speed after a landing <= speed before * ratio (+ slack). Per landing type/quality.
@export var max_speed_ratio := {"left": 0.95, "right": 1.12, "both/normal": 1.0, "both/flat": 1.08,
	"both/sweet": 1.3, "poor": 0.75, "body": 0.85}
@export var speed_ratio_slack := 120.0
## Body / head hit: extra kick along the normal (fraction of impact speed) and spin added.
@export var body_hit_kick := 0.18
@export var body_hit_spin := 5.0
