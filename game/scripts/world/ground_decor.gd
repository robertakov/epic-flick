class_name GroundDecor
extends Node2D
## Purely visual decoration INSIDE the green ground fill of one track chunk: darker soil patches, small stones,
## roots, buried leaves, pebble clusters and cartoon swirls. Sparse, seeded per chunk (same seed = same decor),
## no physics, one canvas item per chunk (drawn once, freed with the chunk).

const INK := Color(0.10, 0.07, 0.05)

## Visible band below the surface where decor is placed (px) and average spacing along x.
const DEPTH_MIN := 55.0
const DEPTH_MAX := 520.0
const SPACING_MIN := 95.0
const SPACING_MAX := 240.0

var items: Array = []
## v30: biome prop style ("" = Green Hills: soil patches, stones, roots, leaves, pebbles, swirls).
var style := ""
const STYLE_KINDS := {
	"moon": ["crater", "crater", "stone", "pebbles"],
	"heavy": ["vein", "stone", "stone", "pebbles"],
	"chocolate": ["nut", "sprinkles", "chip", "chip"],
	"jelly": ["bubble", "bubble", "fruit", "sprinkles"],
	"portal": ["rune", "pebbles", "stone", "rune"],
	"chasms": ["crack", "stone", "fossil", "pebbles"],
	"cavern": ["ore", "stone", "pebbles", "ore"],
	"zone": ["pipe", "stone", "crack", "pebbles"],
}


## surf: chunk surface; height_at / color_at: callables of the TerrainBuilder (deterministic).
func generate(surf: PackedVector2Array, rng: RandomNumberGenerator, height_at: Callable, color_at: Callable,
		skip_before_x: float) -> void:
	z_index = 0
	var x0 := maxf(surf[0].x, skip_before_x)
	var x1 := surf[surf.size() - 1].x
	var x := x0 + rng.randf_range(20.0, SPACING_MAX)
	while x < x1 - 20.0:
		var depth := lerpf(DEPTH_MIN, DEPTH_MAX, pow(rng.randf(), 1.6))   # more near the visible top
		var p := Vector2(x, float(height_at.call(x)) + depth)
		var col: Color = color_at.call(x, "deco")
		var kind := rng.randi_range(0, 99)
		var item := {"p": p, "col": col, "rot": rng.randf_range(-PI, PI), "s": rng.randf_range(1.3, 2.1)}
		if style != "" and STYLE_KINDS.has(style):
			var kinds: Array = STYLE_KINDS[style]
			item.type = kinds[kind % kinds.size()]
			item.pts = _blob(rng, rng.randf_range(9, 17), rng.randf_range(7, 12))
			item.stone = col.lightened(0.18)
			item.n = rng.randi_range(2, 4)
			item.offs = []
			for k in 4:
				item.offs.append(Vector2(rng.randf_range(-16, 16), rng.randf_range(-8, 8)))
			item.hue = rng.randf()
			items.append(item)
			x += rng.randf_range(SPACING_MIN, SPACING_MAX)
			continue
		if kind < 26:
			item.type = "patch"
			item.pts = _blob(rng, rng.randf_range(34, 70), rng.randf_range(14, 26))
		elif kind < 46:
			item.type = "stone"
			item.pts = _blob(rng, rng.randf_range(9, 17), rng.randf_range(7, 12))
			item.stone = Color(0.58, 0.60, 0.52).lerp(col, 0.25)
		elif kind < 62:
			item.type = "root"
			item.pts = _root(rng)
		elif kind < 76:
			item.type = "leaf"
		elif kind < 88:
			item.type = "pebbles"
			item.n = rng.randi_range(2, 4)
			item.offs = []
			for k in item.n:
				item.offs.append(Vector2(rng.randf_range(-16, 16), rng.randf_range(-6, 6)))
		else:
			item.type = "swirl"
		items.append(item)
		x += rng.randf_range(SPACING_MIN, SPACING_MAX)
	queue_redraw()


