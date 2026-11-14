class_name BiomeHazards
extends Node2D
## Runtime biome mechanics that need per-step checks on the active bodies (player robot / jet head and every
## race opponent): portals (Portal Zone), anomalies (Exclusion Zone), chocolate dirt, jelly ripples.
## Everything is generated deterministically from the track seed while the terrain streams, and freed far behind.
## Inactive (no nodes, no work) in Green Hills and every biome without these features.
##
## v36 PLACEMENT (both biomes): heights are relative to the LOCAL terrain and drawn from bands measured on real
##   AI flight trajectories (reports/v36: centre altitude p25 ~400 px, median ~1000, p75 ~1900, p90 ~2700):
##   low (radius+90 .. 520), medium (520 .. 1300), high (1300 .. 2300) - see height_band().
## PORTALS (v36): explicit one-way PAIRS, entry first, exit 1100..2200 px further down the track, one pair every
##   ~2400..4400 px. Entry ellipse 150x240 (was 70x115). Pair kinds: helpful 45 % (exit 350..750 px higher),
##   harmful 30 % (exit 350..650 px lower), neutral 25 % (+-150). The ENTRY arrow shows the outcome (up / down /
##   level); the EXIT arrow is the launch direction (speed kept, clamped 650..2400 px/s, spin kept). Exit portals do
##   not capture (no loops, no ping-pong). Exit protection: 0.8 s cooldown AND the body must leave the exit (1.5x).
##   Every exit keeps >= EXIT_CLEAR px above the highest ground within +-300 px.
## ANOMALIES (Exclusion Zone), one every 1300..2100 px, never two overlapping, never on the launch area:
##   ELECTRIC  r=200 (was 80): on entry ELECTRIC_DMG HP (normal limb / jet-head rules; respects the post-hit /
##             continue invulnerability window) + a shove away + spin charge set to 100 % at once.
##   RADIATION cloud rx=280 ry=160 (was 170x105): 60 % ground pools, 40 % floating clouds (medium band): 4 HP on
##             entry, then 6 HP/s while inside and 1.5 s after leaving (glow + green tint + -N numbers).
##   GRAVITY   r=210 (was 90): entered from BELOW -> vertical speed set to -2000 (thrown up), from ABOVE -> +2000
##             (slammed down). No damage itself.
##   anomaly_hit(body, kind, point) is emitted on every entry (GameManager turns it into player feedback).

const PORTAL_RX := 150.0
const PORTAL_RY := 240.0
const PORTAL_RANGE := 3600.0
const PORTAL_COOLDOWN := 0.8
const EXIT_CLEAR := 420.0              # exit centre above the highest ground within +-300 px (robot fits below)
const ELECTRIC_R := 200.0
## BALANCE TODO (not approved): the electric HP damage is the pre-v36 value, kept configurable here.
const ELECTRIC_DMG := 22.0
const RAD_RX := 280.0
const RAD_RY := 160.0
const RAD_ENTRY := 4.0
const RAD_DPS := 6.0
const RAD_LINGER := 1.5
const GRAV_R := 210.0
const GRAV_SPEED := 2000.0
const BODY_R := 55.0                   # robot torso radius used for hazard overlap

var terrain: TerrainBuilder
var biome: BiomeDef
var bodies_provider: Callable          # -> Array[RigidBody2D] (active player body + opponents)
var fx: Fx
var portals: Array = []                # {pos, dir (exit launch), node, partner (-1 = exit only), arrow, band}
var anomalies: Array = []              # {kind, pos, node, band}
signal anomaly_hit(body: RigidBody2D, kind: String, point: Vector2)
var _gen_x := 0.0
var _rng := RandomNumberGenerator.new()
## v36: portal exit picks use their OWN stream. Sharing _rng with the streamed generation made the exit choice depend
## on how far ahead the track had been generated at that moment (camera / frame timing) - fast-forward could change it.
var _tp_rng := RandomNumberGenerator.new()
var _state := {}                       # body instance id -> {cool, inside_exit, ...}
## Telemetry for tests.
var teleports := 0
var last_teleport := {}


func reset(p_biome: BiomeDef, p_terrain: TerrainBuilder, track_seed: int) -> void:
	clear()
	biome = p_biome
	terrain = p_terrain
	_rng.seed = hash([track_seed, "hazards", biome.id])
	_tp_rng.seed = hash([track_seed, "portal_exit", biome.id])
	_gen_x = terrain.ledge_end_x + 1500.0
	set_physics_process(biome.portals or biome.anomalies or biome.chocolate or biome.jelly)


