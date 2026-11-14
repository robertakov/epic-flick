class_name BiomeProps
extends RefCounted
## World-space biome decoration built once per terrain chunk (freed with the chunk). VISUAL ONLY: no collision
## (the only biome geometry with collision is the terrain itself, the chasm gaps and the cavern ceiling, built by
## TerrainBuilder). Props stand behind the robots (robots are drawn in the "Dynamic" layer at z 10).

const INK := Color(0.10, 0.07, 0.05)
const ZONE_PROPS := ["tree_dead_a", "tree_dead_b", "tree_dead_c", "tree_dead_d", "pine_a", "pine_b", "pine_c", "bush_dead",
	"barrels", "sign_radiation", "slab_a", "slab_b", "slab_rebar", "rubble", "sandbags", "tires", "hedgehog", "spool_a",
	"spool_b", "pipe_rusty", "car", "bus", "truck", "sign_pripyat", "sign_danger", "sign_chernobyl", "crates", "log_pile",
	"concrete_panels", "valve", "pipes_concrete", "pole", "bunker"]
const ZONE_BIG := ["car", "bus", "truck", "bunker", "sign_pripyat", "sign_chernobyl"]

## Jelly ripples pushed by BiomeHazards on landings: [x, time_s, amplitude].
static var ripples: Array = []


static func now() -> float:
	return Time.get_ticks_msec() * 0.001


static func push_ripple(x: float, amp: float) -> void:
	ripples.append([x, now(), amp])
	if ripples.size() > 8:
		ripples.pop_front()


# ---------------- surface props ----------------

static func decorate(root: Node2D, surf: PackedVector2Array, r: RandomNumberGenerator, terrain: TerrainBuilder) -> void:
	var b := terrain.biome
	var x0 := maxf(surf[0].x, terrain.ledge_end_x + 400.0)
	var x1 := surf[surf.size() - 1].x
	if x1 <= x0:
		return
	var layer := PropLayer.new()
	layer.style = b.props
	layer.z_index = -1
	var x := x0 + r.randf_range(60.0, 300.0)
	while x < x1 - 40.0:
		var y := terrain.surface_y(x)
		var n := terrain.normal_at(x)
		if b.props == "zone":
			var name: String = ZONE_PROPS[r.randi_range(0, ZONE_PROPS.size() - 1)]
			var tx := BiomePainter.tex(name)
			if tx:
				var s := Sprite2D.new()
				s.texture = tx
				s.centered = false
				var sc := r.randf_range(0.85, 1.15) * (1.15 if name in ZONE_BIG else 1.0)
				s.scale = Vector2(sc, sc) * (1.0 if r.randf() < 0.5 else 1.0)
				s.flip_h = r.randf() < 0.4 and not name.begins_with("sign")
				s.position = Vector2(x - tx.get_width() * sc * 0.5, y - tx.get_height() * sc + 14.0)
				s.z_index = -1
				root.add_child(s)
			x += r.randf_range(320.0, 700.0)
			continue
		layer.items.append({"p": Vector2(x, y), "n": n, "k": r.randi_range(0, 99), "s": r.randf_range(0.8, 1.25), "ph": r.randf() * TAU})
		x += r.randf_range(200.0, 520.0)
	if not layer.items.is_empty():
		root.add_child(layer)
	else:
		# QA leak fix: an unused layer (always in the Zone, whose props are sprites; sometimes on short chunks) was
		# never added to the tree and never freed -> one orphan node per such chunk for the whole session
		layer.free()


## Pools / skins / animated extras that span the whole chunk.
static func chunk_extras(root: Node2D, surf: PackedVector2Array, _index: int, terrain: TerrainBuilder) -> void:
	var b := terrain.biome
	if b.chocolate:
		for pool in terrain.chocolate_pools:
			var a := maxf(float(pool[0]), surf[0].x)
			var e := minf(float(pool[1]), surf[surf.size() - 1].x)
			if e - a < 20.0:
				continue
			var cp := ChocolatePool.new()
			cp.terrain = terrain
			cp.x0 = a; cp.x1 = e
			cp.edge_l = a <= float(pool[0]) + 1.0
			cp.edge_r = e >= float(pool[1]) - 1.0
			cp.z_index = 2
			root.add_child(cp)
	if b.jelly:
		var js := JellySkin.new()
		js.surf = surf
		js.z_index = 2
		root.add_child(js)


