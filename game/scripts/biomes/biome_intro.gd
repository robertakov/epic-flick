class_name BiomeIntro
extends Control
## Biome title card shown just before gameplay starts (level already built and visible, blurred + dimmed behind).
## ~2 s (in 0.25 s, hold, out 0.3 s). A tap anywhere skips it immediately and is CONSUMED: the overlay keeps blocking
## input until that touch / click is released, then gameplay input starts clean (InputRouter.reset()).
## Physics / timers do not run meanwhile: the robot is frozen until the flick, the flick bar only starts afterwards.
## Each biome has its own lettering treatment, all built from the same inked 1930s cartoon vocabulary.

signal finished(skipped: bool)

const DURATION := 2.0
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 1.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 5.0;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * 0.16;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.105;
	c += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb * 0.105;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.105;
	c += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb * 0.105;
	c += texture(screen_tex, SCREEN_UV + px).rgb * 0.08;
	c += texture(screen_tex, SCREEN_UV - px).rgb * 0.08;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)).rgb * 0.08;
	c += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)).rgb * 0.08;
	c += texture(screen_tex, SCREEN_UV + vec2(2.0 * px.x, 0.0)).rgb * 0.05;
	c += texture(screen_tex, SCREEN_UV - vec2(2.0 * px.x, 0.0)).rgb * 0.05;
	c = mix(c, tint.rgb, 0.28) * 0.62;
	COLOR = vec4(c, amount);
}
"""

var biome: BiomeDef
var active := false
var _t := 0.0
var _swallow := false
var _alpha := 0.0
var _blur: ColorRect
var _title: Control
var _title_layer: CanvasLayer
var _font: SystemFont
var _skipped := false
## Autotest: the harness skips the card instantly unless a test asks for the real presentation.
var instant := false


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_blur = ColorRect.new()
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_blur.material = mat
	add_child(_blur)
	# the lettering lives on its own canvas layer above the UI (layer 10): the screen-reading blur can never sample it
	_title_layer = CanvasLayer.new()
	_title_layer.layer = 11
	_title_layer.visible = false
	add_child(_title_layer)
	_title = Control.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.draw.connect(_draw_title)
	_title_layer.add_child(_title)
	visibility_changed.connect(func() -> void: _title_layer.visible = is_visible_in_tree())
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Impact", "Arial Black", "Roboto Black", "Roboto", "sans-serif"])
	_font.font_weight = 900
	L.apply_fallbacks(_font)


## Leave without starting gameplay (menu / abandon while the card is up).
func cancel() -> void:
	active = false
	_swallow = false
	visible = false


## True while the card is on screen or still swallowing the skip tap.
func blocking() -> bool:
	return active or _swallow


func show_biome(def: BiomeDef) -> void:
	biome = def
	active = true
	_swallow = false
	_skipped = false
	_t = 0.0
	visible = true
	var mat := _blur.material as ShaderMaterial
	mat.set_shader_parameter("tint", _tint())
	if instant:
		call_deferred("_end", true)


func _tint() -> Color:
	match biome.title_style:
		"moon": return Color(0.05, 0.08, 0.25)
		"heavy": return Color(0.35, 0.08, 0.22)
		"chocolate": return Color(0.45, 0.25, 0.12)
		"jelly": return Color(0.55, 0.15, 0.45)
		"portal": return Color(0.22, 0.05, 0.40)
		"chasms": return Color(0.45, 0.15, 0.05)
		"cavern": return Color(0.06, 0.05, 0.05)
		"zone": return Color(0.20, 0.28, 0.06)
	return Color(0.10, 0.35, 0.10)


func _process(dt: float) -> void:
	if not active:
		return
	_t += dt
	_alpha = clampf(_t / 0.25, 0.0, 1.0) * clampf((DURATION - _t) / 0.3, 0.0, 1.0)
	(_blur.material as ShaderMaterial).set_shader_parameter("amount", _alpha)
	_title.queue_redraw()
	if _t >= DURATION:
		_end(false)


func _gui_input(event: InputEvent) -> void:
	var pressed := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	var released := (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed) \
		or (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed)
	if pressed and active:
		accept_event()
		_swallow = true
		_end(true, false)
	elif released and _swallow:
		accept_event()
		_swallow = false
		visible = false
		finished.emit(_skipped)


func _input(event: InputEvent) -> void:
	# a raw ScreenTouch release can arrive outside the Control's gui path: clear the swallow there too
	if _swallow and event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		_swallow = false
		visible = false
		get_viewport().set_input_as_handled()
		finished.emit(_skipped)


func _end(skipped: bool, emit := true) -> void:
	if not active:
		return
	active = false
	_skipped = skipped
	_alpha = 0.0
	(_blur.material as ShaderMaterial).set_shader_parameter("amount", 0.0)
	_title.queue_redraw()
	if emit:
		visible = false
		finished.emit(skipped)


# ---------------- title drawing ----------------

func _draw_title() -> void:
	if not active or biome == null:
		return
	var size := get_viewport_rect().size
	var text := L.data(biome.display_name)
	var a := _alpha
	var t := _t
	var pop := 1.0 + 0.18 * exp(-t * 7.0) * sin(t * 22.0)          # rubber-hose overshoot pop-in
	var fs := int(clampf(size.x * 0.88 / maxf(text.length() * 0.62, 1.0), 60.0, 190.0))
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w
	var origin := Vector2(size.x * 0.5 - total * 0.5 * pop, size.y * 0.5 + fs * 0.35)
	_backdrop(size, a, t, fs, total * pop)
	var st := biome.title_style
	var fill := Color(0.55, 0.88, 0.30)
	var outline := Color(0.10, 0.07, 0.05)
	match st:
		"moon": fill = Color(0.86, 0.90, 1.0)
		"heavy": fill = Color(0.32, 0.86, 0.80)
		"chocolate": fill = Color(0.45, 0.24, 0.11)
		"jelly": fill = Color(1.0, 0.42, 0.72)
		"portal": fill = Color(0.45, 1.0, 0.92)
		"chasms": fill = Color(0.95, 0.55, 0.25)
		"cavern": fill = Color(0.66, 0.62, 0.56)
		"zone": fill = Color(1.0, 0.84, 0.12)
	var x := 0.0
	for i in text.length():
		var ch := text[i]
		var w: float = widths[i]
		var off := Vector2.ZERO
		var sc := Vector2(pop, pop)
		var rot := 0.0
		var col := fill
		match st:
			"moon":
				off.y = sin(t * 2.2 + i * 0.6) * fs * 0.05
			"heavy":
				var land := clampf((t - i * 0.04) / 0.22, 0.0, 1.0)
				off.y = -(1.0 - land) * size.y * 0.5
				sc = Vector2(1.18, 0.78) if land >= 1.0 else Vector2(0.9, 1.15)
			"chocolate":
				off.y = sin(t * 3.0 + i) * fs * 0.025
			"jelly":
				var wob := sin(t * 9.0 + i * 0.9) * 0.14 * exp(-t * 0.8)
				sc = Vector2(pop * (1.0 + wob), pop * (1.0 - wob))
				col = fill if i % 2 == 0 else Color(0.55, 0.95, 0.35)
			"portal":
				var step := int(t * 8.0 + i * 3)
				off = Vector2(((step * 37) % 7 - 3) * 1.6, ((step * 53) % 7 - 3) * 1.6) * (1.0 if t < 0.5 else 0.25)
				col = fill if i % 2 == 0 else Color(1.0, 0.45, 0.92)
			"chasms":
				rot = sin(i * 1.7) * 0.06
				off.y = (i % 2) * fs * 0.05
			"cavern":
				rot = sin(i * 2.3) * 0.04
			"zone":
				rot = sin(i * 3.1) * 0.03
		var p := origin + Vector2(x * pop, 0) + off
		_title.draw_set_transform(p + Vector2(w * 0.5, -fs * 0.35), rot, sc)
		var lp := Vector2(-w * 0.5, fs * 0.35)
		_title.draw_string(_font, lp + Vector2(fs * 0.05, fs * 0.07), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55 * a))
		_title.draw_string_outline(_font, lp, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.13), Color(outline, a))
		_title.draw_string(_font, lp, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
		_letter_detail(st, lp, w, fs, t, i, a)
		_title.draw_set_transform_matrix(Transform2D.IDENTITY)
		x += w


## Per-letter decoration in the letter's local space (baseline at lp.y).
func _letter_detail(st: String, lp: Vector2, w: float, fs: int, t: float, i: int, a: float) -> void:
	var top := lp.y - fs * 0.72
	match st:
		"moon":
			_title.draw_circle(Vector2(lp.x + w * 0.35, top + fs * 0.35), fs * 0.045, Color(0.6, 0.65, 0.85, a))
			_title.draw_circle(Vector2(lp.x + w * 0.62, top + fs * 0.55), fs * 0.03, Color(0.6, 0.65, 0.85, a))
		"chocolate":
			# pink icing cap with drips
			_title.draw_line(Vector2(lp.x + w * 0.12, top - fs * 0.01), Vector2(lp.x + w * 0.88, top - fs * 0.01), Color(1.0, 0.62, 0.78, a), fs * 0.09)
			var drip := fs * (0.10 + 0.08 * fposmod(i * 0.37, 1.0)) * clampf(t * 2.0, 0.0, 1.0)
			_title.draw_line(Vector2(lp.x + w * 0.4, top - fs * 0.01), Vector2(lp.x + w * 0.4, top - fs * 0.01 + drip), Color(1.0, 0.62, 0.78, a), fs * 0.05)
			_title.draw_circle(Vector2(lp.x + w * 0.4, top - fs * 0.01 + drip), fs * 0.03, Color(1.0, 0.62, 0.78, a))
		"jelly":
			_title.draw_line(Vector2(lp.x + w * 0.25, top + fs * 0.18), Vector2(lp.x + w * 0.45, top + fs * 0.15), Color(1, 1, 1, 0.75 * a), fs * 0.045)
		"chasms":
			# a crack runs through the letter
			_title.draw_polyline(PackedVector2Array([Vector2(lp.x + w * 0.2, top + fs * 0.3), Vector2(lp.x + w * 0.45, top + fs * 0.42),
				Vector2(lp.x + w * 0.38, top + fs * 0.5), Vector2(lp.x + w * 0.75, top + fs * 0.62)]), Color(0.18, 0.06, 0.03, a), fs * 0.03)
		"cavern":
			_title.draw_line(Vector2(lp.x + w * 0.15, top + fs * 0.04), Vector2(lp.x + w * 0.85, top + fs * 0.04), Color(0.35, 0.7, 0.3, a), fs * 0.05)
			_title.draw_polyline(PackedVector2Array([Vector2(lp.x + w * 0.3, top + fs * 0.25), Vector2(lp.x + w * 0.5, top + fs * 0.4),
				Vector2(lp.x + w * 0.42, top + fs * 0.55)]), Color(0.22, 0.2, 0.18, a), fs * 0.025)
		"zone":
			for k in 4:
				var u := fposmod(i * 0.71 + k * 0.37, 1.0)
				var v := fposmod(i * 0.29 + k * 0.53, 1.0)
				_title.draw_circle(Vector2(lp.x + w * (0.15 + 0.7 * u), top + fs * (0.15 + 0.6 * v)), fs * 0.02, Color(0.35, 0.25, 0.05, 0.7 * a))


## Theme elements behind the lettering (drawn in screen space).
func _backdrop(size: Vector2, a: float, t: float, fs: int, text_w := 0.0) -> void:
	var c := size * 0.5
	var ink := Color(0.10, 0.07, 0.05, a)
	match biome.title_style:
		"green":
			for k in 18:
				var ang := TAU * k / 18.0 + t * 0.25
				_title.draw_line(c + Vector2.RIGHT.rotated(ang) * fs * 1.1, c + Vector2.RIGHT.rotated(ang) * size.x, Color(1, 0.9, 0.4, 0.22 * a), 30.0)
		"moon":
			for k in 40:
				var p := Vector2(fposmod(k * 137.0, size.x), fposmod(k * 89.0, size.y))
				_title.draw_circle(p, 2.0 + (k % 3), Color(1, 1, 0.9, (0.5 + 0.5 * sin(t * 3.0 + k)) * a))
		"heavy":
			var shake := Vector2(sin(t * 60.0), cos(t * 47.0)) * 6.0 * exp(-t * 4.0)
			_title.draw_set_transform(shake, 0, Vector2.ONE)
			for k in 3:
				_title.draw_line(Vector2(c.x - fs * 3.0, c.y + fs * (0.7 + k * 0.12)), Vector2(c.x + fs * 3.0, c.y + fs * (0.7 + k * 0.12)), Color(0, 0, 0, 0.35 * a), 8.0)
			_title.draw_set_transform_matrix(Transform2D.IDENTITY)
		"chocolate":
			var cs := [Color(1, 0.35, 0.5), Color(0.35, 0.8, 1), Color(1, 0.9, 0.3), Color(0.6, 1, 0.5)]
			for k in 30:
				var p2 := Vector2(fposmod(k * 151.0 + t * 30.0, size.x), fposmod(k * 97.0 + t * 80.0, size.y))
				var d := Vector2.RIGHT.rotated(k) * 9.0
				_title.draw_line(p2 - d, p2 + d, Color(cs[k % 4], a), 7.0)
		"jelly":
			for k in 10:
				var p3 := Vector2(fposmod(k * 211.0, size.x), fposmod(k * 131.0 + sin(t * 2.0 + k) * 20.0, size.y))
				_title.draw_rect(Rect2(p3, Vector2(36, 36)), Color(1, 0.5, 0.75, 0.3 * a))
		"portal":
			for k in 6:
				var r := fs * (0.9 + k * 0.35)
				var a0 := t * (2.0 - k * 0.2) * (1 if k % 2 == 0 else -1)
				_title.draw_arc(c, r, a0, a0 + PI * 1.2, 32, Color(0.4, 1.0, 0.92, 0.35 * a) if k % 2 == 0 else Color(1, 0.4, 0.9, 0.35 * a), 10.0)
		"chasms":
			for k in 12:
				var p4 := Vector2(fposmod(k * 173.0, size.x), fposmod(k * 61.0 + t * 260.0, size.y))
				_title.draw_rect(Rect2(p4, Vector2(14, 12)), Color(0.45, 0.22, 0.12, 0.8 * a))
		"cavern":
			var fl := 0.5 + 0.5 * sin(t * 13.0)
			for s in [-1.0, 1.0]:
				var tp := c + Vector2(s * fs * 3.2, 0)
				_title.draw_circle(tp, fs * (0.9 + 0.1 * fl), Color(1, 0.6, 0.2, 0.18 * a))
		"zone":
			var band := Rect2(0, c.y - fs * 0.62, size.x, fs * 1.05)
			_title.draw_rect(band, Color(0.12, 0.10, 0.04, 0.75 * a))
			var k := -int(fs)
			while k < int(size.x) + int(fs):
				var x0 := float(k) + fposmod(t * 40.0, 60.0)
				_title.draw_colored_polygon(PackedVector2Array([Vector2(x0, band.position.y), Vector2(x0 + 30, band.position.y),
					Vector2(x0 + 30 - 24, band.position.y + 16), Vector2(x0 - 24, band.position.y + 16)]), Color(1, 0.8, 0.1, a))
				_title.draw_colored_polygon(PackedVector2Array([Vector2(x0, band.end.y - 16), Vector2(x0 + 30, band.end.y - 16),
					Vector2(x0 + 30 - 24, band.end.y), Vector2(x0 - 24, band.end.y)]), Color(1, 0.8, 0.1, a))
				k += 60
			for s2 in [-1.0, 1.0]:
				var tc := c + Vector2(s2 * minf(size.x * 0.5 - fs * 0.45, text_w * 0.5 + fs * 0.55), 0)
				_title.draw_circle(tc, fs * 0.42, Color(1, 0.8, 0.1, a))
				for j in 3:
					var a1 := -PI * 0.5 + j * TAU / 3.0 - 0.5
					_title.draw_arc(tc, fs * 0.22, a1, a1 + 1.0, 8, ink, fs * 0.2)
				_title.draw_circle(tc, fs * 0.06, ink)
