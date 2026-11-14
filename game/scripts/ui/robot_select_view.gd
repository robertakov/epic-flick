class_name RobotSelectView
extends Control
## Robot selection / shop: big animated preview, arrows, name, description, stat bars, price, coin balance,
## КУПИТЬ (locked robot) or ИГРАТЬ (owned). Emits requests; GameManager owns the profile and decides.

signal play_requested(id: String)
signal buy_requested(id: String)
signal back_requested
signal robot_focused(id: String)
## Cosmetic only: equip an owned skin of the shown archetype.
signal skin_equip_requested(robot_id: String, skin_id: String, mk2: bool)
## v35 MK2: buy the shown archetype's MK2 / choose BASE (false) or MK2 (true) for it.
signal mk2_buy_requested(id: String)
signal mk2_variant_requested(id: String, on: bool)

var ui: UIController
var catalog: RobotCatalog
var base_cfg: RobotConfig
var index := 0
var owned: Array[String] = []
var coins := 0

var preview: RobotPreview
var _preview_box: Control
var _name: Label
var _desc: Label
var _price: Label
var _coins: Label
var _note: Label
var _bars := {}
var _action: Button
var _left: Button
var _right: Button
var _dots: HBoxContainer
## Skins (cosmetic). skins: SkinCatalog; owned_skin / equipped: callables from GameManager (profile).
var skins: SkinCatalog
var owns_skin: Callable
var equipped_of: Callable
var skin_hint: Callable          # skin id -> where to earn it (text)
var _skin_idx := 0
var _skin_label: Label
var _skin_note: Label
var _skin_left: Button
var _skin_right: Button
## v35 MK2: mk2_state = Callable(def) -> {"eligible", "owned", "active", "boss"} (GameManager / profile).
var mk2_state: Callable
var viewing_mk2 := false
var _mk2_row: HBoxContainer
var _base_tab: Button
var _mk2_tab: Button
var _mk2_note: Label
var _srow: HBoxContainer
var _buy_guard := 0.0            # seconds the MK2 buy button stays disarmed after a press (rapid / double taps)
const MK2_BUY_GUARD_S := 0.8

const STATS := [
	["max_health", "SEL_STAT_HP"],
	["mass_multiplier", "SEL_STAT_MASS"],
	["springs", "SEL_STAT_SPRINGS"],
	["energy", "SEL_STAT_ENERGY"],
	["air_control", "SEL_STAT_CONTROL"],
]


