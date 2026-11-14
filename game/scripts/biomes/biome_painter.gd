class_name BiomePainter
extends RefCounted
## Screen-space backdrops of the special biomes (drawn by Background every frame, parallax from the camera).
## Procedural, inked 1930s-cartoon shapes; ~100-250 cheap draw calls, no textures except the exclusion-zone
## skyline (sprites extracted from Assets/Biom). All animation is time-based (stars twinkle, flames dance,
## jelly wobbles, portals swirl, anomalies pulse).

const INK := Color(0.10, 0.07, 0.05)

static var _tex := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := "res://assets/biomes/zone/%s.png" % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


## ---------------- hand-painted Flow layers (visual pass, tools/flow/*) ----------------
## res://assets/flow/biomes/<style>/{sky,far,mid}.png: painted sky (opaque) + mirror-tiled hill strips. Each biome
## keeps its animated identity elements (stars, Earth, vortex, jelly, torches, birds...) and falls back to the
## procedural shapes for any layer whose texture is missing.
static var _flow := {}
## mean bottom colour of each strip (printed by make_layers.py): flat fill below the painted bottom
const FLOW_FILL := {
	"cavern/mid": Color(0.199, 0.114, 0.093), "chasms/far": Color(0.608, 0.264, 0.176),
	"chasms/mid": Color(0.325, 0.155, 0.109), "chocolate/far": Color(0.259, 0.129, 0.097),
	"chocolate/mid": Color(0.508, 0.271, 0.161), "heavy/far": Color(0.083, 0.042, 0.132),
	"heavy/mid": Color(0.275, 0.167, 0.278), "jelly/far": Color(0.745, 0.268, 0.376),
	"jelly/mid": Color(0.680, 0.753, 0.211), "moon/far": Color(0.368, 0.441, 0.472),
	"moon/mid": Color(0.477, 0.450, 0.533), "portal/far": Color(0.191, 0.131, 0.335),
	"portal/mid": Color(0.157, 0.115, 0.253), "zone/mid": Color(0.233, 0.219, 0.165),
}


static func flow(style: String, layer: String) -> Texture2D:
	var key := style + "/" + layer
	if not _flow.has(key):
		var path := "res://assets/flow/biomes/%s/%s.png" % [style, layer]
		_flow[key] = load(path) if ResourceLoader.exists(path) else null
	return _flow[key]


static func _sky(c: CanvasItem, size: Vector2, style: String, top: Color, bottom: Color) -> void:
	var s := flow(style, "sky")
	if s:
		c.draw_texture_rect(s, Rect2(Vector2.ZERO, size), false)
	else:
		_grad(c, size, top, bottom)


## Painted strip tiled A, mirrored A, A, ... (seamless by construction); flat fill below its painted bottom.
static func strip(c: CanvasItem, size: Vector2, tex: Texture2D, scroll: float, y: float, h: float, fill: Color,
		mod := Color.WHITE) -> void:
	var w := h * tex.get_width() / tex.get_height()
	var x := -fposmod(scroll, 2.0 * w)
	var k := 0
	while x < size.x:
		if k % 2 == 0:
			c.draw_texture_rect(tex, Rect2(x, y, w + 1.0, h), false, mod)
		else:
			c.draw_set_transform(Vector2(x + w, y), 0.0, Vector2(-1.0, 1.0))
			c.draw_texture_rect(tex, Rect2(0, 0, w + 1.0, h), false, mod)
			c.draw_set_transform_matrix(Transform2D.IDENTITY)
		x += w
		k += 1
	if y + h < size.y:
		c.draw_rect(Rect2(0, y + h - 1.0, size.x, size.y - y - h + 1.0), fill * mod)


## Draws the style's painted layer if present; returns false so the caller can fall back to its procedural ridge.
static func _layer(c: CanvasItem, size: Vector2, style: String, layer: String, scroll: float, y: float, h: float) -> bool:
	var tx := flow(style, layer)
	if tx == null:
		return false
	strip(c, size, tx, scroll, y, h, FLOW_FILL.get(style + "/" + layer, Color(0.2, 0.2, 0.2)))
	return true


static func paint(c: CanvasItem, style: String, size: Vector2, cam: Vector2, t: float) -> void:
	match style:
		"moon": _moon(c, size, cam, t)
		"heavy": _heavy(c, size, cam, t)
		"chocolate": _chocolate(c, size, cam, t)
		"jelly": _jelly(c, size, cam, t)
		"portal": _portal(c, size, cam, t)
		"chasms": _chasms(c, size, cam, t)
		"cavern": _cavern(c, size, cam, t)
		"zone": _zone(c, size, cam, t)


# ---------------- helpers ----------------

static func _grad(c: CanvasItem, size: Vector2, top: Color, bottom: Color, bands := 14) -> void:
	for i in bands:
		var t0 := float(i) / bands
		c.draw_rect(Rect2(0, size.y * t0, size.x, size.y / bands + 1), top.lerp(bottom, t0))


static func _hash(i: int, k: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453, 1.0)


