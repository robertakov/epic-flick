class_name SpringContactController
extends Node
## Geometric contact system: spring legs (left / right / both), torso and head contacts.
##
## Each attached leg casts three rays (heel / centre / toe) along the robot's leg axis. Ground inside
## the leg reach compresses the coil; the coil pushes the body along the leg axis with
## F = k*x + c*v (stiffer on extension by a per-landing "gain"), limited by a friction cone around the
## ground normal. Forces act at the hip, so one-foot landings create real torque.
##
## A landing EVENT starts on the first contact after being airborne. A second foot that touches within
## `both_feet_window` turns it into a two-foot landing. The event type decides the release effects:
##   left  -> braking along the surface while the left coil is loaded
##   right -> forward push along the surface while the right coil is loaded
##   both  -> flat (|lean| < flat_angle): huge vertical-ish bounce, tangential speed cut
##            sweet (forward lean in [sweet_min, sweet_max] vs. the normal): strong forward+up impulse
##            otherwise: good normal bounce
##   poor  -> legs far from the normal: weak spring return
## Body/head contacts give a weak, spin-heavy bounce.
##
## Damage zones: every zone (leg_l, leg_r = boot sole reached by the leg rays; torso, head, arm_l, arm_r =
## collision shapes, identified through their shape owner's "zone" meta) reports zone_contact when it
## starts touching the ground, with the normal impact speed of that exact point. DamageController turns
## these into collision events.

signal touchdown(info: Dictionary)
signal landing(info: Dictionary)
signal body_hit(info: Dictionary)
signal zone_contact(zone: StringName, info: Dictionary)
## v36: a last leg whose detach was held back during its own charged landing may break off now (impulse applied).
signal deferred_detach(side: StringName, info: Dictionary)

var cfg: ContactConfig
var robot_cfg: RobotConfig
var body: RigidBody2D
var legs: Array[SpringLeg] = []
var spin_charge: SpinChargeController   # optional: every new contact spends the stored spin energy
## Charge spent by the current contact event, waiting to be applied (feet: at spring release).
var _pending := {}
var ground_mask := 1
var enabled := true

var _ray := PhysicsRayQueryParameters2D.new()
var _influence := 0.0
var _since_contact := 10.0
var _prev_vel := Vector2.ZERO
## Angular-velocity bookkeeping per landing event (telemetry): solver/collision change between steps,
## spring torque, rotation controller.
var _prev_w := 0.0
var dw_ctrl_step := 0.0
var _zone_contact := {}      # zone -> bool (shape zones)
var _zone_free_time := {}    # zone -> seconds since that zone last touched
var _shape_zone := {}        # shape index -> zone (cache)
var _accel := Vector2.ZERO

# landing event state
var _event_active := false
var _event_time := 0.0
var _no_contact_time := 0.0
var _event := {}

var any_leg_contact := false
var any_body_contact := false
var any_contact := false
## v30: a foot touches a chocolate pool in this step (biome visuals: chocolate dirt).
var in_chocolate := false
## v32: momentum chain of this robot (px/s of forward boost, see MomentumRules). Starts at 0 with every robot.
var momentum := 0.0
## Zones touching the ground in THIS physics step: zone -> {point, normal, impact}. Rebuilt every step;
## DamageController reads it (damage while vulnerable, even on continuous or slow contact).
var touching := {}
## v36 last-leg charged landing: side -> damage info of a final leg that broke in the same step it made a valid
## charged feet landing. Order: contact -> classification -> bounce impulse (spring release + charge) -> detach.
var _deferred := {}


func setup(p_body: RigidBody2D, p_cfg: ContactConfig, p_robot_cfg: RobotConfig) -> void:
	body = p_body
	cfg = p_cfg
	robot_cfg = p_robot_cfg
	_ray.collision_mask = ground_mask
	_ray.exclude = [body.get_rid()]
	_ray.hit_from_inside = false


func add_leg(leg: SpringLeg) -> void:
	leg.length = cfg.coil_rest_length
	legs.append(leg)


func get_leg(side: StringName) -> SpringLeg:
	for l in legs:
		if l.side == side:
			return l
	return null


func angular_influence() -> float:
	return _influence