func clear() -> void:
	for p in portals:
		if is_instance_valid(p.node):
			p.node.queue_free()
	for a in anomalies:
		if is_instance_valid(a.node):
			a.node.queue_free()
	portals.clear()
	anomalies.clear()
	_state.clear()
	teleports = 0
	last_teleport = {}
	BiomeProps.ripples.clear()
	set_physics_process(false)


func _generate() -> void:
	if terrain == null or terrain.points.is_empty():
		return
	var limit := terrain.end_x() - 600.0
	while _gen_x < limit:
		if biome.portals:
			_gen_x += _rng.randf_range(1300.0, 2200.0)
			var exit_x := _gen_x + _rng.randf_range(1100.0, 2200.0)
			if exit_x >= limit:
				_gen_x -= 1.0   # retry this pair once more track exists (same RNG order: deterministic)
				break
			var hb := height_band(_rng, PORTAL_RY, 0.2, 0.5)
			var entry := Vector2(_gen_x, _ground_top(_gen_x) - float(hb.h))
			entry.y = minf(entry.y, _ground_top(_gen_x) - EXIT_CLEAR)
			var roll := _rng.randf()
			var kind := "helpful" if roll < 0.45 else ("harmful" if roll < 0.75 else "neutral")
			var rise := _rng.randf_range(350.0, 750.0) if kind == "helpful" else (-_rng.randf_range(350.0, 650.0) if kind == "harmful" else _rng.randf_range(-150.0, 150.0))
			var exit_alt := clampf((_ground_top(exit_x) - entry.y) + rise, EXIT_CLEAR, 2600.0)
			var exit := Vector2(exit_x, _ground_top(exit_x) - exit_alt)
			var ang := deg_to_rad(_rng.randf_range(-42.0, -18.0))
			var hue := _rng.randf()
			# the entry arrow tells the truth about the trip: up / down / level (world height of the exit vs entry)
			var dy := exit.y - entry.y
			var arrow := Vector2.RIGHT.rotated(deg_to_rad(-40.0) if dy < -200.0 else (deg_to_rad(38.0) if dy > 200.0 else 0.0))
			var ei := portals.size()
			portals.append(_add_portal(entry, arrow, hue, ei + 1, arrow, String(hb.band), false))
			portals.append(_add_portal(exit, Vector2.RIGHT.rotated(ang), hue, -1, Vector2.RIGHT.rotated(ang), kind, true))
			_gen_x = exit_x
		elif biome.anomalies:
			_gen_x += _rng.randf_range(1300.0, 2100.0)
			if _gen_x >= limit:
				break
			var kind: String = ["electric", "radiation", "gravity"][_rng.randi_range(0, 2)]
			var pos2: Vector2
			var band := "ground"
			match kind:
				"electric":
					var b1 := height_band(_rng, ELECTRIC_R, 0.25, 0.45)
					pos2 = Vector2(_gen_x, _ground_top(_gen_x) - float(b1.h)); band = String(b1.band)
				"radiation":
					if _rng.randf() < 0.6:
						pos2 = Vector2(_gen_x, terrain.surface_y(_gen_x) - 40.0)
					else:
						pos2 = Vector2(_gen_x, _ground_top(_gen_x) - _rng.randf_range(520.0, 1300.0)); band = "medium"
				_:
					var b2 := height_band(_rng, GRAV_R, 0.25, 0.45)
					pos2 = Vector2(_gen_x, _ground_top(_gen_x) - float(b2.h)); band = String(b2.band)
			var an := AnomalyNode.new()
			an.kind = kind
			an.position = pos2
			an.terrain = terrain
			an.floating = band != "ground"
			an.z_index = 6 if (kind != "radiation" or band != "ground") else 3
			add_child(an)
			anomalies.append({"kind": kind, "pos": pos2, "node": an, "band": band})
		else:
			break


## Height band draw (centre altitude above the local ground): low radius+90..520 / medium 520..1300 / high 1300..2300.
static func height_band(rng: RandomNumberGenerator, radius: float, w_low: float, w_med: float) -> Dictionary:
	var u := rng.randf()
	if u < w_low:
		return {"h": rng.randf_range(radius + 90.0, maxf(radius + 100.0, 520.0)), "band": "low"}
	if u < w_low + w_med:
		return {"h": rng.randf_range(520.0, 1300.0), "band": "medium"}
	return {"h": rng.randf_range(1300.0, 2300.0), "band": "high"}


