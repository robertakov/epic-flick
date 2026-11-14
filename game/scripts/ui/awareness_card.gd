class_name AwarenessCard
extends Control
signal confirmed(kind: String)
signal skipped(kind: String)
var kind := ""
var ui: UIController
var center: CenterContainer
var panel: PanelContainer
var title: Label
var subtitle: Label
var confirm: Button
var skip: Button
var rows: Array[HBoxContainer]=[]
var icons: Array[StarBadge]=[]
var descriptions: Array[Label]=[]
func build(p_ui: UIController) -> void:
	ui=p_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	ui._shade(self,0.78)
	center=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel=ui._paper_panel()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	panel.add_child(box)
	title=ui._gold_label("",60)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	subtitle=ui._ink_label("",26)
	subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(subtitle)
	for i in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",16)
		box.add_child(row); rows.append(row)
		var badge := StarBadge.new()
		badge.custom_minimum_size=Vector2(82,82)
		row.add_child(badge); icons.append(badge)
		var text := ui._ink_label("",27)
		text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		text.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		row.add_child(text); descriptions.append(text)
	var buttons := HBoxContainer.new()
	buttons.alignment=BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation",20)
	box.add_child(buttons)
	confirm=ui._button(L.t("UI_BEGIN"),UIController.GOLD)
	confirm.custom_minimum_size=Vector2(310,86)
	confirm.add_theme_font_size_override("font_size",36)
	confirm.pressed.connect(func() -> void: var value:=kind; visible=false; confirmed.emit(value))
	buttons.add_child(confirm)
	skip=ui._button("",UIController.PAPER)
	skip.custom_minimum_size=Vector2(310,86)
	skip.add_theme_font_size_override("font_size",32)
	skip.pressed.connect(func() -> void: var value:=kind; visible=false; skipped.emit(value))
	buttons.add_child(skip)
	visible=false
func show_campaign(round_number: int, challenges: Array, owned: Array) -> void:
	kind="campaign"
	title.text=L.t("CARD_CHALLENGES_ROUND") % round_number
	subtitle.text=L.t("CARD_CHALLENGES_SUB")
	skip.text=L.t("CARD_TO_MAP")
	for i in 3:
		rows[i].visible=true
		icons[i].gold=bool(owned[i])
		descriptions[i].text=StarChallenges.describe(challenges[i])
	visible=true; layout()
func show_tutorial() -> void:
	kind="tutorial"
	title.text=L.t("TUT_TITLE")
	subtitle.text=L.t("TUT_CARD_SUB")
	skip.text=L.t("UI_SKIP")
	for row in rows: row.visible=false
	visible=true; layout()
func layout() -> void:
	var m := ui.safe_margins
	center.offset_left=m.x+20; center.offset_right=-m.z-20
	center.offset_top=m.y+12; center.offset_bottom=-m.w-12
	var width := minf(1000,get_viewport_rect().size.x-m.x-m.z-40)
	panel.custom_minimum_size.x=width
	panel.size.x=width
	for text in descriptions: text.custom_minimum_size.x=maxf(200,width-180)
	title.add_theme_font_size_override("font_size",48 if width<1000 else 60)
func _process(_dt: float) -> void:
	if visible: layout()