func integrate(state: PhysicsDirectBodyState2D) -> void:
	var dt := state.step
	_accel = (state.linear_velocity - _prev_vel) / dt
	var dw_solver := state.angular_velocity - _prev_w   # collision response + damping since our last step
	var w_before_springs := state.angular_velocity
	var xf := state.transform
	var axis := xf.y.normalized()
	var space := state.get_space_state()

	var touched_now: Array[StringName] = []
	any_leg_contact = false
	touching.clear()
	for leg in legs:
		if not leg.attached:
			continue
		var was := leg.in_contact
		_update_leg(leg, state, xf, axis, space, dt)
		if leg.in_contact:
			any_leg_contact = true
			touching[leg.side] = {"point": leg.ground_point, "normal": leg.ground_normal, "impact": maxf(leg.compression_vel, 0.0)}
			if not was:
				touched_now.append(leg.side)

	var dw_spring := state.angular_velocity - w_before_springs
	var bc := _scan_body_contacts(state, dt)
	# body / head contacts: the rigid-body solver changed the spin since our last step - keep only the scaled share
	if bc.any and absf(dw_solver) > 0.0:
		var ks := _body_spin_k(bc.head)
		state.angular_velocity -= dw_solver * (1.0 - ks)
		dw_solver *= ks
	any_body_contact = bc.any
	var contact_now := any_leg_contact or any_body_contact
	any_contact = contact_now
	# v30 chocolate pools (scoped biome mechanic, inactive elsewhere): feet standing in liquid chocolate are slowed
	# along the surface; the robot can always leave (the pool only resists, the gravity / spring push still works)
	in_chocolate = false
	if any_leg_contact and BiomeRuntime.current().chocolate:
		for leg in legs:
			if leg.attached and leg.in_contact and BiomeRuntime.surface_at(leg.ground_point.x) == &"chocolate":
				var tn := Vector2(-leg.ground_normal.y, leg.ground_normal.x)
				var vt := state.linear_velocity.dot(tn)
				state.linear_velocity -= tn * vt * (1.0 - exp(-BiomeRuntime.CHOCO_DRAG * dt))
				in_chocolate = true
				break

	if contact_now:
		_no_contact_time = 0.0
		_since_contact = 0.0
		if not _event_active:
			_start_event(state, axis, touched_now, bc)
		elif _event_time <= cfg.both_feet_window and not touched_now.is_empty():
			_add_feet(touched_now, state, axis)
		if _event_active and bc.any:
			_event["had_body"] = true
	else:
		_since_contact += dt
		if _event_active:
			_no_contact_time += dt
			if _no_contact_time >= cfg.contact_release_time:
				_end_event(state)
	if _event_active:
		_event_time += dt
		_event["dw_spring"] = _event.get("dw_spring", 0.0) + dw_spring
		_event["dw_solver"] = _event.get("dw_solver", 0.0) + dw_solver
		_event["dw_ctrl"] = _event.get("dw_ctrl", 0.0) + dw_ctrl_step
		# feet boost normally rides the spring release; a long slide on the feet gets it anyway
		if not _pending.is_empty() and spin_charge and _event_time >= spin_charge.cfg.feet_release_timeout:
			_apply_pending(state)
	# v36: the held-back last leg breaks off as soon as its landing impulse has been applied
	if not _deferred.is_empty() and (_pending.is_empty() or not _event_active):
		var held := _deferred
		_deferred = {}
		for side in held:
			deferred_detach.emit(side, held[side])

	if contact_now:
		# impact: contact torques dominate; long resting contact: let the spin roll the robot along
		var k := clampf((_event_time - 0.25) / 0.3, 0.0, 1.0)
		_influence = lerpf(robot_cfg.collision_angular_influence, robot_cfg.resting_contact_influence, k)
	else:
		_influence = robot_cfg.collision_angular_influence * clampf(1.0 - _since_contact / maxf(robot_cfg.collision_influence_time, 0.001), 0.0, 1.0)


## Store velocity after all modifications so next step can measure impact speed.
func post_step(state: PhysicsDirectBodyState2D) -> void:
	_prev_vel = state.linear_velocity
	_prev_w = state.angular_velocity