## Highest ground (smallest y) within +-300 px: heights are measured from it so nothing sits inside a crest.
func _ground_top(x: float) -> float:
	var top := terrain.surface_y(x)
	for o in [-300.0, -150.0, 150.0, 300.0]:
		top = minf(top, terrain.surface_y(x + o))
	return top


func _add_portal(pos: Vector2, dir: Vector2, hue: float, partner: int, arrow: Vector2, band: String, is_exit: bool) -> Dictionary:
	var node := PortalNode.new()
	node.position = pos
	node.facing = arrow
	node.hue = hue
	node.is_exit = is_exit
	node.z_index = 5
	add_child(node)
	return {"pos": pos, "dir": dir, "node": node, "partner": partner, "arrow": arrow, "band": band}


## Generate everything the streamed track already allows (normally done every physics step).
func generate_now() -> void:
	if terrain != null and (biome.portals or biome.anomalies):
		_generate()


## Adds one anomaly at `pos` (used to host the secret artifact when its stretch has none). Kept in x order.
func add_anomaly(kind: String, pos: Vector2) -> Dictionary:
	var an := AnomalyNode.new()
	an.kind = kind
	an.position = pos
	an.terrain = terrain
	an.floating = true
	an.z_index = 6
	add_child(an)
	var e := {"kind": kind, "pos": pos, "node": an, "band": "medium"}
	var i := 0
	while i < anomalies.size() and float(anomalies[i].pos.x) < pos.x:
		i += 1
	anomalies.insert(i, e)
	return e


func _recycle(behind_x: float) -> void:
	while not portals.is_empty() and float(portals[0].pos.x) < behind_x - 6000.0:
		var p: Dictionary = portals.pop_front()
		if is_instance_valid(p.node):
			p.node.queue_free()
	while not anomalies.is_empty() and float(anomalies[0].pos.x) < behind_x - 6000.0:
		var a: Dictionary = anomalies.pop_front()
		if is_instance_valid(a.node):
			a.node.queue_free()


func _physics_process(dt: float) -> void:
	if terrain == null:
		return
	if biome.portals or biome.anomalies:
		_generate()
	var bodies: Array = bodies_provider.call() if bodies_provider.is_valid() else []
	var min_x := INF
	var seen := {}
	for b in bodies:
		var body := b as RigidBody2D
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		seen[body.get_instance_id()] = true
		var p := body.global_position
		if not (is_finite(p.x) and is_finite(p.y)):
			continue
		min_x = minf(min_x, p.x)
		var st: Dictionary = _state.get(body.get_instance_id(), {})
		if st.is_empty():
			st = {"cool": 0.0, "exit": -1, "inside": {}, "rad": 0.0, "rad_tick": 0.0, "dirt": 0.0, "was_contact": true}
			_state[body.get_instance_id()] = st
		st.cool = maxf(0.0, float(st.cool) - dt)
		if biome.portals:
			step_portals(body, st)
		if biome.anomalies:
			step_anomalies(body, st, dt)
		if body is RobotController:
			_step_surface(body as RobotController, st, dt)
	# robots that left the active list (run ended, finished opponent) still wear their chocolate dirt off
	for id in _state:
		var st: Dictionary = _state[id]
		if seen.has(id) or float(st.get("dirt", 0.0)) <= 0.0:
			continue
		var r := instance_from_id(id) as RobotController
		if r == null or not is_instance_valid(r):
			continue
		st.dirt = maxf(0.0, float(st.dirt) - dt / 5.0)
		_tint(r, st)
	if is_finite(min_x):
		_recycle(min_x)


# ---------------- portals ----------------

func step_portals(body: RigidBody2D, st: Dictionary) -> void:
	var p := body.global_position
	var ex := int(st.exit)
	if ex >= 0 and ex < portals.size():
		if not _in_portal(p, portals[ex].pos, 1.5):
			st.exit = -1
		else:
			return
	if float(st.cool) > 0.0:
		return
	for i in portals.size():
		if int(portals[i].get("partner", -1)) >= 0 and _in_portal(p, portals[i].pos, 1.0):
			var dest := choose_destination(i)
			if dest >= 0:
				teleport(body, i, dest)
				st.cool = PORTAL_COOLDOWN
				st.exit = dest
			return


static func _in_portal(p: Vector2, c: Vector2, k: float) -> bool:
	var d := p - c
	return (d.x * d.x) / (PORTAL_RX * PORTAL_RX * k * k) + (d.y * d.y) / (PORTAL_RY * PORTAL_RY * k * k) <= 1.0


