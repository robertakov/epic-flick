class_name Background
extends CanvasLayer
## Screen-space cartoon backdrop (sky, sun, clouds, two hill bands) scrolled from the camera position.
## Green Hills uses hand-painted 1930s-cartoon layers (Google Flow, tools/flow/*): painted sky, animated sun sheet,
## drifting cloud sprites and two horizontally seamless hill strips. Every layer falls back to the original
## procedural drawing if its texture is missing. Other biomes are painted by BiomePainter.

var camera: Camera2D
var _canvas: Node2D

## Animated sun sheet layout is fixed here on purpose (no JSON at runtime - non-resource files need the export
## include_filter).
const SUN_SHEET_PATH := "res://assets/flow/sun_1930s_sheet.png"
const SUN_FRAMES := 72
const SUN_COLS := 9
const SUN_FRAME_PX := 256
const SUN_FPS := 12.0
const SUN_DRAW_PX := 260.0   # on-screen size at the 1280x720 base (old procedural sun: ~210 px incl. rays)
const GH_DIR := "res://assets/flow/green_hills/"
const CLOUD_COUNT := 5
## on-screen widths of the 5 cloud sprites (base 1280x720)
const CLOUD_W := [230.0, 150.0, 130.0, 120.0, 210.0]
const CLOUD_DRIFT := 7.0      # px/s, very slow wind
const FAR_H := 250.0          # drawn height of the far hill strip
const MID_H := 250.0          # drawn height of the middle hill strip
## mean bottom-row colours printed by make_layers.py (flat fill below each strip)
const FAR_FILL := Color(0.519, 0.608, 0.528)
const MID_FILL := Color(0.412, 0.566, 0.280)

var _sun_sheet: Texture2D
var _sky: Texture2D
var _far: Texture2D
var _mid: Texture2D
var _clouds: Array[Texture2D] = []


func _ready() -> void:
	layer = -10
	_sun_sheet = _tex(SUN_SHEET_PATH)
	_sky = _tex(GH_DIR + "sky.png")
	_far = _tex(GH_DIR + "hills_far.png")
	_mid = _tex(GH_DIR + "hills_mid.png")
	for i in CLOUD_COUNT:
		var c := _tex(GH_DIR + "cloud_%d.png" % i)
		if c == null:
			_clouds.clear()
			break
		_clouds.append(c)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_bg)
	add_child(_canvas)


static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _process(_dt: float) -> void:
	_canvas.queue_redraw()


func _hill(x: float, seed_phase: float, amp: float) -> float:
	return amp * (0.55 * sin(x * 0.0021 + seed_phase) + 0.3 * sin(x * 0.0053 + seed_phase * 2.1) + 0.15 * sin(x * 0.011 + seed_phase * 0.7))


func _draw_bg() -> void:
	var size := _canvas.get_viewport_rect().size
	var cam := camera.get_screen_center_position() if camera else Vector2.ZERO
	var t := Time.get_ticks_msec() * 0.001
	# v30: special biomes paint their own world (BiomePainter); Green Hills keeps its own backdrop below
	var style := BiomeRuntime.current().sky
	if style != "green":
		BiomePainter.paint(_canvas, style, size, cam, t)
		return
	if _sky:
		_canvas.draw_texture_rect(_sky, Rect2(Vector2.ZERO, size), false)
	else:
		_draw_procedural_sky(size)
	# sun
	var sun := Vector2(size.x * 0.82, size.y * 0.2)
	if _sun_sheet:
		var f := int(t * SUN_FPS) % SUN_FRAMES
		var src := Rect2((f % SUN_COLS) * SUN_FRAME_PX, (f / SUN_COLS) * SUN_FRAME_PX, SUN_FRAME_PX, SUN_FRAME_PX)
		var d := SUN_DRAW_PX
		_canvas.draw_texture_rect_region(_sun_sheet, Rect2(sun - Vector2(d, d) * 0.5, Vector2(d, d)), src)
	else:
		_draw_procedural_sun(sun)
	# clouds: same slots as the original backdrop, plus a slow wind drift and a barely visible bob
	var cw := size.x + 600.0
	for c in 5:
		var cx := fposmod(c * 430.0 - cam.x * 0.05 - t * CLOUD_DRIFT * (0.8 + 0.1 * c), cw) - 300.0
		var cy := 70.0 + (c * 53) % 150
		if _clouds.is_empty():
			_cloud(Vector2(cx, cy), 0.8 + 0.15 * (c % 3))
		else:
			var tex: Texture2D = _clouds[c]
			var w: float = CLOUD_W[c]
			var h := w * tex.get_height() / tex.get_width()
			var bob := sin(t * 0.6 + c * 1.7) * 3.0
			_canvas.draw_texture_rect(tex, Rect2(cx - w * 0.25, cy - h * 0.5 + bob, w, h), false)
	# hills: far and near
	var vy := clampf(-cam.y * 0.01, -60.0, 60.0)
	if _far and _mid:
		BiomePainter.strip(_canvas, size, _far, cam.x * 0.08, size.y * 0.6 - 95.0 + vy, FAR_H, FAR_FILL)
		BiomePainter.strip(_canvas, size, _mid, cam.x * 0.18, size.y * 0.74 - 85.0 + vy * 1.5, MID_H, MID_FILL)
	else:
		_hills(size, cam.x * 0.08, size.y * 0.6 + vy, 70.0, 1.3, Color(0.70, 0.82, 0.82))
		_hills(size, cam.x * 0.18, size.y * 0.74 + vy * 1.5, 90.0, 4.2, Color(0.60, 0.78, 0.66))


func _draw_procedural_sky(size: Vector2) -> void:
	var top := Color(0.36, 0.66, 0.9)
	var bottom := Color(0.98, 0.9, 0.66)
	var bands := 12
	for i in bands:
		var t0 := float(i) / bands
		_canvas.draw_rect(Rect2(0, size.y * t0, size.x, size.y / bands + 1), top.lerp(bottom, t0 * t0 * 0.9 + 0.05))


func _draw_procedural_sun(sun: Vector2) -> void:
	for k in 12:
		var a := TAU * k / 12.0 + Time.get_ticks_msec() * 0.0002
		_canvas.draw_line(sun + Vector2.RIGHT.rotated(a) * 70, sun + Vector2.RIGHT.rotated(a) * 105, Color(1, 0.88, 0.4, 0.8), 10)
	_canvas.draw_circle(sun, 62, Color(0.12, 0.08, 0.05))
	_canvas.draw_circle(sun, 56, Color(1, 0.86, 0.35))


func _hills(size: Vector2, scroll: float, base_y: float, amp: float, phase: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var step := 24.0
	var x := 0.0
	while x <= size.x + step:
		pts.append(Vector2(x, base_y + _hill(x + scroll, phase, amp)))
		x += step
	var line := pts.duplicate()
	pts.append(Vector2(size.x + step, size.y))
	pts.append(Vector2(0, size.y))
	_canvas.draw_colored_polygon(pts, color)
	_canvas.draw_polyline(line, Color(0.12, 0.09, 0.07, 0.8), 5.0, true)


func _cloud(p: Vector2, s: float) -> void:
	var blobs := [Vector2(0, 0), Vector2(45, -18), Vector2(90, 0), Vector2(40, 12)]
	var radii := [34.0, 42.0, 32.0, 30.0]
	for i in blobs.size():
		_canvas.draw_circle(p + blobs[i] * s, (radii[i] + 5.0) * s, Color(0.15, 0.12, 0.1, 0.55))
	for i in blobs.size():
		_canvas.draw_circle(p + blobs[i] * s, radii[i] * s, Color(1, 1, 1, 0.95))
