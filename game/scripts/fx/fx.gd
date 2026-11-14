class_name Fx
extends Node2D
## Cartoon VFX spawner. Effects encode contact strength/quality (size, colour, word), so they help the
## player read the physics. Hand-drawn frame-by-frame VFX can later replace these procedural ones
## without touching gameplay: every effect is requested through the same few calls.

signal shake_requested(strength: float, duration: float)
signal physical_feedback(impact_intensity: float)
var _last_touchdown := -1

static var _puff: Texture2D
static var _spark: Texture2D
var _font: Font


## Visual pass: hand-drawn Flow sprites (res://assets/flow/fx/) replace the procedural puff / starburst; the
## procedural versions stay as fallback. Light neutral art, so the requested colour still tints it.
const FLOW_PUFF := "res://assets/flow/fx/puff.png"
const FLOW_BURSTS := ["res://assets/flow/fx/burst_0.png", "res://assets/flow/fx/burst_1.png", "res://assets/flow/fx/burst_2.png"]
static var _bursts: Array[Texture2D] = []


static func puff_texture() -> Texture2D:
	if _puff == null:
		_puff = load(FLOW_PUFF) if ResourceLoader.exists(FLOW_PUFF) else _make_puff(64)
	return _puff


static func burst_textures() -> Array[Texture2D]:
	if _bursts.is_empty():
		for p in FLOW_BURSTS:
			if ResourceLoader.exists(p):
				_bursts.append(load(p))
	return _bursts


static func _make_puff(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length() / c
			var col := Color(0, 0, 0, 0)
			if d < 0.78:
				var shade := 1.0 - 0.18 * clampf((Vector2(x - c * 0.7, y - c * 0.7).length() / c), 0.0, 1.0)
				col = Color(shade, shade, shade * 0.98, 1.0)
			elif d < 0.95:
				col = Color(0.12, 0.1, 0.1, 1.0)
			elif d < 1.0:
				col = Color(0.12, 0.1, 0.1, (1.0 - d) / 0.05)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func spark_texture() -> Texture2D:
	if _spark == null:
		var size := 32
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var c := size / 2.0
		for y in size:
			for x in size:
				var d := Vector2(x + 0.5 - c, y + 0.5 - c).length() / c
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 0.6))
		_spark = ImageTexture.create_from_image(img)
	return _spark


var _edge_layer: CanvasLayer
var _edge: Control
var _edge_t := 1.0
var _edge_dur := 0.22
var _edge_k := 0.0


func _ready() -> void:
	z_index = 20
	# screen-edge flash lives in its own layer under the HUD (layer 10): HUD stays readable, never shakes
	_edge_layer = CanvasLayer.new()
	_edge_layer.layer = 5
	add_child(_edge_layer)
	_edge = Control.new()
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.visible = false
	_edge.draw.connect(_draw_edge)
	_edge_layer.add_child(_edge)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Impact", "Arial Black", "Roboto Black", "sans-serif"])
	f.font_weight = 900
	L.apply_fallbacks(f)
	_font = f


# ---------------- building blocks ----------------

func dust(pos: Vector2, normal: Vector2, strength: float, color := Color(0.93, 0.86, 0.72)) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(clampf(6 + strength * 14, 6, 26))
	p.lifetime = 0.55 + 0.35 * strength
	p.texture = puff_texture()
	p.angle_min = -180.0   # hand-drawn puff: random orientation per particle reads as different puffs
	p.angle_max = 180.0
	p.direction = normal
	p.spread = 80.0
	p.gravity = Vector2(0, -80)
	p.initial_velocity_min = 120.0 + 260.0 * strength
	p.initial_velocity_max = 260.0 + 520.0 * strength
	p.damping_min = 300.0
	p.damping_max = 600.0
	p.scale_amount_min = 0.35 + 0.25 * strength
	p.scale_amount_max = 0.7 + 0.5 * strength
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.15))
	p.scale_amount_curve = curve
	p.color = color
	p.position = pos
	add_child(p)
	p.emitting = true
	_free_later(p, p.lifetime + 0.2)


