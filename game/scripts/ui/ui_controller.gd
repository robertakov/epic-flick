class_name UIController
extends CanvasLayer
## Main menu, in-run HUD (distance, module status, spin indicator, hint) and the result screen.
## Everything is laid out with anchors so any landscape aspect ratio works.

signal play_pressed            # Free Run
signal campaign_pressed
signal debug_toggled(on: bool)
signal retry_pressed
signal menu_pressed
signal tutorial_pressed
signal profile_chip_pressed
signal artifact_pressed
var tutorial_overlay: TutorialOverlay
## v31: profile screen + the "PLAYER N" chip in the menu top bar (opens the profile screen).
var profiles_view: ProfileSelectView
var profile_chip: Button
## v32: paid continue offer.
var continue_card: ContinueCard
## v32: equip toggle of the secret artifact (exists in the UI only after this profile discovered it).
var artifact_button: Button
var awareness: AwarenessCard
var biome_intro: BiomeIntro

signal abandon_pressed
signal restart_pressed
signal setting_changed(key: String, value: float)
signal sfx_volume_changed(percent: float)
var sfx_slider: HSlider
var sfx_label: Label
var sfx_row: HBoxContainer
signal settings_reset

const INK := Color(0.1, 0.06, 0.04)
## v33 UI layering: every modal / full-screen overlay root draws in this z band. Menu content (robot preview parts
## carry their rig z 1..4, the robot-select preview 4) always stays BELOW any modal, independent of tree order.
const Z_MODAL := 100
const CREAM := Color(1.0, 0.95, 0.82)

var font: SystemFont
var menu: Control
var menu_content: Control
var menu_grid: Control
var menu_stage: Control
var menu_robot_preview: RobotPreview
var menu_buttons: Array[Button] = []
var menu_title: Label
var hud: Control
var results: Control
var distance_label: Label
var best_label_menu: Label
var result_distance: Label
var result_best: Label
var result_record: Label
var result_reason: Label
var hint: Label
var spin_icon: Control
var health_bar: Control
var charge_bar: Control
var _charge := 0.0
var _charge_shown := 0.0
var _charge_flash := 0.0
var _charge_time := 0.0
var _hp_value := 100.0
var _hp_shown := 100.0
var _hp_ghost := 100.0
var _hp_max := 100.0
var _hp_flash := 0.0
var module_icons := {}
## Instant restart button in the HUD; hidden when the game mode forbids it (future competitive mode).
var restart_enabled := true
var restart_button: Button
var abandon_button: Button
var _buttons: Array[Button] = []
var _holding := false
var _spin_angle := 0.0


func _ready() -> void:
	layer = 10
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Impact", "Arial Black", "Roboto Black", "sans-serif"])
	font.font_weight = 900
	# v34: bundled Noto CJK subsets guarantee zh / ja / ko glyphs (no tofu) whatever the device fonts are
	L.apply_fallbacks(font)
	_build_hud()
	_build_menu()
	_build_results()
	awareness=AwarenessCard.new()
	add_child(awareness)
	awareness.build(self)
	biome_intro = BiomeIntro.new()
	biome_intro.name = "BiomeIntro"
	add_child(biome_intro)
	biome_intro.build()
	profiles_view = ProfileSelectView.new()
	add_child(profiles_view)
	profiles_view.build(self)
	continue_card = ContinueCard.new()
	add_child(continue_card)
	continue_card.build(self)
	achievements_view = AchievementsView.new()
	add_child(achievements_view)
	achievements_view.build(self)
	achievement_toast = AchievementToast.new()
	add_child(achievement_toast)
	achievement_toast.build(self)
	for m in modal_roots():
		m.z_index = Z_MODAL
	show_menu(0.0, {})
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()


# ---------------- safe area (display cutouts, rounded corners, system bars) ----------------

## Extra padding kept from every screen edge for rounded corners (viewport px).
const CORNER_PAD := 10.0
## Tests can force margins (left, top, right, bottom in viewport px) to simulate a cutout.
var debug_safe_margins := Vector4(-1, -1, -1, -1)
var safe_margins := Vector4.ZERO


## The HUD sits in the screen corners, so it is inset by the OS safe area. Menu / results / statistics
## are centred panels well inside the screen and keep their full-screen shade.
func apply_safe_area() -> void:
	var m := Vector4.ZERO
	if debug_safe_margins.x >= 0.0:
		m = debug_safe_margins
	elif OS.has_feature("mobile"):
		var win := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var vp := get_viewport().get_visible_rect().size
		if win.x > 0.0 and win.y > 0.0 and safe.size.x > 0.0:
			var k := vp / win
			m = Vector4(safe.position.x * k.x, safe.position.y * k.y, maxf(win.x - safe.end.x, 0.0) * k.x,
				maxf(win.y - safe.end.y, 0.0) * k.y)
	m = Vector4(maxf(m.x, CORNER_PAD), maxf(m.y, CORNER_PAD), maxf(m.z, CORNER_PAD), maxf(m.w, CORNER_PAD))
	safe_margins = m
	hud.offset_left = m.x - CORNER_PAD
	hud.offset_top = m.y - CORNER_PAD
	hud.offset_right = -(m.z - CORNER_PAD)
	hud.offset_bottom = -(m.w - CORNER_PAD)
	_layout_menu()
	_layout_settings()


# ---------------- helpers ----------------

func _label(text: String, size: int, color := CREAM, outline := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 104)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 50)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color if st != "pressed" else color.darkened(0.2)
		if st == "hover":
			sb.bg_color = color.lightened(0.12)
		sb.border_color = INK
		sb.set_border_width_all(7)
		sb.set_corner_radius_all(30)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 0 if st == "pressed" else 8
		sb.shadow_offset = Vector2(0, 6)
		sb.content_margin_left = 24
		sb.content_margin_right = 24
		b.add_theme_stylebox_override(st, sb)
	b.focus_mode = Control.FOCUS_NONE
	b.button_down.connect(func() -> void:
		# visual pass: rubber-hose squash & stretch (squash wide, spring tall, settle) - transform only
		var tw := b.create_tween()
		b.pivot_offset = b.size * 0.5
		tw.tween_property(b, "scale", Vector2(1.08, 0.86), 0.05)
		tw.tween_property(b, "scale", Vector2(0.96, 1.05), 0.07)
		tw.tween_property(b, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	_buttons.append(b)
	return b


func _panel(color := Color(0.98, 0.84, 0.45)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = INK
	sb.set_border_width_all(8)
	sb.set_corner_radius_all(36)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 28
	sb.content_margin_bottom = 32
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 14
	p.add_theme_stylebox_override("panel", sb)
	return p


## True when a screen position belongs to UI (InputRouter must ignore it).
func blocks_point(pos: Vector2) -> bool:
	if awareness!=null and awareness.visible:
		return true
	if profiles_view != null and profiles_view.visible:
		return true
	if continue_card != null and continue_card.visible:
		return true
	if biome_intro != null and biome_intro.blocking():
		return true
	if achievements_view and achievements_view.visible: return true
	if (robot_select and robot_select.visible) or (campaign_map and campaign_map.visible) \
			or (campaign_result and campaign_result.visible) or menu.visible or results.visible or (stats_view and stats_view.visible) or (settings_view and settings_view.visible):
		return true
	for b in _buttons:
		if b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return true
	return false


# ---------------- HUD ----------------

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	distance_label = _label(L.t("UNIT_M_N") % 0, 64)
	distance_label.position = Vector2(36, 18)
	hud.add_child(distance_label)
	# health bar under the distance (top-left corner, never over the robot)
	health_bar = Control.new()
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.position = Vector2(34, 104)
	health_bar.size = Vector2(300, 46)
	health_bar.draw.connect(_draw_health)
	hud.add_child(health_bar)
	# spin-charge meter right under the HP bar
	charge_bar = Control.new()
	charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_bar.position = Vector2(34, 158)
	charge_bar.size = Vector2(300, 40)
	charge_bar.draw.connect(_draw_charge)
	hud.add_child(charge_bar)
	# module status (top-right): six slots of the samurai
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -500.0
	box.offset_right = -24.0
	box.offset_top = 22.0
	box.offset_bottom = 96.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 6)
	hud.add_child(box)
	# instant restart: top-right under the module icons (away from HP / charge / distance on the left)
	restart_button = _button(L.t("UI_RETRY"), PAPER)
	restart_button.custom_minimum_size = Vector2(200, 72)
	restart_button.add_theme_font_size_override("font_size", 34)
	restart_button.anchor_left = 1.0
	restart_button.anchor_right = 1.0
	restart_button.offset_left = -224.0
	restart_button.offset_right = -24.0
	restart_button.offset_top = 108.0
	restart_button.offset_bottom = 180.0
	fit_button_font(restart_button, 200.0, 34, 22)
	restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	hud.add_child(restart_button)
	abandon_button = _button(L.t("UI_MENU"), PAPER)
	abandon_button.custom_minimum_size = Vector2(180,72)
	abandon_button.add_theme_font_size_override("font_size",30)
	abandon_button.anchor_left = 1.0
	abandon_button.anchor_right = 1.0
	abandon_button.offset_left = -420
	abandon_button.offset_right = -240
	abandon_button.offset_top = 108
	abandon_button.offset_bottom = 180
	fit_button_font(abandon_button, 180.0, 30, 20)
	abandon_button.pressed.connect(func() -> void: abandon_pressed.emit())
	hud.add_child(abandon_button)
	var icons := [["head", "head_neutral"], ["torso", "torso"], ["arm_l", "arm_l_fist"], ["arm_r", "arm_r_fist"],
		["leg_l", "leg_l_boot"], ["leg_r", "leg_r_boot"]]
	for it in icons:
		var holder := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 0.95, 0.8, 0.85)
		sb.border_color = INK
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(14)
		holder.add_theme_stylebox_override("panel", sb)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.custom_minimum_size = Vector2(70, 70)
		var tr := TextureRect.new()
		tr.texture = load("res://assets/robot/%s.png" % it[1])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(62, 62)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
		box.add_child(holder)
		module_icons[StringName(it[0])] = holder
	# spin indicator (bottom-left): shows the current spin direction
	spin_icon = Control.new()
	spin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spin_icon.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	spin_icon.position = Vector2(30, -150)
	spin_icon.custom_minimum_size = Vector2(120, 120)
	spin_icon.draw.connect(_draw_spin_icon)
	hud.add_child(spin_icon)
	hint = _label(L.t("HUD_HINT"), 34, CREAM, 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position = Vector2(-460, -130)
	hint.size = Vector2(920, 100)
	hud.add_child(hint)


func _draw_spin_icon() -> void:
	var c := Vector2(60, 60)
	var col := Color(0.45, 0.85, 1.0) if _holding else Color(1.0, 0.75, 0.25)
	spin_icon.draw_circle(c, 56, Color(0.1, 0.06, 0.04, 0.55))
	spin_icon.draw_arc(c, 38, _spin_angle, _spin_angle + PI * 1.5, 24, INK, 18)
	spin_icon.draw_arc(c, 38, _spin_angle, _spin_angle + PI * 1.5, 24, col, 11)
	var dir := -1.0 if _holding else 1.0
	var end_a := _spin_angle + (PI * 1.5 if dir > 0 else 0.0)
	var tip := c + Vector2.RIGHT.rotated(end_a) * 38
	var tangent := Vector2.RIGHT.rotated(end_a + PI * 0.5 * dir)
	var n := Vector2.RIGHT.rotated(end_a)
	var tri := PackedVector2Array([tip + tangent * 22, tip + n * 16, tip - n * 16])
	spin_icon.draw_colored_polygon(tri, col)
	spin_icon.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), INK, 4)


