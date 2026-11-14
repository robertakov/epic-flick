class_name SecretArtifact
extends Node2D
## v32: the ONE secret artifact of the release - a small brass "atom" medal hanging in the air of ONE fixed Exclusion
## Zone campaign level. Never hinted at. Robot collision does nothing (no physics body at all): the player has to SEE
## it and TAP it on the screen while it is visible (tap within TAP_RADIUS screen px of it). Discovery is permanent per
## profile (ProfileStore.artifact); afterwards the profile can equip / unequip it in the main menu.
## Effect when equipped (player robot only, offline only - GameManager.competitive_mode ignores it): v36 EXACTLY +15
## displayed stat points on five stats, applied as a runtime ModuleDefinition (base stats never change).

## Fixed level: the first Exclusion Zone round of the deterministic campaign schedule (BiomeSchedule) is r22.
const NODE_ID := "r22"
## v36 placement: INSIDE an anomaly - the first gravity (else electric) anomaly from X_M on, inside its swirl,
## drawn BEHIND the anomaly's own effects so it is partly hidden but findable: the player learns that artifacts live
## in anomalies. The artifact itself gets no new effect. If that stretch has no airborne anomaly (rare), a gravity
## anomaly is added there to host it (deterministic per track).
const X_M := 140.0
const HEIGHT := 760.0                 # host anomaly height if one has to be added (medium band)
const SEARCH_M := 40.0                # host search window after X_M
var host: Node2D                      # the anomaly node it sits in (QA / tests)
const TAP_RADIUS := 46.0
## v36 (owner decision): "+15" = +15 points of the player-facing 0..100 stat scale, where 100 = the best robot of the
## catalog (the scale the robot-select bars use: value / catalog maximum). HP is shown as a number: exactly +15 HP.
##   HP           max_health                          +15 HP
##   acceleration momentum_gain + momentum_max        +15 points each (the speed-chain build-up and its ceiling)
##   spring power rebound_power                       +15 points (natural feet rebound height; the landing feel stays)
##   control      air_control                         +15 points
##   energy       energy_boost_multiplier x charge_rate (the Energy bar) +15 points: both factors by the same root
## Nothing else: never mass_multiplier, size, colliders / joints / body_hit_scale, spring_strength / bounce,
## momentum_forward_cap, damage taken or any hidden stat. (A bar of a robot already at the top is drawn capped at 100.)
const POINTS := 15.0
const WHITELIST := ["max_health", "momentum_gain", "momentum_max", "rebound_power", "air_control", "energy_boost_multiplier", "charge_rate"]

signal collected

var gm: GameManager
var _t := 0.0
var _taken := false


## stats: the robot's stats BEFORE the artifact (base + MK2 module); catalog: the scale (catalog maxima).
static func module(stats: Dictionary = {}, catalog: RobotCatalog = null) -> ModuleDefinition:
	var cat := catalog if catalog != null else RobotCatalog.new()
	var k := POINTS / 100.0
	var m := ModuleDefinition.new()
	m.id = "secret_artifact"
	m.display_name = "Артефакт Зоны"
	m.slot = "artifact"
	m.stat_offsets = {"max_health": POINTS,
		"momentum_gain": k * cat.stat_max("momentum_gain"), "momentum_max": k * cat.stat_max("momentum_max"),
		"rebound_power": k * cat.stat_max("rebound_power"), "air_control": k * cat.stat_max("air_control")}
	var e := float(stats.get("energy_boost_multiplier", 1.0)) * float(stats.get("charge_rate", 1.0))
	var f := sqrt((e + k * energy_max(cat)) / maxf(e, 0.0001))
	m.stat_multipliers = {"energy_boost_multiplier": f, "charge_rate": f}
	return m


## Catalog maximum of the Energy bar value (energy_boost_multiplier x charge_rate).
static func energy_max(cat: RobotCatalog) -> float:
	var mx := 0.0001
	for d in cat.robots:
		mx = maxf(mx, d.energy_boost_multiplier * d.charge_rate)
	return mx


## Displayed points (0..100 scale, uncapped) of the five artifact stats for a stats dictionary (tests / QA).
static func points(stats: Dictionary, cat: RobotCatalog) -> Dictionary:
	return {"hp": float(stats.max_health),
		"acceleration": 100.0 * float(stats.momentum_gain) / cat.stat_max("momentum_gain"),
		"acceleration_max": 100.0 * float(stats.momentum_max) / cat.stat_max("momentum_max"),
		"spring": 100.0 * float(stats.rebound_power) / cat.stat_max("rebound_power"),
		"control": 100.0 * float(stats.air_control) / cat.stat_max("air_control"),
		"energy": 100.0 * float(stats.energy_boost_multiplier) * float(stats.charge_rate) / energy_max(cat)}