## v36: the fixed partner of an ENTRY portal (exit portals do not capture: -1). Never the entrance itself.
func choose_destination(entrance: int) -> int:
	if entrance < 0 or entrance >= portals.size():
		return -1
	var p := int(portals[entrance].get("partner", -1))
	return p if p >= 0 and p < portals.size() and p != entrance else -1


func teleport(body: RigidBody2D, from: int, to: int) -> void:
	var exit_pos: Vector2 = portals[to].pos
	var dir: Vector2 = portals[to].dir
	var speed := clampf(body.linear_velocity.length(), 650.0, 2400.0)
	var vel := dir * speed
	var xf := body.global_transform
	xf.origin = exit_pos + dir * 20.0
	PhysicsServer2D.body_set_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer2D.body_set_state(body.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, vel)
	body.global_transform = xf
	body.linear_velocity = vel
	teleports += 1
	last_teleport = {"from": from, "to": to, "body": body.get_instance_id(), "pos": xf.origin, "vel": vel}
	for k in [from, to]:
		if is_instance_valid(portals[k].node):
			portals[k].node.flash()
	if body.has_method("on_teleported"):
		body.call("on_teleported")
	teleported.emit(body)


signal teleported(body: RigidBody2D)


# ---------------- anomalies ----------------

func step_anomalies(body: RigidBody2D, st: Dictionary, dt: float) -> void:
	var p := body.global_position
	var inside: Dictionary = st.inside
	var robot := body as RobotController
	var in_rad := false
	for a in anomalies:
		var c: Vector2 = a.pos
		if absf(p.x - c.x) > 600.0:
			continue
		var key := int(a.node.get_instance_id()) if is_instance_valid(a.node) else 0
		var hit := false
		match String(a.kind):
			"electric": hit = p.distance_to(c) < ELECTRIC_R + BODY_R
			"gravity": hit = p.distance_to(c) < GRAV_R + BODY_R * 0.5
			"radiation":
				var d := p - c
				hit = (d.x * d.x) / (RAD_RX * RAD_RX) + (d.y * d.y) / ((RAD_RY + BODY_R) * (RAD_RY + BODY_R)) <= 1.0
		if not hit:
			inside.erase(key)
			continue
		var entered := not inside.has(key)
		inside[key] = true
		match String(a.kind):
			"electric":
				if entered:
					if robot:
						# v36: the post-hit / continue spawn protection also protects from the shock damage
						if not robot.damage.is_invulnerable():
							robot.damage.apply_external(ELECTRIC_DMG, &"electric", {"point": p, "normal": (p - c).normalized()})
						# v36: the discharge fills the spin charge to 100 % at once
						if robot.spin_charge:
							robot.spin_charge.fill()
					body.linear_velocity += (p - c).normalized() * 520.0
					if is_instance_valid(a.node): a.node.flash()
					anomaly_hit.emit(body, "electric", p)
			"gravity":
				if entered:
					# one anomaly type: the side of entry decides the throw
					var from_below := p.y > c.y
					body.linear_velocity = Vector2(body.linear_velocity.x, -GRAV_SPEED if from_below else GRAV_SPEED)
					if is_instance_valid(a.node): a.node.flash()
					anomaly_hit.emit(body, "gravity", p)
			"radiation":
				in_rad = true
				if entered:
					if robot:
						robot.damage.apply_external(RAD_ENTRY, &"radiation", {"point": p, "normal": Vector2.UP}, false)
					anomaly_hit.emit(body, "radiation", p)
				st.rad = RAD_LINGER
	if robot:
		if not in_rad:
			st.rad = maxf(0.0, float(st.rad) - dt)
		if float(st.rad) > 0.0 or in_rad:
			st.rad_tick = float(st.rad_tick) + dt
			if float(st.rad_tick) >= 0.5:
				st.rad_tick = 0.0
				robot.damage.apply_external(RAD_DPS * 0.5, &"radiation", {"point": p, "normal": Vector2.UP}, false)
		else:
			st.rad_tick = 0.0
		_tint(robot, st)


# ---------------- chocolate dirt / jelly ripples ----------------

func _step_surface(robot: RobotController, st: Dictionary, dt: float) -> void:
	if biome.chocolate:
		if robot.contacts.in_chocolate:
			st.dirt = minf(1.0, float(st.dirt) + dt * 2.2)
		else:
			st.dirt = maxf(0.0, float(st.dirt) - dt / 5.0)   # cleans off over ~5 s
		_tint(robot, st)
	if biome.jelly:
		var c := robot.contacts.any_leg_contact
		if c and not bool(st.was_contact):
			BiomeProps.push_ripple(robot.global_position.x, clampf(robot.linear_velocity.length() / 120.0, 4.0, 18.0))
		st.was_contact = c