func _draw_health() -> void:
	var w := health_bar.size.x
	var h := health_bar.size.y
	var r := Rect2(Vector2(0, 0), Vector2(w, h))
	var ratio := clampf(_hp_shown / maxf(_hp_max, 1.0), 0.0, 1.0)
	var ghost := clampf(_hp_ghost / maxf(_hp_max, 1.0), 0.0, 1.0)
	var inner := r.grow(-6)
	# frame + trough
	health_bar.draw_style_box(_hp_box(INK, 16), r)
	health_bar.draw_style_box(_hp_box(Color(0.25, 0.14, 0.1), 11), inner)
	# ghost (recent loss) then the real fill: green -> yellow -> red
	if ghost > ratio:
		health_bar.draw_style_box(_hp_box(Color(1, 0.95, 0.85), 11),
			Rect2(inner.position, Vector2(inner.size.x * ghost, inner.size.y)))
	if ratio > 0.0:
		var col := Color(0.95, 0.25, 0.18).lerp(Color(1.0, 0.82, 0.2), clampf(ratio * 2.0, 0.0, 1.0))
		if ratio > 0.5:
			col = Color(1.0, 0.82, 0.2).lerp(Color(0.45, 0.9, 0.3), (ratio - 0.5) * 2.0)
		if _hp_flash > 0.0:
			col = col.lerp(Color.WHITE, _hp_flash)
		var fill := Rect2(inner.position, Vector2(maxf(inner.size.x * ratio, 14.0), inner.size.y))
		health_bar.draw_style_box(_hp_box(col, 11), fill)
		health_bar.draw_rect(Rect2(fill.position + Vector2(8, 4), Vector2(maxf(fill.size.x - 16, 0), 5)), Color(1, 1, 1, 0.35))
	var txt := "HP %d" % int(round(_hp_value))
	var fs := 30
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2((w - tw) * 0.5, h * 0.5 + fs * 0.36)
	health_bar.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, INK)
	health_bar.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)


var _box_cache := {}


## Shared rounded box for the HUD bars (drawn immediately, so one instance per radius is enough;
## avoids allocating several StyleBoxes every frame).
func _hp_box(col: Color, radius: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = _box_cache.get(radius)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(radius)
		_box_cache[radius] = sb
	sb.bg_color = col
	return sb


## Update the health readout (animated: fill snaps, a pale "ghost" shows the chunk just lost).
func set_health(hp: float, max_hp: float, instant := false) -> void:
	_hp_max = max_hp
	if instant:
		_hp_shown = hp
		_hp_ghost = hp
		_hp_flash = 0.0
	elif hp < _hp_value:
		_hp_flash = 1.0
		_hp_ghost = maxf(_hp_ghost, _hp_shown)
		health_bar.pivot_offset = health_bar.size * 0.5
		var tw := health_bar.create_tween()
		tw.tween_property(health_bar, "scale", Vector2(1.12, 1.12), 0.06)
		tw.tween_property(health_bar, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	_hp_value = hp
	health_bar.queue_redraw()


## Spin charge 0..1. A big drop = the charge was released: flash + pop.
func set_charge(r: float, instant := false) -> void:
	if instant:
		_charge = r
		_charge_shown = r
		_charge_flash = 0.0
		return
	if r < _charge - 0.15:
		_charge_flash = 1.0
		charge_bar.pivot_offset = Vector2(0.0, charge_bar.size.y * 0.5) # Pulse inward, preserving the left safe-area margin.
		var tw := charge_bar.create_tween()
		tw.tween_property(charge_bar, "scale", Vector2(1.18, 1.18), 0.07)
		tw.tween_property(charge_bar, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	_charge = r


func _draw_charge() -> void:
	var w := charge_bar.size.x
	var h := charge_bar.size.y
	var r := Rect2(Vector2.ZERO, Vector2(w, h))
	var full := _charge >= 0.999
	var pulse := 0.5 + 0.5 * sin(_charge_time * 9.0)
	if full:
		# soft golden halo (expressive but small)
		charge_bar.draw_style_box(_hp_box(Color(1.0, 0.8, 0.2, 0.25 + 0.3 * pulse), 22), r.grow(4.0 + 3.0 * pulse))
	charge_bar.draw_style_box(_hp_box(INK, 16), r)
	var inner := r.grow(-6)
	charge_bar.draw_style_box(_hp_box(Color(0.2, 0.12, 0.18), 11), inner)
	var ratio := clampf(_charge_shown, 0.0, 1.0)
	if ratio > 0.005:
		var col := Color(1.0, 0.55, 0.12).lerp(Color(1.0, 0.88, 0.25), ratio)
		if full:
			col = col.lerp(Color(1, 1, 0.8), 0.35 * pulse)
		if _charge_flash > 0.0:
			col = col.lerp(Color.WHITE, _charge_flash)
		var fill := Rect2(inner.position, Vector2(maxf(inner.size.x * ratio, 12.0), inner.size.y))
		charge_bar.draw_style_box(_hp_box(col, 11), fill)
		charge_bar.draw_rect(Rect2(fill.position + Vector2(8, 4), Vector2(maxf(fill.size.x - 16, 0), 4)), Color(1, 1, 1, 0.4))
	# notches every 35% = one automatic clockwise turn
	for i in range(1, 3):
		var x := inner.position.x + inner.size.x * 0.35 * i
		charge_bar.draw_line(Vector2(x, inner.position.y + 3), Vector2(x, inner.end.y - 3), Color(0.1, 0.06, 0.04, 0.7), 3.0)
	var txt := L.t("HUD_CHARGE_MAX") if full else L.t("HUD_CHARGE") % int(round(_charge * 100.0))
	var fs := 26
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2((w - tw) * 0.5, h * 0.5 + fs * 0.36)
	charge_bar.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, INK)
	charge_bar.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.7) if full else CREAM)
	if full:
		# two little stars orbiting the end of the meter
		for k in 2:
			var a := _charge_time * 5.0 + PI * k
			var c := Vector2(w - 14, h * 0.5) + Vector2(cos(a), sin(a)) * Vector2(16, 12)
			_star(charge_bar, c, 7.0 + 2.0 * pulse)


