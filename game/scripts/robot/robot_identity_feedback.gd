class_name RobotIdentityFeedback
extends Node2D
## One event adapter for player AND AI. Bounded local drawing; never emits gameplay haptics/shake.
signal presentation_event(event: String, intensity: float, sfx_hook: String)
var visual: RobotVisual
var profile: RobotIdentityProfile
var particles: Array[Dictionary] = []
var event_counts: Dictionary = {}
var _seen: Dictionary = {}
var _clock := 0.0
var _airborne := false
var _compressing := false
var _full := false
var _low := false
var _dead := false
var _rocket := false
var _rocket_head: RigidBody2D
var _burst := 0.0
var _ring := 0.0
var _ring_point := Vector2.ZERO
## v32 leg thrusters (Chronobot): SHORT flashes only, never a constant flame. level 0..1, time left / duration (s).
const THRUST_MAX_S := 0.26
var _thrust_level := 0.0
var _thrust_t := 0.0
var _thrust_dur := 0.0
var thrust_flashes := 0   # count of flashes fired (tests / QA)


## Fires one brief thruster flash (keeps the stronger one when they overlap).
func thrust_flash(level: float, duration: float) -> void:
	if _rocket:
		return
	level = clampf(level, 0.0, 1.0)
	duration = clampf(duration, 0.05, THRUST_MAX_S)
	if _thrust_t > 0.0 and _thrust_level * (_thrust_t / maxf(_thrust_dur, 0.001)) >= level:
		return
	_thrust_level = level
	_thrust_t = duration
	_thrust_dur = duration
	thrust_flashes += 1


func _momentum_ratio() -> float:
	var c := visual.contacts
	return clampf(c.momentum / maxf(c.cfg.momentum_max, 1.0), 0.0, 1.0) if c and c.cfg else 0.0

func setup(p_visual: RobotVisual) -> void:
	visual = p_visual
	profile = RobotIdentityProfile.for_robot(visual.rig.robot_id)
	name = "IdentityFeedback"
	use_parent_material = false

func _ready() -> void:
	var r := visual.robot as RobotController
	if r == null:
		return
	r.touchdown.connect(func(i: Dictionary) -> void:
		event("SPRING_COMPRESS", clampf(float(i.impact) / 1600.0, 0.0, 1.0), i)
		# thrusters "soften" a feet touchdown: a small puff
		if profile.leg_exhaust and String(i.get("type", "")) in ["left", "right", "both"]:
			thrust_flash(0.35 + 0.25 * _momentum_ratio(), 0.12))
	r.landed.connect(func(i: Dictionary) -> void:
		event("GOOD_LANDING" if String(i.quality) in ["sweet", "flat"] else "BAD_LANDING", clampf(float(i.get("speed_in", 0.0)) / 1600.0, 0.0, 1.0), i)
		# ...and kick the rebound: the burst grows with the momentum chain
		if profile.leg_exhaust and String(i.get("type", "")) in ["left", "right", "both"]:
			var mr := _momentum_ratio()
			thrust_flash(0.5 + 0.5 * mr, 0.16 + 0.10 * mr))
	r.body_hit.connect(func(i: Dictionary) -> void: event("HARD_IMPACT", clampf(float(i.impact) / 1600.0, 0.0, 1.0), i))
	r.charge_released.connect(func(c: float, _bonus: Vector2, i: Dictionary) -> void:
		_burst = 0.35 * c
		if profile.leg_exhaust and c > 0.05:
			thrust_flash(0.6 + 0.4 * c, 0.22)
		event("CHARGED_LANDING", c, i))
	r.limb_lost.connect(func(_side: StringName, _part: RigidBody2D) -> void: event("LIMB_LOST", 0.6))
	r.rocket_launched.connect(func(head: RigidBody2D) -> void:
		_rocket_head = head
		_rocket = true
		event("ROCKET_PHASE_START", 1.0))
	r.damaged.connect(func(_amount: float, zone: StringName, health: float, i: Dictionary) -> void:
		if zone == &"head":
			event("HEAD_HIT", clampf(float(i.get("impact", 0.0)) / 1600.0, 0.0, 1.0), i)
		if health <= r.damage_config.max_health * 0.25 and not _low:
			_low = true
			event("LOW_HP", 0.5)
		if health <= 0.0 and not _dead:
			_dead = true
			event("DEATH", 1.0))
	event("IDLE", 0.0)

