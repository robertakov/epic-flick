class_name CampaignResultView
extends Control
## Result of a campaign attempt: win / loss, your distance vs. every opponent, rewards (coins, first-clear,
## boss skin), and ЕЩЁ РАЗ / КАРТА / ДАЛЕЕ.

signal retry_requested
signal map_requested
signal next_requested

var center: CenterContainer
var ui: UIController
var _panel: PanelContainer
var _title: Label
var _round: Label
var _rows: VBoxContainer
var _reward: Label
var _skin: Label
var _stars: Label
var ceremony: StarCeremony
var next_button: Button


func build(p_ui: UIController) -> void:
	ui = p_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	ui._shade(self, 0.55)
	center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = ui._paper_panel()
	center.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_title = ui._gold_label("", 60)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_round = ui._ink_label("", 25, UIController.GREY)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_round)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	v.add_child(_rows)
	_reward = ui._label("", 28, Color(0.8, 0.5, 0.0), 0)
	_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_reward)
	_skin = ui._label("", 32, Color(0.6, 0.2, 0.8), 0)
	_skin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_skin)
	_stars = ui._ink_label("", 23)
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_stars)
	_stars.visible=false
	ceremony=StarCeremony.new()
	v.add_child(ceremony)
	ceremony.build(ui)
	visibility_changed.connect(func() -> void: if not visible: ceremony.cancel())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	var retry := ui._button(L.t("TUT_AGAIN"), UIController.GOLD)
	retry.custom_minimum_size = Vector2(280, 86)
	retry.pressed.connect(func() -> void: retry_requested.emit())
	row.add_child(retry)
	var map := ui._button(L.t("RES_MAP"), UIController.PAPER)
	map.custom_minimum_size = Vector2(220, 86)
	map.pressed.connect(func() -> void: map_requested.emit())
	row.add_child(map)
	next_button = ui._button(L.t("RES_NEXT"), Color(1.0, 0.6, 0.2))
	next_button.custom_minimum_size = Vector2(260, 86)
	next_button.pressed.connect(func() -> void: next_requested.emit())
	row.add_child(next_button)


## r: won, title, player_m, enemies [{name, m, color}], coins, coins_kind ("first" | "replay" | ""), skin_name,
##    has_next
func show_result(r: Dictionary) -> void:
	visible = true
	var won: bool = r.won
	_title.text = L.t("RES_WIN") if won else L.t("RES_LOSS")
	_title.add_theme_color_override("font_color", UIController.GOLD if won else Color(0.95, 0.35, 0.25))
	_round.text = L.data(String(r.get("title", "")))
	for ch in _rows.get_children():
		ch.queue_free()
	var lines := [[L.t("RES_YOU"), float(r.player_m), UIController.INK]]
	for e in r.enemies:
		lines.append([L.data(String(e.name)), float(e.m), (e.color as Color).darkened(0.35)])
	var best := 0.0
	for l in lines:
		best = maxf(best, l[1])
	for l in lines:
		var h := HBoxContainer.new()
		var name_l := ui._ink_label(String(l[0]), 32, l[2])
		name_l.custom_minimum_size = Vector2(340, 0)
		h.add_child(name_l)
		var d := ui._ink_label(L.f("RES_ROW", {"m": int(l[1]), "mark": "  ★" if is_equal_approx(l[1], best) else ""}), 36, l[2])
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		d.custom_minimum_size = Vector2(220, 0)
		h.add_child(d)
		_rows.add_child(h)
	var coins := int(r.get("coins", 0))
	match String(r.get("coins_kind", "")):
		"first":
			_reward.text = L.pf("RES_FIRST_WIN", coins)
		"replay":
			_reward.text = L.pf("RES_REPLAY", coins) if coins > 0 else L.t("RES_ROUND_CLEARED")
		_:
			_reward.text = "" if won else L.t("RES_TRY_AGAIN")
	var skin := String(r.get("skin_name", ""))
	_skin.text = (L.t("RES_NEW_SKIN") % L.data(skin)) if skin != "" else ""
	_skin.visible = skin != ""
	var marks := []
	var before: Array = r.get("stars_before", [false, false, false])
	var fresh: Array = r.get("stars_new", [])
	for i in 3:
		marks.append(L.t("RES_STAR_NEW") if fresh.has(i) else (L.t("RES_STAR_HAD") if i < before.size() and before[i] else "☆"))
	_stars.text = L.f("RES_STARS_LINE", {"marks": "   ".join(marks), "coins": L.pf("RES_STAR_COINS", int(r.get("star_coins", 0))), "total": int(r.get("stars_total", 0))})
	ceremony.present(before,fresh,int(r.get("stars_total",0)),int(r.get("stars_available",0)))
	next_button.visible = won and bool(r.get("has_next", false))
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.7, 0.7)
	_panel.create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(_dt: float) -> void:
	if not visible: return
	var m := ui.safe_margins
	center.offset_left=m.x+16; center.offset_right=-m.z-16
	center.offset_top=m.y+12; center.offset_bottom=-m.w-12