func _star(ci: CanvasItem, c: Vector2, rad: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(c + Vector2.RIGHT.rotated(TAU * i / 10.0 - PI * 0.5) * (rad if i % 2 == 0 else rad * 0.45))
	ci.draw_colored_polygon(pts, Color(1.0, 0.95, 0.5))
	pts.append(pts[0])
	ci.draw_polyline(pts, INK, 2.0)


func set_holding(h: bool) -> void:
	_holding = h


func set_distance(m: float) -> void:
	distance_label.text = L.t("UNIT_M_N") % int(m)


func set_module(part: StringName, present: bool) -> void:
	var h: Control = module_icons.get(part)
	if h == null:
		return
	h.modulate = Color.WHITE if present else Color(0.4, 0.3, 0.3, 0.55)
	if not present:
		var tw := h.create_tween()
		h.pivot_offset = h.size * 0.5
		tw.tween_property(h, "scale", Vector2(1.4, 1.4), 0.08)
		tw.tween_property(h, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)



func set_robot_art(rig: RigData, palette: Material) -> void:
	for part in module_icons:
		var image := module_icons[part].get_child(0) as TextureRect
		image.texture = RobotArtLibrary.icon(rig, String(part))
		image.material = palette


func reset_modules() -> void:
	for k in module_icons:
		module_icons[k].modulate = Color.WHITE


func _process(dt: float) -> void:
	if menu.visible and menu_title != null:
		# visual pass: the title "breathes" like a hand-animated 1930s title card (transform only, layout untouched)
		var tt := Time.get_ticks_msec() * 0.001
		menu_title.pivot_offset = menu_title.size * Vector2(0.5, 0.6)
		menu_title.rotation = sin(tt * 1.05) * 0.010
		menu_title.scale = Vector2.ONE * (1.0 + 0.010 * sin(tt * 2.1))
	if results.visible and _burst.visible:
		_burst_time += dt
		_burst.queue_redraw()
	if hud.visible:
		# health animation: fill eases to the value, ghost drains after a short delay, flash fades
		_hp_shown = lerpf(_hp_shown, _hp_value, 1.0 - exp(-14.0 * dt))
		_hp_ghost = move_toward(_hp_ghost, _hp_shown, dt * 40.0) if _hp_flash < 0.4 else _hp_ghost
		_hp_flash = maxf(_hp_flash - dt * 2.5, 0.0)
		health_bar.queue_redraw()
		_charge_shown = lerpf(_charge_shown, _charge, 1.0 - exp(-18.0 * dt))
		_charge_flash = maxf(_charge_flash - dt * 2.0, 0.0)
		_charge_time += dt
		charge_bar.queue_redraw()
		_spin_angle += (-TAU * 1.0 if _holding else TAU * 2.0) * dt * 0.5
		spin_icon.queue_redraw()


func fade_hint(delay: float) -> void:
	hint.modulate.a = 1.0
	var tw := hint.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(hint, "modulate:a", 0.0, 0.8)


# ---------------- shared style (1930s cartoon: black & white base, gold accents) ----------------

const GOLD := Color(1.0, 0.78, 0.15)
const PAPER := Color(0.99, 0.97, 0.9)
const GREY := Color(0.38, 0.33, 0.3)


## v34 localization: a fixed-width button keeps its size; a long translated caption shrinks (down to min_fs).
func fit_button_font(b: Button, width: float, fs: int, min_fs: int) -> void:
	while fs > min_fs and font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width - 28.0:
		fs -= 1
	b.add_theme_font_size_override("font_size", fs)


func _ink_label(text: String, size: int, color := INK) -> Label:
	var l := _label(text, size, color, 0)
	return l


func _gold_label(text: String, size: int) -> Label:
	return _label(text, size, GOLD, int(size * 0.2))


func _shade(parent: Control, alpha: float) -> ColorRect:
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.04, 0.03, alpha)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
	return shade


func _paper_panel() -> PanelContainer:
	var p := _panel(PAPER)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_top = 22
	sb.content_margin_bottom = 24
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	return p


func _ink_rule(vertical: bool) -> ColorRect:
	var r := ColorRect.new()
	r.color = INK
	r.custom_minimum_size = Vector2(6, 0) if vertical else Vector2(0, 5)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _fmt_time(s: float) -> String:
	if s >= 60.0:
		return "%d:%02d" % [int(s) / 60, int(s) % 60]
	return L.t("UNIT_S") % L.dec(s)


# ---------------- menu ----------------

var achievement_system: AchievementSystem
var achievements_view: AchievementsView
var achievement_toast: AchievementToast
var achievements_button: Button
var stats_view: Control
var robot_select: RobotSelectView
var campaign_map: CampaignMapView
var campaign_result: CampaignResultView
var race_hud: RaceHud
var star_hud: StarHud
var flick_bar: FlickPowerBar
var debug_layer: CanvasLayer
var debug_label: Label
var debug_enabled := false
var _title_taps: Array[int] = []


func _build_debug() -> void:
	debug_layer = CanvasLayer.new()
	debug_layer.layer = 30
	add_child(debug_layer)
	debug_label = Label.new()
	debug_label.add_theme_font_size_override("font_size", 18)
	debug_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 5)
	debug_label.position = Vector2(14, 210)
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_layer.add_child(debug_label)
	debug_layer.visible = false


func set_debug(on: bool) -> void:
	# QA: the diagnostics overlay (AI / hidden adaptive-difficulty internals) exists only in debug builds; a release
	# export ignores the five title taps and any saved debug.cfg. Test APKs are debug exports and keep it.
	debug_enabled = on and OS.is_debug_build()
	debug_layer.visible = debug_enabled


func _on_title_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var now := Time.get_ticks_msec()
		_title_taps.append(now)
		_title_taps = _title_taps.filter(func(t: int) -> bool: return now - t < 2500)
		if _title_taps.size() >= 5:
			_title_taps.clear()
			set_debug(not debug_enabled)
			debug_toggled.emit(debug_enabled)


func is_campaign_map_open() -> bool:
	return campaign_map.visible
var coins_label_menu: Label
var result_coins: Label
var _meta_coins := 0
var _meta_stars := 0


func set_coins(n: int) -> void:
	_meta_coins = n
	_refresh_wallet()

func set_stars(n: int) -> void:
	_meta_stars = n
	_refresh_wallet()

func _refresh_wallet() -> void:
	coins_label_menu.text = L.t("MENU_WALLET") % [_meta_coins, _meta_stars]
	if menu_content != null:
		_layout_menu()


func is_robot_select_open() -> bool:
	return robot_select.visible


func close_robot_select() -> void:
	robot_select.visible = false
var _stats_totals: GridContainer
var _stats_recent: VBoxContainer
var _stats_data := {}
var _menu_button_centers: Array[Vector2] = []
var _menu_circle_d := 112.0
## v34: decorative second robot hopping over the round buttons (MenuJumper); the big menu robot is separate.
var menu_jumper: MenuJumper


func menu_circle_diameter() -> float:
	return _menu_circle_d


## Called by GameManager once the robot catalog exists. Every time the menu is shown a new random robot is picked.
func setup_menu_jumper(p_catalog: RobotCatalog, cfg: RobotConfig) -> void:
	menu_jumper = MenuJumper.new()
	menu_jumper.ui = self
	menu_jumper.catalog = p_catalog
	menu_jumper.base_cfg = cfg
	menu_stage.add_child(menu_jumper)
	menu_jumper.pick(menu_robot_preview.def.id if menu_robot_preview.def else "")
	menu_title.z_index = 5   # the decorative hopper passes BEHIND the title, never over it
	menu.visibility_changed.connect(func() -> void:
		if menu.visible and menu_jumper:
			menu_jumper.pick(menu_robot_preview.def.id if menu_robot_preview.def else ""))