func star(pos: Vector2, radius: float, color: Color, rot := 0.0) -> void:
	var bursts := burst_textures()
	if not bursts.is_empty():
		# variant from the position, never the global RNG (seeded runs must stay reproducible)
		var tex: Texture2D = bursts[posmod(int(pos.x * 0.7 + pos.y * 1.3), bursts.size())]
		var s := Sprite2D.new()
		s.texture = tex
		s.modulate = color.lerp(Color.WHITE, 0.25)
		s.rotation = rot
		s.position = pos
		var k := radius * 2.3 / maxf(tex.get_width(), tex.get_height())
		s.scale = Vector2.ONE * 0.2 * k
		add_child(s)
		var tws := create_tween()
		tws.tween_property(s, "scale", Vector2.ONE * 1.1 * k, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tws.tween_property(s, "scale", Vector2.ONE * 0.9 * k, 0.08)
		tws.parallel().tween_property(s, "rotation", rot + 0.25, 0.2)
		tws.tween_property(s, "modulate:a", 0.0, 0.15)
		tws.tween_callback(s.queue_free)
		return
	var pts := PackedVector2Array()
	var n := 8
	for i in n * 2:
		var r := radius if i % 2 == 0 else radius * 0.45
		pts.append(Vector2.RIGHT.rotated(TAU * i / (n * 2) + rot) * r)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = color
	var line := Line2D.new()
	line.points = pts
	line.closed = true
	line.width = 5.0
	line.default_color = Color(0.1, 0.06, 0.05)
	poly.add_child(line)
	poly.position = pos
	poly.scale = Vector2.ONE * 0.2
	add_child(poly)
	var tw := create_tween()
	tw.tween_property(poly, "scale", Vector2.ONE * 1.1, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(poly, "scale", Vector2.ONE * 0.9, 0.08)
	tw.parallel().tween_property(poly, "rotation", 0.25, 0.2)
	tw.tween_property(poly, "modulate:a", 0.0, 0.15)
	tw.tween_callback(poly.queue_free)


## Popup words are rasterised at only two font sizes and reach the requested size through scale
## (always scaled down -> crisp). Every distinct font size builds its own permanent glyph cache
## (~3 MB with the outline), so free sizes would grow memory for the whole session.
const WORD_BASE_SIZES := [64, 112]


func word(pos: Vector2, text: String, color: Color, size := 64, tilt := -0.12) -> void:
	var base: int = WORD_BASE_SIZES[0] if size <= WORD_BASE_SIZES[0] else WORD_BASE_SIZES[1]
	var k := float(size) / base
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", base)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.04))
	l.add_theme_constant_override("outline_size", int(base * 0.22))
	l.position = pos - Vector2(base * len(text) * 0.3, base * 0.6)
	l.pivot_offset = Vector2(base * len(text) * 0.3, base * 0.6)
	l.rotation = tilt
	l.scale = Vector2.ONE * 0.3 * k
	l.z_index = 30
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.15 * k, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE * k, 0.1)
	tw.tween_interval(0.35)
	tw.tween_property(l, "position:y", l.position.y - 60.0, 0.35)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


func sparks(pos: Vector2, dir: Vector2, amount: int, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.45
	p.texture = spark_texture()
	p.direction = dir
	p.spread = 60.0
	p.gravity = Vector2(0, 1400)
	p.initial_velocity_min = 350.0
	p.initial_velocity_max = 750.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.6
	p.color = color
	p.position = pos
	add_child(p)
	p.emitting = true
	_free_later(p, 0.7)


func _free_later(n: Node, t: float) -> void:
	get_tree().create_timer(t).timeout.connect(n.queue_free)


func shake(strength: float, duration := 0.25) -> void:
	# Visual-only calls never produce haptics.
	shake_requested.emit(strength, duration)


func impact_feedback(strength: float, duration := 0.25) -> void:
	var impact_intensity := clampf(strength / 38.0, 0.0, 1.0)
	shake_requested.emit(impact_intensity * 38.0, duration)
	physical_feedback.emit(impact_intensity)


func reset_contact_feedback() -> void:
	_last_touchdown = -1


# ---------------- gameplay events ----------------

func spring_touchdown(info: Dictionary) -> void:
	var s := clampf(info.impact / 1600.0, 0.1, 1.0)
	dust(info.point, info.normal, s)
	# touchdown is sometimes re-emitted when a second foot upgrades the SAME contact.
	var event_id := int(info.get("time", -1))
	if info.impact > 30.0 and (event_id < 0 or event_id != _last_touchdown):
		_last_touchdown = event_id
		impact_feedback(6.0 * s, 0.15)


func landing_burst(info: Dictionary) -> void:
	if info.has("spin_bonus"):
		return   # power_bounce() draws this landing (no double words)
	var p: Vector2 = info.point
	var n: Vector2 = info.normal
	match info.type:
		&"both":
			if info.quality == &"sweet":
				word(p + n * 150, "BOING!", Color(1.0, 0.85, 0.15), 76)
				star(p + n * 40, 70, Color(1, 0.92, 0.3))
				impact_feedback(10.0, 0.2)
			elif info.quality == &"flat":
				word(p + n * 150, "BOING!", Color(0.55, 0.95, 1.0), 64)
				star(p + n * 30, 52, Color(0.7, 0.95, 1.0))
			else:
				word(p + n * 140, "BOING", Color(1, 1, 1), 50)
		&"right":
			word(p + n * 130 + Vector2(40, 0), "ZOOM!", Color(0.45, 1.0, 0.45), 54, -0.2)
			sparks(p, Vector2(-1, -0.4), 14, Color(1, 0.8, 0.3))
		&"left":
			word(p + n * 130, "SKRRT", Color(1.0, 0.55, 0.35), 46, 0.1)
			dust(p, Vector2(-1, -0.5).normalized(), 0.6, Color(0.85, 0.72, 0.55))
		&"poor":
			word(p + n * 120, "BONK", Color(0.8, 0.8, 0.8), 44, 0.15)


func body_hit(info: Dictionary) -> void:
	var s := clampf(info.impact / 1400.0, 0.15, 1.0)
	var p: Vector2 = info.point
	var n: Vector2 = info.normal
	if n.dot(Vector2.UP) < 0.0:
		n = -n
	dust(p, n, s, Color(0.8, 0.78, 0.75))
	if info.impact > 240.0:
		star(p + n * 20, 40 + 40 * s, Color(1.0, 0.45, 0.2))
		word(p + n * 130, "CRASH!", Color(1.0, 0.4, 0.25), int(48 + 24 * s), 0.12)
		sparks(p, n, 12, Color(1, 0.75, 0.2))
	impact_feedback(8.0 + 14.0 * s, 0.25)


## Floating damage number; colour tells the hit class (feet / side / head).
func damage_number(pos: Vector2, amount: float, zone_class: StringName) -> void:
	var col := Color(1.0, 0.9, 0.3)
	if zone_class == &"side":
		col = Color(1.0, 0.55, 0.2)
	elif zone_class == &"head":
		col = Color(1.0, 0.25, 0.2)
	word(pos + Vector2(70, -110), "-%d" % int(round(amount)), col, 44 if zone_class == &"feet" else 58, 0.08)


## Spin charge spent on a new contact. Strength = EFFECTIVE boost (charge x zone efficiency x robot energy),
## so 100% on the feet is a big gold explosion and 100% on the torso only a small puff. 0.1-0.3 s long.
func charged_impact(pos: Vector2, normal: Vector2, effective: float, zone_class: StringName) -> void:
	if normal.dot(Vector2.UP) < 0.0:
		normal = -normal
	var k := clampf(effective, 0.0, 1.8)
	if k < 0.03:
		return
	_flash_disc(pos + normal * 20.0, 40.0 + 120.0 * k)
	star(pos + normal * 25.0, 40.0 + 100.0 * k, Color(1.0, 0.82, 0.15) if zone_class == &"feet" else Color(1.0, 0.95, 0.75), 0.2)
	sparks(pos + normal * 15.0, normal, 6 + int(22.0 * k), Color(1.0, 0.85, 0.3))
	if zone_class == &"feet" and k > 0.25:
		word(pos + normal * 200 + Vector2(30, 0), L.t("FX_SUPER_BOING") if k > 0.8 else L.t("FX_BOING_PLUS"), Color(1.0, 0.78, 0.1), int(52 + 34 * minf(k, 1.0)), -0.1)
	elif k > 0.12:
		word(pos + normal * 150, L.t("FX_PFF"), Color(0.95, 0.9, 0.8), 40, 0.1)
	if k >= 0.35:
		edge_flash(k)
	impact_feedback(3.0 + 17.0 * minf(k, 1.4), 0.12 + 0.12 * minf(k, 1.0))


## Very short white disc at the contact point (the "flash" of the starburst).
func _flash_disc(pos: Vector2, radius: float) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		pts.append(Vector2.RIGHT.rotated(TAU * i / 20.0) * radius)
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = Color(1, 1, 0.92, 0.85)
	p.position = pos
	p.scale = Vector2.ONE * 0.4
	add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.07)
	tw.parallel().tween_property(p, "modulate:a", 0.0, 0.14)
	tw.tween_callback(p.queue_free)


## Vintage cartoon sparks/rays in the screen corners for a strong boost (0.1-0.25 s).
func edge_flash(k: float) -> void:
	_edge_k = clampf(k, 0.0, 1.5)
	_edge_dur = 0.12 + 0.12 * minf(k, 1.0)
	_edge_t = 0.0
	_edge.visible = true


func _process(dt: float) -> void:
	if _edge.visible:
		_edge_t += dt
		if _edge_t >= _edge_dur:
			_edge.visible = false
		else:
			_edge.queue_redraw()


func _draw_edge() -> void:
	var s := _edge.size
	var a := (1.0 - _edge_t / _edge_dur) * clampf(0.35 + 0.45 * _edge_k, 0.0, 0.85)
	var gold := Color(1.0, 0.85, 0.3, a)
	var white := Color(1.0, 1.0, 0.95, a)
	var corners := [Vector2.ZERO, Vector2(s.x, 0), Vector2(0, s.y), s]
	var rays := 5 + int(4 * minf(_edge_k, 1.0))
	var grow := 0.6 + 0.4 * _edge_t / _edge_dur
	for c in corners:
		var toward: Vector2 = (s * 0.5 - c).normalized()
		for i in rays:
			var ang := toward.angle() + (float(i) / (rays - 1) - 0.5) * 1.3
			var ray_len := (90.0 + 120.0 * minf(_edge_k, 1.2)) * grow * (0.7 + 0.3 * ((i * 7) % 3) / 2.0)
			var tip: Vector2 = c + Vector2.RIGHT.rotated(ang) * ray_len
			var side: Vector2 = Vector2.RIGHT.rotated(ang + PI * 0.5) * 9.0
			_edge.draw_colored_polygon(PackedVector2Array([c + side, tip, c - side]), gold if i % 2 == 0 else white)
		# a small 4-point spark flying in
		var sp: Vector2 = c + toward * (60.0 + 80.0 * _edge_t / _edge_dur)
		for j in 4:
			var d := Vector2.RIGHT.rotated(j * PI * 0.5) * 16.0
			_edge.draw_line(sp - d * 0.2, sp + d, white, 4.0)


## (legacy name kept for callers/tests)
func power_bounce(pos: Vector2, normal: Vector2, c: float) -> void:
	if normal.dot(Vector2.UP) < 0.0:
		normal = -normal
	star(pos + normal * 30, 60 + 70 * c, Color(1.0, 0.8, 0.15), 0.2)
	var ring := 10 + int(18 * c)
	for i in 2:
		sparks(pos + normal * 20, normal.rotated((i - 0.5) * 1.2), ring, Color(1.0, 0.85, 0.3))
	word(pos + normal * 200 + Vector2(30, 0), L.t("FX_SUPER_BOING") if c > 0.8 else L.t("FX_BOING_PLUS"), Color(1.0, 0.78, 0.1), int(56 + 30 * c), -0.1)
	impact_feedback(8.0 + 10.0 * c, 0.22)


func limb_pop(pos: Vector2) -> void:
	impact_feedback(12.0, 0.25)
	star(pos, 44, Color(1, 1, 1))
	sparks(pos, Vector2.UP, 16, Color(1, 0.85, 0.4))
	word(pos + Vector2(0, -90), "KRAK!", Color(1, 0.95, 0.85), 48, 0.1)


func rocket_ignite(pos: Vector2, _info: Dictionary) -> void:
	star(pos, 110, Color(1, 0.75, 0.2))
	dust(pos, Vector2.UP, 1.0, Color(0.9, 0.9, 0.9))
	word(pos + Vector2(0, -170), "BOOM!", Color(1.0, 0.75, 0.15), 92)
	edge_flash(1.2)
	# body destroyed + jet head ignition: the strongest shake in the game
	impact_feedback(38.0, 0.6)


func flick_impact(pos: Vector2) -> void:
	star(pos, 120, Color(1, 1, 0.85))
	sparks(pos, Vector2.RIGHT, 22, Color(1, 0.95, 0.6))
	word(pos + Vector2(40, -170), L.t("FX_CLICK"), Color(1.0, 0.9, 0.2), 96)
	impact_feedback(22.0, 0.35)


## Remove transient effects between attempts, preserving the reusable edge overlay.
func reset_attempt() -> void:
	reset_contact_feedback()
	_edge_t = 1.0
	_edge_k = 0.0
	for child in get_children():
		if child != _edge_layer:
			child.queue_free()