func _blob(rng: RandomNumberGenerator, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 9
	for i in n:
		var a := TAU * i / n
		var k := rng.randf_range(0.78, 1.15)
		pts.append(Vector2(cos(a) * rx * k, sin(a) * ry * k))
	return pts


func _root(rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var p := Vector2.ZERO
	var a := rng.randf_range(0.6, 2.5)   # mostly downwards
	for i in 6:
		pts.append(p)
		a += rng.randf_range(-0.5, 0.5)
		p += Vector2.RIGHT.rotated(a) * rng.randf_range(10, 18)
	return pts


func _draw() -> void:
	for it in items:
		var p: Vector2 = it.p
		var col: Color = it.col
		var s: float = it.s
		draw_set_transform(p, it.rot if it.type != "leaf" and it.type != "swirl" else 0.0, Vector2(s, s))
		match it.type:
			"patch":
				var c := col
				c.a = 0.6
				draw_colored_polygon(it.pts, c)
			"stone":
				draw_colored_polygon(it.pts, it.stone)
				var o: PackedVector2Array = (it.pts as PackedVector2Array).duplicate()
				o.append(o[0])
				draw_polyline(o, INK, 2.5, true)
				draw_line(Vector2(-3, -3), Vector2(2, -4), Color(1, 1, 1, 0.35), 2.0)
			"root":
				var rc := Color(0.33, 0.22, 0.12).lerp(col, 0.25)
				draw_polyline(it.pts, INK, 6.0, true)
				draw_polyline(it.pts, rc, 3.5, true)
				var mid: Vector2 = it.pts[3]
				draw_line(mid, mid + Vector2(10, 8), rc, 2.5, true)
			"leaf":
				# tiny buried sprout / leaf shape
				draw_set_transform(p, it.rot * 0.3, Vector2(s, s))
				var lc := col.lightened(0.28)
				var leaf := PackedVector2Array([Vector2(0, 0), Vector2(8, -6), Vector2(18, -4), Vector2(10, 2)])
				draw_colored_polygon(leaf, lc)
				var leaf2 := PackedVector2Array([Vector2(0, 0), Vector2(-7, -7), Vector2(-16, -6), Vector2(-9, 2)])
				draw_colored_polygon(leaf2, lc)
				draw_line(Vector2(0, 0), Vector2(0, 10), col.darkened(0.3), 2.5)
			"pebbles":
				for k in it.n:
					var c2: Vector2 = it.offs[k]
					draw_circle(c2, 4.5, INK)
					draw_circle(c2, 3.0, Color(0.6, 0.62, 0.55).lerp(col, 0.3))
			"swirl":
				var sc := col.darkened(0.25)
				sc.a = 0.85
				var pts := PackedVector2Array()
				for i in 22:
					var a := i * 0.45
					pts.append(Vector2(cos(a), sin(a)) * (2.0 + i * 0.75))
				draw_polyline(pts, sc, 2.5, true)
			_:
				_draw_style_item(it)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## v30 biome underground props (cartoon, inked, drawn once per chunk).
func _draw_style_item(it: Dictionary) -> void:
	var col: Color = it.col
	match String(it.type):
		"crater":
			draw_set_transform(it.p, 0.0, Vector2(it.s * 1.6, it.s * 0.7))
			draw_circle(Vector2.ZERO, 13.0, col.darkened(0.25))
			draw_arc(Vector2.ZERO, 13.0, PI * 1.05, TAU * 0.98, 12, col.lightened(0.35), 3.0, true)
			draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 18, INK, 2.0, true)
		"vein":
			var c := Color(0.35, 0.95, 0.85)
			var pts := PackedVector2Array([Vector2(-18, 4), Vector2(-6, -3), Vector2(4, 2), Vector2(18, -6)])
			draw_polyline(pts, INK, 7.0, true)
			draw_polyline(pts, c, 3.5, true)
		"nut":
			draw_set_transform(it.p, it.rot, Vector2(it.s, it.s * 0.62))
			draw_circle(Vector2.ZERO, 10.0, INK)
			draw_circle(Vector2.ZERO, 8.0, Color(0.88, 0.70, 0.45))
			draw_line(Vector2(-5, 0), Vector2(5, 0), Color(0.6, 0.42, 0.22), 2.0)
		"sprinkles":
			var cs := [Color(1, 0.35, 0.5), Color(0.35, 0.8, 1), Color(1, 0.9, 0.3), Color(0.6, 1, 0.5)]
			for k in 4:
				var o: Vector2 = it.offs[k]
				var d := Vector2.RIGHT.rotated(it.rot + k * 1.3) * 5.0
				draw_line(o - d, o + d, INK, 5.0, true)
				draw_line(o - d, o + d, cs[k], 3.0, true)
		"chip":
			var tri := PackedVector2Array([Vector2(0, -9), Vector2(8, 6), Vector2(-8, 6)])
			draw_colored_polygon(tri, Color(0.30, 0.16, 0.08))
			var o := tri.duplicate(); o.append(o[0])
			draw_polyline(o, INK, 2.0, true)
		"bubble":
			draw_circle(Vector2.ZERO, 7.0 + 5.0 * float(it.hue), Color(1, 1, 1, 0.22))
			draw_arc(Vector2.ZERO, 7.0 + 5.0 * float(it.hue), 0.0, TAU, 16, Color(1, 1, 1, 0.75), 2.0, true)
			draw_circle(Vector2(-3, -3), 2.0, Color(1, 1, 1, 0.9))
		"fruit":
			draw_circle(Vector2.ZERO, 11.0, INK)
			draw_circle(Vector2.ZERO, 9.5, Color(1.0, 0.75, 0.2) if float(it.hue) < 0.5 else Color(0.5, 0.95, 0.35))
			for k in 6:
				draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(k * TAU / 6.0) * 8.0, Color(1, 1, 0.85), 1.5)
		"rune":
			var c2 := Color(0.55, 1.0, 0.95, 0.85)
			draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 18, c2, 2.5, true)
			draw_line(Vector2(-6, 0), Vector2(6, 0), c2, 2.0)
			draw_line(Vector2(0, -6), Vector2(0, 6), c2, 2.0)
		"crack":
			var z := PackedVector2Array([Vector2(-20, -6), Vector2(-8, 3), Vector2(0, -4), Vector2(9, 5), Vector2(20, -2)])
			draw_polyline(z, col.darkened(0.55), 3.0, true)
		"fossil":
			var sp := PackedVector2Array()
			for i in 20:
				var a := i * 0.55
				sp.append(Vector2(cos(a), sin(a)) * (2.0 + i * 0.6))
			draw_polyline(sp, col.lightened(0.3), 2.5, true)
		"ore":
			var oc := Color(0.45, 0.95, 1.0) if float(it.hue) < 0.5 else Color(1.0, 0.55, 0.95)
			for k in 3:
				var base := Vector2(-8 + k * 8, 4)
				var shard := PackedVector2Array([base + Vector2(-4, 0), base + Vector2(0, -14 - k * 3), base + Vector2(4, 0)])
				draw_colored_polygon(shard, oc)
				var so := shard.duplicate(); so.append(so[0])
				draw_polyline(so, INK, 1.5, true)
		"pipe":
			draw_line(Vector2(-16, 0), Vector2(16, 0), INK, 11.0)
			draw_line(Vector2(-16, 0), Vector2(16, 0), Color(0.55, 0.32, 0.18), 7.0)
			draw_line(Vector2(-16, -2), Vector2(16, -2), Color(0.75, 0.48, 0.28), 2.0)
		"stone":
			draw_colored_polygon(it.pts, it.stone)
			var o2: PackedVector2Array = (it.pts as PackedVector2Array).duplicate()
			o2.append(o2[0])
			draw_polyline(o2, INK, 2.5, true)
		"pebbles":
			for k in it.n:
				var c3: Vector2 = it.offs[k]
				draw_circle(c3, 4.5, INK)
				draw_circle(c3, 3.0, col.lightened(0.3))