var _menu_pedestal_rect := Rect2()
var _menu_char_rect := Rect2()
const MENU_CIRCLE_COLORS := [
	Color(1.0, 0.58, 0.18),
	Color(1.0, 0.78, 0.15),
	Color(0.99, 0.96, 0.86),
	Color(0.95, 0.92, 0.84),
]


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu)
	_shade(menu, 0.08)
	var v := Control.new()
	menu_content = v
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(v)
	menu_stage = Control.new()
	menu_stage.name = "MenuStage"
	menu_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_stage.draw.connect(_draw_menu_stage)
	v.add_child(menu_stage)
	menu_grid = menu_stage
	menu_robot_preview = RobotPreview.new()
	menu_robot_preview.name = "MenuRobotPreview"
	menu_stage.add_child(menu_robot_preview)
	best_label_menu = _label(L.t("MENU_RECORD_NONE"), 38, GOLD, 11)
	best_label_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	best_label_menu.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(best_label_menu)
	coins_label_menu = _label("", 32, CREAM, 10)
	coins_label_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	coins_label_menu.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coins_label_menu.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(coins_label_menu)
	profile_chip = _button("PLAYER 1", PAPER)
	profile_chip.name = "ProfileChip"
	profile_chip.add_theme_font_size_override("font_size", 26)
	profile_chip.pressed.connect(func() -> void: profile_chip_pressed.emit())
	profile_chip.visible = false
	v.add_child(profile_chip)
	artifact_button = _button("", GOLD)
	artifact_button.name = "ArtifactToggle"
	artifact_button.pressed.connect(func() -> void: artifact_pressed.emit())
	artifact_button.visible = false
	v.add_child(artifact_button)
	var title := _label(L.t("MENU_TITLE"), 92, GOLD, 22)
	menu_title = title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.rotation = 0.0
	# hidden developer switch: 5 quick taps on the title toggle the AI / balance debug overlay
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_title_input)
	v.add_child(title)
	var camp := _button(L.t("MENU_CAMPAIGN"), MENU_CIRCLE_COLORS[0])
	camp.pressed.connect(func() -> void: campaign_pressed.emit())
	v.add_child(camp)
	var play := _button(L.t("MENU_FREE_RUN"), MENU_CIRCLE_COLORS[1])
	play.pressed.connect(func() -> void: play_pressed.emit())
	v.add_child(play)
	var st := _button(L.t("MENU_STATS"), MENU_CIRCLE_COLORS[2])
	st.pressed.connect(open_stats)
	v.add_child(st)
	var se := _button(L.t("MENU_SETTINGS"), MENU_CIRCLE_COLORS[3])
	se.pressed.connect(open_settings)
	v.add_child(se)
	menu_buttons.assign([camp, play, st, se])
	for i in menu_buttons.size():
		var b := menu_buttons[i]
		b.clip_text = true
		b.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		b.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
		b.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
		b.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
		b.draw.connect(_draw_menu_circle_button.bind(b, i))
	_build_stats_view()
	_build_settings_view()
	robot_select = RobotSelectView.new()
	robot_select.name = "RobotSelect"
	add_child(robot_select)
	robot_select.build(self)
	campaign_map = CampaignMapView.new()
	campaign_map.name = "CampaignMap"
	add_child(campaign_map)
	campaign_map.build(self)
	campaign_result = CampaignResultView.new()
	campaign_result.name = "CampaignResult"
	add_child(campaign_result)
	campaign_result.build(self)
	race_hud = RaceHud.new()
	race_hud.name = "RaceHud"
	hud.add_child(race_hud)
	race_hud.build(self)
	race_hud.visible = false
	star_hud = StarHud.new()
	hud.add_child(star_hud)
	star_hud.build(self)
	flick_bar = FlickPowerBar.new()
	flick_bar.name = "FlickPowerBar"
	hud.add_child(flick_bar)
	flick_bar.build(self)
	_build_debug()


func set_menu_robot(p_def: RobotDefinition, base_cfg: RobotConfig, skin: SkinDefinition = null, mk2 := false) -> void:
	if menu_robot_preview == null or p_def == null or base_cfg == null:
		return
	menu_robot_preview.show_robot(p_def, base_cfg, skin, mk2)
	_layout_menu()


func _style_menu_circle_button(b: Button, color: Color, diameter: float, border_w: int) -> void:
	var rad := int(ceil(diameter * 0.5))
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.size = Vector2(diameter, diameter)
	b.pivot_offset = b.size * 0.5
	b.add_theme_font_size_override("font_size", 32)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color if st != "pressed" else color.darkened(0.18)
		if st == "hover":
			sb.bg_color = color.lightened(0.12)
		sb.border_color = INK
		sb.set_border_width_all(border_w)
		sb.set_corner_radius_all(rad)
		sb.shadow_color = Color(0, 0, 0, 0.38)
		sb.shadow_size = 0 if st == "pressed" else int(round(clampf(diameter * 0.06, 4.0, 10.0)))
		sb.shadow_offset = Vector2(0, clampf(diameter * 0.045, 3.0, 7.0))
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(st, sb)


