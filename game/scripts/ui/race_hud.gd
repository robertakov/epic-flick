class_name RaceHud
extends Control
## Campaign race HUD (top centre): you vs. opponents with live distances, and the "waiting for the opponent"
## banner once the player's own attempt is over.

signal speed_up_requested

var ui: UIController
var _rows: VBoxContainer
var _labels: Array[Label] = []
var _banner: PanelContainer
var _banner_label: Label
var speed_button: Button


func build(p_ui: UIController) -> void:
	ui = p_ui
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.position = Vector2(-150, 10)
	_rows.custom_minimum_size = Vector2(300, 0)
	_rows.add_theme_constant_override("separation", 0)
	add_child(_rows)
	_banner = ui._paper_panel()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.position = Vector2(-300, 230)
	_banner.custom_minimum_size = Vector2(600, 0)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_child(bv)
	_banner_label = ui._ink_label("", 32)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_banner_label)
	speed_button = ui._button(L.t("RACE_SPEEDUP"), UIController.GOLD)
	speed_button.custom_minimum_size = Vector2(300, 76)
	speed_button.add_theme_font_size_override("font_size", 34)
	speed_button.pressed.connect(func() -> void: speed_up_requested.emit())
	var cc := CenterContainer.new()
	cc.add_child(speed_button)
	bv.add_child(cc)
	add_child(_banner)
	_banner.visible = false


## names / colors of the opponents (row 0 = the player).
func setup(names: Array, colors: Array) -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	var all := [L.t("RES_YOU")] + names
	for i in all.size():
		var l := ui._label("", 26, UIController.CREAM if i == 0 else colors[i - 1], 7)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(300, 0)
		_rows.add_child(l)
		_labels.append(l)
	_labels[0].set_meta("name", L.t("RES_YOU"))
	for i in names.size():
		_labels[i + 1].set_meta("name", L.data(String(names[i])))
	show_waiting(false)


## dists[0] = player; finished[i] marks finished competitors.
func update_distances(dists: Array, finished: Array) -> void:
	for i in mini(dists.size(), _labels.size()):
		var mark := "  ✓" if finished[i] else ""
		_labels[i].text = L.f("RACE_ROW", {"name": _labels[i].get_meta("name", ""), "m": int(dists[i]), "tag": mark})


func show_waiting(on: bool, text := "") -> void:
	_banner.visible = on
	_banner_label.text = text
	speed_button.visible = on
