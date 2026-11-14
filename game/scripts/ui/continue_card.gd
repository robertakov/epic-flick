class_name ContinueCard
extends Control
## Paid continue offer (v32), shown with the game paused the first time an attempt ends - only when affordable.
## v34 two-stage spending, safe against accidental / double / multi taps:
##   1. offer:   reason, "Цена / У тебя", buttons [ЗАВЕРШИТЬ] [ПРОДОЛЖИТЬ — 600 МОНЕТ] (armed after ARM_S)
##   2. confirm: "ПОТРАТИТЬ 600 МОНЕТ И ПРОДОЛЖИТЬ?" [ПОДТВЕРДИТЬ] [ОТМЕНА] (armed after CONFIRM_ARM_S; ПОДТВЕРДИТЬ is
##      where ЗАВЕРШИТЬ was and ОТМЕНА where ПРОДОЛЖИТЬ was, so a double tap on ПРОДОЛЖИТЬ lands on ОТМЕНА)
## `accepted` is emitted ONLY by ПОДТВЕРДИТЬ, at most once per offer (latched); ОТМЕНА goes back to the offer and
## spends / consumes nothing. GameManager.accept_continue() additionally refuses a second purchase.

signal accepted
signal declined

const ARM_S := 0.6
const CONFIRM_ARM_S := 0.5
var ui: UIController
var center: CenterContainer
var offer_panel: PanelContainer
var confirm_panel: PanelContainer
var title: Label
var price_label: Label
var info: Label
var yes: Button              # offer: ПРОДОЛЖИТЬ — N МОНЕТ (opens the confirmation)
var no: Button               # offer: ЗАВЕРШИТЬ
var confirm_title: Label
var confirm_yes: Button      # ПОДТВЕРДИТЬ (the only spend)
var confirm_no: Button       # ОТМЕНА
var stage := "offer"         # "offer" | "confirm" | "done"
var _armed_t := 0.0
var _price := 0


func build(p_ui: UIController) -> void:
	ui = p_ui
	name = "ContinueCard"
	process_mode = Node.PROCESS_MODE_ALWAYS   # works while the game is paused
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	ui._shade(self, 0.6)
	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	offer_panel = ui._paper_panel()
	center.add_child(offer_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	offer_panel.add_child(v)
	title = ui._gold_label(L.t("CONT_TITLE"), 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	info = ui._ink_label("", 24)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	price_label = ui._ink_label("", 32)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(price_label)
	var note := ui._ink_label(L.t("CONT_SUB"), 22)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 22)
	v.add_child(h)
	no = _btn(h, L.t("CONT_END"), UIController.PAPER, 260)
	no.pressed.connect(func() -> void:
		if visible and stage == "offer" and _armed_t <= 0.0:
			stage = "done"
			declined.emit())
	yes = _btn(h, "", UIController.GOLD, 380)
	yes.icon = ui.coin_icon(44)
	yes.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	yes.add_theme_constant_override("h_separation", 10)
	yes.pressed.connect(func() -> void:
		if visible and stage == "offer" and _armed_t <= 0.0:
			_open_confirm())
	# confirmation panel (same place, replaces the offer)
	confirm_panel = ui._paper_panel()
	center.add_child(confirm_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 16)
	confirm_panel.add_child(cv)
	confirm_title = ui._gold_label("", 40)
	confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_title.custom_minimum_size.x = 640
	cv.add_child(confirm_title)
	var ch := HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_theme_constant_override("separation", 22)
	cv.add_child(ch)
	confirm_yes = _btn(ch, L.t("UI_CONFIRM"), UIController.GOLD, 300)
	confirm_yes.pressed.connect(func() -> void:
		if visible and stage == "confirm" and _armed_t <= 0.0:
			stage = "done"            # latch: every further tap is ignored
			confirm_yes.disabled = true
			confirm_no.disabled = true
			accepted.emit())
	confirm_no = _btn(ch, L.t("UI_CANCEL"), UIController.PAPER, 300)
	confirm_no.pressed.connect(func() -> void:
		if visible and stage == "confirm" and _armed_t <= 0.0:
			_back_to_offer())
	visible = false


func _btn(parent: Control, text: String, col: Color, w: float) -> Button:
	var b := ui._button(text, col)
	b.custom_minimum_size = Vector2(w, 80)
	b.add_theme_font_size_override("font_size", 30)
	parent.add_child(b)
	return b


## Navigation invalidates the interaction, not just its pixels. Hidden buttons cannot retain an armed purchase.
func cancel() -> void:
	visible = false
	stage = "done"
	_armed_t = 0.0
	_price = 0
	for b in [yes, no, confirm_yes, confirm_no]:
		b.disabled = true
		b.set_pressed_no_signal(false)


func show_offer(price: int, coins: int, reason: String) -> void:
	cancel()
	_price = price
	info.text = L.data(reason)
	price_label.text = L.pf("CONT_PRICE", price, {"have": coins})
	yes.text = L.f("CONT_BUY", {"n": price})   # + the coin icon (no word needed, reads in every language)
	confirm_title.text = L.pf("CONT_CONFIRM_Q", price)
	_back_to_offer()
	_armed_t = ARM_S
	visible = true


func _open_confirm() -> void:
	stage = "confirm"
	offer_panel.visible = false
	confirm_panel.visible = true
	confirm_yes.disabled = true
	confirm_no.disabled = true
	_armed_t = CONFIRM_ARM_S


func _back_to_offer() -> void:
	stage = "offer"
	offer_panel.visible = true
	confirm_panel.visible = false
	_armed_t = maxf(_armed_t, 0.25)


func armed() -> bool:
	return visible and _armed_t <= 0.0


func _process(dt: float) -> void:
	if not visible:
		return
	_armed_t = maxf(_armed_t - dt, 0.0)
	var locked := _armed_t > 0.0
	yes.disabled = locked or stage != "offer"
	no.disabled = locked or stage != "offer"
	if stage == "confirm":
		confirm_yes.disabled = locked
		confirm_no.disabled = locked
	var m := ui.safe_margins
	center.offset_left = m.x + 16
	center.offset_right = -m.z - 16
	center.offset_top = m.y + 8
	center.offset_bottom = -m.w - 8