## Temporary visual-only modulation of the robot (chocolate dirt / radiation glow). Never touches textures.
func _tint(robot: RobotController, st: Dictionary) -> void:
	if not is_instance_valid(robot.visual):
		return
	if not robot.has_meta("base_modulate"):
		robot.set_meta("base_modulate", robot.visual.modulate)
	var base: Color = robot.get_meta("base_modulate")
	var col := base
	var dirt := float(st.dirt)
	if dirt > 0.0:
		col = col * Color(1.0, 1.0, 1.0).lerp(Color(0.62, 0.40, 0.24), dirt * 0.75)
	if float(st.rad) > 0.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		col = col * Color(1.0, 1.0, 1.0).lerp(Color(0.55, 1.25, 0.45), 0.35 + 0.25 * pulse)
	robot.visual.modulate = col
	robot.visual.set_meta("chocolate_dirt", dirt)


func dirt_of(body: Node) -> float:
	var st: Dictionary = _state.get(body.get_instance_id(), {})
	return float(st.get("dirt", 0.0))


# ======================================================================================================

class PortalNode extends Node2D:
	var facing := Vector2.RIGHT
	var hue := 0.0
	var is_exit := false
	var _flash := 0.0

	func flash() -> void:
		_flash = 1.0

	func _process(dt: float) -> void:
		_flash = maxf(0.0, _flash - dt * 2.5)
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() * 0.001 + hue * 10.0
		var rx := BiomeHazards.PORTAL_RX
		var ry := BiomeHazards.PORTAL_RY
		# upright oval = the exact trigger ellipse; rhythmically distorting rings (squash pulse, counter-rotating dashes)
		var pulse := 1.0 + 0.06 * sin(t * 5.0) + 0.25 * _flash
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(pulse, 1.0 / pulse))
		_ellipse(rx + 18.0, ry + 18.0, Color(0.10, 0.07, 0.05), 14.0)
		_ellipse(rx + 18.0, ry + 18.0, Color(0.45, 1.0, 0.92), 8.0)
		_ellipse_fill(rx, ry, Color(0.12, 0.02, 0.22, 0.85) if not is_exit else Color(0.05, 0.14, 0.20, 0.7))
		for k in 3:
			var rr := 0.25 + 0.25 * k
			var spin := t * (2.0 - k * 0.5) * (1 if k % 2 == 0 else -1)
			for j in 6:
				var a0 := spin + j * TAU / 6.0
				var p0 := Vector2(cos(a0) * rx * rr, sin(a0) * ry * rr)
				var p1 := Vector2(cos(a0 + 0.5) * rx * rr, sin(a0 + 0.5) * ry * rr)
				draw_line(p0, p1, Color(1.0, 0.4, 0.9, 0.9) if k % 2 == 0 else Color(0.5, 1.0, 0.95, 0.9), 5.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# exit arrow showing the facing (where you come out)
		var tip := facing * (rx + 60.0)
		draw_line(facing * (rx + 26.0), tip, Color(0.10, 0.07, 0.05), 10.0)
		draw_line(facing * (rx + 26.0), tip, Color(1.0, 0.85, 0.3), 5.0)
		var side := Vector2(-facing.y, facing.x) * 12.0
		draw_colored_polygon(PackedVector2Array([tip + facing * 16.0, tip + side, tip - side]), Color(1.0, 0.85, 0.3))

	func _ellipse(rx: float, ry: float, col: Color, w: float) -> void:
		var pts := PackedVector2Array()
		for i in 33:
			var a := TAU * i / 32.0
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(pts, col, w, true)

	func _ellipse_fill(rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)


class AnomalyNode extends Node2D:
	var kind := "electric"
	var floating := false
	var terrain: TerrainBuilder
	var _flash := 0.0
	var _seed := 0

	func _ready() -> void:
		_seed = int(position.x) & 1023

	func flash() -> void:
		_flash = 1.0

	func _process(dt: float) -> void:
		_flash = maxf(0.0, _flash - dt * 2.0)
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() * 0.001 + _seed
		match kind:
			"electric": _electric(t)
			"radiation": _radiation(t)
			"gravity": _gravity(t)

	func _electric(t: float) -> void:
		var r := BiomeHazards.ELECTRIC_R
		var pulse := 0.5 + 0.5 * sin(t * 9.0)
		draw_circle(Vector2.ZERO, r * 1.45 + 6.0 * pulse, Color(0.4, 0.7, 1.0, 0.12 + 0.2 * _flash))
		draw_circle(Vector2.ZERO, r + 5.0, Color(0.10, 0.07, 0.05))
		draw_circle(Vector2.ZERO, r, Color(0.10, 0.16, 0.36))
		draw_circle(Vector2.ZERO, r * (0.45 + 0.08 * pulse), Color(0.65, 0.88, 1.0, 0.9))
		# stepped (hand-drawn) lightning arcs, re-drawn 12 times a second
		var step := int(t * 12.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = step * 7919 + _seed
		for k in 5:
			var a := rng.randf() * TAU
			var pts := PackedVector2Array([Vector2.ZERO])
			for j in 4:
				var rr := r * (0.35 + j * 0.28)
				pts.append(Vector2.RIGHT.rotated(a + rng.randf_range(-0.5, 0.5)) * rr)
			draw_polyline(pts, Color(0.10, 0.07, 0.05), 7.0)
			draw_polyline(pts, Color(0.85, 0.95, 1.0), 3.5)
		for k in 6:
			var sp := Vector2.RIGHT.rotated(rng.randf() * TAU) * r * rng.randf_range(1.0, 1.35)
			draw_circle(sp, 4.0, Color(1, 1, 0.7))

	func _radiation(t: float) -> void:
		var rx := BiomeHazards.RAD_RX
		var ry := BiomeHazards.RAD_RY
		var pulse := 0.5 + 0.5 * sin(t * 2.4)
		for k in 4:
			var s := 1.0 - k * 0.18
			draw_set_transform(Vector2(0, -ry * 0.35 * k * 0.3), 0, Vector2(rx * s, ry * s * 0.9) / 100.0)
			draw_circle(Vector2.ZERO, 100.0, Color(0.45, 1.0, 0.25, 0.10 + 0.05 * pulse))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# sickly bubbles / particles rising
		for k in 9:
			var u := fposmod(t * 0.35 + k * 0.11, 1.0)
			var x := sin(k * 2.3 + t * 0.7) * rx * 0.7
			draw_circle(Vector2(x, -u * ry * 1.6 + ry * 0.2), 4.0 + 6.0 * (1.0 - u), Color(0.6, 1.0, 0.35, 0.7 * (1.0 - u)))
		# radiation trefoil warning on the ground glow
		var c := Vector2(0, -ry * 0.25)
		for k in 3:
			var a0 := -PI * 0.5 + k * TAU / 3.0 - 0.5
			draw_arc(c, 22.0, a0, a0 + 1.0, 8, Color(0.10, 0.07, 0.05, 0.6), 22.0)
		draw_circle(c, 6.0, Color(0.10, 0.07, 0.05, 0.6))

	func _gravity(t: float) -> void:
		var r := BiomeHazards.GRAV_R
		var wob := 1.0 + 0.12 * sin(t * 6.0) + 0.3 * _flash
		draw_set_transform(Vector2.ZERO, t * 1.8, Vector2(wob, 1.0 / wob))
		for k in 5:
			var rr := r * (1.15 - k * 0.2)
			var a0 := t * (2.0 + k) * (1 if k % 2 == 0 else -1)
			draw_arc(Vector2.ZERO, rr, a0, a0 + PI * 1.3, 20, Color(0.10, 0.07, 0.05), 9.0)
			draw_arc(Vector2.ZERO, rr, a0, a0 + PI * 1.3, 20, Color(0.75, 0.45, 1.0) if k % 2 == 0 else Color(0.4, 1.0, 0.85), 5.0)
		draw_circle(Vector2.ZERO, r * 0.22, Color(0.05, 0.0, 0.1))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# orbiting debris pulled around
		for k in 5:
			var a := t * 2.5 + k * TAU / 5.0
			var p := Vector2(cos(a) * r * 1.25, sin(a) * r * 0.9)
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.5, 0.42, 0.36))
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.10, 0.07, 0.05), false, 2.0)
		# up / down arrows: the two possible throws
		for s in [-1.0, 1.0]:
			var tip := Vector2(0, s * (r + 34.0 + 6.0 * sin(t * 4.0)))
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-12, -s * 16), tip + Vector2(12, -s * 16)]), Color(1, 0.9, 0.3, 0.9))