func _draw_menu_circle_button(b: Button, idx: int) -> void:
	var d := minf(b.size.x, b.size.y)
	if d <= 10.0:
		return
	var c := b.size * 0.5
	var r := d * 0.5
	var s := d / 150.0
	# Cartoon inner highlight arc
	b.draw_arc(c, maxf(r - 9.0 * s, 8.0), deg_to_rad(200.0), deg_to_rad(340.0), 20, Color(1.0, 1.0, 1.0, 0.42), maxf(4.5 * s, 2.5))
	b.draw_arc(c, maxf(r - 7.0 * s, 8.0), deg_to_rad(25.0), deg_to_rad(155.0), 18, Color(0.1, 0.06, 0.04, 0.16), maxf(3.5 * s, 2.0))
	# tin-plate rivets (top only: never under the caption)
	for a in [200.0, 340.0]:
		var rp := c + Vector2.RIGHT.rotated(deg_to_rad(a)) * (r - 13.0 * s)
		b.draw_circle(rp, 5.0 * s, INK)
		b.draw_circle(rp, 3.4 * s, Color(1, 1, 1, 0.55))
		b.draw_circle(rp + Vector2(-1.0, -1.0) * s, 1.4 * s, Color(1, 1, 1, 0.9))
	var ic := Vector2(c.x, d * 0.31)
	match idx:
		0:
			# КАМПАНИЯ: cartoon crown/trophy banner emblem
			var crown := PackedVector2Array([
				ic + Vector2(-24.0, 12.0) * s,
				ic + Vector2(-28.0, -10.0) * s,
				ic + Vector2(-11.0, 1.0) * s,
				ic + Vector2(0.0, -16.0) * s,
				ic + Vector2(11.0, 1.0) * s,
				ic + Vector2(28.0, -10.0) * s,
				ic + Vector2(24.0, 12.0) * s,
			])
			b.draw_colored_polygon(crown, GOLD)
			var crown_line := crown.duplicate()
			crown_line.append(crown[0])
			b.draw_polyline(crown_line, INK, maxf(3.5 * s, 2.0))
			_star(b, ic + Vector2(0.0, -2.0) * s, 7.5 * s)
		1:
			# СВОБОДНЫЙ ЗАБЕГ: cartoon lightning speed bolt
			var bolt := PackedVector2Array([
				ic + Vector2(6.0, -20.0) * s,
				ic + Vector2(-18.0, 2.0) * s,
				ic + Vector2(-2.0, 2.0) * s,
				ic + Vector2(-10.0, 20.0) * s,
				ic + Vector2(18.0, -4.0) * s,
				ic + Vector2(2.0, -4.0) * s,
			])
			b.draw_colored_polygon(bolt, CREAM)
			var bolt_line := bolt.duplicate()
			bolt_line.append(bolt[0])
			b.draw_polyline(bolt_line, INK, maxf(3.5 * s, 2.0))
		2:
			# СТАТИСТИКА: ascending cartoon chart bars + star
			var cols := [Color(0.35, 0.78, 0.95), Color(1.0, 0.65, 0.22), GOLD]
			var hs := [14.0, 22.0, 30.0]
			for k in 3:
				var bx := ic.x + (k - 1) * 16.0 * s - 5.5 * s
				var bh: float = hs[k] * s
				var br := Rect2(Vector2(bx, ic.y + 14.0 * s - bh), Vector2(11.0 * s, bh))
				b.draw_rect(br, cols[k])
				b.draw_rect(br, INK, false, maxf(2.8 * s, 1.8))
			_star(b, ic + Vector2(16.0, -21.0) * s, 6.5 * s)
		3:
			# НАСТРОЙКИ: cartoon 8-tooth gear
			var pts := PackedVector2Array()
			for k in 16:
				var a := TAU * float(k) / 16.0 - PI * 0.125
				var gr := (19.5 if (k % 2 == 0) else 13.5) * s
				pts.append(ic + Vector2(cos(a), sin(a)) * gr)
			b.draw_colored_polygon(pts, GOLD)
			pts.append(pts[0])
			b.draw_polyline(pts, INK, maxf(3.2 * s, 2.0))
			b.draw_circle(ic, 6.5 * s, INK)
			b.draw_circle(ic, 4.0 * s, PAPER)
	# Draw high-contrast outlined Russian caption inside the circle
	var max_tw := d * 0.80
	if idx == 1:
		var lines := [L.t("MENU_FREE_RUN_L1"), L.t("MENU_FREE_RUN_L2")]
		var fs := int(round(clampf(d * 0.155, 12.0, 26.0)))
		while fs > 11 and maxf(font.get_string_size(lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, font.get_string_size(lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) > max_tw:
			fs -= 1
		var out_sz := maxi(int(round(float(fs) * 0.30)), 4)
		for li in 2:
			var lw := font.get_string_size(lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var lp := Vector2(c.x - lw * 0.5, d * (0.63 + 0.16 * float(li)) + float(fs) * 0.32)
			b.draw_string_outline(font, lp, lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, out_sz, INK)
			b.draw_string(font, lp, lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)
	else:
		var txt := b.text
		var fs := int(round(clampf(d * 0.185, 13.0, 30.0)))
		while fs > 11 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_tw:
			fs -= 1
		var out_sz := maxi(int(round(float(fs) * 0.30)), 4)
		var lw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := Vector2(c.x - lw * 0.5, d * 0.72 + float(fs) * 0.32)
		b.draw_string_outline(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, out_sz, INK)
		b.draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)


func _draw_menu_stage() -> void:
	if menu_stage == null:
		return
	# Top-left record badge & top-right currency badge backdrops
	for lbl in [best_label_menu, coins_label_menu]:
		if lbl != null and lbl.visible and lbl.size.x > 4.0:
			var pill := Rect2(lbl.position - Vector2(10.0, 3.0), lbl.size + Vector2(20.0, 6.0))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.10, 0.06, 0.04, 0.66)
			sb.border_color = INK
			sb.set_border_width_all(4)
			sb.set_corner_radius_all(int(ceil(pill.size.y * 0.48)))
			menu_stage.draw_style_box(sb, pill)
	# Downhill dashed path connecting the 4 circular buttons
	if _menu_button_centers.size() == 4:
		for i in 3:
			var p0 := _menu_button_centers[i]
			var p1 := _menu_button_centers[i + 1]
			for step_i in range(1, 5):
				var t := float(step_i) / 5.0
				var pt := p0.lerp(p1, t) + Vector2(0.0, sin(t * PI) * 5.0)
				menu_stage.draw_circle(pt, 7.5, INK)
				menu_stage.draw_circle(pt, 4.5, GOLD if i == 0 else CREAM)
	# Right-side character cartoon nameplate. v28: no ground shadow / dark turf ellipse under the robot's feet
	# (design rule: nothing dark is drawn or baked under a playable character).
	if _menu_pedestal_rect.size.x > 10.0 and menu_robot_preview != null and menu_robot_preview.def != null:
		var pc := _menu_pedestal_rect.get_center()
		var ry := _menu_pedestal_rect.size.y * 0.42
		var rname := L.data(menu_robot_preview.def.display_name).to_upper()
		var nfs := int(round(clampf(_menu_pedestal_rect.size.x * 0.11, 16.0, 30.0)))
		var nw := font.get_string_size(rname, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
		var badge_w := maxf(nw + 36.0, 130.0)
		var badge_h := float(nfs) + 14.0
		var badge_rect := Rect2(Vector2(pc.x - badge_w * 0.5, pc.y + ry * 0.45), Vector2(badge_w, badge_h))
		if badge_rect.end.y <= menu_content.size.y - 2.0:
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = Color(0.12, 0.07, 0.05, 0.82)
			bsb.border_color = GOLD
			bsb.set_border_width_all(3)
			bsb.set_corner_radius_all(int(ceil(badge_h * 0.48)))
			menu_stage.draw_style_box(bsb, badge_rect)
			var tp := Vector2(pc.x - nw * 0.5, badge_rect.position.y + badge_h * 0.5 + float(nfs) * 0.34)
			menu_stage.draw_string_outline(font, tp, rname, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, 6, INK)
			menu_stage.draw_string(font, tp, rname, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, GOLD)


## Size only menu controls against the usable viewport, including Android cutouts.
func _layout_menu() -> void:
	if menu_content == null or menu_buttons.is_empty():
		return
	var m := safe_margins
	menu_content.offset_left = m.x + 16
	menu_content.offset_top = m.y + 12
	menu_content.offset_right = -m.z - 16
	menu_content.offset_bottom = -m.w - 12
	var vp := get_viewport().get_visible_rect().size
	var W := maxf(vp.x - m.x - m.z - 32.0, 320.0)
	var H := maxf(vp.y - m.y - m.w - 24.0, 240.0)
	menu_content.size = Vector2(W, H)
	var u := clampf(minf(W / 1800.0, H / 1000.0), 0.42, 1.05)

	# 1. Top-Left Record & Top-Right Currency
	var bfs := int(round(clampf(38.0 * u, 18.0, 40.0)))
	best_label_menu.add_theme_font_size_override("font_size", bfs)
	best_label_menu.add_theme_constant_override("outline_size", int(round(clampf(10.0 * u, 5.0, 12.0))))
	var best_min := best_label_menu.get_minimum_size()
	var bar_x := 10.0
	if profile_chip != null and profile_chip.visible:
		# v31: "PLAYER N" chip first in the top bar, same height as the record badge
		var pfs := int(round(clampf(26.0 * u, 15.0, 28.0)))
		profile_chip.add_theme_font_size_override("font_size", pfs)
		var pw := font.get_string_size(profile_chip.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x + 44.0
		profile_chip.custom_minimum_size = Vector2(pw, best_min.y + 4.0)
		profile_chip.size = profile_chip.custom_minimum_size
		profile_chip.position = Vector2(4.0, 2.0)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb: StyleBoxFlat = profile_chip.get_theme_stylebox(st)
			sb.set_border_width_all(4)
			sb.set_corner_radius_all(int(ceil(profile_chip.size.y * 0.48)))
			sb.shadow_size = 0
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
		bar_x = profile_chip.position.x + pw + 22.0
	best_label_menu.position = Vector2(bar_x, 4.0)
	best_label_menu.size = Vector2(best_min.x + 6.0, best_min.y + 4.0)
	if artifact_button != null and artifact_button.visible:
		# v32: small equip pill after the record (only once the artifact was found)
		var afs := int(round(clampf(24.0 * u, 14.0, 26.0)))
		artifact_button.add_theme_font_size_override("font_size", afs)
		var aw := font.get_string_size(artifact_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x + 40.0
		artifact_button.custom_minimum_size = Vector2(aw, best_min.y + 4.0)
		artifact_button.size = artifact_button.custom_minimum_size
		artifact_button.position = Vector2(best_label_menu.position.x + best_label_menu.size.x + 22.0, 2.0)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb: StyleBoxFlat = artifact_button.get_theme_stylebox(st)
			sb.set_border_width_all(4)
			sb.set_corner_radius_all(int(ceil(artifact_button.size.y * 0.48)))
			sb.shadow_size = 0
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0

	var cfs := int(round(clampf(30.0 * u, 15.0, 34.0)))
	coins_label_menu.add_theme_font_size_override("font_size", cfs)
	coins_label_menu.add_theme_constant_override("outline_size", int(round(clampf(9.0 * u, 4.0, 10.0))))
	var coins_min := coins_label_menu.get_minimum_size()
	var left_end := best_label_menu.position.x + best_label_menu.size.x
	if artifact_button != null and artifact_button.visible:
		left_end = artifact_button.position.x + artifact_button.size.x
	var max_coins_w := maxf(W - (left_end + 24.0), 120.0)
	while cfs > 12 and coins_min.x > max_coins_w:
		cfs -= 1
		coins_label_menu.add_theme_font_size_override("font_size", cfs)
		coins_min = coins_label_menu.get_minimum_size()
	coins_label_menu.size = Vector2(coins_min.x + 6.0, coins_min.y + 4.0)
	coins_label_menu.position = Vector2(maxf(W - coins_label_menu.size.x - 10.0, left_end + 12.0), 4.0)

	# 2. Main Title: "ЭПИЧЕСКИЙ ЩЕЛБАН" (no subtitle)
	var top_bar_bottom := maxf(best_label_menu.position.y + best_label_menu.size.y, coins_label_menu.position.y + coins_label_menu.size.y) + 6.0 * u
	var max_title_w := W * 0.57
	var raw_tw := font.get_string_size(menu_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x
	var tfs := int(clampf(floorf(96.0 * max_title_w / maxf(raw_tw + 20.0, max_title_w)), 28.0, 96.0))
	menu_title.add_theme_font_size_override("font_size", tfs)
	menu_title.add_theme_constant_override("outline_size", int(round(clampf(float(tfs) * 0.22, 6.0, 22.0))))
	var title_min := menu_title.get_minimum_size()
	menu_title.position = Vector2(10.0, top_bar_bottom)
	menu_title.size = Vector2(title_min.x + 8.0, title_min.y + 4.0)

	# 3. 4 Circular Downhill Buttons (middle-left -> middle-bottom)
	var buttons_top := menu_title.position.y + menu_title.size.y + 8.0 * u
	var avail_w := maxf(W * 0.55 - 12.0, 368.0)
	var max_d_x := (avail_w - 15.0) / 4.0
	# v34: ~17% larger circles (tester: menu controls felt small); same downhill layout / spacing rules
	var D := clampf(minf(max_d_x, H * 0.19), 96.0, 176.0)
	var border_w := int(round(clampf(7.0 * u, 4.0, 8.0)))
	var x0 := 8.0 + D * 0.5
	var x3 := maxf(W * 0.49, x0 + 3.0 * (D + 5.0))
	var y0 := clampf(maxf(buttons_top + D * 0.5 + 4.0, H * 0.36), buttons_top + D * 0.5 + 2.0, H - D * 1.35)
	var y3 := H - D * 0.5 - 6.0
	_menu_button_centers.clear()
	for i in menu_buttons.size():
		var b := menu_buttons[i]
		_style_menu_circle_button(b, MENU_CIRCLE_COLORS[i], D, border_w)
		var t := float(i) / 3.0
		var cx := lerpf(x0, x3, t)
		var cy := lerpf(y0, y3, t)
		b.position = Vector2(cx - D * 0.5, cy - D * 0.5)
		_menu_button_centers.append(Vector2(cx, cy))
		b.queue_redraw()
	_menu_circle_d = D

	# 4. Large Selected Playable Robot on the Right Side
	var char_left := minf(x3 + D * 0.5 + 16.0 * u, W * 0.62)
	var char_top := top_bar_bottom + 4.0 * u
	_menu_char_rect = Rect2(Vector2(char_left, char_top), Vector2(maxf(W - char_left - 6.0, 140.0), maxf(H - char_top - 8.0, 180.0)))
	if menu_robot_preview != null and menu_robot_preview.rig != null:
		var bounds := menu_robot_preview.art_bounds()
		var ped_h := clampf(44.0 * u, 20.0, 48.0)
		var fit_area := Rect2(_menu_char_rect.position + Vector2(8.0, 4.0), Vector2(maxf(_menu_char_rect.size.x - 16.0, 80.0), maxf(_menu_char_rect.size.y - ped_h - 8.0, 120.0)))
		var fit := minf(fit_area.size.x / maxf(bounds.size.x, 1.0), fit_area.size.y / maxf(bounds.size.y, 1.0)) * 0.94
		# v34: presentation-only correction (Самуробот x0.88); the feet stay on foot_y below
		var sc := clampf(fit, 0.42, 1.85) * RobotPreview.presentation_scale(menu_robot_preview.def.id if menu_robot_preview.def else "")
		menu_robot_preview.scale = Vector2.ONE * sc
		var foot_y := fit_area.end.y - 4.0 * u
		var cx_char := fit_area.get_center().x
		menu_robot_preview.position = Vector2(
			cx_char - bounds.get_center().x * sc,
			foot_y - (bounds.end.y - 18.0) * sc
		)
		var ped_w := clampf(bounds.size.x * sc * 0.78, 110.0, fit_area.size.x * 0.88)
		_menu_pedestal_rect = Rect2(Vector2(cx_char - ped_w * 0.5, foot_y - ped_h * 0.35), Vector2(ped_w, ped_h))
	if menu_stage != null:
		menu_stage.queue_redraw()


func show_menu(best: float, stats_data := {}) -> void:
	if achievements_view: achievements_view.visible = false
	if awareness: awareness.visible=false
	if biome_intro: biome_intro.cancel()
	if flick_bar: flick_bar.hide_immediate()
	if continue_card: continue_card.visible = false
	best_label_menu.text = (L.t("MENU_RECORD") % int(best)) if best > 0.0 else L.t("MENU_RECORD_NONE")
	_stats_data = stats_data
	menu.visible = true
	hud.visible = false
	results.visible = false
	stats_view.visible = false
	settings_view.visible = false
	robot_select.visible = false
	campaign_map.visible = false
	campaign_result.visible = false
	_layout_menu()


## v31: chip text "PLAYER N" (hidden in the single-file debug harness or while no player is active).
func set_profile_chip(slot_name: String, profiles_enabled: bool) -> void:
	profile_chip.text = slot_name
	profile_chip.visible = profiles_enabled and slot_name != ""
	_layout_menu()


## Modal / overlay screens that must render above the menu (and its robot preview). Single source for layering + tests.
func modal_roots() -> Array[Control]:
	var out: Array[Control] = []
	for c in [settings_view, stats_view, results, robot_select, campaign_map, campaign_result, awareness, profiles_view,
			continue_card, tutorial_overlay, achievements_view]:
		if c != null:
			out.append(c)
	return out


## v34: "tap to skip" hint while the jet head flies (bottom centre, never over the HUD controls).
var rocket_hint: Label


func rocket_hint_visible() -> bool:
	return rocket_hint != null and rocket_hint.visible


func show_rocket_hint(on: bool) -> void:
	if rocket_hint == null:
		rocket_hint = _label(L.t("HUD_ROCKET_SKIP"), 30, CREAM, 9)
		rocket_hint.name = "RocketSkipHint"
		rocket_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hud.add_child(rocket_hint)
	var vp := get_viewport().get_visible_rect().size
	rocket_hint.size = Vector2(vp.x * 0.6, 44)
	rocket_hint.position = Vector2(vp.x * 0.2, vp.y - safe_margins.w - 150)
	rocket_hint.visible = on


## v32: the artifact toggle exists only after discovery (nothing hints at it before).
func set_artifact_state(discovered: bool, equipped: bool) -> void:
	artifact_button.visible = discovered
	artifact_button.text = L.t("MENU_ARTIFACT_ON") if equipped else L.t("MENU_ARTIFACT_OFF")
	_layout_menu()


func open_profiles(summaries: Array, active: int, can_back: bool) -> void:
	profiles_view.open(summaries, active, can_back)


func close_profiles() -> void:
	profiles_view.cancel_delete()
	profiles_view.visible = false


func is_profiles_open() -> bool:
	return profiles_view != null and profiles_view.visible


func show_hud() -> void:
	if achievements_view: achievements_view.visible = false
	menu.visible = false
	robot_select.visible = false
	campaign_map.visible = false
	campaign_result.visible = false
	results.visible = false
	stats_view.visible = false
	settings_view.visible = false
	hud.visible = true
	restart_button.visible = restart_enabled
	abandon_button.visible = true
	hint.visible = true
	reset_modules()
	set_distance(0)
	set_health(_hp_max, _hp_max, true)
	set_charge(0.0, true)


# ---------------- settings panel ----------------

var settings_center: CenterContainer
var settings_panel: PanelContainer
var settings_footer: Array[Button] = []
var settings_view: Control
var _sliders := {}
## Settings tabs: rows before this index = "ОСНОВНЫЕ", from it on = "ВРАЩЕНИЕ".
const SETTINGS_PAGE2 := 6
var _setting_rows := {}      # key -> [controls of the row]
var _tab_buttons: Array[Button] = []
var settings_page := 0
var _slider_values := {}
## v34: only presentation / accessibility settings are player-facing; gameplay physics are fixed release values
## (SettingsStore.FIXED) and have no controls any more.
const SETTING_ROWS := [
	["shake", "SET_SHAKE", "%d%%"],
	["vibration", "SET_VIBRATION", "%d%%"],
]


func _grabber_texture(d: int, col: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := d / 2.0
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5 - c, y + 0.5 - c).length() / c
			var px := Color(0, 0, 0, 0)
			if r < 0.74:
				px = col
			elif r < 0.98:
				px = INK
			elif r < 1.0:
				px = Color(INK.r, INK.g, INK.b, (1.0 - r) / 0.02)
			img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)


## v34: small gold coin (the Continue price button). Procedural like the slider grabbers - no new art asset.
var _coin_tex: ImageTexture


func coin_icon(d := 44) -> ImageTexture:
	if _coin_tex != null and _coin_tex.get_width() == d:
		return _coin_tex
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := d / 2.0
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5 - c, y + 0.5 - c).length() / c
			var px := Color(0, 0, 0, 0)
			if r < 0.56:
				px = Color(1.0, 0.84, 0.25)
			elif r < 0.66:
				px = Color(0.80, 0.55, 0.10)
			elif r < 0.84:
				px = GOLD.lightened(0.15)
			elif r < 0.98:
				px = INK
			elif r < 1.0:
				px = Color(INK.r, INK.g, INK.b, (1.0 - r) / 0.02)
			# little shine
			if r < 0.84 and Vector2(x + 0.5 - c * 0.72, y + 0.5 - c * 0.66).length() < d * 0.07:
				px = Color(1, 0.98, 0.85)
			img.set_pixel(x, y, px)
	_coin_tex = ImageTexture.create_from_image(img)
	return _coin_tex


func _slider(key: String) -> HSlider:
	var s := HSlider.new()
	var sp: Array = SettingsStore.spec(key)
	s.min_value = sp[0]
	s.max_value = sp[1]
	s.step = sp[2]
	s.custom_minimum_size = Vector2(520, 64)
	s.focus_mode = Control.FOCUS_NONE
	s.scrollable = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.25, 0.18, 0.15)
	track.border_color = INK
	track.set_border_width_all(4)
	track.set_corner_radius_all(14)
	track.content_margin_top = 12
	track.content_margin_bottom = 12
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(14)
	fill.content_margin_top = 12
	fill.content_margin_bottom = 12
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", _grabber_texture(56, PAPER))
	s.add_theme_icon_override("grabber_highlight", _grabber_texture(56, Color(1, 0.95, 0.7)))
	s.value_changed.connect(func(v: float) -> void:
		_slider_values[key].text = SETTING_ROWS.filter(func(r: Array) -> bool: return r[0] == key)[0][2] % v
		if not _filling:
			setting_changed.emit(key, v))
	return s


var _filling := false
signal language_chosen(code: String)
var language_row: HBoxContainer
var language_button: Button
var language_picker: Control
var _language_options: Array[Button] = []
var _language_choice := "auto"


func _build_settings_view() -> void:
	settings_view = Control.new()
	settings_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_view.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_view.visible = false
	add_child(settings_view)
	_shade(settings_view, 0.6)
	settings_view.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_settings())
	var center := CenterContainer.new()
	settings_center=center
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_view.add_child(center)
	var panel := _paper_panel()
	settings_panel=panel
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var t := _label(L.t("MENU_SETTINGS"), 44, GOLD, 12)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	# v34: one page (no tabs): shake, vibration, sound volume
	# one row per setting: name | slider | value
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for row in SETTING_ROWS:
		var name_l := _ink_label(L.t(row[1]), 26)
		name_l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(name_l)
		var s := _slider(row[0])
		s.custom_minimum_size = Vector2(440, 60)   # touch-friendly
		_sliders[row[0]] = s
		grid.add_child(s)
		var val := _ink_label("", 28)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.custom_minimum_size = Vector2(140, 0)
		_slider_values[row[0]] = val
		grid.add_child(val)
		_setting_rows[row[0]] = [name_l, s, val]
	sfx_row = HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation",20)
	v.add_child(sfx_row)
	var sfx_title := _ink_label(L.t("SET_SFX"),28)
	sfx_title.custom_minimum_size=Vector2(320,64)
	sfx_row.add_child(sfx_title)
	sfx_slider=HSlider.new()
	sfx_slider.min_value=0; sfx_slider.max_value=100; sfx_slider.step=5
	sfx_slider.custom_minimum_size=Vector2(520,64)
	sfx_slider.focus_mode=Control.FOCUS_NONE; sfx_slider.scrollable=false
	sfx_slider.add_theme_icon_override("grabber",_grabber_texture(56,PAPER))
	sfx_slider.add_theme_icon_override("grabber_highlight",_grabber_texture(56,GOLD))
	sfx_row.add_child(sfx_slider)
	sfx_label=_ink_label("75%",28)
	sfx_label.custom_minimum_size=Vector2(140,64)
	sfx_row.add_child(sfx_label)
	sfx_slider.value_changed.connect(func(value: float) -> void:
		sfx_label.text="%d%%"%value
		if not _filling: sfx_volume_changed.emit(value))
	# v34: LANGUAGE (app-global) - name | current language button (opens the picker)
	language_row = HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 20)
	v.add_child(language_row)
	var lang_title := _ink_label(L.t("SET_LANGUAGE"), 28)
	lang_title.custom_minimum_size = Vector2(320, 64)
	lang_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	language_row.add_child(lang_title)
	language_button = _button(language_caption(L.AUTO), CREAM)
	language_button.custom_minimum_size = Vector2(520, 68)
	language_button.add_theme_font_size_override("font_size", 28)
	language_button.pressed.connect(open_language_picker)
	language_row.add_child(language_button)
	_build_language_picker()
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 28)
	v.add_child(buttons)
	var def := _button(L.t("UI_DEFAULTS"), PAPER)
	def.custom_minimum_size = Vector2(330, 80)
	def.add_theme_font_size_override("font_size", 36)
	def.pressed.connect(func() -> void: settings_reset.emit())
	buttons.add_child(def)
	settings_footer.append(def)
	var close := _button(L.t("UI_DONE"), GOLD)
	close.custom_minimum_size = Vector2(240, 80)
	close.add_theme_font_size_override("font_size", 40)
	close.pressed.connect(close_settings)
	buttons.add_child(close)
	settings_footer.append(close)
	var learn := _button(L.t("TUT_TITLE"),PAPER)
	learn.custom_minimum_size=Vector2(240,80)
	learn.add_theme_font_size_override("font_size",30)
	learn.pressed.connect(func() -> void: tutorial_pressed.emit())
	buttons.add_child(learn)
	settings_footer.append(learn)