# ---------------- chasms ----------------

static func chasm(root: Node2D, g: Array, _terrain: TerrainBuilder) -> void:
	var a := ChasmVisual.new()
	a.xa = float(g[0]); a.xb = float(g[1]); a.ya = float(g[2]); a.yb = float(g[3])
	a.z_index = 1
	root.add_child(a)


static func cliff_edges(root: Node2D, run: PackedVector2Array, bottom: float, left: bool, right: bool) -> void:
	for side in 2:
		if (side == 0 and not left) or (side == 1 and not right):
			continue
		var p := run[0] if side == 0 else run[run.size() - 1]
		var inward := 1.0 if side == 0 else -1.0
		var pts := PackedVector2Array()
		var y := p.y
		var k := 0
		while y < minf(bottom, p.y + 1400.0):
			pts.append(Vector2(p.x + inward * (4.0 + 10.0 * float(k % 2)), y))
			y += 46.0
			k += 1
		var wall := Line2D.new()
		wall.points = pts
		wall.width = 16.0
		wall.default_color = INK
		root.add_child(wall)
		var shade := Line2D.new()
		var sp := PackedVector2Array()
		for q in pts:
			sp.append(q + Vector2(inward * 18.0, 0))
		shade.points = sp
		shade.width = 22.0
		shade.default_color = Color(0, 0, 0, 0.25)
		root.add_child(shade)
		# warning stake at the lip of a jump (left rim of a gap = right end of this run)
		if side == 1:
			var post := Node2D.new()
			post.position = p + Vector2(-60.0, 4.0)
			var pole := Line2D.new()
			pole.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -110)])
			pole.width = 12.0
			pole.default_color = INK
			post.add_child(pole)
			for s in 4:
				var band := Line2D.new()
				band.points = PackedVector2Array([Vector2(0, -12 - s * 24), Vector2(0, -26 - s * 24)])
				band.width = 8.0
				band.default_color = Color(0.95, 0.15, 0.1) if s % 2 == 0 else Color(1, 1, 1)
				post.add_child(band)
			var flag := Polygon2D.new()
			flag.polygon = PackedVector2Array([Vector2(0, -110), Vector2(34, -98), Vector2(0, -86)])
			flag.color = Color(1.0, 0.75, 0.1)
			post.add_child(flag)
			post.z_index = -1
			root.add_child(post)


# ---------------- cavern ceiling ----------------

static func ceiling_visual(root: Node2D, line: PackedVector2Array, top: float, terrain: TerrainBuilder, r: RandomNumberGenerator) -> void:
	var fill := Polygon2D.new()
	var poly := line.duplicate()
	poly.append(Vector2(line[line.size() - 1].x, top))
	poly.append(Vector2(line[0].x, top))
	fill.polygon = poly
	fill.color = terrain.color_at(line[0].x, "dirt").darkened(0.15)
	root.add_child(fill)
	var band := Line2D.new()
	var bp := PackedVector2Array()
	for p in line:
		bp.append(p + Vector2(0, -26))
	band.points = bp
	band.width = 40.0
	band.default_color = terrain.color_at(line[0].x, "dirt_dark")
	root.add_child(band)
	var edge := Line2D.new()
	edge.points = line
	edge.width = 30.0
	edge.default_color = INK
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	root.add_child(edge)
	var lip := Line2D.new()
	var lp := PackedVector2Array()
	for p in line:
		lp.append(p + Vector2(0, -3))
	lip.points = lp
	lip.width = 12.0
	lip.default_color = terrain.color_at(line[0].x, "top").darkened(0.15)
	root.add_child(lip)
	# glowing ore veins embedded in the ceiling rock (inside the rock: no visual/collision mismatch)
	var glow := PropLayer.new()
	glow.style = "ceiling"
	glow.z_index = 1
	for i in maxi(1, line.size() / 6):
		var p: Vector2 = line[r.randi_range(0, line.size() - 1)]
		glow.items.append({"p": p + Vector2(r.randf_range(-30, 30), -r.randf_range(45, 120)), "n": Vector2.UP, "k": r.randi_range(0, 99),
			"s": r.randf_range(0.7, 1.2), "ph": r.randf() * TAU})
	root.add_child(glow)


