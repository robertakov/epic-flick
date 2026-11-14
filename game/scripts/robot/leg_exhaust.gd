class_name LegExhaust
extends Node2D
## Cheap polygons, owned by one physical leg's visual; no force and no particle nodes.
## v32: driven only by SHORT flashes (RobotIdentityFeedback.thrust_flash); larger, ink-outlined cartoon flame so it
## reads on a phone. intensity 0 = invisible.
var intensity := 0.0
var phase := 0.0
var attached := true
var ink: Polygon2D
var outer: Polygon2D
var core: Polygon2D

func _init() -> void:
	ink = Polygon2D.new()
	ink.color = Color(0.1, 0.06, 0.04, 0.9)
	outer = Polygon2D.new()
	outer.color = Color(1.0, 0.32, 0.03, 0.95)
	core = Polygon2D.new()
	core.color = Color(1.0, 0.91, 0.26, 0.98)
	add_child(ink)
	add_child(outer)
	add_child(core)
	visible = false
	use_parent_material = false

func disable() -> void:
	attached = false
	intensity = 0.0
	visible = false

static func _flame(width: float, length: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-width, 0), Vector2(width, 0), Vector2(width * 0.6, length * 0.45), Vector2(0, length), Vector2(-width * 0.65, length * 0.45)])

func _process(dt: float) -> void:
	phase += dt
	visible = attached and intensity > 0.035
	if not visible:
		return
	var length := 16.0 + 48.0 * intensity + sin(floorf(phase * 14.0) * 2.1) * 3.0
	var width := 6.0 + 7.0 * intensity
	ink.polygon = _flame(width + 3.0, length + 5.0)
	outer.polygon = _flame(width, length)
	core.polygon = PackedVector2Array([Vector2(-width * 0.45, 0), Vector2(width * 0.45, 0), Vector2(0, length * 0.7)])