func build(p_ui: UIController) -> void:
	ui = p_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	ui._shade(self, 0.55)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 30
	root.offset_right = -30
	root.offset_top = 8
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	# header: title + coins
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := ui._label(L.t("SEL_TITLE"), 58, UIController.GOLD, 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_coins = ui._label(L.pf("SEL_COINS", 0), 44, UIController.GOLD, 12)
	head.add_child(_coins)
	# middle: arrow | preview | info | arrow
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 18)
	root.add_child(mid)
	_left = ui._button("◀", UIController.PAPER)
	_left.custom_minimum_size = Vector2(110, 130)
	_left.add_theme_font_size_override("font_size", 60)
	_left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_left.pressed.connect(func() -> void: step(-1))
	mid.add_child(_left)
	_preview_box = Control.new()
	_preview_box.custom_minimum_size = Vector2(400, 430)
	_preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_box.clip_contents = false
	mid.add_child(_preview_box)
	preview = RobotPreview.new()
	# v29: the rig draws legs at z -1 and the Kengurobot tail at z -3 (relative); without an offset they sorted
	# below this screen's full-screen dark shade (z 0) and were darkened by 55%. Lift the whole preview above it.
	preview.z_index = 4
	_preview_box.add_child(preview)
	_preview_box.resized.connect(_place_preview)
	# skin row under the preview (appearance only - the build / stats never change)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_top = -146
	_preview_box.add_child(col)
	# v35: BASE / MK2 tabs of the shown archetype (MK2 = upgraded variant: own art + a few stats, same body)
	_mk2_row = HBoxContainer.new()
	_mk2_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mk2_row.add_theme_constant_override("separation", 8)
	col.add_child(_mk2_row)
	_base_tab = ui._button(L.t("MK2_TAB_BASE"), UIController.PAPER)
	_mk2_tab = ui._button(L.t("MK2_TAB"), UIController.GOLD)
	for b in [_base_tab, _mk2_tab]:
		b.custom_minimum_size = Vector2(150, 50)
		b.add_theme_font_size_override("font_size", 24)
		_mk2_row.add_child(b)
	ui.fit_button_font(_base_tab, 150.0, 24, 16)
	_base_tab.pressed.connect(func() -> void: set_view_mk2(false))
	_mk2_tab.pressed.connect(func() -> void: set_view_mk2(true))
	var srow := HBoxContainer.new()
	_srow = srow
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 8)
	col.add_child(srow)
	_skin_left = ui._button("◀", UIController.PAPER)
	_skin_left.custom_minimum_size = Vector2(64, 56)
	_skin_left.add_theme_font_size_override("font_size", 30)
	_skin_left.pressed.connect(func() -> void: step_skin(-1))
	srow.add_child(_skin_left)
	_skin_label = ui._label("", 28, UIController.CREAM, 8)
	_skin_label.custom_minimum_size = Vector2(230, 0)
	_skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	srow.add_child(_skin_label)
	_skin_right = ui._button("▶", UIController.PAPER)
	_skin_right.custom_minimum_size = Vector2(64, 56)
	_skin_right.add_theme_font_size_override("font_size", 30)
	_skin_right.pressed.connect(func() -> void: step_skin(1))
	srow.add_child(_skin_right)
	_skin_note = ui._label("", 20, UIController.GOLD, 6)
	_skin_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_skin_note)
	_mk2_note = ui._label("", 20, UIController.GOLD, 6)
	_mk2_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# CJK text has no spaces: wrap anywhere there, at word boundaries elsewhere (never widen the preview column)
	_mk2_note.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY if L.locale().split("_")[0] in ["zh", "ja", "ko"] else TextServer.AUTOWRAP_WORD_SMART
	_mk2_note.custom_minimum_size = Vector2(380, 0)
	col.add_child(_mk2_note)
	var panel := ui._paper_panel()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(panel)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	panel.add_child(info)
	# v34: a little tighter so 3-line translated descriptions keep the bottom buttons on screen
	_name = ui._gold_label("", 50)
	info.add_child(_name)
	_desc = ui._ink_label("", 22, UIController.GREY)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(440, 56)
	info.add_child(_desc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	info.add_child(grid)
	for s in STATS:
		var l := ui._ink_label(L.t(s[1]), 24)
		l.custom_minimum_size = Vector2(170, 0)
		grid.add_child(l)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(260, 26)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_meta("v", 0.0)
		bar.draw.connect(_draw_bar.bind(bar))
		grid.add_child(bar)
		_bars[s[0]] = bar
	_price = ui._ink_label("", 30)
	info.add_child(_price)
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 10)
	info.add_child(_dots)
	_right = ui._button("▶", UIController.PAPER)
	_right.custom_minimum_size = Vector2(110, 130)
	_right.add_theme_font_size_override("font_size", 60)
	_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_right.pressed.connect(func() -> void: step(1))
	mid.add_child(_right)
	# bottom: back | note | action
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 30)
	root.add_child(bottom)
	var back := ui._button(L.t("UI_BACK"), UIController.PAPER)
	back.custom_minimum_size = Vector2(240, 86)
	back.add_theme_font_size_override("font_size", 40)
	back.pressed.connect(func() -> void: back_requested.emit())
	bottom.add_child(back)
	_note = ui._label("", 30, Color(1.0, 0.55, 0.4), 8)
	_note.custom_minimum_size = Vector2(300, 0)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_note)
	_action = ui._button(L.t("UI_PLAY"), Color(1.0, 0.6, 0.2))
	_action.custom_minimum_size = Vector2(360, 92)
	_action.add_theme_font_size_override("font_size", 48)
	_action.pressed.connect(_on_action)
	bottom.add_child(_action)


