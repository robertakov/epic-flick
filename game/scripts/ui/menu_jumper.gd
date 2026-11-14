class_name MenuJumper
extends Node2D
## v34: purely decorative SECOND menu robot. v36: it is now a real (miniature) rigid body: it falls from above the
## screen through the round menu buttons under gravity, tumbles, and bounces off invisible circle proxies of those
## buttons (impulse solver with restitution, friction and the resulting torque; springy feet bounce more, like the
## game's spring legs). No paths, no interpolation, no canned hops: every motion comes from the simulation.
## - one random robot per fall, from the protagonists AND the enemy roster (existing preview rigs, no new art)
## - a Node2D in the menu stage: it never receives / swallows touches, never takes focus, never presses a button,
##   never writes saves, records, challenges or events, plays no sound
## - its own simulation and its own RNG (never the global one, never the physics world): gameplay is untouched
## The original big menu robot (UIController.menu_robot_preview) is a different node and is not touched.

var ui: UIController
var catalog: RobotCatalog
var base_cfg: RobotConfig
var preview: RobotPreview
var rng := RandomNumberGenerator.new()
var current_id := ""
var is_enemy := false
## Telemetry (tests): button bounces so far and the button last bounced off (-1 = none yet).
var jumps := 0
var at_index := -1
var falls := 0
## Rigid-body state in the menu stage's coordinates (origin = centre of the robot art).
var vel := Vector2.ZERO
var spin := 0.0
var _h := 100.0                 # robot art height in stage px
var _circles: Array = []        # [local Vector2, radius, is_foot]
var _rest := 0.0
var _visible_last := false

const HEIGHT_OF_D := 0.95        # robot height relative to the button diameter (playful, not obstructive)
const STEP := 1.0 / 120.0
const GRAVITY_PER_H := 16.0      # gravity in robot heights / s^2 (scale-free: same feel at any screen size)
const E_FOOT := 0.78             # spring feet
const E_BODY := 0.32
const FRICTION := 0.45
const MAX_SPIN := 14.0


func _init() -> void:
	name = "MenuJumper"
	z_index = 3
	rng.randomize()


func pool() -> Array:
	var out := []
	for r in catalog.robots:
		out.append({"id": r.id, "enemy": false})
	for e in EnemyRoster.data().get("identities", {}):
		out.append({"id": String(e), "enemy": true})
	return out


## Picks a new random robot (avoids repeating the previous pick and the big menu robot when possible).
func pick(avoid := "") -> void:
	var options := pool().filter(func(o: Dictionary) -> bool: return o.id != current_id and o.id != avoid)
	if options.is_empty():
		options = pool()
	show_choice(options[rng.randi_range(0, options.size() - 1)])


func show_choice(o: Dictionary) -> void:
	if preview:
		preview.queue_free()
	preview = RobotPreview.new()
	preview.phase_offset = rng.randf() * 3.0
	add_child(preview)
	current_id = String(o.id)
	is_enemy = bool(o.enemy)
	if is_enemy:
		var arch: Array = EnemyRoster.data().identities[current_id].get("archetypes", ["tin"])
		var def := catalog.get_by_id(String(arch[0]))
		preview.show_enemy(current_id, def if def else catalog.robots[0], base_cfg)
	else:
		preview.show_robot(catalog.get_by_id(current_id), base_cfg)
	_fit()
	_spawn()


func _fit() -> void:
	if preview == null or ui == null:
		return
	var d := ui.menu_circle_diameter()
	var b := preview.art_bounds()
	var s := clampf(d * HEIGHT_OF_D / maxf(b.size.y, 1.0), 0.08, 1.2)
	preview.scale = Vector2.ONE * s
	preview.position = -b.get_center() * s
	_h = maxf(b.size.y * s, 10.0)
	var w := b.size.x * s
	# collision proxies of the robot (body-local): head, torso, two springy feet
	_circles = [[Vector2(0, -0.30 * _h), 0.17 * _h, false], [Vector2(0, -0.02 * _h), minf(0.22 * _h, 0.42 * w), false],
		[Vector2(-0.14 * _h, 0.42 * _h), 0.075 * _h, true], [Vector2(0.14 * _h, 0.42 * _h), 0.075 * _h, true]]