## Wavy / jagged band from base_y down to the bottom of the screen.
static func _ridge(c: CanvasItem, size: Vector2, scroll: float, base_y: float, amp: float, freq: float, color: Color,
		jag := 0.0, ink := 5.0, step := 22.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= size.x + step:
		var u := x + scroll
		var y := base_y + amp * (0.55 * sin(u * freq) + 0.3 * sin(u * freq * 2.37 + 1.3) + 0.15 * sin(u * freq * 5.1 + 0.4))
		if jag > 0.0:
			y += jag * (absf(fposmod(u * 0.021, 2.0) - 1.0) - 0.5)
		pts.append(Vector2(x, y))
		x += step
	var line := pts.duplicate()
	pts.append(Vector2(size.x + step, size.y))
	pts.append(Vector2(0, size.y))
	c.draw_colored_polygon(pts, color)
	if ink > 0.0:
		c.draw_polyline(line, Color(INK, 0.85), ink, true)
	return line


static func _blob(c: CanvasItem, p: Vector2, r: float, col: Color, ink := 4.0) -> void:
	c.draw_circle(p, r + ink, INK)
	c.draw_circle(p, r, col)


static func _wrap(x: float, w: float) -> float:
	return fposmod(x, w)


# ---------------- MOON ----------------

static func _moon(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	_sky(c, size, "moon", Color(0.02, 0.03, 0.09), Color(0.13, 0.15, 0.27))
	for i in 80:
		var x := _wrap(_hash(i, 1) * 3000.0 - cam.x * 0.01, 3000.0) * size.x / 3000.0
		var y := _hash(i, 2) * size.y * 0.72
		var tw := 0.6 + 0.4 * sin(t * (1.5 + _hash(i, 3) * 3.0) + i)
		var r := (1.2 + _hash(i, 4) * 2.2) * tw
		c.draw_circle(Vector2(x, y), r, Color(1, 1, 0.92, 0.55 + 0.45 * tw))
		if i % 11 == 0:
			c.draw_line(Vector2(x - r * 3, y), Vector2(x + r * 3, y), Color(1, 1, 0.9, 0.5 * tw), 1.5)
			c.draw_line(Vector2(x, y - r * 3), Vector2(x, y + r * 3), Color(1, 1, 0.9, 0.5 * tw), 1.5)
	# the Earth, clearly visible: ocean, continents, clouds, night side, halo
	var e := Vector2(size.x * 0.76, size.y * 0.22)
	var er := minf(size.y * 0.13, 92.0)
	c.draw_circle(e, er * 1.35, Color(0.45, 0.7, 1.0, 0.10))
	c.draw_circle(e, er * 1.15, Color(0.45, 0.7, 1.0, 0.16))
	_blob(c, e, er, Color(0.20, 0.50, 0.92), 5.0)
	var spin := t * 0.03
	for k in 4:
		var a := spin + k * 1.7
		var cp := e + Vector2(cos(a) * er * 0.45, sin(a * 1.3) * er * 0.35)
		var poly := PackedVector2Array()
		for j in 9:
			var aa := TAU * j / 9.0
			poly.append(cp + Vector2(cos(aa), sin(aa)) * er * (0.22 + 0.1 * _hash(k * 9 + j, 7)))
		c.draw_colored_polygon(poly, Color(0.30, 0.72, 0.30))
	for k in 3:
		c.draw_arc(e + Vector2(0, (k - 1) * er * 0.38), er * 0.75, -2.6 + spin, -1.2 + spin, 10, Color(1, 1, 1, 0.75), 5.0, true)
	c.draw_arc(e + Vector2(er * 0.28, 0), er * 0.95, -1.35, 1.35, 20, Color(0.02, 0.03, 0.10, 0.55), er * 0.55, true)
	c.draw_arc(e, er, 0, TAU, 40, INK, 5.0, true)
	# far grey mountains with craters, near ridge
	var vy := clampf(-cam.y * 0.01, -50.0, 50.0)
	if flow("moon", "far") and flow("moon", "mid"):
		_layer(c, size, "moon", "far", cam.x * 0.05, size.y * 0.62 + vy - 95.0, 230.0)
		_layer(c, size, "moon", "mid", cam.x * 0.14, size.y * 0.75 + vy * 1.4 - 70.0, 240.0)
		return
	_ridge(c, size, cam.x * 0.05, size.y * 0.62 + vy, 60.0, 0.004, Color(0.24, 0.26, 0.36), 34.0)
	var near := _ridge(c, size, cam.x * 0.14, size.y * 0.75 + vy * 1.4, 45.0, 0.006, Color(0.34, 0.36, 0.46), 20.0)
	for i in 6:
		var px := _wrap(i * 380.0 - cam.x * 0.14, size.x + 300.0) - 150.0
		var idx := clampi(int(px / 22.0), 0, near.size() - 1)
		var py := near[idx].y + 30.0 + (i % 3) * 14.0
		c.draw_set_transform(Vector2(px, py), 0.0, Vector2(1.0, 0.35))
		c.draw_circle(Vector2.ZERO, 26.0 + (i % 2) * 12.0, Color(0.27, 0.29, 0.38))
		c.draw_arc(Vector2.ZERO, 26.0 + (i % 2) * 12.0, PI, TAU, 14, Color(0.55, 0.57, 0.66), 4.0, true)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	# tiny lander on the far range every ~3500 px
	var lx := _wrap(1900.0 - cam.x * 0.05, 3500.0)
	if lx < size.x:
		var ly := size.y * 0.62 + vy - 32.0
		c.draw_rect(Rect2(lx - 14, ly - 10, 28, 16), Color(0.85, 0.75, 0.35))
		c.draw_line(Vector2(lx - 14, ly + 6), Vector2(lx - 22, ly + 22), INK, 3.0)
		c.draw_line(Vector2(lx + 14, ly + 6), Vector2(lx + 22, ly + 22), INK, 3.0)
		c.draw_line(Vector2(lx + 4, ly - 10), Vector2(lx + 4, ly - 36), INK, 2.0)
		c.draw_rect(Rect2(lx + 4, ly - 36, 16, 10), Color(0.9, 0.2, 0.2))


# ---------------- HEAVY WORLD ----------------

static func _heavy(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	_sky(c, size, "heavy", Color(0.16, 0.05, 0.16), Color(0.86, 0.42, 0.24))
	if flow("heavy", "sky") == null:
		_heavy_planet(c, size, t)
	# gravity streaks falling fast
	for i in 18:
		var x := _wrap(_hash(i, 5) * size.x * 1.3 - cam.x * 0.03, size.x)
		var y := fposmod(_hash(i, 6) * size.y + t * (420.0 + 260.0 * _hash(i, 8)), size.y * 1.2) - size.y * 0.1
		c.draw_line(Vector2(x, y), Vector2(x, y + 46.0), Color(1, 0.85, 0.7, 0.22), 3.0)
	var vy := clampf(-cam.y * 0.01, -50.0, 50.0)
	if flow("heavy", "far") and flow("heavy", "mid"):
		_layer(c, size, "heavy", "far", cam.x * 0.06, size.y * 0.66 + vy - 70.0, 200.0)
		_layer(c, size, "heavy", "mid", cam.x * 0.16, size.y * 0.78 + vy * 1.5 - 60.0, 220.0)
		return
	_heavy_ground(c, size, cam, vy)


static func _heavy_planet(c: CanvasItem, size: Vector2, t: float) -> void:
	# the colossal planet that "pulls" everything down
	var pc := Vector2(size.x * 0.68, size.y * 0.30)
	var pr := size.y * 0.42
	c.draw_circle(pc, pr * 1.06, Color(0.95, 0.55, 0.30, 0.18))
	_blob(c, pc, pr, Color(0.62, 0.30, 0.42), 6.0)
	var bands := [Color(0.74, 0.40, 0.44), Color(0.52, 0.22, 0.38), Color(0.80, 0.52, 0.46), Color(0.46, 0.18, 0.34)]
	for b in 7:
		var y0 := -pr + pr * 2.0 * (b + 0.15) / 7.0
		var y1 := y0 + pr * 2.0 / 7.0 * 0.55
		var poly := PackedVector2Array()
		for j in 13:
			var yy := lerpf(y0, y1, j / 12.0)
			poly.append(pc + Vector2(-sqrt(maxf(pr * pr - yy * yy, 0.0)) * 0.98, yy + sin(j + t * 0.3) * 2.0))
		for j in range(12, -1, -1):
			var yy2 := lerpf(y0, y1, j / 12.0)
			poly.append(pc + Vector2(sqrt(maxf(pr * pr - yy2 * yy2, 0.0)) * 0.98, yy2))
		c.draw_colored_polygon(poly, bands[b % bands.size()])
	c.draw_arc(pc, pr, 0.0, TAU, 60, INK, 6.0, true)
	# ring (front half drawn over the planet)
	c.draw_set_transform(pc, -0.25, Vector2(1.0, 0.22))
	c.draw_arc(Vector2.ZERO, pr * 1.55, 0.05, PI - 0.05, 40, INK, 26.0, true)
	c.draw_arc(Vector2.ZERO, pr * 1.55, 0.05, PI - 0.05, 40, Color(0.98, 0.78, 0.55), 16.0, true)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _heavy_ground(c: CanvasItem, size: Vector2, cam: Vector2, vy: float) -> void:
	# crushed squat mesas and fallen pillars
	var far := _ridge(c, size, cam.x * 0.06, size.y * 0.66 + vy, 22.0, 0.003, Color(0.30, 0.12, 0.26), 0.0)
	for i in 5:
		var px := _wrap(i * 520.0 - cam.x * 0.06, size.x + 500.0) - 250.0
		var idx := clampi(int(px / 22.0), 0, far.size() - 1)
		var base := far[idx].y + 10.0
		var w := 150.0 + (i % 3) * 60.0
		var h := 46.0 + (i % 2) * 22.0
		var mesa := PackedVector2Array([Vector2(px - w * 0.6, base), Vector2(px - w * 0.5, base - h), Vector2(px + w * 0.45, base - h - 8.0),
			Vector2(px + w * 0.6, base)])
		c.draw_colored_polygon(mesa, Color(0.36, 0.15, 0.30))
		var mo := mesa.duplicate(); mo.append(mo[0])
		c.draw_polyline(mo, INK, 4.0, true)
		c.draw_line(Vector2(px - w * 0.2, base - h + 4), Vector2(px - w * 0.1, base - 6), Color(0.15, 0.04, 0.12), 3.0)
	_ridge(c, size, cam.x * 0.16, size.y * 0.78 + vy * 1.5, 18.0, 0.005, Color(0.42, 0.18, 0.32), 0.0)
	for i in 4:
		var px2 := _wrap(i * 700.0 + 300.0 - cam.x * 0.16, size.x + 600.0) - 300.0
		var py2 := size.y * 0.78 + vy * 1.5 + 6.0
		c.draw_set_transform(Vector2(px2, py2), 0.08 * (i - 1.5), Vector2.ONE)
		c.draw_rect(Rect2(-90, -22, 180, 22), Color(0.52, 0.30, 0.44))
		c.draw_rect(Rect2(-90, -22, 180, 22), INK, false, 4.0)
		for k in 4:
			c.draw_line(Vector2(-60 + k * 40, -22), Vector2(-60 + k * 40, 0), INK, 2.0)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------- CHOCOLATE WORLD ----------------

static func _chocolate(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	_sky(c, size, "chocolate", Color(0.50, 0.80, 0.98), Color(1.0, 0.92, 0.82))
	var sun := Vector2(size.x * 0.84, size.y * 0.19)
	for k in 16:
		var a := TAU * k / 16.0 + t * 0.15
		var col := Color(1.0, 0.55, 0.70) if k % 2 == 0 else Color(1, 1, 1)
		c.draw_line(sun + Vector2.RIGHT.rotated(a) * 72, sun + Vector2.RIGHT.rotated(a) * 112, col, 12.0)
	_blob(c, sun, 60.0, Color(1.0, 0.86, 0.35), 6.0)
	c.draw_arc(sun + Vector2(0, 8), 26.0, 0.3, PI - 0.3, 10, INK, 4.0)
	c.draw_circle(sun + Vector2(-18, -10), 5.0, INK)
	c.draw_circle(sun + Vector2(18, -10), 5.0, INK)
	# cotton-candy clouds
	for i in 4:
		var cx := _wrap(i * 470.0 - cam.x * 0.05 - t * 6.0, size.x + 400.0) - 200.0
		var cy := 70.0 + (i * 41) % 120
		var ct := flow("chocolate", "cloud_%02d" % i)
		if ct:
			var cw := 170.0 + 40.0 * (i % 2)
			var chh := cw * ct.get_height() / ct.get_width()
			c.draw_texture_rect(ct, Rect2(cx, cy - chh * 0.5 + sin(t * 0.6 + i * 1.9) * 3.0, cw, chh), false)
			continue
		for j in 4:
			c.draw_circle(Vector2(cx + j * 38.0, cy + (j % 2) * 10.0), 34.0 + 4.0, Color(INK, 0.4))
		for j in 4:
			c.draw_circle(Vector2(cx + j * 38.0, cy + (j % 2) * 10.0), 34.0, Color(1.0, 0.78, 0.88) if j % 2 == 0 else Color(1, 0.93, 0.97))
	var vy := clampf(-cam.y * 0.01, -50.0, 50.0)
	# chocolate hills with icing drips
	if not _layer(c, size, "chocolate", "far", cam.x * 0.06, size.y * 0.60 + vy - 70.0, 210.0):
		var far := _ridge(c, size, cam.x * 0.06, size.y * 0.60 + vy, 55.0, 0.004, Color(0.48, 0.28, 0.16), 0.0)
		for i in range(0, far.size() - 1, 3):
			var p := far[i]
			var drip := 10.0 + 14.0 * _hash(i + int(cam.x * 0.06 / 66.0), 3)
			c.draw_line(p, p + Vector2(0, drip), Color(1, 0.96, 0.95), 9.0)
			c.draw_circle(p + Vector2(0, drip), 5.0, Color(1, 0.96, 0.95))
		c.draw_polyline(far, Color(1, 0.96, 0.95), 10.0, true)
	if _layer(c, size, "chocolate", "mid", cam.x * 0.15, size.y * 0.73 + vy * 1.4 - 95.0, 250.0):
		return
	# candy canes, lollipops and gingerbread folk on the mid hills
	var mid := _ridge(c, size, cam.x * 0.15, size.y * 0.73 + vy * 1.4, 35.0, 0.006, Color(0.66, 0.40, 0.22), 0.0)
	for i in 7:
		var px := _wrap(i * 300.0 + 80.0 - cam.x * 0.15, size.x + 600.0) - 300.0
		var idx := clampi(int(px / 22.0), 0, mid.size() - 1)
		var base := mid[idx].y + 6.0
		match i % 3:
			0:
				var cane := PackedVector2Array([Vector2(px, base), Vector2(px, base - 120)])
				c.draw_polyline(cane, INK, 22.0)
				c.draw_polyline(cane, Color(1, 1, 1), 15.0)
				for s in 6:
					c.draw_line(Vector2(px - 7, base - 10 - s * 20), Vector2(px + 7, base - 20 - s * 20), Color(0.92, 0.12, 0.18), 6.0)
				c.draw_arc(Vector2(px + 22, base - 120), 22.0, PI, TAU, 12, INK, 22.0)
				c.draw_arc(Vector2(px + 22, base - 120), 22.0, PI, TAU, 12, Color(0.92, 0.12, 0.18), 14.0)
			1:
				c.draw_line(Vector2(px, base), Vector2(px, base - 95), Color(0.97, 0.95, 0.9), 7.0)
				_blob(c, Vector2(px, base - 120), 34.0, Color(1.0, 0.45, 0.65), 5.0)
				var sp := PackedVector2Array()
				for k in 26:
					var a := k * 0.6 + t * 1.2
					sp.append(Vector2(px, base - 120) + Vector2(cos(a), sin(a)) * (2.0 + k * 1.15))
				c.draw_polyline(sp, Color(1, 1, 1), 5.0, true)
			2:
				_ginger(c, Vector2(px, base), 1.0 + 0.2 * sin(t * 2.0 + i))


static func _ginger(c: CanvasItem, p: Vector2, bob: float) -> void:
	var col := Color(0.78, 0.48, 0.24)
	var h := Vector2(p.x, p.y - 92 - bob * 2.0)
	_blob(c, h, 18.0, col, 4.0)
	var body := PackedVector2Array([p + Vector2(-20, -70), p + Vector2(20, -70), p + Vector2(24, -26), p + Vector2(-24, -26)])
	c.draw_colored_polygon(body, col)
	c.draw_line(p + Vector2(-20, -66), p + Vector2(-44, -50 - bob * 6.0), col, 14.0)
	c.draw_line(p + Vector2(20, -66), p + Vector2(44, -50 + bob * 6.0), col, 14.0)
	c.draw_line(p + Vector2(-12, -28), p + Vector2(-18, 0), col, 14.0)
	c.draw_line(p + Vector2(12, -28), p + Vector2(18, 0), col, 14.0)
	c.draw_polyline(PackedVector2Array([p + Vector2(-20, -70), p + Vector2(-24, -26), p + Vector2(24, -26), p + Vector2(20, -70)]), INK, 3.0)
	for k in 3:
		c.draw_circle(p + Vector2(0, -62 + k * 12), 3.5, Color(1, 0.3, 0.4))
	c.draw_circle(h + Vector2(-6, -3), 2.5, INK)
	c.draw_circle(h + Vector2(6, -3), 2.5, INK)
	c.draw_arc(h + Vector2(0, 3), 7.0, 0.3, PI - 0.3, 8, Color(1, 1, 1), 2.5)


# ---------------- JELLY WORLD ----------------

static func _jelly(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	_sky(c, size, "jelly", Color(0.58, 0.94, 0.86), Color(1.0, 0.86, 0.95))
	for i in 9:
		var x := _wrap(_hash(i, 1) * 2600.0 - cam.x * 0.04 + t * 12.0, size.x + 200.0) - 100.0
		var y := 50.0 + _hash(i, 2) * size.y * 0.45 + sin(t * 1.3 + i) * 10.0
		var s := 26.0 + _hash(i, 3) * 22.0
		var sq := 1.0 + 0.12 * sin(t * 4.0 + i * 1.7)
		var cols := [Color(1.0, 0.35, 0.55, 0.75), Color(0.45, 0.95, 0.35, 0.75), Color(1.0, 0.78, 0.2, 0.75), Color(0.55, 0.6, 1.0, 0.75)]
		c.draw_set_transform(Vector2(x, y), sin(t * 0.7 + i) * 0.2, Vector2(sq, 1.0 / sq))
		if i % 3 == 2:
			_bear(c, s * 0.9, cols[i % 4])
		else:
			c.draw_rect(Rect2(-s, -s, s * 2, s * 2), cols[i % 4])
			c.draw_rect(Rect2(-s, -s, s * 2, s * 2), Color(INK, 0.8), false, 4.0)
			c.draw_line(Vector2(-s * 0.6, -s * 0.6), Vector2(-s * 0.1, -s * 0.6), Color(1, 1, 1, 0.8), 5.0)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	var vy := clampf(-cam.y * 0.01, -50.0, 50.0)
	# wobbling jelly hills (raspberry, lime) - the whole range jiggles
	var w1 := sin(t * 3.2) * 10.0
	if flow("jelly", "far") and flow("jelly", "mid"):
		# painted jelly ranges keep the jiggle: horizontal sway + vertical bounce, opposite phases
		_layer(c, size, "jelly", "far", cam.x * 0.05 + w1, size.y * 0.60 + vy + sin(t * 2.6) * 6.0 - 80.0, 220.0)
		_layer(c, size, "jelly", "mid", cam.x * 0.13 - w1, size.y * 0.74 + vy * 1.4 + sin(t * 3.1 + 1.0) * 8.0 - 70.0, 230.0)
		return
	_ridge(c, size, cam.x * 0.05 + w1, size.y * 0.60 + vy + sin(t * 2.6) * 6.0, 60.0, 0.004, Color(0.98, 0.45, 0.62, 0.9))
	_ridge(c, size, cam.x * 0.13 - w1, size.y * 0.74 + vy * 1.4 + sin(t * 3.1 + 1.0) * 8.0, 40.0, 0.006, Color(0.50, 0.88, 0.40, 0.92))


static func _bear(c: CanvasItem, s: float, col: Color) -> void:
	c.draw_circle(Vector2(0, -s * 0.9), s * 0.55, col)
	c.draw_circle(Vector2(-s * 0.45, -s * 1.35), s * 0.22, col)
	c.draw_circle(Vector2(s * 0.45, -s * 1.35), s * 0.22, col)
	c.draw_circle(Vector2(0, 0), s * 0.75, col)
	c.draw_circle(Vector2(-s * 0.55, s * 0.6), s * 0.3, col)
	c.draw_circle(Vector2(s * 0.55, s * 0.6), s * 0.3, col)
	c.draw_arc(Vector2(0, 0), s * 0.75, 0, TAU, 18, Color(INK, 0.7), 3.0)
	c.draw_arc(Vector2(0, -s * 0.9), s * 0.55, 0, TAU, 14, Color(INK, 0.7), 3.0)


# ---------------- PORTAL ZONE ----------------

static func _portal(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	_sky(c, size, "portal", Color(0.07, 0.03, 0.17), Color(0.34, 0.14, 0.48))
	var painted := flow("portal", "far") != null and flow("portal", "mid") != null
	for i in (0 if painted else 50):
		var x := _wrap(_hash(i, 1) * 2400.0 - cam.x * 0.012, 2400.0) * size.x / 2400.0
		c.draw_circle(Vector2(x, _hash(i, 2) * size.y * 0.7), 1.5 + _hash(i, 3) * 1.5, Color(0.8, 1, 1, 0.6))
	# the great vortex
	var v := Vector2(size.x * 0.30, size.y * 0.26)
	for k in 7:
		var r := 30.0 + k * 26.0
		var a0 := t * (0.9 - k * 0.08) + k * 0.9
		var col := Color(0.35, 1.0, 0.92, 0.75 - k * 0.08) if k % 2 == 0 else Color(1.0, 0.35, 0.9, 0.7 - k * 0.08)
		c.draw_arc(v, r, a0, a0 + PI * 1.3, 24, col, 9.0 - k * 0.6, true)
	_blob(c, v, 22.0, Color(0.02, 0.0, 0.06), 4.0)
	var pvy := clampf(-cam.y * 0.01, -50.0, 50.0)
	if painted:
		_layer(c, size, "portal", "far", cam.x * 0.07, size.y * 0.58 + pvy - 60.0, 220.0)
	# drifting doors and frames
	for i in 5:
		var x2 := _wrap(i * 430.0 - cam.x * 0.07, size.x + 300.0) - 150.0
		var y2 := size.y * 0.35 + (i % 3) * 50.0 + sin(t * 1.2 + i) * 14.0
		c.draw_set_transform(Vector2(x2, y2), sin(t * 0.5 + i) * 0.25, Vector2.ONE)
		c.draw_rect(Rect2(-22, -36, 44, 72), Color(0.95, 0.35, 0.85, 0.35))
		c.draw_rect(Rect2(-22, -36, 44, 72), Color(0.4, 1.0, 0.95, 0.9), false, 4.0)
		c.draw_circle(Vector2(12, 2), 3.0, Color(1, 0.9, 0.4))
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	var vy := pvy
	if painted:
		_layer(c, size, "portal", "mid", cam.x * 0.16, size.y * 0.80 + vy * 1.5 - 95.0, 230.0)
		return
	# floating geometric islands with neon edges
	for i in 4:
		var x3 := _wrap(i * 600.0 + 200.0 - cam.x * 0.12, size.x + 500.0) - 250.0
		var y3 := size.y * 0.62 + vy + (i % 2) * 40.0 + sin(t * 0.9 + i * 2.0) * 8.0
		var isl := PackedVector2Array([Vector2(x3 - 90, y3), Vector2(x3 + 90, y3), Vector2(x3 + 40, y3 + 60), Vector2(x3 - 30, y3 + 70)])
		c.draw_colored_polygon(isl, Color(0.22, 0.16, 0.36))
		c.draw_line(Vector2(x3 - 90, y3), Vector2(x3 + 90, y3), Color(0.45, 1, 0.92), 6.0)
		var io := isl.duplicate(); io.append(io[0])
		c.draw_polyline(io, INK, 3.0)
	_ridge(c, size, cam.x * 0.16, size.y * 0.80 + vy * 1.5, 26.0, 0.006, Color(0.20, 0.14, 0.34), 0.0, 4.0)


# ---------------- CHASMS ----------------

static func _chasms(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	_sky(c, size, "chasms", Color(0.92, 0.48, 0.28), Color(1.0, 0.86, 0.58))
	var vy := clampf(-cam.y * 0.01, -50.0, 50.0)
	if flow("chasms", "far") and flow("chasms", "mid"):
		# the painted sky carries its own setting sun
		_layer(c, size, "chasms", "far", cam.x * 0.05, size.y * 0.58 + vy - 90.0, 260.0)
		_layer(c, size, "chasms", "mid", cam.x * 0.14, size.y * 0.76 + vy * 1.4 - 80.0, 240.0)
		_chasms_air(c, size, cam, t)
		return
	var sun := Vector2(size.x * 0.70, size.y * 0.52)
	c.draw_circle(sun, 96.0, Color(1.0, 0.95, 0.65, 0.35))
	_blob(c, sun, 74.0, Color(1.0, 0.80, 0.40), 5.0)
	# layered canyon mesas, split by deep dark cracks
	var far := _ridge(c, size, cam.x * 0.05, size.y * 0.58 + vy, 70.0, 0.0035, Color(0.70, 0.34, 0.22), 40.0)
	for i in 4:
		var y := size.y * 0.66 + vy + i * 22.0
		c.draw_line(Vector2(0, y), Vector2(size.x, y + sin(cam.x * 0.001 + i) * 6.0), Color(0.58, 0.26, 0.16, 0.5), 5.0)
	for i in 5:
		var px := _wrap(i * 410.0 - cam.x * 0.05, size.x + 300.0) - 150.0
		var idx := clampi(int(px / 22.0), 0, far.size() - 1)
		var top := far[idx].y
		var crack := PackedVector2Array()
		for k in 7:
			crack.append(Vector2(px + (12.0 if k % 2 == 0 else -12.0) * (1.0 - k / 7.0), top + k * 26.0))
		c.draw_polyline(crack, Color(0.15, 0.05, 0.03), 9.0 - 0.0, true)
	_ridge(c, size, cam.x * 0.14, size.y * 0.76 + vy * 1.4, 40.0, 0.006, Color(0.55, 0.24, 0.15), 30.0)
	_chasms_air(c, size, cam, t)


static func _chasms_air(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	# drifting broken rock chunks over the abyss
	for i in 6:
		var x2 := _wrap(i * 330.0 + t * 8.0 - cam.x * 0.09, size.x + 200.0) - 100.0
		var y2 := size.y * (0.40 + 0.06 * (i % 3)) + sin(t * 0.8 + i * 1.7) * 12.0
		var rock := PackedVector2Array([Vector2(-26, -10), Vector2(-4, -18), Vector2(24, -8), Vector2(18, 10), Vector2(-14, 14)])
		c.draw_set_transform(Vector2(x2, y2), sin(t * 0.4 + i) * 0.4, Vector2.ONE * (0.8 + 0.25 * (i % 3)))
		c.draw_colored_polygon(rock, Color(0.42, 0.22, 0.15))
		var ro := rock.duplicate(); ro.append(ro[0])
		c.draw_polyline(ro, INK, 3.0)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	# circling birds of prey
	for i in 3:
		var a := t * 0.4 + i * 2.1
		var b := Vector2(size.x * 0.4 + cos(a) * 160.0, size.y * 0.25 + sin(a) * 40.0)
		var fl := sin(t * 6.0 + i) * 6.0
		c.draw_polyline(PackedVector2Array([b + Vector2(-14, -fl), b, b + Vector2(14, -fl)]), INK, 3.0)


# ---------------- CAVERN ----------------

static func _cavern(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	_sky(c, size, "cavern", Color(0.09, 0.07, 0.08), Color(0.19, 0.15, 0.14))
	if flow("cavern", "sky") and flow("cavern", "mid"):
		# painted back wall (strata + stalactites) and stalagmite row; the glowing life stays procedural
		_layer(c, size, "cavern", "mid", cam.x * 0.10, size.y * 0.70 - 40.0, 260.0)
		_cavern_lights(c, size, cam, t)
		return
	# geological layers of the far wall
	var layer_cols := [Color(0.22, 0.17, 0.15), Color(0.17, 0.13, 0.12), Color(0.26, 0.20, 0.16), Color(0.15, 0.12, 0.12)]
	for i in 6:
		var by := size.y * (0.12 + i * 0.15)
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= size.x + 30.0:
			pts.append(Vector2(x, by + 18.0 * sin((x + cam.x * 0.04) * 0.004 + i * 1.3) + 8.0 * sin((x + cam.x * 0.04) * 0.013 + i)))
			x += 30.0
		var band := pts.duplicate()
		band.append(Vector2(size.x + 30.0, by + size.y * 0.15 + 30.0))
		band.append(Vector2(0, by + size.y * 0.15 + 30.0))
		c.draw_colored_polygon(band, layer_cols[i % layer_cols.size()])
		c.draw_polyline(pts, Color(0.05, 0.04, 0.04, 0.6), 3.0, true)
	# distant stalactites / stalagmites
	for i in 12:
		var px := _wrap(i * 170.0 - cam.x * 0.10, size.x + 200.0) - 100.0
		var h := 50.0 + 70.0 * _hash(i, 4)
		var tri := PackedVector2Array([Vector2(px - 26, 0), Vector2(px + 26, 0), Vector2(px + 3, h)])
		c.draw_colored_polygon(tri, Color(0.12, 0.09, 0.09))
		var tri2 := PackedVector2Array([Vector2(px + 60, size.y), Vector2(px + 110, size.y), Vector2(px + 86, size.y - h * 1.3)])
		c.draw_colored_polygon(tri2, Color(0.13, 0.10, 0.09))
	_cavern_lights(c, size, cam, t)


static func _cavern_lights(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	# glowing crystals, mushrooms and torches (local lights: atmospheric darkness, fully readable foreground)
	for i in 6:
		var px := _wrap(i * 360.0 + 120.0 - cam.x * 0.16, size.x + 400.0) - 200.0
		var py := size.y * (0.55 + 0.1 * (i % 3))
		var breath := 0.5 + 0.5 * sin(t * 1.6 + i * 1.3)
		match i % 3:
			0:
				var cc := Color(0.35, 0.95, 1.0) if i % 2 == 0 else Color(1.0, 0.45, 0.95)
				c.draw_circle(Vector2(px, py), 70.0 + 14.0 * breath, Color(cc, 0.10 + 0.06 * breath))
				for k in 4:
					var base := Vector2(px - 24 + k * 16, py + 20)
					var shard := PackedVector2Array([base + Vector2(-9, 0), base + Vector2(-2 + k, -38 - k * 9), base + Vector2(9, 0)])
					c.draw_colored_polygon(shard, cc.lerp(Color.WHITE, 0.2 * breath))
					var so := shard.duplicate(); so.append(so[0])
					c.draw_polyline(so, INK, 3.0)
			1:
				var mc := Color(0.55, 1.0, 0.55)
				c.draw_circle(Vector2(px, py), 54.0 + 10.0 * breath, Color(mc, 0.10 + 0.05 * breath))
				for k in 3:
					var sway := sin(t * 1.4 + i + k) * 5.0
					var stem := Vector2(px - 20 + k * 22, py + 24)
					var cap := stem + Vector2(sway, -30 - k * 6)
					c.draw_line(stem, cap, Color(0.92, 0.9, 0.78), 6.0)
					c.draw_circle(cap, 15.0 - k * 2.0 + 4.0, INK)
					c.draw_circle(cap, 15.0 - k * 2.0, mc.lerp(Color(0.2, 0.9, 0.5), breath * 0.5))
					c.draw_circle(cap + Vector2(-4, -4), 3.0, Color(1, 1, 1, 0.8))
			2:
				_torch(c, Vector2(px, py - 30.0), t, i)


static func _torch(c: CanvasItem, p: Vector2, t: float, i: int) -> void:
	var fl := 0.5 + 0.5 * sin(t * 13.0 + i)
	c.draw_circle(p + Vector2(0, -24), 90.0 + 10.0 * fl, Color(1.0, 0.6, 0.2, 0.10))
	c.draw_circle(p + Vector2(0, -24), 50.0 + 6.0 * fl, Color(1.0, 0.7, 0.3, 0.14))
	c.draw_line(p, p + Vector2(0, 40), INK, 10.0)
	c.draw_line(p, p + Vector2(0, 40), Color(0.5, 0.3, 0.15), 6.0)
	# hand-drawn style 4-pose flame cycle (stepped, not smooth)
	var pose := int(t * 10.0 + i) % 4
	var lean: float = [-6.0, 4.0, -2.0, 7.0][pose]
	var hgt: float = [44.0, 52.0, 40.0, 48.0][pose]
	var flame := PackedVector2Array([p + Vector2(-13, 0), p + Vector2(-10 + lean * 0.3, -hgt * 0.5), p + Vector2(lean, -hgt),
		p + Vector2(10 + lean * 0.3, -hgt * 0.45), p + Vector2(13, 0)])
	c.draw_colored_polygon(flame, Color(1.0, 0.45, 0.10))
	var fo := flame.duplicate(); fo.append(fo[0])
	c.draw_polyline(fo, INK, 3.0)
	var inner := PackedVector2Array([p + Vector2(-6, 0), p + Vector2(lean * 0.6, -hgt * 0.6), p + Vector2(6, 0)])
	c.draw_colored_polygon(inner, Color(1.0, 0.92, 0.4))


# ---------------- EXCLUSION ZONE ----------------

const ZONE_SKYLINE := ["block_bear", "pylon_a", "block_a", "cooling_tower", "reactor", "crane", "block_atom", "pylon_b",
	"ferris_wheel", "block_b", "watchtower"]


## Ground anchors measured in the existing cropped PNGs (opaque base; no artwork changes).
## Skyline X/size retain the original distant parallax. Convert the displayed anchor back to world X,
## query the authoritative local terrain there, then project Y with the real camera transform.
const ZONE_GROUND_ANCHORS := {
	"block_bear": Vector2(98.5, 219),
	"pylon_a": Vector2(90.0, 143),
	"block_a": Vector2(102.5, 196),
	"cooling_tower": Vector2(76.5, 212),
	"reactor": Vector2(154.0, 219),
	"crane": Vector2(70.0, 143),
	"block_atom": Vector2(104.0, 196),
	"pylon_b": Vector2(52.0, 143),
	"ferris_wheel": Vector2(109.5, 219),
	"block_b": Vector2(90.0, 219),
	"watchtower": Vector2(56.0, 143),
}


## Opaque foot spans in source pixels (bottom 8 rows); arms/booms are not foundations.
const ZONE_FOOT_SPANS := {
	"block_bear": Vector2(0, 196),
	"pylon_a": Vector2(4, 178),
	"block_a": Vector2(1, 204),
	"cooling_tower": Vector2(2, 152),
	"reactor": Vector2(0, 306),
	"crane": Vector2(0, 138),
	"block_atom": Vector2(0, 207),
	"pylon_b": Vector2(6, 103),
	"ferris_wheel": Vector2(0, 218),
	"block_b": Vector2(0, 179),
	"watchtower": Vector2(1, 110),
}


static func zone_layout(size: Vector2, cam: Vector2, world_to_screen: Transform2D, terrain: TerrainBuilder) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(terrain) or terrain.points.is_empty():
		return out
	var spacing := 260.0
	var scroll := cam.x * 0.06
	var first := int(floor(scroll / spacing)) - 1
	var screen_to_terrain := (world_to_screen * terrain.global_transform).affine_inverse()
	for k in range(first, first + int(size.x / spacing) + 3):
		var name: String = ZONE_SKYLINE[posmod(k, ZONE_SKYLINE.size())]
		var tx := tex(name)
		if tx == null: continue
		var sc := (size.y * (0.30 if name in ["reactor", "cooling_tower", "ferris_wheel"] else 0.24)) / tx.get_height()
		var x := k * spacing - scroll + _hash(posmod(k, 97), 3) * 60.0
		var anchor: Vector2 = ZONE_GROUND_ANCHORS[name]
		var ground_x := (screen_to_terrain * Vector2(x + anchor.x * sc, 0)).x
		# Do not fake a horizontal extrapolation outside the streamed surface.
		if ground_x < terrain.points[0].x or ground_x > terrain.end_x(): continue
		# Support the whole opaque foot, not only its centre: the downhill corner must not float.
		# Lowest local surface under the foot is the minimal burial that supports every corner.
		var foot: Vector2 = ZONE_FOOT_SPANS[name]
		var left := (screen_to_terrain * Vector2(x + foot.x * sc, 0)).x
		var right := (screen_to_terrain * Vector2(x + foot.y * sc, 0)).x
		if left < terrain.points[0].x or right > terrain.end_x(): continue
		var support := Vector2(left, terrain.surface_y(left))
		var end := Vector2(right, terrain.surface_y(right))
		if end.y > support.y: support = end
		for point in terrain.points:
			if point.x > right: break
			if point.x >= left and point.y > support.y: support = point
		ground_x = support.x
		var ground := world_to_screen * terrain.to_global(support)
		anchor.x = (ground.x - x) / sc
		var rect := Rect2(Vector2(x, ground.y - anchor.y * sc), tx.get_size() * sc)
		out.append({"name": name, "rect": rect, "anchor": anchor, "scale": sc, "world_x": ground_x, "ground": ground})
	return out


static func _zone(c: CanvasItem, size: Vector2, cam: Vector2, t: float) -> void:
	_sky(c, size, "zone", Color(0.30, 0.35, 0.26), Color(0.70, 0.70, 0.52))
	var painted_sky := flow("zone", "sky") != null
	# toxic green swirl in the clouds (cf. Assets/Biom reference scene)
	var v := Vector2(size.x * 0.55, size.y * 0.15)
	for k in 5:
		var a0 := t * (0.35 + k * 0.05) + k * 1.2
		c.draw_arc(v, 40.0 + k * 22.0, a0, a0 + PI * 1.2, 22, Color(0.55, 1.0, 0.45, 0.45 - k * 0.06), 10.0 - k, true)
	# murky clouds (the painted sky already has its own)
	for i in (0 if painted_sky else 5):
		var cx := _wrap(i * 420.0 - cam.x * 0.03, size.x + 400.0) - 200.0
		var cy := 40.0 + (i * 37) % 110
		for j in 4:
			c.draw_circle(Vector2(cx + j * 44.0, cy + (j % 2) * 12.0), 38.0, Color(0.52, 0.55, 0.42, 0.85))
	var vy := clampf(-cam.y * 0.01, -50.0, 50.0)
	# Pripyat skyline: the extracted sheet objects, hazed into the distance
	var horizon := size.y * 0.66 + vy
	for item in zone_layout(size, cam, c.get_viewport().get_canvas_transform(), BiomeRuntime.terrain):
		c.draw_texture_rect(tex(item.name), item.rect, false, Color(0.62, 0.66, 0.56, 1.0))
	# haze + dark forest band in front
	c.draw_rect(Rect2(0, horizon - size.y * 0.35, size.x, size.y * 0.35), Color(0.62, 0.64, 0.50, 0.25))
	if _layer(c, size, "zone", "mid", cam.x * 0.12, size.y * 0.74 + vy * 1.4 - 90.0, 230.0):
		return
	var pines := PackedVector2Array()
	var x2 := 0.0
	while x2 <= size.x + 30.0:
		var u := x2 + cam.x * 0.12
		var spike := absf(fposmod(u * 0.025, 2.0) - 1.0)
		pines.append(Vector2(x2, size.y * 0.74 + vy * 1.4 - 26.0 * spike - 10.0 * sin(u * 0.004)))
		x2 += 15.0
	var band := pines.duplicate()
	band.append(Vector2(size.x + 30.0, size.y))
	band.append(Vector2(0, size.y))
	c.draw_colored_polygon(band, Color(0.20, 0.26, 0.16))
	c.draw_polyline(pines, Color(INK, 0.8), 3.0, true)