func _place_preview() -> void:
	# preview origin = torso centre; the robot is ~300 px tall at scale 1 -> scale it to the box
	var s := _preview_box.size
	preview.position = Vector2(s.x * 0.5, s.y * 0.48)
	var k := clampf(s.y / 380.0, 0.6, 1.4)
	if preview.def:
		preview.scale = Vector2.ONE * k * preview.def.size
	else:
		preview.scale = Vector2.ONE * k
	if preview.art_torso:
		var bounds := preview.art_bounds()
		var area := Rect2(Vector2(12, 6), Vector2(maxf(s.x - 24, 1), maxf(s.y - 158, 1)))   # v35: tabs + skin row below
		var fit := minf(area.size.x / maxf(bounds.size.x, 1), area.size.y / maxf(bounds.size.y, 1))
		preview.scale = Vector2.ONE * minf(preview.scale.x, fit)
		preview.position = area.get_center() - bounds.get_center() * preview.scale
		# v34 presentation correction, anchored at the feet (the sole stays where the fitted robot stood)
		var p := RobotPreview.presentation_scale(preview.def.id if preview.def else "")
		if p != 1.0:
			var feet_y: float = preview.position.y + bounds.end.y * preview.scale.y
			preview.scale *= p
			preview.position = Vector2(area.get_center().x - bounds.get_center().x * preview.scale.x, feet_y - bounds.end.y * preview.scale.y)


func open(p_catalog: RobotCatalog, p_base_cfg: RobotConfig, selected_id: String, p_owned: Array[String], p_coins: int) -> void:
	catalog = p_catalog
	base_cfg = p_base_cfg
	owned = p_owned
	coins = p_coins
	index = maxi(catalog.index_of(selected_id), 0)
	_note.text = ""
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	_refresh(true)


func _process(dt: float) -> void:
	_buy_guard = maxf(_buy_guard - dt, 0.0)


func _mk2(d: RobotDefinition) -> Dictionary:
	if d == null or not d.has_mk2():
		return {}
	return mk2_state.call(d) if mk2_state.is_valid() else {"eligible": false, "owned": false, "active": false, "boss": ""}


## Switch the shown variant of the current archetype (preview, stats, price and action follow).
func set_view_mk2(on: bool) -> void:
	var d := current()
	if d == null or (on and not d.has_mk2()):
		return
	viewing_mk2 = on
	_note.text = ""
	_skin_idx = _equipped_index(d)    # v36: each version keeps its own colour scheme
	_show_preview(d)
	_refresh(false)


## Stats of the shown variant (MK2 = base stats + the MK2 module; never size / mass).
func shown_stats(d: RobotDefinition) -> Dictionary:
	return ModuleDefinition.apply_all(d.base_stats(), [d.mk2_module()]) if viewing_mk2 and d.has_mk2() else d.base_stats()


func refresh_profile(p_owned: Array[String], p_coins: int, note := "") -> void:
	owned = p_owned
	coins = p_coins
	_note.text = note
	_refresh(false)


func current() -> RobotDefinition:
	return catalog.robots[index] if catalog and not catalog.robots.is_empty() else null


func step(d: int) -> void:
	if catalog == null or catalog.robots.is_empty():
		return
	index = posmod(index + d, catalog.robots.size())
	_note.text = ""
	_refresh(true)
	var cur := current()
	if cur and owned.has(cur.id):
		robot_focused.emit(cur.id)
	# little slide-in of the new robot
	preview.modulate.a = 0.0
	var tw := preview.create_tween()
	tw.tween_property(preview, "modulate:a", 1.0, 0.15)


