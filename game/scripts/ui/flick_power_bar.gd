class_name FlickPowerBar
extends Control
## Interactive pre-launch power meter for the giant hand flick (Щелбан).
## Four explicit zones:
##   MINIMUM (0.00..0.28) -> 0.80x baseline launch speed
##   NORMAL  (0.28..0.64) -> 1.00x baseline launch speed
##   STRONG  (0.64..0.88) -> 1.08x baseline launch speed
##   MAXIMUM (0.88..1.00) -> 1.20x baseline launch speed

signal power_locked(tier: String, multiplier: float, ratio: float)

const TIERS := {
	"MINIMUM": {"min": 0.00, "max": 0.28, "mult": 0.80, "short": "FLICK_MIN", "title": "FLICK_MIN_L", "col": Color(0.36, 0.62, 0.92)},
	"NORMAL":  {"min": 0.28, "max": 0.64, "mult": 1.00, "short": "FLICK_NORM", "title": "FLICK_NORM_L", "col": Color(0.38, 0.82, 0.36)},
	"STRONG":  {"min": 0.64, "max": 0.88, "mult": 1.08, "short": "FLICK_STRONG", "title": "FLICK_STRONG_L", "col": Color(0.98, 0.72, 0.16)},
	"MAXIMUM": {"min": 0.88, "max": 1.00, "mult": 1.20, "short": "FLICK_MAX", "title": "FLICK_MAX_L", "col": Color(0.96, 0.26, 0.20)},
}
const TIER_ORDER := ["MINIMUM", "NORMAL", "STRONG", "MAXIMUM"]

var ui: UIController
var active := false
var locked := false
var wait_for_tap := true
var marker_ratio := 0.46
var locked_tier := "NORMAL"
var locked_multiplier := 1.0
var oscillation_speed := 1.35
var _phase := 0.46
var _flash := 0.0
var _fade_tween: Tween


static func tier_for_ratio(r: float) -> String:
	var x := clampf(r, 0.0, 1.0)
	if x < 0.28:
		return "MINIMUM"
	if x < 0.64:
		return "NORMAL"
	if x < 0.88:
		return "STRONG"
	return "MAXIMUM"


static func multiplier_for_tier(tier_name: String) -> float:
	if TIERS.has(tier_name):
		return float(TIERS[tier_name].mult)
	return 1.0


static func ratio_for_tier(tier_name: String) -> float:
	if TIERS.has(tier_name):
		var d: Dictionary = TIERS[tier_name]
		return (float(d.min) + float(d.max)) * 0.5
	return 0.46


func build(p_ui: UIController) -> void:
	ui = p_ui
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(600, 136)
	custom_minimum_size = size
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -200.0
	offset_right = 400.0
	offset_top = 186.0
	offset_bottom = 322.0
	pivot_offset = size * 0.5
	visible = false
	draw.connect(_draw_bar)


func begin(p_wait_for_tap := true) -> void:
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	active = true
	locked = false
	wait_for_tap = p_wait_for_tap
	_phase = 0.18
	marker_ratio = 0.18
	locked_tier = tier_for_ratio(marker_ratio)
	locked_multiplier = multiplier_for_tier(locked_tier)
	_flash = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	visible = true
	queue_redraw()


func hide_immediate() -> void:
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	active = false
	locked = false
	visible = false


func lock_current() -> Dictionary:
	return lock_at_ratio(marker_ratio)


func lock_at_ratio(r: float) -> Dictionary:
	marker_ratio = clampf(r, 0.0, 1.0)
	locked_tier = tier_for_ratio(marker_ratio)
	locked_multiplier = multiplier_for_tier(locked_tier)
	locked = true
	_flash = 1.0
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.06, 1.08), 0.06)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	queue_redraw()
	power_locked.emit(locked_tier, locked_multiplier, marker_ratio)
	return {"tier": locked_tier, "multiplier": locked_multiplier, "ratio": marker_ratio}


func lock_tier(tier_name: String) -> Dictionary:
	return lock_at_ratio(ratio_for_tier(tier_name))


func fade_out(delay := 0.32) -> void:
	active = false
	if not visible:
		return
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_interval(delay)
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.22)
	_fade_tween.tween_callback(func() -> void: visible = false)


func _process(dt: float) -> void:
	if not visible:
		return
	if active and not locked:
		_phase = fmod(_phase + dt * oscillation_speed, 2.0)
		marker_ratio = 1.0 - absf(_phase - 1.0)
		locked_tier = tier_for_ratio(marker_ratio)
		locked_multiplier = multiplier_for_tier(locked_tier)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 3.0)
	queue_redraw()


