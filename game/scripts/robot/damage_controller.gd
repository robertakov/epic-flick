class_name DamageController
extends Node
## Health + module damage (v0.7: invulnerability timer).
##
## Every physics step tick() receives the zones touching the ground in that step (feet = spring-leg rays,
## torso / head / arms = collision shapes). While the robot is VULNERABLE and anything touches, it takes the
## damage of the single most severe zone touching in that step (head > torso/side/arm > feet) and becomes
## invulnerable for `invulnerability_time`. When the timer ends and the robot still (or again) touches, it is
## damaged again - no lift-off and no minimum impact speed needed. At most one damage per physics step.
## Damage never depends on speed, angle or spin charge.
## Modules break by HEALTH RATIO (hp / max_hp) thresholds, so a future higher max HP scales automatically.
## After every HP change the missing limbs are reconciled with the thresholds: a hit crossing several
## thresholds breaks several limbs, the head rule (both arms) can never double-remove, nothing is skipped.

signal damage_applied(amount: float, zone_class: StringName, health: float, info: Dictionary)
signal limb_lost(limb: StringName, info: Dictionary)
signal rocket_triggered(info: Dictionary)

const SEVERITY := {&"feet": 1, &"side": 2, &"head": 3}

var cfg: DamageConfig
var max_health := 100.0
var health := 100.0
var limbs_remaining: Array[StringName] = [&"arm_l", &"arm_r", &"leg_l", &"leg_r"]
var rocket_fired := false
var arms_forced := false
var hits := 0                     # number of damage applications this attempt
var invulnerable_left := 0.0
## Invulnerability after a hit (s). Set from the player settings; defaults to the config value.
var invulnerability_time := 0.5
var _last_tick_frame := -1
## Damage is armed once the robot has been airborne after the launch: standing on the launch ledge at the
## moment of the flick is not a collision.
var armed := false


func _ready() -> void:
	max_health = cfg.max_health
	health = max_health
	invulnerability_time = cfg.invulnerability_time


## Zone -> damage class. Returns &"" for zones that never cause damage.
func zone_class(zone: StringName) -> StringName:
	match zone:
		&"leg_l", &"leg_r":
			return &"feet"
		&"torso":
			return &"side"
		&"arm_l", &"arm_r":
			return &"side" if cfg.arm_contact_counts_as_side else &""
		&"head":
			return &"head"
	return &""


func damage_for(c: StringName) -> float:
	match c:
		&"feet":
			return cfg.damage_feet
		&"side":
			return cfg.damage_side
		&"head":
			return cfg.damage_head
	return 0.0


func is_invulnerable() -> bool:
	return invulnerable_left > 0.0


func health_ratio() -> float:
	return health / maxf(max_health, 0.0001)


## Called once per physics step. touching: zone -> {point, normal, impact} for zones on the ground now.
## frame: physics frame id, guards against two damage applications in the same step.
func tick(dt: float, touching: Dictionary, frame := -1) -> void:
	if frame >= 0 and frame == _last_tick_frame:
		return
	_last_tick_frame = frame
	if not armed:
		armed = touching.is_empty()
		return
	if invulnerable_left > 0.0:
		# the window ends inside this step -> vulnerable again in the same step (interval = exactly the setting)
		invulnerable_left = maxf(invulnerable_left - dt, 0.0)
		if invulnerable_left > 0.00001:
			return
	if rocket_fired or touching.is_empty():
		return
	# most severe zone touching in this step
	var best_zone := &""
	var best_class := &""
	for z in touching:
		var c := zone_class(z)
		if c != &"" and (best_class == &"" or SEVERITY[c] > SEVERITY[best_class]):
			best_class = c
			best_zone = z
	if best_class == &"":
		return
	var info: Dictionary = (touching[best_zone] as Dictionary).duplicate()
	info["zone"] = best_zone
	# final stage: limbs gone and HP empty -> the first torso contact once the invulnerability of the hit
	# that emptied HP has run out fires the jet head (we only get here while vulnerable)
	if health <= 0.0 and limbs_remaining.is_empty():
		if touching.has(&"torso"):
			_fire_rocket(info)
		return
	_apply(best_class, info)


func _apply(c: StringName, info: Dictionary) -> void:
	hits += 1
	info["event"] = hits
	var before := health
	health = maxf(health - damage_for(c), 0.0)
	if c == &"head" and cfg.head_hit_removes_arms:
		arms_forced = true
	info["hp_before"] = before
	invulnerable_left = invulnerability_time
	damage_applied.emit(before - health, c, health, info)
	_sync_limbs(info)


## The robot came to rest on its torso at 0 HP and nothing else happens (see DamageConfig).
func on_resting_torso(info: Dictionary) -> void:
	if cfg.rocket_on_resting_torso and not rocket_fired and limbs_remaining.is_empty() and health <= 0.0:
		info["resting"] = true
		_fire_rocket(info)


func _fire_rocket(info: Dictionary) -> void:
	if rocket_fired:
		return
	rocket_fired = true
	rocket_triggered.emit(info)


## Make the attached modules match the current health ratio (+ critical rules). Idempotent.
func _sync_limbs(info: Dictionary) -> void:
	var need := {"arm": 0, "leg": 0}
	var ratio := health_ratio()
	for i in mini(cfg.limb_thresholds.size(), cfg.threshold_parts.size()):
		if ratio <= cfg.limb_thresholds[i] + 0.000001:
			need[cfg.threshold_parts[i]] += 1
	if arms_forced:
		need["arm"] = cfg.arm_order.size()
	if health <= 0.0:
		need["arm"] = cfg.arm_order.size()
		need["leg"] = cfg.leg_order.size()
	_lose_up_to(cfg.arm_order, need["arm"], info)
	_lose_up_to(cfg.leg_order, need["leg"], info)


func _lose_up_to(order: PackedStringArray, wanted_missing: int, info: Dictionary) -> void:
	var missing := 0
	for l in order:
		if not limbs_remaining.has(StringName(l)):
			missing += 1
	for l in order:
		if missing >= wanted_missing:
			return
		var limb := StringName(l)
		if limbs_remaining.has(limb):
			limbs_remaining.erase(limb)
			missing += 1
			limb_lost.emit(limb, info)


func has_legs() -> bool:
	return limbs_remaining.has(&"leg_l") or limbs_remaining.has(&"leg_r")


## v30 environmental damage (exclusion-zone anomalies). Same HP / limb-threshold / jet-head rules as collision
## damage; zone_class &"electric" or &"radiation". set_invulnerable: start the normal post-hit window (electric
## shock); radiation ticks do not. Ignored before the launch damage arming and after the jet head fired.
func apply_external(amount: float, zone_class: StringName, info: Dictionary, set_invulnerable := true) -> void:
	if rocket_fired or amount <= 0.0 or not armed:
		return
	hits += 1
	info["event"] = hits
	info["zone"] = zone_class
	var before := health
	health = maxf(health - amount, 0.0)
	info["hp_before"] = before
	if set_invulnerable:
		invulnerable_left = invulnerability_time
	damage_applied.emit(before - health, zone_class, health, info)
	_sync_limbs(info)


## v32 paid continue: a freshly built robot starts at `ratio` of its max HP (whole: no limb change) with a spawn
## protection window.
func restore_for_continue(ratio: float, invulnerable_s: float) -> void:
	health = clampf(max_health * ratio, 1.0, max_health)
	invulnerable_left = maxf(invulnerable_s, 0.0)


## Test hook: set HP without triggering module changes.
func debug_set_health(hp: float) -> void:
	health = clampf(hp, 0.0, max_health)