func _cast(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	_ray.from = from
	_ray.to = to
	return space.intersect_ray(_ray)


func _update_leg(leg: SpringLeg, state: PhysicsDirectBodyState2D, xf: Transform2D, axis: Vector2,
		space: PhysicsDirectSpaceState2D, dt: float) -> void:
	var hip_w := xf * leg.hip
	var perp := Vector2(-axis.y, axis.x)
	var reach := leg.reach(cfg)
	# probe as far as the leg currently is (a free leg stretched by spin touches earlier)
	var probe := leg.cap_len + maxf(leg.length, cfg.coil_rest_length) + leg.boot_len
	var best := INF
	var n := Vector2.UP
	var pt := Vector2.ZERO
	for o in [-cfg.foot_half_width, 0.0, cfg.foot_half_width]:
		var base: Vector2 = hip_w + perp * o
		var hit := _cast(space, base - axis * 6.0, base + axis * probe)
		if hit:
			var d: float = (hit.position - base).dot(axis)
			if d < best:
				best = d
				n = hit.normal
				pt = hit.position
	if best >= probe:
		if leg.in_contact:
			leg.in_contact = false
			leg.length_vel = -leg.compression_vel
		leg.compression = 0.0
		leg.load_ratio = 0.0
		# felt axial acceleration: frame accel minus gravity minus centrifugal (spinning flings legs out)
		var wv := state.angular_velocity
		var foot_r := leg.hip.y + leg.cap_len + leg.length
		leg.step_free(cfg, dt, (_accel - state.total_gravity).dot(axis) - wv * wv * foot_r)
		return

	var up := -axis
	var r := hip_w - xf.origin
	var w := state.angular_velocity
	var v_hip := state.linear_velocity + Vector2(-w * r.y, w * r.x)
	var comp := reach - maxf(best, 0.0)
	var comp_vel := v_hip.dot(axis)
	var max_c := cfg.coil_rest_length - cfg.coil_min_length
	var m := 1.0 / maxf(state.inverse_mass, 0.0001)
	var k := cfg.spring_stiffness

	if not leg.in_contact:
		leg.in_contact = true
		leg.bottomed = false
		leg.peak_load = 0.0
		leg.contact_time = 0.0
		var nn := n if n.dot(Vector2.UP) >= 0.0 else -n
		var rp := pt - xf.origin
		var vp := _prev_vel + Vector2(-w * rp.y, w * rp.x)
		zone_contact.emit(leg.side, {"impact": maxf(-vp.dot(nn), 0.0), "normal": nn, "point": pt})
	leg.contact_time += dt

	var gain := _gain_for(leg.side)
	var eff_comp := comp
	var weak_valid_feet: bool = _event_active and _event.get("type", &"") in [&"left", &"right", &"both"] \
		and _pending.is_empty() and not any_body_contact and not _event.get("had_body", false) \
		and _all_legs_attached() and leg.peak_load * max_c < cfg.min_natural_extension_comp
	if weak_valid_feet and (comp_vel < 0.0 or (leg.contact_time >= 0.025 and comp_vel <= 25.0)):
		eff_comp = maxf(comp, cfg.min_natural_extension_comp)
	var spring := k * minf(eff_comp, max_c)
	if comp_vel < 0.0 or (weak_valid_feet and eff_comp > comp):
		spring *= gain * cfg.spring_power_scale
	var zeta := cfg.damping_ratio_compress if comp_vel > 0.0 else cfg.damping_ratio_extend
	var f := spring + 2.0 * zeta * sqrt(k * m) * comp_vel
	if comp <= 0.0:
		f = 0.0   # extended past rest length: the coil touches but does not push yet
	if comp > max_c:
		# bottom-out: very stiff, well damped stop -> harsh landing
		f += cfg.bottom_out_stiffness * (comp - max_c) + 2.0 * 0.6 * sqrt(cfg.bottom_out_stiffness * m) * maxf(comp_vel, 0.0)
		leg.bottomed = true
	f = maxf(f, 0.0)

	var force := up * f
	var fn := force.dot(n)
	if fn <= 0.0:
		force = Vector2.ZERO
	else:
		var ft := force - n * fn
		var lim := cfg.foot_friction * fn
		if ft.length() > lim:
			ft = ft.normalized() * lim
		force = n * fn + ft

	# Gameplay: left foot brakes, right foot pushes forward, while their coil is loaded.
	var load := clampf(comp / max_c, 0.0, 1.0)
	var tangent := Vector2(-n.y, n.x)
	if tangent.x < 0.0:
		tangent = -tangent
	var et: StringName = _event.get("type", &"") if _event_active else &""
	var extra := Vector2.ZERO
	if et == &"left" and leg.side == &"leg_l":
		var vt := state.linear_velocity.dot(tangent)
		var dv := minf(cfg.left_brake_accel * load * dt, absf(vt))
		extra -= tangent * signf(vt) * dv * m / dt
	elif et == &"right" and leg.side == &"leg_r":
		extra += tangent * cfg.right_boost_accel * load * m

	state.linear_velocity += (force + extra) / m * dt
	# angular side effect of the spring push (main source of the counter-clockwise kick after a forward-lean landing)
	var torque := (r.x * force.y - r.y * force.x) * cfg.spring_torque_scale * cfg.bounce_spin_scale * cfg.bounce_spin_feet
	state.angular_velocity += torque * state.inverse_inertia * dt

	leg.compression = comp
	leg.compression_vel = comp_vel
	leg.load_ratio = load
	leg.peak_load = maxf(leg.peak_load, load)
	leg.ground_normal = n
	leg.ground_point = pt
	leg.length = clampf(cfg.coil_rest_length - comp, cfg.coil_min_length * 0.55, cfg.coil_max_length)
	leg.length_vel = -comp_vel


func _gain_for(side: StringName) -> float:
	if not _event_active:
		return 1.0
	match _event.get("type", &""):
		&"left":
			return cfg.gain_left
		&"right":
			return cfg.gain_right
		&"both":
			match _event.get("quality", &""):
				&"flat":
					return cfg.gain_both_flat
				&"sweet":
					return cfg.gain_both_sweet
			return cfg.gain_both_normal
		&"poor":
			return cfg.gain_poor
	return 1.0


func _zone_of_shape(shape: int) -> StringName:
	if not _shape_zone.has(shape):
		var owner_id := body.shape_find_owner(shape)
		var node := body.shape_owner_get_owner(owner_id) as Node
		_shape_zone[shape] = StringName(node.get_meta(&"zone", &"torso")) if node else &"torso"
	return _shape_zone[shape]


## Real physical contacts of the body shapes (solver contacts, not proximity).
func _scan_body_contacts(state: PhysicsDirectBodyState2D, dt: float) -> Dictionary:
	var res := {"any": false, "torso": false, "head": false, "zones": [], "normal": Vector2.UP, "point": Vector2.ZERO}
	var now := {}
	var data := {}
	for i in state.get_contact_count():
		var obj := state.get_contact_collider_object(i)
		if obj == null or not (obj as Node).is_in_group(&"ground"):
			continue
		var zone := _zone_of_shape(state.get_contact_local_shape(i))
		var n := state.get_contact_local_normal(i)
		if n.dot(Vector2.UP) < 0.0:
			n = -n
		var p := state.get_contact_local_position(i)
		var r := p - state.transform.origin
		var w := state.angular_velocity
		var vp := _prev_vel + Vector2(-w * r.y, w * r.x)
		var impact := maxf(-vp.dot(n), 0.0)
		if not now.has(zone) or impact > data[zone].impact:
			now[zone] = true
			data[zone] = {"impact": impact, "normal": n, "point": p}
		res.any = true
		res.normal = n
		res.point = p
	for z in data:
		touching[z] = data[z]
	res.torso = now.has(&"torso")
	res.head = now.has(&"head")
	res.zones = now.keys()
	for zone in [&"torso", &"head", &"arm_l", &"arm_r"]:
		var touching: bool = now.has(zone)
		if touching:
			if not _zone_contact.get(zone, false):
				var d: Dictionary = data[zone]
				zone_contact.emit(zone, d.duplicate())
				# cartoon reaction + weak geometric bounce, once per real impact of torso/head
				if _zone_free_time.get(zone, 10.0) > 0.12 and d.impact > 1.0:
					if zone == &"torso" or zone == &"head":
						_body_kick(state, d.normal, d.impact)
					body_hit.emit({"kind": zone, "impact": d.impact, "normal": d.normal, "point": d.point,
						"velocity": _prev_vel})
			_zone_free_time[zone] = 0.0
		else:
			_zone_free_time[zone] = _zone_free_time.get(zone, 10.0) + dt
		_zone_contact[zone] = touching
	return res


func _body_spin_k(head: bool) -> float:
	return cfg.bounce_spin_scale * (cfg.bounce_spin_head if head else cfg.bounce_spin_body)


func is_zone_in_contact(zone: StringName) -> bool:
	if zone == &"leg_l" or zone == &"leg_r":
		var l := get_leg(zone)
		return l != null and l.attached and l.in_contact
	return _zone_contact.get(zone, false)


## Weak, geometry-driven bounce for a bad (body/head) contact: some pop along the normal and spin
## from the tangential slide. No randomness.
func _body_kick(state: PhysicsDirectBodyState2D, n: Vector2, impact: float) -> void:
	if n.dot(Vector2.UP) < 0.0:
		n = -n
	state.linear_velocity += n * impact * cfg.body_hit_kick
	var tangent := Vector2(-n.y, n.x)
	var slide := _prev_vel.dot(tangent)
	state.angular_velocity += clampf(slide / 600.0, -1.0, 1.0) * cfg.body_hit_spin * _body_spin_k(_zone_contact.get(&"head", false))


func _lean(axis: Vector2, n: Vector2) -> float:
	# signed angle from the surface normal to the robot's up axis; + = leaning forward (clockwise)
	return rad_to_deg(n.angle_to(-axis))


func _start_event(state: PhysicsDirectBodyState2D, axis: Vector2, touched: Array[StringName], bc: Dictionary) -> void:
	_event_active = true
	_event_time = 0.0
	var n: Vector2 = bc.normal
	var pos: Vector2 = bc.point
	if not touched.is_empty():
		var leg := get_leg(touched[0])
		n = leg.ground_normal
		pos = leg.ground_point
	if n.dot(Vector2.UP) < 0.0:
		n = -n
	var lean := _lean(axis, n)
	var impact := absf(_prev_vel.dot(n))
	_event = {"type": &"body", "quality": &"", "impact": impact, "normal": n, "point": pos, "lean": lean,
		"w_in": _prev_w, "up": -axis, "first": touched[0] if not touched.is_empty() else &"", "time": Time.get_ticks_msec(),
		"speed_in": _prev_vel.length(), "contact_x": state.transform.origin.x, "charge_ratio": 0.0, "had_body": bc.any}
	if touched.size() >= 2:
		_classify_both(lean)
	elif touched.size() == 1:
		if absf(lean) > cfg.poor_angle:
			_event.type = &"poor"
		else:
			_event.type = &"left" if touched[0] == &"leg_l" else &"right"
	var valid_low_feet: bool = _event.type in [&"left", &"right", &"both"] and not bc.any and _all_legs_attached() and minf(_prev_vel.dot(n), state.linear_velocity.dot(n)) <= -15.0
	if impact < cfg.min_landing_speed and not valid_low_feet:
		# resting / rolling contact: plain spring, no landing modifiers
		_event.type = &"soft"
		_event.quality = &""
	# spin charge: EVERY new contact (also soft / grazing) spends the whole charge, once per event
	_pending = {}
	if spin_charge:
		var zc := _first_zone_class(touched, bc)
		var stored := spin_charge.ratio()
		_event["charge_ratio"] = stored
		var eff := spin_charge.consume(zc)
		_event["charge_zone"] = zc
		if eff > 0.0:
			_pending = {"eff": eff, "stored": stored, "zone_class": zc}
			_event["spin_bonus"] = eff
			if zc != &"feet":
				_apply_pending(state)   # no spring to ride: the (weak) push happens right away
	touchdown.emit(_event.duplicate())


func _add_feet(touched: Array[StringName], state: PhysicsDirectBodyState2D, axis: Vector2) -> void:
	var t: StringName = _event.type
	if t == &"soft":
		return
	if (t == &"left" and touched.has(&"leg_r")) or (t == &"right" and touched.has(&"leg_l")) \
			or (t == &"body" and touched.size() >= 2):
		_classify_both(_event.lean)
		touchdown.emit(_event.duplicate())
	elif t == &"body" and touched.size() == 1:
		_event.type = &"left" if touched[0] == &"leg_l" else &"right"


## Zone class that touched first in this new contact: feet if a leg touched, otherwise the worst body zone.
func _first_zone_class(touched: Array[StringName], bc: Dictionary) -> StringName:
	if not touched.is_empty():
		return &"feet"
	var zones: Array = bc.get("zones", [])
	if zones.has(&"head"):
		return &"head"
	if zones.has(&"torso"):
		return &"side"
	if zones.has(&"arm_l") or zones.has(&"arm_r"):
		return &"arm"
	return &"feet"   # legs already resting on the ground when the event opened


## Adds the pending spin boost to the body velocity (bounded) and reports it.
func _apply_pending(state: PhysicsDirectBodyState2D) -> void:
	var p := _pending
	_pending = {}
	var n: Vector2 = _event.get("normal", Vector2.UP)
	var t := Vector2(-n.y, n.x)
	var fwd := t if t.x >= 0.0 else -t
	var up := -state.transform.y.normalized()
	var v := state.linear_velocity
	var spring_landing: bool = p.zone_class==&"feet" and _event.get("type",&"") in [&"left",&"right",&"both",&"poor"]
	var cap_scale := sqrt(cfg.spring_power_scale) if spring_landing else 1.0
	var out := spin_charge.clamp_out(v + spin_charge.boost_vector(p.eff, n, up, fwd), n, p.eff, cfg, cap_scale)
	state.linear_velocity = out
	spin_charge.notify_applied(p.stored, out - v, {"zone_class": p.zone_class, "effective": p.eff, "charge": p.stored,
		"point": _event.get("point", body.global_position), "normal": n, "type": _event.get("type", &"")})


func _classify_both(lean: float) -> void:
	_event.type = &"both"
	if absf(lean) <= cfg.flat_angle:
		_event.quality = &"flat"
	elif lean >= cfg.sweet_angle_min and lean <= cfg.sweet_angle_max:
		_event.quality = &"sweet"
	elif absf(lean) > cfg.poor_angle:
		_event.type = &"poor"
		_event.quality = &""
	else:
		_event.quality = &"normal"


## v36: called by RobotController when damage removes `side`. The FINAL attached leg, touching the ground in a valid
## (left / right / both) feet landing that holds a pending feet charge, keeps working as a spring until that landing
## releases (its bounce + charge impulse are applied first) and only then detaches. Returns true when held back.
func defer_last_leg_detach(side: StringName, info: Dictionary) -> bool:
	var leg := get_leg(side)
	if leg == null or not leg.attached or not leg.in_contact or not _event_active:
		return false
	if _event.get("type", &"") not in [&"left", &"right", &"both"] or _pending.is_empty() or _pending.get("zone_class", &"") != &"feet":
		return false
	for l in legs:
		if l != leg and l.attached:
			return false
	_deferred[side] = info
	return true


func has_deferred_detach() -> bool:
	return not _deferred.is_empty()


func _all_legs_attached() -> bool:
	for l in legs:
		if not l.attached:
			return false
	return not legs.is_empty()


func _end_event(state: PhysicsDirectBodyState2D) -> void:
	_event_active = false
	var n: Vector2 = _event.normal
	var tangent := Vector2(-n.y, n.x)
	var v := state.linear_velocity
	if _event.type == &"both" and _event.quality == &"flat":
		var vt := v.dot(tangent)
		v -= tangent * vt * (1.0 - cfg.flat_tangent_keep)
	elif _event.type == &"both" and _event.quality == &"sweet":
		var up: Vector2 = _event.up
		v += up * minf(_event.impact * cfg.sweet_impulse_factor, cfg.sweet_impulse_max) * sqrt(cfg.spring_power_scale)
	# Spring return energy scales as power; velocity ceilings scale as sqrt(energy).
	# Body/poor-body contacts retain their original guards. Charge is applied afterwards unchanged.
	var feet: bool = _event.type in [&"left", &"right", &"both", &"poor"]
	var power_speed := sqrt(cfg.spring_power_scale) if feet else 1.0
	var valid_feet: bool = _event.type in [&"left", &"right", &"both"]
	# v32: robot jump specialisation (Kengurobot), valid feet only: 1.0 for every other robot = unchanged rules
	var jump: float = clampf(cfg.rebound_power, 0.5, 2.0) if valid_feet else 1.0
	var min_rebound := cfg.min_natural_rebound_speed * power_speed * jump if (valid_feet and _pending.is_empty() and not _event.get("had_body", false) and _all_legs_attached()) else 0.0
	# energy guard: a short landing can never return more speed than its type allows
	if _event.type != &"soft" and _event_time < 0.45:
		var key: String = String(_event.type) if _event.type != &"both" else "both/" + String(_event.quality)
		var ratio: float = cfg.max_speed_ratio.get(key, 1.0)
		var limit: float = maxf((_event.speed_in * ratio + cfg.speed_ratio_slack) * power_speed * jump, min_rebound)
		if v.length() > limit:
			v = v.normalized() * limit
	var vn := v.dot(n)
	if jump != 1.0 and vn > 0.0:
		# stronger natural spring: more speed ALONG THE NORMAL only (higher, not faster)
		v += n * (vn * jump - vn)
		vn *= jump
	if min_rebound > 0.0 and vn < min_rebound:
		v += n * (min_rebound - vn)
		vn = min_rebound
	if vn > cfg.max_release_normal_speed * power_speed * jump:
		v -= n * (vn - cfg.max_release_normal_speed * power_speed * jump)
	if v.length() > cfg.max_release_speed * power_speed:
		v = v.normalized() * cfg.max_release_speed * power_speed
	state.linear_velocity = v
	if not _pending.is_empty():
		_apply_pending(state)
		v = state.linear_velocity
	# v30 biome surface (scoped modifier; exactly 1.0 in Green Hills): jelly amplifies, heavy world weakens and
	# chocolate resists the rebound of a valid feet landing, applied on top of the normal spring + charge result.
	if valid_feet:
		var px: float = (_event.get("point", body.global_position) as Vector2).x
		var mod := BiomeRuntime.feet_release(px)
		var vn_out := v.dot(n)
		if mod != 1.0 and vn_out > 0.0:
			var target := vn_out * mod
			if mod > 1.0:
				target = minf(target, maxf(vn_out, cfg.max_release_normal_speed * power_speed * BiomeRuntime.rebound_cap(px)))
			elif BiomeRuntime.surface_at(px) == &"chocolate":
				target = maxf(target, minf(vn_out, BiomeRuntime.CHOCO_MIN_EXIT))
			v += n * (target - vn_out)
			if is_finite(v.x) and is_finite(v.y):
				state.linear_velocity = v
			else:
				v = state.linear_velocity
	# v32 momentum: every classified landing updates the chain; valid feet releases get a FORWARD-only push
	# (never vertical), faded by the robot's forward cap and held to the existing release-speed guard.
	momentum = MomentumRules.update(momentum, _event, cfg.momentum_gain, cfg.momentum_max)
	var m_boost := 0.0
	if valid_feet and momentum > 0.0:
		var fwd := MomentumRules.forward_tangent(n)
		m_boost = MomentumRules.boost(momentum, v.dot(fwd), cfg.momentum_forward_cap)
		if m_boost > 0.0:
			var guard := maxf(v.length(), cfg.max_release_speed * power_speed)
			var boosted := v + fwd * m_boost
			if boosted.length() > guard:
				boosted = boosted.normalized() * guard
			if is_finite(boosted.x) and is_finite(boosted.y):
				m_boost = boosted.dot(fwd) - v.dot(fwd)
				v = boosted
				state.linear_velocity = v
			else:
				m_boost = 0.0
	_event["momentum"] = momentum
	_event["momentum_boost"] = m_boost
	_event["speed_out"] = v.length()
	_event["velocity_out"] = v
	_event["duration"] = _event_time
	_event["w_out"] = state.angular_velocity
	landing.emit(_event.duplicate())