func event(kind: String, strength: float, info: Dictionary = {}) -> void:
	if not RobotIdentityProfile.EVENTS.has(kind):
		return
	# Per-semantic-event deduplication, preserving contact upgrades for existing gameplay FX.
	var key := kind + ":" + str(info.get("event", info.get("time", "")))
	if not info.is_empty() and _seen.has(key) and _clock - float(_seen[key]) < 0.09:
		return
	_seen[key] = _clock
	if _seen.size() > 64:
		_seen.clear()
	event_counts[kind] = int(event_counts.get(kind, 0)) + 1
	presentation_event.emit(kind, strength, profile.sound_hook(kind))
	var response: Dictionary = profile.event_responses.get(kind, {})
	var accent := strength * float(response.get("gain", 1.0))
	var duration := float(response.get("duration", 0.4))
	if visual.art_torso:
		visual.art_torso.react(accent, duration)
	if visual.head and visual.head.video_part:
		visual.head.video_part.react(accent, duration)
	if visual.head and response.has("face"):
		visual.head.set_expression(StringName(response.face), duration, 4)
	if kind in ["GOOD_LANDING", "BAD_LANDING", "HARD_IMPACT", "CHARGED_LANDING", "SPRING_RELEASE"] and strength >= 0.12:
		var point: Vector2 = info.get("point", visual.robot.global_position + Vector2(0, 115))
		var count := mini(int(ceil(strength * profile.particle_gain)), 12)
		for i in count:
			if particles.size() >= 24:
				break
			var angle := -PI + PI * (float(i) + 0.5) / maxf(count, 1)
			particles.append({"p": point, "v": Vector2.from_angle(angle) * (35.0 + strength * 110.0), "age": 0.0, "life": 0.25 + strength * 0.35, "size": 1.0 + strength * 3.0})
		if profile.impact_ring:
			_ring = strength
			_ring_point = point

func _process(dt: float) -> void:
	_clock += dt
	_burst = maxf(_burst - dt, 0.0)
	_ring = maxf(_ring - dt * 2.0, 0.0)
	_thrust_t = maxf(_thrust_t - dt, 0.0)
	# flash envelope: full at the start, fading to zero; nothing once it has run out (no constant flame)
	var thrust := _thrust_level * (_thrust_t / maxf(_thrust_dur, 0.001)) if _thrust_t > 0.0 and not _rocket else 0.0
	var airborne := visual.launched and not visual.contacts.any_leg_contact and not visual.contacts.any_body_contact
	if airborne != _airborne:
		_airborne = airborne
		event("AIRBORNE" if airborne else "IDLE", clampf(visual.robot.linear_velocity.length() / 1800.0, 0.0, 1.0) if airborne else 0.0)
	var compression := false
	var exhaust_energy := 0.0
	for side in visual.legs:
		var lv: LegVisual = visual.legs[side]
		compression = compression or (lv.leg != null and lv.leg.in_contact and lv.leg.load_ratio > 0.15)
		if lv.exhaust:
			lv.exhaust.intensity = thrust if lv.leg != null and lv.leg.attached else 0.0
			exhaust_energy = maxf(exhaust_energy, lv.exhaust.intensity)
	if _compressing and not compression and visual.launched:
		event("SPRING_RELEASE", clampf(visual.robot.linear_velocity.length() / 1600.0, 0.0, 1.0))
	_compressing = compression
	if visual.charge_ratio >= 0.999 and not _full:
		event("FULL_CHARGE", 0.7)
	_full = visual.charge_ratio >= 0.999
	var sound_tick := int(_clock * 8.0) != int((_clock - dt) * 8.0)
	if sound_tick and exhaust_energy > 0.035:
		var thrust_event := "LEG_THRUST_LOW" if exhaust_energy < 0.55 else "LEG_THRUST_STRONG"
		presentation_event.emit(thrust_event, clampf(exhaust_energy, 0.0, 1.0), profile.sound_hook(thrust_event))
	if _rocket and sound_tick and is_instance_valid(_rocket_head):
		# Sustained hook is throttled; no repeated ignition or physical impact.
		presentation_event.emit("ROCKET_PHASE_ACTIVE", clampf(_rocket_head.linear_velocity.length() / 1800.0, 0.0, 1.0), profile.sound_hook("ROCKET_PHASE_ACTIVE"))
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.age += dt
		if p.age >= p.life:
			particles.remove_at(i)
		else:
			p.p += p.v * dt
			p.v.y += 240.0 * dt
	queue_redraw()

func _draw() -> void:
	for p in particles:
		var color := profile.particle_color
		color.a = 1.0 - float(p.age) / float(p.life)
		var local := to_local(p.p)
		if profile.particle_kind == "streak":
			draw_line(local, local - (p.v as Vector2).normalized() * p.size * 3.0, color, 1.5)
		else:
			draw_circle(local, p.size, color)
	if _ring > 0.0:
		var color := profile.particle_color
		color.a = _ring * 0.6
		draw_arc(to_local(_ring_point), 12.0 + (1.0 - _ring) * 28.0, PI, TAU, 12, color, 2.0)