## v34 language picker: Auto + the 13 supported languages, each written in its own language (endonym).
func _build_language_picker() -> void:
	language_picker = Control.new()
	language_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	language_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	language_picker.visible = false
	settings_view.add_child(language_picker)
	_shade(language_picker, 0.55)
	language_picker.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			language_picker.visible = false)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	language_picker.add_child(c)
	var panel := _paper_panel()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t := _label(L.t("SET_LANGUAGE"), 40, GOLD, 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	_language_options.clear()
	for code in [L.AUTO] + L.codes():
		var b := _button("", PAPER)
		b.custom_minimum_size = Vector2(330, 66)
		b.add_theme_font_size_override("font_size", 26)
		b.set_meta("language", code)
		b.pressed.connect(func() -> void:
			language_picker.visible = false
			language_chosen.emit(code))
		grid.add_child(b)
		_language_options.append(b)
	_refresh_language_options()


static func endonym(code: String) -> String:
	for l in L.LOCALES:
		if l[0] == code:
			return l[1]
	return code


## "Auto (English)" shows what Auto resolves to on this device.
static func language_caption(choice: String) -> String:
	if choice == L.AUTO:
		return "%s (%s)" % [L.t("SET_LANG_AUTO"), endonym(L.resolve(L.AUTO))]
	return endonym(choice)


func set_language_choice(choice: String) -> void:
	_language_choice = choice
	if language_button:
		language_button.text = language_caption(choice)
	_refresh_language_options()


func _refresh_language_options() -> void:
	for b in _language_options:
		var code: String = b.get_meta("language")
		b.text = ("● " if code == _language_choice else "") + language_caption(code)


func open_language_picker() -> void:
	_refresh_language_options()
	language_picker.visible = true


## Shows stored values without echoing them back as changes.
func set_settings_values(values: Dictionary) -> void:
	_filling = true
	for k in _sliders:
		if values.has(k):
			_sliders[k].value = values[k]
			_slider_values[k].text = SETTING_ROWS.filter(func(r: Array) -> bool: return r[0] == k)[0][2] % float(values[k])
	_filling = false


func show_settings_page(p: int) -> void:
	# v34: a single page - everything player-adjustable is always visible
	settings_page = 0
	sfx_row.visible = true
	language_row.visible = true
	for k in _setting_rows:
		for ctl in _setting_rows[k]:
			ctl.visible = true


func set_sfx_volume(percent: float) -> void:
	_filling=true
	sfx_slider.value=percent
	sfx_label.text="%d%%"%percent
	_filling=false

func open_settings() -> void:
	show_settings_page(settings_page)
	settings_view.visible = true
	settings_view.modulate.a = 0.0
	var tw := settings_view.create_tween()
	tw.tween_property(settings_view, "modulate:a", 1.0, 0.18)


func close_settings() -> void:
	language_picker.visible = false
	settings_view.visible = false


func is_settings_open() -> bool:
	return settings_view.visible


# ---------------- statistics panel ----------------

func _build_stats_view() -> void:
	stats_view = Control.new()
	stats_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	stats_view.mouse_filter = Control.MOUSE_FILTER_STOP
	stats_view.visible = false
	add_child(stats_view)
	_shade(stats_view, 0.6)
	# tap outside the panel closes it
	stats_view.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_stats())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_view.add_child(center)
	var panel := _paper_panel()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t := _label(L.t("MENU_STATS"), 54, GOLD, 12)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	v.add_child(cols)
	_stats_totals = GridContainer.new()
	_stats_totals.columns = 2
	_stats_totals.custom_minimum_size = Vector2(470, 0)
	_stats_totals.add_theme_constant_override("h_separation", 24)
	_stats_totals.add_theme_constant_override("v_separation", 2)
	cols.add_child(_stats_totals)
	cols.add_child(_ink_rule(true))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 2)
	cols.add_child(right)
	var rh := _ink_label(L.t("STATS_RECENT"), 28)
	right.add_child(rh)
	_stats_recent = VBoxContainer.new()
	_stats_recent.add_theme_constant_override("separation", 0)
	right.add_child(_stats_recent)
	var close := _button(L.t("UI_CLOSE"), GOLD)
	close.custom_minimum_size = Vector2(280, 84)
	close.add_theme_font_size_override("font_size", 40)
	close.pressed.connect(close_stats)
	var cc := CenterContainer.new()
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	cc.add_child(buttons)
	achievements_button = _button(L.t("ACH_TITLE"), PAPER)
	achievements_button.custom_minimum_size = Vector2(390, 84)
	achievements_button.add_theme_font_size_override("font_size", 28)
	buttons.add_child(achievements_button)
	achievements_button.pressed.connect(func() -> void:
		stats_view.visible = false
		achievements_view.open(achievement_system))
	buttons.add_child(close)
	v.add_child(cc)


