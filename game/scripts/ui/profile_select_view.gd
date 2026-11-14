class_name ProfileSelectView
extends Control
## v31 profile screen: three identical PLAYER cards. Occupied card -> short summary + ИГРАТЬ + УДАЛИТЬ;
## empty card -> НОВАЯ ИГРА. Deleting always goes through a confirmation dialog (УДАЛИТЬ PLAYER N?).
## Pure view: GameManager does the loading / saving / deleting (signals below).

signal slot_chosen(slot: int)
signal delete_confirmed(slot: int)
signal back_requested

var ui: UIController
var center: CenterContainer
var panel: PanelContainer
var title: Label
var back_button: Button
var cards: Array[PanelContainer] = []
var names: Array[Label] = []
var lines: Array[Label] = []
var play_buttons: Array[Button] = []
var delete_buttons: Array[Button] = []
var active_badges: Array[Label] = []
var confirm: Control
var confirm_title: Label
var confirm_yes: Button
var confirm_no: Button
var pending_delete := 0
var _summaries: Array = []


func build(p_ui: UIController) -> void:
	ui = p_ui
	name = "ProfileSelect"
	z_index = 50   # above the menu robot preview (z_index 4), which would otherwise draw over the cards
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	ui._shade(self, 0.82)
	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = ui._paper_panel()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	title = ui._gold_label(L.t("PROF_TITLE"), 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	for i in ProfileManager.SLOTS:
		var slot := i + 1
		var card := ui._panel(UIController.CREAM)
		var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 14
		sb.content_margin_bottom = 16
		card.name = "Slot%d" % slot
		row.add_child(card)
		cards.append(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var nm := ui._gold_label(ProfileManager.slot_name(slot), 40)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)
		names.append(nm)
		var badge := ui._ink_label(L.t("PROF_CURRENT"), 20, Color(0.15, 0.5, 0.15))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(badge)
		active_badges.append(badge)
		var info := ui._ink_label("", 26)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.custom_minimum_size.y = 120
		info.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(info)
		lines.append(info)
		var play := ui._button(L.t("UI_PLAY"), UIController.GOLD)
		play.name = "Play%d" % slot
		play.custom_minimum_size = Vector2(250, 76)
		play.add_theme_font_size_override("font_size", 30)
		play.pressed.connect(func() -> void: if pending_delete == 0: slot_chosen.emit(slot))
		v.add_child(play)
		play_buttons.append(play)
		var del := ui._button(L.t("UI_DELETE"), Color(0.93, 0.55, 0.45))
		del.name = "Delete%d" % slot
		del.custom_minimum_size = Vector2(250, 52)
		del.add_theme_font_size_override("font_size", 22)
		del.pressed.connect(func() -> void: ask_delete(slot))
		v.add_child(del)
		delete_buttons.append(del)
	back_button = ui._button(L.t("UI_BACK"), UIController.PAPER)
	back_button.custom_minimum_size = Vector2(240, 64)
	back_button.add_theme_font_size_override("font_size", 28)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func() -> void: if pending_delete == 0: back_requested.emit())
	box.add_child(back_button)
	_build_confirm()
	visible = false


func _build_confirm() -> void:
	confirm = Control.new()
	confirm.name = "DeleteConfirm"
	confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(confirm)
	ui._shade(confirm, 0.6)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm.add_child(c)
	var p := ui._paper_panel()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	confirm_title = ui._gold_label("", 46)
	confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(confirm_title)
	var txt := ui._ink_label(L.t("PROF_DELETE_WARN"), 28)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(txt)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	confirm_no = ui._button(L.t("UI_CANCEL"), UIController.PAPER)
	confirm_no.custom_minimum_size = Vector2(250, 76)
	confirm_no.add_theme_font_size_override("font_size", 30)
	confirm_no.pressed.connect(cancel_delete)
	h.add_child(confirm_no)
	confirm_yes = ui._button(L.t("UI_DELETE"), Color(0.9, 0.35, 0.28))
	confirm_yes.custom_minimum_size = Vector2(250, 76)
	confirm_yes.add_theme_font_size_override("font_size", 30)
	confirm_yes.pressed.connect(func() -> void:
		var slot := pending_delete
		pending_delete = 0
		confirm.visible = false
		if slot > 0:
			delete_confirmed.emit(slot))
	h.add_child(confirm_yes)
	confirm.visible = false


## summaries: ProfileManager.summary() per slot. active: current slot (0 = none). can_back: a player is active.
func open(summaries: Array, active: int, can_back: bool) -> void:
	_summaries = summaries
	pending_delete = 0
	confirm.visible = false
	for i in cards.size():
		var s: Dictionary = summaries[i] if i < summaries.size() else {"exists": false}
		var used := bool(s.get("exists", false))
		active_badges[i].modulate.a = 1.0 if (used and active == i + 1) else 0.0
		if used:
			lines[i].text = L.f("PROF_SUMMARY", {"round": int(s.round), "stars": int(s.stars), "coins": int(s.coins)})
			play_buttons[i].text = L.t("UI_PLAY")
		else:
			lines[i].text = L.t("PROF_NEW")
			play_buttons[i].text = L.t("UI_BEGIN")
		lines[i].add_theme_font_size_override("font_size", 26 if used else 36)
		delete_buttons[i].visible = used
		# keeps the three cards the same height whether or not the delete button is shown
		delete_buttons[i].modulate.a = 1.0
		var sb: StyleBoxFlat = cards[i].get_theme_stylebox("panel")
		sb.bg_color = UIController.CREAM if used else UIController.PAPER
		sb.border_color = UIController.GOLD.darkened(0.25) if active == i + 1 else UIController.INK
	back_button.visible = can_back
	visible = true
	layout()


func ask_delete(slot: int) -> void:
	pending_delete = slot
	confirm_title.text = L.t("PROF_DELETE_Q") % ProfileManager.slot_name(slot)
	confirm.visible = true


func cancel_delete() -> void:
	pending_delete = 0
	confirm.visible = false


func confirm_open() -> bool:
	return confirm.visible


func layout() -> void:
	var m := ui.safe_margins
	center.offset_left = m.x + 16
	center.offset_right = -m.z - 16
	center.offset_top = m.y + 8
	center.offset_bottom = -m.w - 8
	var vp := get_viewport_rect().size
	var avail := vp.x - m.x - m.z - 32.0 - 80.0 - 36.0
	var w := clampf(avail / 3.0, 200.0, 330.0)
	var k := w / 330.0
	for i in cards.size():
		cards[i].custom_minimum_size.x = w
		names[i].add_theme_font_size_override("font_size", int(40 * k))
		play_buttons[i].custom_minimum_size = Vector2(w - 36.0, 76.0 * maxf(k, 0.8))
		delete_buttons[i].custom_minimum_size = Vector2(w - 36.0, 52.0 * maxf(k, 0.8))
		# an empty slot still reserves the delete row so all three cards stay identical in size
		if not delete_buttons[i].visible:
			play_buttons[i].custom_minimum_size.y += 52.0 * maxf(k, 0.8) + 6.0
	title.add_theme_font_size_override("font_size", int(54 * clampf(k, 0.75, 1.0)))


func _process(_dt: float) -> void:
	if visible:
		layout()
