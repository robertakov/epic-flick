class_name ChargeAura
extends Node2D
## Cartoon "wound-up" look for the spin charge. The real spin barely changes (0.50 -> 0.60 rev/s), so the
## aura sells the energy: whirl arcs spinning much faster than the body, orbiting stars, motion trails and
## crackle at the top end. Everything scales with the charge; at 0 % nothing is drawn; when the charge is spent
## it vanishes in the same frame. Pure visuals, drawn in world space around the robot (top_level).

const INK := Color(0.1, 0.06, 0.04)

var robot: RigidBody2D
var ratio := 0.0
var _phase := 0.0
var _star_phase := 0.0
var _time := 0.0
var _radius := 150.0


func setup(p_robot: RigidBody2D, size_scale: float) -> void:
	robot = p_robot
	top_level = true
	z_index = -1
	_radius = 172.0 * size_scale
	name = "ChargeAura"


func set_ratio(r: float) -> void:
	ratio = clampf(r, 0.0, 1.0)
	visible = ratio > 0.03
	if not visible:
		_phase = robot.global_rotation if robot else 0.0


func _process(dt: float) -> void:
	if robot == null:
		return
	global_position = robot.global_position
	if not visible:
		return
	_time += dt
	# the whirl runs ahead of the body: 1x .. 4.5x the real angular velocity
	var w := maxf(robot.angular_velocity, TAU * 0.4)
	_phase += w * (1.0 + 3.5 * ratio) * dt
	_star_phase += w * (1.6 + 2.0 * ratio) * dt
	queue_redraw()


func _draw() -> void:
	var r := ratio
	var gold := Color(1.0, 0.82, 0.2)
	var white := Color(1.0, 0.98, 0.9)
	# 1. whirl arcs: 1 -> 6 arcs, longer and thicker with charge, tapered tails
	var arcs := 2 + int(round(6.0 * r))
	for i in arcs:
		var a0 := _phase + TAU * i / arcs
		var rad := _radius * (0.9 + 0.22 * float(i % 3) / 2.0)
		var length := 0.6 + 0.9 * r
		var col := white.lerp(gold, minf(r * 1.3, 1.0))
		col.a = minf(0.6 + 0.6 * r, 1.0)
		_tapered_arc(rad, a0, length, 7.0 + 12.0 * r, col)
	# speed lines trailing the flight direction (cartoon motion lines), more and longer with charge
	var v := robot.linear_velocity
	if v.length() > 150.0 and r > 0.15:
		var back := -v.normalized()
		var side := Vector2(-back.y, back.x)
		var lines := 2 + int(4.0 * r)
		for i in lines:
			var off := (float(i) / maxf(lines - 1, 1) - 0.5) * _radius * 1.4
			var flick := 0.75 + 0.25 * sin(_time * 30.0 + i * 2.3)
			var p0 := back * _radius * 0.85 + side * off
			var p1 := p0 + back * _radius * (0.5 + 0.9 * r) * flick
			draw_line(p0, p1, INK, 8.0, true)
			draw_line(p0, p1, white, 4.0, true)
	# 2. motion-trail ghosts hugging the body (2 broad translucent sweeps)
	if r > 0.1:
		for k in 2:
			var a := _phase * 0.8 + PI * k
			var c := gold
			c.a = 0.18 + 0.27 * r
			draw_arc(Vector2.ZERO, _radius * 0.62, a - 1.2 * r, a, 18, c, 22.0 + 22.0 * r, true)
	# 3. orbiting stars: 0 -> 7
	var stars := int(floor(r * 8.0 + 0.5)) if r > 0.1 else 0
	for i in stars:
		var a := -_star_phase * (1.0 + 0.15 * (i % 3)) + TAU * i / maxf(stars, 1)
		var orbit := _radius * (0.8 + 0.25 * sin(_time * 3.0 + i))
		var p := Vector2(cos(a), sin(a)) * orbit
		var tw := 0.75 + 0.25 * sin(_time * 14.0 + i * 1.7)
		_star(p, (11.0 + 12.0 * r) * tw, gold if i % 2 == 0 else white)
	# 4. crackle near full charge: little zig-zag sparks around the rim
	if r > 0.6:
		var n := int(2 + 7 * (r - 0.6) / 0.4)
		for i in n:
			var a := _phase * 1.3 + TAU * i / n + sin(_time * 9.0 + i) * 0.3
			var base := Vector2(cos(a), sin(a)) * _radius * 1.12
			var t := Vector2(-base.y, base.x).normalized() * 9.0
			var o := base.normalized() * 10.0
			var pts := PackedVector2Array([base - o, base + t, base + o - t, base + o * 2.0])
			draw_polyline(pts, INK, 6.0, true)
			draw_polyline(pts, white, 3.0, true)
	# 5. full charge: pulsing halo ring
	if r >= 0.999:
		var pulse := 0.5 + 0.5 * sin(_time * 10.0)
		var c := gold
		c.a = 0.35 + 0.35 * pulse
		draw_arc(Vector2.ZERO, _radius * (1.22 + 0.05 * pulse), 0.0, TAU, 48, c, 5.0, true)


func _tapered_arc(rad: float, a0: float, length: float, width: float, col: Color) -> void:
	var seg := 8
	for s in seg:
		var t0 := float(s) / seg
		var t1 := float(s + 1) / seg
		var p0 := Vector2(cos(a0 - length * t0), sin(a0 - length * t0)) * rad
		var p1 := Vector2(cos(a0 - length * t1), sin(a0 - length * t1)) * rad
		var w := width * (1.0 - t0 * 0.85)
		var c := col
		c.a *= 1.0 - t0 * 0.7
		draw_line(p0, p1, Color(INK.r, INK.g, INK.b, c.a), w + 4.0, true)
		draw_line(p0, p1, c, w, true)


func _star(c: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(c + Vector2.RIGHT.rotated(TAU * i / 10.0 - PI * 0.5 + _time * 4.0) * (rad if i % 2 == 0 else rad * 0.42))
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, INK, 2.5, true)
