class_name AchievementBadge
extends Control
var hidden_badge := false
var earned := false
var badge_font: Font
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(64, 64)
func _draw() -> void:
	var centre := size * .5
	var radius := minf(size.x, size.y) * .43
	draw_circle(centre, radius, UIController.INK)
	draw_circle(centre, radius - 4, UIController.GOLD if earned else Color(.63, .58, .46))
	if hidden_badge and badge_font:
		draw_string(badge_font, centre + Vector2(-10, 12), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UIController.INK)
	else:
		var points := PackedVector2Array()
		for i in 10:
			points.append(centre + Vector2.UP.rotated(i * TAU / 10) * radius * (.73 if i % 2 == 0 else .34))
		draw_colored_polygon(points, UIController.PAPER if earned else UIController.INK)