func _centers() -> Array[Vector2]:
	return ui._menu_button_centers


## Top point of button i (in the menu stage's coordinates).
func spot(i: int) -> Vector2:
	var c: Vector2 = _centers()[i]
	return c - Vector2(0, ui.menu_circle_diameter() * 0.5 - 4.0)


## Visible area of the screen in stage coordinates.
func _screen() -> Rect2:
	var parent := get_parent() as CanvasItem
	if parent == null:
		return Rect2(0, 0, 1280, 720)
	var inv := parent.get_global_transform().affine_inverse()
	var vp := get_viewport_rect()
	var a := inv * vp.position
	var b := inv * vp.end
	return Rect2(a, b - a).abs()


## New fall from above the screen, over the button column(s), with a small random drift and tumble.
func _spawn() -> void:
	if ui == null or _centers().is_empty():
		return
	var lo := INF
	var hi := -INF
	for c in _centers():
		lo = minf(lo, c.x)
		hi = maxf(hi, c.x)
	var r := ui.menu_circle_diameter() * 0.5
	var scr := _screen()
	position = Vector2(rng.randf_range(lo - r * 0.6, hi + r * 0.6), scr.position.y - _h * 0.8)
	rotation = rng.randf_range(-0.6, 0.6)
	vel = Vector2(rng.randf_range(-0.6, 0.6) * _h, rng.randf_range(0.0, 1.5) * _h)
	spin = rng.randf_range(-3.0, 3.0)
	_rest = 0.0
	falls += 1


func _process(dt: float) -> void:
	var on := is_visible_in_tree() and ui != null and _centers().size() >= 2 and preview != null
	if on and not _visible_last:
		_fit()
	_visible_last = on
	if not on:
		return
	dt = minf(dt, 0.05)
	var n := maxi(1, int(ceil(dt / STEP)))
	for i in n:
		_step(dt / n)
	var scr := _screen()
	if position.y > scr.end.y + _h or position.x < scr.position.x - 2.0 * _h or position.x > scr.end.x + 2.0 * _h or _rest > 2.5:
		pick(ui.menu_robot_preview.def.id if ui.menu_robot_preview and ui.menu_robot_preview.def else "")


## One rigid-body step: gravity, integration, circle-vs-circle contacts against every button proxy.
func _step(h: float) -> void:
	var g := GRAVITY_PER_H * _h
	var m := 1.0
	var inertia := m * pow(0.32 * _h, 2.0)
	vel.y += g * h
	position += vel * h
	rotation += spin * h
	spin *= exp(-0.35 * h)
	var br := ui.menu_circle_diameter() * 0.5
	var touched := false
	for bi in _centers().size():
		var c: Vector2 = _centers()[bi]
		for q in _circles:
			var w: Vector2 = position + (q[0] as Vector2).rotated(rotation)
			var d := w - c
			var dist := d.length()
			var pen := br + float(q[1]) - dist
			if pen <= 0.0 or dist < 0.001:
				continue
			touched = true
			var nrm := d / dist
			var r := (c + nrm * br) - position
			var vc := vel + Vector2(-spin * r.y, spin * r.x)
			var vn := vc.dot(nrm)
			position += nrm * pen * 0.85          # positional correction (no sinking into the button)
			if vn >= 0.0:
				continue
			var e := E_FOOT if bool(q[2]) else E_BODY
			var rn := r.x * nrm.y - r.y * nrm.x
			var j := -(1.0 + e) * vn / (1.0 / m + rn * rn / inertia)
			var t := Vector2(-nrm.y, nrm.x)
			var rt := r.x * t.y - r.y * t.x
			var jt := clampf(-vc.dot(t) / (1.0 / m + rt * rt / inertia), -FRICTION * j, FRICTION * j)
			var imp := nrm * j + t * jt
			vel += imp / m
			spin = clampf(spin + (r.x * imp.y - r.y * imp.x) / inertia, -MAX_SPIN, MAX_SPIN)
			if vn < -0.8 * _h:
				jumps += 1
				at_index = bi
	# a robot that came to rest on top of a button for a while starts a new fall (see _process)
	_rest = _rest + h if touched and vel.length() < 0.4 * _h and absf(spin) < 0.5 else 0.0