## Host anomaly for this level's track: {pos (artifact world position), node (host anomaly), kind}.
static func place(terrain: TerrainBuilder, hazards: BiomeHazards, px_per_m: float) -> Dictionary:
	var x0 := X_M * px_per_m
	var x1 := (X_M + SEARCH_M) * px_per_m
	hazards.generate_now()
	for want in ["gravity", "electric"]:
		for a in hazards.anomalies:
			var p: Vector2 = a.pos
			if String(a.kind) == want and p.x >= x0 and p.x <= x1 and is_instance_valid(a.node):
				return {"pos": p + offset_in(want), "node": a.node, "kind": want}
	var hp := Vector2(x0, terrain.surface_y(x0) - HEIGHT)
	var added: Dictionary = hazards.add_anomaly("gravity", hp)
	return {"pos": hp + offset_in("gravity"), "node": added.node, "kind": "gravity"}


## Where inside the anomaly it hangs: off-centre (the dark core would hide it completely).
static func offset_in(kind: String) -> Vector2:
	# gravity: inside the open swirl (its arcs and debris pass over it); electric: at the rim of the opaque core,
	# half hidden under it and the glow - noticeable, but clearly part of the anomaly
	if kind == "gravity":
		return Vector2(0.38, 0.22) * BiomeHazards.GRAV_R
	return Vector2(0.76, 0.76) * BiomeHazards.ELECTRIC_R


func _ready() -> void:
	name = "SecretArtifact"
	# v36: drawn behind the host anomaly's effects (absolute z just below the anomaly node)
	z_as_relative = false
	z_index = (_abs_z(host) - 1) if is_instance_valid(host) else 8


static func _abs_z(n: Node) -> int:
	var z := 0
	var c := n as CanvasItem
	while c != null:
		z += c.z_index
		if not c.z_as_relative:
			break
		c = c.get_parent() as CanvasItem
	return z


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


## Screen-space hit test (viewport coordinates of a touch / click).
func hit(screen_pos: Vector2) -> bool:
	if _taken or not is_visible_in_tree():
		return false
	var c := get_global_transform_with_canvas().origin
	var vp := get_viewport_rect()
	return vp.has_point(c) and c.distance_to(screen_pos) <= TAP_RADIUS


func _input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pos = (event as InputEventMouseButton).position
	if pos == Vector2.INF or not hit(pos):
		return   # every other tap stays a normal game tap
	get_viewport().set_input_as_handled()
	take()


func take() -> void:
	if _taken:
		return
	_taken = true
	collected.emit()
	queue_free()


func _draw() -> void:
	# small, subtle: a weathered brass medal with an atom, gently swaying on a scrap of wire; a rare tiny glint
	var sway := sin(_t * 1.7) * 0.12
	draw_set_transform(Vector2.ZERO, sway, Vector2.ONE)
	var ink := Color(0.1, 0.06, 0.04)
	draw_line(Vector2(0, -34), Vector2(0, -14), Color(0.35, 0.3, 0.25), 2.0)
	draw_circle(Vector2(0, 0), 15.0, ink)
	draw_circle(Vector2(0, 0), 12.5, Color(0.72, 0.58, 0.28))
	draw_circle(Vector2(-3, -3), 5.0, Color(0.86, 0.74, 0.42))
	for k in 3:
		var a := k * PI / 3.0
		draw_set_transform(Vector2.ZERO, sway + a, Vector2(1.0, 0.38))
		draw_arc(Vector2.ZERO, 8.5, 0, TAU, 14, Color(0.25, 0.32, 0.12), 1.6)
	draw_set_transform(Vector2.ZERO, sway, Vector2.ONE)
	draw_circle(Vector2.ZERO, 2.6, Color(0.45, 0.6, 0.15))
	var glint := fposmod(_t, 4.5)
	if glint < 0.25:
		var g := 1.0 - absf(glint - 0.125) / 0.125
		draw_line(Vector2(6, -10), Vector2(6, -10 - 7.0 * g), Color(1, 1, 0.85, g), 2.0)
		draw_line(Vector2(2, -6), Vector2(10, -6), Color(1, 1, 0.85, g * 0.8), 1.5)
