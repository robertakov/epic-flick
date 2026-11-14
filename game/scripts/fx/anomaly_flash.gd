class_name AnomalyFlash
extends CanvasLayer
## v36 screen-space feedback of the Exclusion-Zone anomalies the PLAYER enters (presentation only: never physics,
## never input - the layer has no Controls, so it can never swallow a touch).
##   electric()  - large jagged lightning arcs from the robot across a big part of the screen + a short white flash;
##                 strong peak, quick decay (~0.4 s)
##   radiation() - a brief whole-screen "radiation noise" of many small dots (~0.55 s)
## Own RNG (never the gameplay one).

const ELECTRIC_TIME := 0.42
const RADIATION_TIME := 0.55

var rng := RandomNumberGenerator.new()
var _canvas: Node2D
var _e_t := -1.0
var _e_from := Vector2.ZERO
var _e_seed := 0
var _r_t := -1.0
var _r_seed := 0
## Telemetry (tests / QA).
var electric_count := 0
var radiation_count := 0


func _init() -> void:
	name = "AnomalyFlash"
	layer = 20
	rng.randomize()


func _ready() -> void:
	_canvas = Node2D.new()
	_canvas.name = "Canvas"
	add_child(_canvas)
	_canvas.draw.connect(_draw_fx)
	set_process(false)


func electric(screen_from: Vector2) -> void:
	_e_t = 0.0
	_e_from = screen_from
	_e_seed = rng.randi()
	electric_count += 1
	set_process(true)


func radiation() -> void:
	_r_t = 0.0
	_r_seed = rng.randi()
	radiation_count += 1
	set_process(true)


func is_active() -> bool:
	return _e_t >= 0.0 or _r_t >= 0.0


func _process(dt: float) -> void:
	var real := dt / maxf(Engine.time_scale, 0.01)   # same speed while the game fast-forwards
	if _e_t >= 0.0:
		_e_t += real
		if _e_t > ELECTRIC_TIME:
			_e_t = -1.0
	if _r_t >= 0.0:
		_r_t += real
		if _r_t > RADIATION_TIME:
			_r_t = -1.0
	if not is_active():
		set_process(false)
	_canvas.queue_redraw()


func _draw_fx() -> void:
	var vp := _canvas.get_viewport_rect().size
	if _e_t >= 0.0:
		var k := 1.0 - _e_t / ELECTRIC_TIME
		var a := k * k                                     # strong peak, quick decay
		if _e_t < 0.07:
			_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.85, 0.93, 1.0, 0.32 * (1.0 - _e_t / 0.07)))
		var r := RandomNumberGenerator.new()
		r.seed = _e_seed + int(_e_t * 30.0) * 977          # re-strike ~30 times a second
		for b in 6:
			var ang := r.randf() * TAU
			var reach := vp.length() * r.randf_range(0.32, 0.6)
			var p := _e_from
			var pts := PackedVector2Array([p])
			var segs := 9
			for s in segs:
				ang += r.randf_range(-0.55, 0.55)
				p += Vector2.RIGHT.rotated(ang) * reach / segs
				pts.append(p)
				if s == 4 and r.randf() < 0.7:
					# a fork
					var q := p
					var fa := ang + r.randf_range(-1.0, 1.0)
					var fork := PackedVector2Array([q])
					for f in 4:
						fa += r.randf_range(-0.6, 0.6)
						q += Vector2.RIGHT.rotated(fa) * reach / segs
						fork.append(q)
					_canvas.draw_polyline(fork, Color(0.10, 0.07, 0.05, a * 0.8), 9.0)
					_canvas.draw_polyline(fork, Color(0.55, 0.80, 1.0, a), 4.0)
			_canvas.draw_polyline(pts, Color(0.10, 0.07, 0.05, a * 0.85), 14.0)
			_canvas.draw_polyline(pts, Color(0.50, 0.75, 1.0, a), 8.0)
			_canvas.draw_polyline(pts, Color(1.0, 1.0, 0.92, a), 3.0)
		_canvas.draw_circle(_e_from, 60.0 * (0.6 + k), Color(0.75, 0.9, 1.0, 0.45 * a))
	if _r_t >= 0.0:
		var k2 := 1.0 - _r_t / RADIATION_TIME
		var r2 := RandomNumberGenerator.new()
		r2.seed = _r_seed + int(_r_t * 24.0) * 131
		_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.35, 0.9, 0.25, 0.10 * k2))
		for i in 900:
			var pt := Vector2(r2.randf() * vp.x, r2.randf() * vp.y)
			var sz := r2.randf_range(2.0, 5.0)
			var c := Color(0.85, 1.0, 0.7, k2 * r2.randf_range(0.35, 0.95)) if r2.randf() < 0.75 else Color(0.1, 0.1, 0.08, k2 * 0.6)
			_canvas.draw_rect(Rect2(pt, Vector2(sz, sz)), c)