# ======================================================================================================
# drawing nodes
# ======================================================================================================

class PropLayer extends Node2D:
	var style := ""
	var items: Array = []
	var animated := false

	func _ready() -> void:
		animated = style in ["cavern", "portal", "jelly", "ceiling", "chocolate"]
		set_process(animated)

	func _process(_dt: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() * 0.001
		for it in items:
			var p: Vector2 = it.p
			var k: int = it.k
			var s: float = it.s
			var ph: float = it.ph
			draw_set_transform(p, 0.0, Vector2(s, s))
			match style:
				"moon": _moon(k)
				"heavy": _heavy(k)
				"chocolate": _chocolate(k, t + ph)
				"jelly": _jelly(k, t + ph)
				"portal": _portal(k, t + ph)
				"chasms": _chasms(k)
				"cavern": _cavern(k, t + ph)
				"ceiling": _ore(k, t + ph)
		draw_set_transform_matrix(Transform2D.IDENTITY)

	func _ink_poly(pts: PackedVector2Array, col: Color, w := 4.0) -> void:
		draw_colored_polygon(pts, col)
		var o := pts.duplicate(); o.append(o[0])
		draw_polyline(o, INK, w, true)

	func _moon(k: int) -> void:
		if k < 55:
			_ink_poly(PackedVector2Array([Vector2(-40, 8), Vector2(-30, -26), Vector2(4, -38), Vector2(36, -20), Vector2(44, 8)]), Color(0.66, 0.67, 0.75))
			draw_circle(Vector2(-6, -18), 6.0, Color(0.5, 0.51, 0.6))
			draw_circle(Vector2(14, -10), 4.0, Color(0.5, 0.51, 0.6))
		elif k < 90:
			_ink_poly(PackedVector2Array([Vector2(-18, 6), Vector2(-12, -14), Vector2(10, -16), Vector2(18, 6)]), Color(0.58, 0.59, 0.68), 3.0)
		else:
			draw_line(Vector2(0, 8), Vector2(0, -90), INK, 5.0)
			_ink_poly(PackedVector2Array([Vector2(0, -90), Vector2(46, -84), Vector2(46, -58), Vector2(0, -62)]), Color(0.95, 0.3, 0.25), 3.0)

	func _heavy(k: int) -> void:
		if k < 45:
			# boulder flattened by the gravity
			_ink_poly(PackedVector2Array([Vector2(-56, 8), Vector2(-48, -16), Vector2(30, -22), Vector2(58, 8)]), Color(0.44, 0.26, 0.38))
			draw_line(Vector2(-30, -10), Vector2(10, -12), Color(0.25, 0.12, 0.2), 3.0)
		elif k < 80:
			for i in 3:
				var bx := -16.0 + i * 16.0
				_ink_poly(PackedVector2Array([Vector2(bx - 9, 8), Vector2(bx + (i - 1) * 4, -46 - i * 10), Vector2(bx + 9, 8)]), Color(0.35, 0.92, 0.85), 3.0)
		else:
			_ink_poly(PackedVector2Array([Vector2(-26, 8), Vector2(-26, -34), Vector2(26, -26), Vector2(26, 8)]), Color(0.55, 0.36, 0.50))

	func _chocolate(k: int, t: float) -> void:
		if k < 25:
			draw_line(Vector2(0, 8), Vector2(0, -70), Color(0.97, 0.95, 0.9), 6.0)
			draw_circle(Vector2(0, -88), 26.0, INK)
			draw_circle(Vector2(0, -88), 22.0, Color(0.55, 0.85, 1.0))
			var sp := PackedVector2Array()
			for i in 22:
				var a := i * 0.6 + t
				sp.append(Vector2(0, -88) + Vector2(cos(a), sin(a)) * (2.0 + i * 0.9))
			draw_polyline(sp, Color(1, 1, 1), 4.0, true)
		elif k < 50:
			_ink_poly(PackedVector2Array([Vector2(-22, 8), Vector2(-18, -20), Vector2(0, -30), Vector2(18, -20), Vector2(22, 8)]), Color(0.95, 0.3, 0.45))
			draw_circle(Vector2(-6, -16), 4.0, Color(1, 1, 1, 0.8))
		elif k < 75:
			draw_circle(Vector2(0, -16), 26.0, INK)
			draw_circle(Vector2(0, -16), 22.0, Color(0.86, 0.62, 0.34))
			for i in 5:
				draw_circle(Vector2(-12 + i * 6, -22 + (i % 2) * 10), 3.5, Color(0.3, 0.16, 0.08))
		else:
			var cane := PackedVector2Array([Vector2(0, 8), Vector2(0, -80)])
			draw_polyline(cane, INK, 16.0)
			draw_polyline(cane, Color(1, 1, 1), 10.0)
			for i in 4:
				draw_line(Vector2(-5, -6 - i * 18), Vector2(5, -14 - i * 18), Color(0.9, 0.12, 0.18), 5.0)
			draw_arc(Vector2(14, -80), 14.0, PI, TAU, 10, INK, 16.0)
			draw_arc(Vector2(14, -80), 14.0, PI, TAU, 10, Color(0.9, 0.12, 0.18), 10.0)

	func _jelly(k: int, t: float) -> void:
		var sq := 1.0 + 0.1 * sin(t * 5.0)
		var cols := [Color(1, 0.3, 0.5, 0.85), Color(0.4, 0.95, 0.3, 0.85), Color(1, 0.8, 0.2, 0.85), Color(0.5, 0.55, 1, 0.85)]
		var col: Color = cols[k % 4]
		if k < 50:
			var w := 24.0 * sq
			var h := 44.0 / sq
			draw_rect(Rect2(-w, 6 - h, w * 2, h), col)
			draw_rect(Rect2(-w, 6 - h, w * 2, h), Color(INK, 0.8), false, 4.0)
			draw_line(Vector2(-w * 0.6, 12 - h), Vector2(-w * 0.1, 12 - h), Color(1, 1, 1, 0.85), 4.0)
		else:
			draw_circle(Vector2(0, -26 / sq), 16.0, col)
			draw_circle(Vector2(-10, -40 / sq), 6.0, col)
			draw_circle(Vector2(10, -40 / sq), 6.0, col)
			draw_circle(Vector2(0, -6), 20.0 * sq, col)
			draw_arc(Vector2(0, -6), 20.0 * sq, 0, TAU, 16, Color(INK, 0.7), 3.0)

	func _portal(k: int, t: float) -> void:
		if k < 60:
			_ink_poly(PackedVector2Array([Vector2(-14, 8), Vector2(-10, -90), Vector2(10, -90), Vector2(14, 8)]), Color(0.30, 0.24, 0.46))
			var g := 0.5 + 0.5 * sin(t * 3.0)
			draw_circle(Vector2(0, -102), 22.0 + 6.0 * g, Color(0.4, 1.0, 0.92, 0.25))
			draw_circle(Vector2(0, -102), 12.0, INK)
			draw_circle(Vector2(0, -102), 9.0, Color(0.4, 1.0, 0.92).lerp(Color(1, 0.4, 0.9), g))
		else:
			_ink_poly(PackedVector2Array([Vector2(-26, 8), Vector2(-20, -28), Vector2(18, -32), Vector2(26, 8)]), Color(0.36, 0.30, 0.52))
			draw_arc(Vector2(0, -12), 8.0, 0, TAU, 12, Color(0.4, 1, 0.92, 0.5 + 0.5 * sin(t * 2.0)), 3.0)

	func _chasms(k: int) -> void:
		if k < 50:
			_ink_poly(PackedVector2Array([Vector2(-36, 8), Vector2(-28, -24), Vector2(6, -34), Vector2(34, -14), Vector2(40, 8)]), Color(0.64, 0.38, 0.24))
			draw_line(Vector2(-10, -28), Vector2(0, -6), Color(0.3, 0.14, 0.08), 3.0)
		elif k < 80:
			for i in 3:
				draw_line(Vector2(i * 8 - 8, 8), Vector2(i * 14 - 14, -40 - i * 6), INK, 5.0)
				draw_line(Vector2(i * 8 - 8, 8), Vector2(i * 14 - 14, -40 - i * 6), Color(0.5, 0.36, 0.2), 2.5)
		else:
			for i in 3:
				_ink_poly(PackedVector2Array([Vector2(-14, 8 - i * 18), Vector2(-12, -8 - i * 18), Vector2(12, -10 - i * 18), Vector2(14, 8 - i * 18)]), Color(0.7, 0.5, 0.32), 3.0)

	func _cavern(k: int, t: float) -> void:
		var breath := 0.5 + 0.5 * sin(t * 1.7)
		if k < 35:
			var mc := Color(0.5, 1.0, 0.55)
			draw_circle(Vector2(0, -30), 46.0 + 8.0 * breath, Color(mc, 0.13))
			for i in 3:
				var sway := sin(t * 1.5 + i) * 4.0
				var stem := Vector2(-16 + i * 16, 8)
				var cap := stem + Vector2(sway, -26 - i * 8)
				draw_line(stem, cap, Color(0.93, 0.9, 0.8), 6.0)
				draw_circle(cap, 15.0, INK)
				draw_circle(cap, 12.0, mc.lerp(Color(0.25, 0.85, 0.5), breath))
				draw_circle(cap + Vector2(-3, -4), 3.0, Color(1, 1, 1, 0.85))
		elif k < 65:
			var cc := Color(0.4, 0.92, 1.0) if k % 2 == 0 else Color(1.0, 0.5, 0.95)
			draw_circle(Vector2(0, -20), 50.0 + 8.0 * breath, Color(cc, 0.12))
			for i in 3:
				var b := Vector2(-12 + i * 12, 8)
				_ink_poly(PackedVector2Array([b + Vector2(-8, 0), b + Vector2(-2 + i * 2, -34 - i * 10), b + Vector2(8, 0)]), cc.lerp(Color.WHITE, 0.25 * breath), 3.0)
		elif k < 85:
			BiomePainter._torch(self, Vector2(0, -50), t, k)
			draw_line(Vector2(0, -10), Vector2(0, 8), INK, 8.0)
		else:
			# small stalagmite (visual only, kept short and behind the robot)
			_ink_poly(PackedVector2Array([Vector2(-18, 8), Vector2(-2, -46), Vector2(18, 8)]), Color(0.48, 0.42, 0.37), 3.0)

	func _ore(k: int, t: float) -> void:
		var cc := Color(0.4, 0.92, 1.0) if k % 2 == 0 else Color(1.0, 0.55, 0.9)
		var breath := 0.5 + 0.5 * sin(t * 1.3)
		draw_circle(Vector2.ZERO, 34.0 + 6.0 * breath, Color(cc, 0.12))
		for i in 3:
			var b := Vector2(-10 + i * 10, 10)
			_ink_poly(PackedVector2Array([b + Vector2(-6, 0), b + Vector2(0, -22 - i * 6), b + Vector2(6, 0)]), cc, 2.5)


class ChocolatePool extends Node2D:
	var terrain: TerrainBuilder
	var x0 := 0.0
	var x1 := 0.0
	var edge_l := true
	var edge_r := true
	var _top := PackedVector2Array()

	func _ready() -> void:
		var x := x0
		while x < x1:
			_top.append(Vector2(x, terrain.surface_y(x) - 18.0))
			x += 24.0
		_top.append(Vector2(x1, terrain.surface_y(x1) - 18.0))
		set_process(true)

	func _process(_dt: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		if _top.size() < 2:
			return
		var t := Time.get_ticks_msec() * 0.001
		var top := PackedVector2Array()
		for i in _top.size():
			var p := _top[i]
			top.append(p + Vector2(0, sin(t * 2.2 + p.x * 0.02) * 2.5))
		var poly := top.duplicate()
		for i in range(_top.size() - 1, -1, -1):
			poly.append(_top[i] + Vector2(0, 74))
		draw_colored_polygon(poly, Color(0.38, 0.19, 0.08))
		draw_polyline(top, INK, 6.0, true)
		var shine := PackedVector2Array()
		for p in top:
			shine.append(p + Vector2(0, 9))
		draw_polyline(shine, Color(0.72, 0.48, 0.30), 6.0, true)
		var deep := PackedVector2Array()
		for p in top:
			deep.append(p + Vector2(0, 40))
		draw_polyline(deep, Color(0.26, 0.12, 0.05), 10.0, true)
		# slow liquid bubbles
		for i in range(2, top.size() - 2, 5):
			var u := fposmod(t * 0.6 + i * 0.37, 1.0)
			draw_circle(top[i] + Vector2(0, 10 - 8 * u), 3.0 + 4.0 * u, Color(0.45, 0.26, 0.14, 1.0 - u))
		# drips over the pool rims
		if edge_l:
			draw_circle(top[0] + Vector2(-4, 22), 16.0, Color(0.38, 0.19, 0.08))
		if edge_r:
			draw_circle(top[top.size() - 1] + Vector2(4, 22), 16.0, Color(0.38, 0.19, 0.08))


class JellySkin extends Node2D:
	var surf := PackedVector2Array()

	func _process(_dt: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _ready() -> void:
		set_process(true)

	func _draw() -> void:
		var t := Time.get_ticks_msec() * 0.001
		var hl := PackedVector2Array()
		var gloss := PackedVector2Array()
		for i in range(0, surf.size(), 3):
			var p := surf[i]
			var w := sin(t * 4.0 + p.x * 0.012) * 3.0
			for rp in BiomeProps.ripples:
				var age := t - float(rp[1])
				if age < 1.6 and age >= 0.0:
					var d := absf(p.x - float(rp[0]))
					w += float(rp[2]) * exp(-d * 0.004) * sin(d * 0.03 - age * 14.0) * exp(-age * 2.4)
			hl.append(p + Vector2(0, -8 + w))
			gloss.append(p + Vector2(0, 26 + w * 0.6))
		if hl.size() >= 2:
			draw_polyline(hl, Color(1, 0.9, 0.97, 0.9), 8.0, true)
			draw_polyline(gloss, Color(1, 1, 1, 0.25), 10.0, true)


class ChasmVisual extends Node2D:
	var xa := 0.0
	var xb := 0.0
	var ya := 0.0
	var yb := 0.0

	func _draw() -> void:
		var top_l := Vector2(xa, ya)
		var top_r := Vector2(xb, yb)
		var depth := maxf(ya, yb) + 1500.0
		# the abyss: inner walls receding into darkness
		var cols := [Color(0.30, 0.14, 0.09), Color(0.18, 0.08, 0.05), Color(0.07, 0.03, 0.02)]
		for i in 3:
			var y0 := lerpf(maxf(ya, yb), depth, i / 3.0)
			var y1 := lerpf(maxf(ya, yb), depth, (i + 1) / 3.0)
			var inset := 18.0 + i * 22.0
			var poly := PackedVector2Array([Vector2(xa + inset, y0 if i > 0 else ya + 30.0), Vector2(xb - inset, y0 if i > 0 else yb + 30.0),
				Vector2(xb - inset - 22.0, y1), Vector2(xa + inset + 22.0, y1)])
			draw_colored_polygon(poly, cols[i])
		# rising dust wisps
		var t := Time.get_ticks_msec() * 0.001
		for k in 4:
			var u := fposmod(t * 0.25 + k * 0.25, 1.0)
			var p := Vector2(lerpf(xa + 40.0, xb - 40.0, (k + 0.5) / 4.0), lerpf(depth - 300.0, maxf(ya, yb) + 60.0, u))
			draw_circle(p, 18.0 + 20.0 * u, Color(0.6, 0.45, 0.35, 0.18 * (1.0 - u)))
		draw_line(top_l, top_l + Vector2(16, 60), INK, 8.0)
		draw_line(top_r, top_r + Vector2(-16, 60), INK, 8.0)

	func _ready() -> void:
		set_process(true)

	func _process(_dt: float) -> void:
		if is_visible_in_tree():
			queue_redraw()