func _draw_bar() -> void:
	if ui == null or ui.font == null:
		return
	var f := ui.font
	var ink := UIController.INK
	var cream := UIController.CREAM
	var w := size.x
	var cur_tier := locked_tier if locked else tier_for_ratio(marker_ratio)
	var cur_info: Dictionary = TIERS[cur_tier]

	# Backdrop card
	var card_rect := Rect2(Vector2(0, 0), size)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.12, 0.08, 0.06, 0.88)
	bg_sb.border_color = ink
	bg_sb.set_border_width_all(6)
	bg_sb.set_corner_radius_all(24)
	draw_style_box(bg_sb, card_rect)

	# Header text
	var header := (L.t("FLICK_LABEL") % L.t(String(cur_info.title))) if locked else L.t("FLICK_PROMPT")
	var h_fs := 26
	var h_w := f.get_string_size(header, HORIZONTAL_ALIGNMENT_LEFT, -1, h_fs).x
	var h_col := Color(cur_info.col).lightened(0.25) if locked else UIController.GOLD
	draw_string_outline(f, Vector2((w - h_w) * 0.5, 34), header, HORIZONTAL_ALIGNMENT_LEFT, -1, h_fs, 8, ink)
	draw_string(f, Vector2((w - h_w) * 0.5, 34), header, HORIZONTAL_ALIGNMENT_LEFT, -1, h_fs, h_col)

	# Segmented bar
	var bar_x := 28.0
	var bar_y := 50.0
	var bar_w := w - 56.0
	var bar_h := 44.0
	var bar_rect := Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h))
	draw_rect(bar_rect.grow(5.0), ink, true)

	for t_name in TIER_ORDER:
		var td: Dictionary = TIERS[t_name]
		var x0 := bar_x + bar_w * float(td.min)
		var x1 := bar_x + bar_w * float(td.max)
		var seg_rect := Rect2(Vector2(x0, bar_y), Vector2(x1 - x0, bar_h))
		var col: Color = td.col
		if t_name == cur_tier:
			col = col.lightened(0.18 + 0.25 * _flash)
		else:
			col = col.darkened(0.18)
		draw_rect(seg_rect, col, true)
		draw_rect(Rect2(seg_rect.position + Vector2(2, 3), Vector2(maxf(0.0, seg_rect.size.x - 4), 7)), Color(1, 1, 1, 0.28), true)
		if float(td.min) > 0.0:
			draw_line(Vector2(x0, bar_y - 2), Vector2(x0, bar_y + bar_h + 2), ink, 4.0)
		var lbl := L.t(String(td.short))
		var l_fs := 20 if t_name != "MAXIMUM" else 19
		var l_w := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, l_fs).x
		var l_pos := Vector2((x0 + x1 - l_w) * 0.5, bar_y + bar_h * 0.5 + l_fs * 0.36)
		draw_string_outline(f, l_pos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, l_fs, 6, ink)
		draw_string(f, l_pos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, l_fs, cream)

	# Moving / locked marker needle + triangles
	var mx := bar_x + bar_w * clampf(marker_ratio, 0.0, 1.0)
	var needle_col := Color.WHITE if not locked else Color(1.0, 0.96, 0.55)
	draw_rect(Rect2(Vector2(mx - 6, bar_y - 8), Vector2(12, bar_h + 16)), ink, true)
	draw_rect(Rect2(Vector2(mx - 3, bar_y - 6), Vector2(6, bar_h + 12)), needle_col, true)
	var top_tri := PackedVector2Array([Vector2(mx, bar_y - 2), Vector2(mx - 12, bar_y - 16), Vector2(mx + 12, bar_y - 16)])
	draw_colored_polygon(top_tri, needle_col)
	draw_polyline(PackedVector2Array([top_tri[0], top_tri[1], top_tri[2], top_tri[0]]), ink, 3.0)
	var bot_tri := PackedVector2Array([Vector2(mx, bar_y + bar_h + 2), Vector2(mx - 12, bar_y + bar_h + 16), Vector2(mx + 12, bar_y + bar_h + 16)])
	draw_colored_polygon(bot_tri, needle_col)
	draw_polyline(PackedVector2Array([bot_tri[0], bot_tri[1], bot_tri[2], bot_tri[0]]), ink, 3.0)

	# Sub-caption
	var sub := (L.t("FLICK_LOCKED") % int(round(locked_multiplier * 100.0))) if locked else L.f("FLICK_NOW", {"name": L.t(String(cur_info.short)), "pct": int(round(float(cur_info.mult) * 100.0))})
	var s_fs := 20
	var s_w := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, s_fs).x
	draw_string_outline(f, Vector2((w - s_w) * 0.5, 124), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, s_fs, 6, ink)
	draw_string(f, Vector2((w - s_w) * 0.5, 124), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, s_fs, cream)