func _refresh(new_robot: bool) -> void:
	var d := current()
	if d == null:
		return
	var mk := _mk2(d)
	if new_robot:
		viewing_mk2 = bool(mk.get("active", false))
		_skin_idx = _equipped_index(d)
		_show_preview(d)
	_name.text = L.f("MK2_NAME", {"name": L.data(d.display_name)}) if viewing_mk2 else L.data(d.display_name)
	# long localized names (e.g. ja "カンガルーボット MK2") shrink instead of widening the info panel
	var nfs := 50
	while nfs > 30 and ui.font.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > 440.0:
		nfs -= 2
	_name.add_theme_font_size_override("font_size", nfs)
	_mk2_row.visible = d.has_mk2()
	_base_tab.modulate = Color.WHITE if not viewing_mk2 else Color(1, 1, 1, 0.6)
	_mk2_tab.modulate = Color.WHITE if viewing_mk2 else Color(1, 1, 1, 0.6)
	var st := shown_stats(d)
	_desc.text = L.data(d.description)
	_coins.text = L.pf("SEL_COINS", coins)
	var vals := {
		"max_health": float(st.max_health) / catalog.stat_max("max_health"),
		"mass_multiplier": float(st.mass_multiplier) / catalog.stat_max("mass_multiplier"),
		"springs": (float(st.spring_strength) * float(st.bounce)) / _max_over("springs"),
		"energy": (float(st.energy_boost_multiplier) * float(st.charge_rate)) / _max_over("energy"),
		"air_control": float(st.air_control) / catalog.stat_max("air_control"),
	}
	for k in _bars:
		_bars[k].set_meta("v", clampf(vals[k], 0.05, 1.0))
		_bars[k].set_meta("label", "%d" % int(st.max_health) if k == "max_health" else "")
		_bars[k].queue_redraw()
	var is_owned := owned.has(d.id)
	# v36: the colour-scheme row sits under BASE / MK2 for both versions; on a not-yet-owned MK2 the MK2 status
	# note takes the scheme note's place (the row still previews the schemes on that version)
	var mk2_have := bool(mk.get("owned", false))
	_srow.visible = true
	_skin_note.visible = not viewing_mk2 or mk2_have
	_mk2_note.visible = viewing_mk2 and not mk2_have
	if viewing_mk2:
		_mk2_note.text = mk2_status_text(d, mk)
		if bool(mk.get("owned", false)):
			_price.text = L.t("MK2_OWNED")
			_action.text = L.t("UI_PLAY")
			_action.modulate = Color.WHITE
		else:
			_price.text = L.pf("MK2_PRICE", d.mk2_price) if d.mk2_purchasable() else L.t("MK2_SOON")
			_action.text = L.t("MK2_BUY")
			var can := is_owned and bool(mk.get("eligible", false)) and d.mk2_purchasable() and coins >= d.mk2_price
			_action.modulate = Color.WHITE if can else Color(1, 1, 1, 0.55)
	elif is_owned:
		_price.text = L.t("SEL_OWNED") if d.price > 0 else L.t("SEL_FREE")
		_action.text = L.t("UI_PLAY")
		_action.modulate = Color.WHITE
	else:
		_price.text = L.pf("SEL_PRICE", d.price)
		_action.text = L.t("UI_BUY")
		_action.modulate = Color.WHITE if coins >= d.price else Color(1, 1, 1, 0.55)
	for ch in _dots.get_children():
		ch.queue_free()
	for i in catalog.robots.size():
		var dot := ui._label("●" if i == index else "○", 26, UIController.INK, 0)
		_dots.add_child(dot)


func _robot_skins(d: RobotDefinition) -> Array[SkinDefinition]:
	return skins.for_robot(d.id) if skins else ([] as Array[SkinDefinition])


func _equipped_index(d: RobotDefinition) -> int:
	var list := _robot_skins(d)
	var eq: String = equipped_of.call(d.id, viewing_mk2) if equipped_of.is_valid() else SkinDefinition.default_id(d.id)
	for i in list.size():
		if list[i].id == eq:
			return i
	return 0


func _show_preview(d: RobotDefinition) -> void:
	var list := _robot_skins(d)
	var skin: SkinDefinition = list[_skin_idx] if not list.is_empty() else null
	preview.show_robot(d, base_cfg, skin, viewing_mk2)
	_place_preview()
	_refresh_skin_row(d)


func _refresh_skin_row(d: RobotDefinition) -> void:
	var list := _robot_skins(d)
	var many := list.size() > 1
	_skin_left.visible = many
	_skin_right.visible = many
	if list.is_empty():
		_skin_label.text = ""
		_skin_note.text = ""
		return
	var s := list[_skin_idx]
	var have: bool = owns_skin.call(s.id) if owns_skin.is_valid() else true
	var eq: String = equipped_of.call(d.id, viewing_mk2) if equipped_of.is_valid() else ""
	_skin_label.text = L.data(s.display_name)
	if not have:
		_skin_label.text = L.f("SEL_SKIN_LOCKED", {"name": L.data(s.display_name)})
		_skin_note.text = skin_hint.call(s.id) if skin_hint.is_valid() else L.t("SEL_LOCKED")
		preview.modulate = Color(0.55, 0.55, 0.6, 0.8)
	else:
		_skin_note.text = L.f("SEL_SKIN_N_ON" if s.id == eq else "SEL_SKIN_N", {"i": _skin_idx + 1, "n": list.size()})
		preview.modulate = Color.WHITE


