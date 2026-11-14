class_name SpinChargeConfig
extends Resource
## Spin charge (v0.9): the AUTOMATIC clockwise spin stores energy while the robot is in the air; the manual
## counter-clockwise spin (screen held) only steers - it neither adds nor drains charge.
## EVERY new ground contact (even a light or grazing one) immediately spends the WHOLE charge as an extra impulse,
## scaled by the body zone that touched first. Charge is a fraction 0..max_charge (1.0 = 100%).
## Damage is a separate system and never reads the charge.

@export var enabled := true

@export_group("Charging")
## Charge gained per full 360 deg of ACTUAL automatic clockwise rotation in the air (partial turns proportional).
## 0.35 -> full charge after ~2.9 turns.
@export var charge_per_rotation := 0.35
@export var max_charge := 1.0
## Only rotation in the air charges (rolling on the ground does not farm energy).
@export var count_only_airborne := true
## The automatic spin gets physically a little faster with charge: speed * (1 + spin_speedup_at_full * charge).
## v0.9.1: 0 - the spin now accelerates per completed turn instead (RobotConfig.auto_spin_accel).
@export var spin_speedup_at_full := 0.0

@export_group("Spending (every new contact spends everything)")
## Below this the charge is simply cleared without an impulse or effect.
@export var min_charge_to_use := 0.02
## Share of the charge converted into impulse, by the zone class that touched first.
@export var zone_efficiency := {"feet": 1.0, "arm": 0.3, "side": 0.25, "head": 0.25}
## Feet: the impulse is added when the spring releases (end of the landing event) so it really becomes the next
## jump. If the robot keeps sliding on its feet longer than this, the impulse is applied anyway (s).
@export var feet_release_timeout := 0.3

@export_group("Impulse (px/s at 100% effective boost; scales linearly)")
## Along the bisector of the surface normal and the robot's up axis ("new jump").
@export var boost_up := 700.0
## Forward along the surface (down-track).
@export var boost_forward := 520.0
## The landing speed caps (ContactConfig.max_release_*) get this much headroom at 100% effective boost,
## so the boost is felt but stays bounded. RobotConfig.max_speed (3400) still applies on top.
@export var bonus_cap_headroom := 650.0