func open_stats() -> void:
	_fill_stats(_stats_data)
	stats_view.visible = true
	stats_view.modulate.a = 0.0
	var tw := stats_view.create_tween()
	tw.tween_property(stats_view, "modulate:a", 1.0, 0.18)


func close_stats() -> void:
	stats_view.visible = false


func is_stats_open() -> bool:
	return stats_view.visible


func _fill_stats(d: Dictionary) -> void:
	for ch in _stats_totals.get_children():
		ch.queue_free()
	for ch in _stats_recent.get_children():
		ch.queue_free()
	var s: Dictionary = StatsStore.defaults()
	s.merge(d, true)
	var attempts := int(s.attempts)
	var best := float(s.best_m)
	var rows := [
		[L.t("STATS_BEST"), (L.t("UNIT_M_N") % int(best)) if best > 0.0 else "—"],
		[L.t("STATS_ATTEMPTS"), str(attempts)],
		[L.t("STATS_TOTAL_DIST"), L.t("UNIT_M_N") % int(s.total_m)],
		[L.t("STATS_AVG_DIST"), (L.t("UNIT_M_N") % int(float(s.total_m) / attempts)) if attempts > 0 else "—"],
		[L.t("STATS_TIME"), _fmt_time(float(s.total_time_s))],
		[L.t("STATS_GOOD"), str(int(s.good_landings))],
		[L.t("STATS_BAD"), str(int(s.bad_landings))],
		[L.t("STATS_BEST_CHARGE"), "%d%%" % int(round(float(s.best_attempt_charge) * 100.0))],
		[L.t("STATS_FULL_BOUNCES"), str(int(s.full_charge_bounces))],
	]
	for r in rows:
		_stats_totals.add_child(_ink_label(r[0], 24, GREY))
		var val := _ink_label(r[1], 28)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats_totals.add_child(val)
	var recent: Array = s.recent
	if recent.is_empty():
		_stats_recent.add_child(_ink_label(L.t("STATS_EMPTY"), 24, GREY))
	for i in recent.size():
		var e: Dictionary = recent[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var n := _ink_label("%d." % (i + 1), 24, GREY)
		n.custom_minimum_size = Vector2(42, 0)
		line.add_child(n)
		var dist := _ink_label(L.t("UNIT_M_N") % int(e.get("distance_m", 0.0)), 26)
		dist.custom_minimum_size = Vector2(120, 0)
		line.add_child(dist)
		line.add_child(_ink_label(_fmt_time(float(e.get("duration_s", 0.0))), 22, GREY))
		var star := _label(L.t("STATS_RECORD_TAG") if e.get("record", false) else "", 22, GOLD, 5)
		star.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(star)
		_stats_recent.add_child(line)


# ---------------- results ----------------

var _res_panel: PanelContainer
var _res_rows: Array[Control] = []
var _res_values := {}
var _burst: Control
var _burst_time := 0.0


func _build_results() -> void:
	results = Control.new()
	results.set_anchors_preset(Control.PRESET_FULL_RECT)
	results.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(results)
	_shade(results, 0.5)
	# rotating sun-burst behind the panel, only for a new record
	_burst = Control.new()
	_burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst.draw.connect(_draw_burst)
	results.add_child(_burst)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	results.add_child(center)
	_res_panel = _paper_panel()
	center.add_child(_res_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_res_panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 30)
	v.add_child(top)
	# left: the result
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(470, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 2)
	top.add_child(left)
	var t := _ink_label(L.t("RES_OVER"), 42)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(t)
	result_reason = _ink_label("", 24, GREY)
	result_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(result_reason)
	result_distance = _gold_label(L.t("UNIT_M_N") % 0, 124)
	result_distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(result_distance)
	result_record = _label(L.t("RES_NEW_RECORD"), 50, Color(0.95, 0.2, 0.12), 12)
	result_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_record.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_record.custom_minimum_size = Vector2(0, 84)   # room for the tilted stamp
	left.add_child(result_record)
	result_best = _ink_label("", 30)
	result_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(result_best)
	result_coins = _label("", 32, GOLD, 8)
	result_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(result_coins)
	top.add_child(_ink_rule(true))
	# right: this attempt's numbers
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 4)
	top.add_child(right)
	right.add_child(_ink_label(L.t("RES_THIS_RUN"), 30))
	right.add_child(_ink_rule(false))
	_res_rows.clear()
	for key in [["landings", L.t("RES_LANDINGS")], ["good", L.t("RES_GOOD")], ["bad", L.t("RES_BAD")], ["max_charge", L.t("RES_MAX_CHARGE")],
			["boosted", L.t("RES_BOOSTED")], ["duration", L.t("RES_TIME")]]:
		var row := HBoxContainer.new()
		row.add_child(_ink_label(key[1], 26, GREY))
		var val := _ink_label("0", 30)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		right.add_child(row)
		_res_rows.append(row)
		_res_values[key[0]] = val
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 28)
	v.add_child(row2)
	var retry := _button(L.t("TUT_AGAIN"), GOLD)
	retry.pressed.connect(func() -> void: retry_pressed.emit())
	row2.add_child(retry)
	var m := _button(L.t("UI_MENU"), PAPER)
	m.custom_minimum_size = Vector2(240, 104)
	m.pressed.connect(func() -> void: menu_pressed.emit())
	row2.add_child(m)