## Browse the shown archetype's skins; an owned skin is equipped right away (purely cosmetic).
func step_skin(dir: int) -> void:
	var d := current()
	var list := _robot_skins(d)
	if d == null or list.size() < 2:
		return
	_skin_idx = posmod(_skin_idx + dir, list.size())
	var s := list[_skin_idx]
	if owns_skin.is_valid() and owns_skin.call(s.id):
		skin_equip_requested.emit(d.id, s.id, viewing_mk2)
	_show_preview(d)


func _max_over(key: String) -> float:
	var m := 0.0001
	for d in catalog.robots:
		var v := (d.spring_strength * d.bounce) if key == "springs" else (d.energy_boost_multiplier * d.charge_rate)
		m = maxf(m, v)
	return m


func _draw_bar(bar: Control) -> void:
	var v: float = bar.get_meta("v", 0.0)
	var r := Rect2(Vector2.ZERO, bar.size)
	bar.draw_style_box(ui._hp_box(UIController.INK, 10), r)
	var inner := r.grow(-4)
	bar.draw_style_box(ui._hp_box(Color(0.3, 0.22, 0.18), 7), inner)
	bar.draw_style_box(ui._hp_box(UIController.GOLD, 7), Rect2(inner.position, Vector2(maxf(inner.size.x * v, 10.0), inner.size.y)))
	var txt: String = bar.get_meta("label", "")
	if txt != "":
		var fs := 20
		var tw := ui.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := Vector2(inner.end.x - tw - 6, inner.position.y + inner.size.y * 0.5 + fs * 0.36)
		bar.draw_string_outline(ui.font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, UIController.INK)
		bar.draw_string(ui.font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIController.CREAM)


## Player-facing state of the shown MK2: locked (why) / buy / owned / chosen.
func mk2_status_text(d: RobotDefinition, mk: Dictionary) -> String:
	if bool(mk.get("owned", false)):
		return L.t("MK2_PLAYING") if bool(mk.get("active", false)) else L.t("MK2_OWNED")
	if not owned.has(d.id):
		return L.t("MK2_NEED_BASE")
	if not bool(mk.get("eligible", false)):
		return L.t("MK2_LOCKED_BOSS") % String(mk.get("boss", ""))
	if not d.mk2_purchasable():
		return L.t("MK2_SOON")
	return L.t("MK2_UNLOCKED")


func _on_action() -> void:
	var d := current()
	if d == null:
		return
	if viewing_mk2 and d.has_mk2():
		var mk := _mk2(d)
		if bool(mk.get("owned", false)):
			mk2_variant_requested.emit(d.id, true)
			play_requested.emit(d.id)
			return
		var reason := ""
		if not owned.has(d.id):
			reason = L.t("MK2_NEED_BASE")
		elif not bool(mk.get("eligible", false)):
			reason = L.t("MK2_LOCKED_BOSS") % String(mk.get("boss", ""))
		elif not d.mk2_purchasable():
			reason = L.t("MK2_SOON")
		elif coins < d.mk2_price:
			reason = L.pf("SEL_NEED", d.mk2_price - coins)
		if reason != "":
			_note.text = reason
			var tw0 := _note.create_tween()
			_note.pivot_offset = _note.size * 0.5
			tw0.tween_property(_note, "scale", Vector2(1.15, 1.15), 0.06)
			tw0.tween_property(_note, "scale", Vector2.ONE, 0.2)
			return
		if _buy_guard > 0.0:
			return             # rapid / double tap: one purchase request only
		_buy_guard = MK2_BUY_GUARD_S
		mk2_buy_requested.emit(d.id)
		return
	if owned.has(d.id):
		if d.has_mk2():
			mk2_variant_requested.emit(d.id, false)
		play_requested.emit(d.id)
	elif coins < d.price:
		_note.text = L.pf("SEL_NEED", d.price - coins)
		var tw := _note.create_tween()
		_note.pivot_offset = _note.size * 0.5
		tw.tween_property(_note, "scale", Vector2(1.15, 1.15), 0.06)
		tw.tween_property(_note, "scale", Vector2.ONE, 0.2)
	else:
		buy_requested.emit(d.id)
