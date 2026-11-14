class_name DamageConfig
extends Resource
## Health-based damage model (v0.7). Touching the ground while vulnerable costs HP (even a perfect landing,
## even a slow touch); every hit starts a short invulnerability. Modules break at health-RATIO thresholds.
## All numbers live here - scripts hold no damage constants.

@export_group("Health")
## Maximum HP. Future upgrades can raise it; limb thresholds are ratios, so they scale automatically.
@export var max_health := 100.0
## Invulnerability after a hit (s). Default for the player setting "Неуязвимость после удара" (0.1..2.0).
@export var invulnerability_time := 0.5

@export_group("Damage per collision (fixed, not speed-scaled yet)")
## Landing on the spring legs (left, right or both - including a perfect landing).
@export var damage_feet := 15.0
## Torso / side hit (an attached arm taking the hit counts as a side hit).
@export var damage_side := 35.0
## Head hit.
@export var damage_head := 50.0
## A full head hit tears off both arms immediately (critical rule).
@export var head_hit_removes_arms := true
## Arms touching the ground count as side hits (false = arms are ignored for damage).
@export var arm_contact_counts_as_side := true

@export_group("Module thresholds")
## Module breaks when hp / max_hp <= threshold. Pairs with threshold_parts ("arm" / "leg").
## Defaults: 75% -> first arm, 50% -> second arm, 25% -> first leg, 0% -> second leg.
@export var limb_thresholds: PackedFloat32Array = [0.75, 0.5, 0.25, 0.0]
@export var threshold_parts: PackedStringArray = ["arm", "arm", "leg", "leg"]
## Which arm / leg goes first.
@export var arm_order: PackedStringArray = ["arm_l", "arm_r"]
@export var leg_order: PackedStringArray = ["leg_l", "leg_r"]

@export_group("Final stage")
## When the robot lies on its torso with no limbs and 0 HP and stops (no new bounce possible),
## the resting torso contact counts as the final hit so the jet head still fires.
@export var rocket_on_resting_torso := true

@export_group("Detached modules")
@export var detach_impulse := 520.0
@export var detach_spin := 9.0