func _draw_burst() -> void:
	var size := _burst.size
	var c := size * 0.5
	var r := size.length()
	for i in 16:
		var a0 := _burst_time * 0.6 + TAU * i / 16.0
		var pts := PackedVector2Array([c, c + Vector2.RIGHT.rotated(a0) * r, c + Vector2.RIGHT.rotated(a0 + TAU / 32.0) * r])
		_burst.draw_colored_polygon(pts, Color(1.0, 0.8, 0.2, 0.22))


## summary: distance_m, best_m, record, reason, landings, good, bad, max_charge, boosted, duration_s
func show_results(summary: Dictionary) -> void:
	abandon_button.visible=false
	restart_button.visible=false
	var distance := float(summary.get("distance_m", 0.0))
	var best := float(summary.get("best_m", 0.0))
	var record := bool(summary.get("record", false))
	hud.visible = true
	results.visible = true
	stats_view.visible = false
	result_reason.text = L.data(str(summary.get("reason", "")))
	result_best.text = L.t("RES_PERSONAL_BEST") % int(best)
	result_coins.text = L.pf("RES_COINS", int(summary.coins_earned), {"total": int(summary.get("coins_total", 0))}) if summary.has("coins_earned") else ""
	result_record.visible = record
	_burst.visible = record
	_res_values.landings.text = str(int(summary.get("landings", 0)))
	_res_values.good.text = str(int(summary.get("good", 0)))
	_res_values.bad.text = str(int(summary.get("bad", 0)))
	_res_values.max_charge.text = "%d%%" % int(round(float(summary.get("max_charge", 0.0)) * 100.0))
	_res_values.boosted.text = str(int(summary.get("boosted", 0)))
	_res_values.duration.text = _fmt_time(float(summary.get("duration_s", 0.0)))
	# entrance: fade, panel pops in, distance counts up, rows appear one by one
	results.modulate.a = 0.0
	var tw := results.create_tween()
	tw.tween_property(results, "modulate:a", 1.0, 0.2)
	_res_panel.pivot_offset = _res_panel.size * 0.5
	_res_panel.scale = Vector2(0.7, 0.7)
	var tp := _res_panel.create_tween()
	tp.tween_property(_res_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	result_distance.text = L.t("UNIT_M_N") % 0
	var td := result_distance.create_tween()
	td.tween_interval(0.2)
	td.tween_method(func(x: float) -> void: result_distance.text = L.t("UNIT_M_N") % int(x), 0.0, distance, 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	td.tween_callback(func() -> void: result_distance.text = L.t("UNIT_M_N") % int(distance))
	result_distance.pivot_offset = result_distance.size * 0.5
	td.tween_property(result_distance, "scale", Vector2(1.12, 1.12), 0.08)
	td.tween_property(result_distance, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	for i in _res_rows.size():
		var row := _res_rows[i]
		row.modulate.a = 0.0
		var tr := row.create_tween()
		tr.tween_interval(0.25 + 0.08 * i)
		tr.tween_property(row, "modulate:a", 1.0, 0.15)
	if record:
		# rubber-stamp "НОВЫЙ РЕКОРД!" slams in after the count-up, then a gold star shower
		result_record.pivot_offset = result_record.size * 0.5
		result_record.scale = Vector2(3.0, 3.0)
		result_record.rotation = -0.5
		result_record.modulate.a = 0.0
		var ts := result_record.create_tween()
		ts.tween_interval(0.95)
		ts.tween_property(result_record, "modulate:a", 1.0, 0.01)
		ts.parallel().tween_property(result_record, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ts.parallel().tween_property(result_record, "rotation", -0.07, 0.22)
		ts.tween_callback(_star_shower)
		ts.tween_property(result_record, "scale", Vector2(1.08, 1.08), 0.35).set_trans(Tween.TRANS_SINE)
		ts.tween_property(result_record, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SINE)


func _star_shower() -> void:
	var size := results.size
	for i in 14:
		var s := Control.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.size = Vector2(40, 40)
		var rad := randf_range(9.0, 18.0)
		s.draw.connect(func() -> void: _star(s, Vector2(20, 20), rad))
		s.position = Vector2(size.x * 0.5, size.y * 0.42)
		results.add_child(s)
		var target := s.position + Vector2(randf_range(-560, 560), randf_range(-330, 230))
		var tw := s.create_tween()
		tw.tween_property(s, "position", target, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "rotation", randf_range(-4.0, 4.0), 0.9)
		tw.tween_property(s, "modulate:a", 0.0, 0.4)
		tw.tween_callback(s.queue_free)



func _layout_settings() -> void:
	if settings_center==null:
		return
	var m := safe_margins
	settings_center.offset_left=m.x+12
	settings_center.offset_right=-m.z-12
	settings_center.offset_top=m.y+8
	settings_center.offset_bottom=-m.w-8
	var usable := get_viewport().get_visible_rect().size.x-m.x-m.z-24
	var name_width := clampf((usable-220)*0.42,240,430)
	var slider_width := clampf(usable-80-40-110-name_width,200,440)
	for controls in _setting_rows.values():
		controls[0].custom_minimum_size.x=name_width
		controls[0].size_flags_horizontal=Control.SIZE_FILL
		controls[1].custom_minimum_size.x=slider_width
		controls[2].custom_minimum_size.x=110
	if language_row:
		language_row.get_child(0).custom_minimum_size.x=name_width
		language_button.custom_minimum_size.x=slider_width+130
	for b in settings_footer:
		b.custom_minimum_size.x=290 if b.text==L.t("UI_DEFAULTS") else 210
		b.add_theme_font_size_override("font_size",30)
