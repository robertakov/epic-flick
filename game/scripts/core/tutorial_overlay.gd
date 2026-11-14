class_name TutorialOverlay
extends Control
## v33 tutorial visuals: ONE short prompt at a time + indicators drawn on the real things (flick bar, robot, feet,
## ground, charge bar, HP bar, part icons). No dimming mask, no text panels during play. Never intercepts gameplay
## input (mouse_filter IGNORE); only the deliberate skip (with confirmation) and the final ИГРАТЬ are buttons.

## Exact prompts per TutorialDirector.Step while the robot moves (after the gate opened).
const PROMPTS := {
	0: "TUT_P0",
	1: "TUT_P1",
	2: "TUT_P2",
	3: "TUT_P3",
	4: "TUT_P4",
	5: "TUT_P5",
}
## v34 gate prompts: the robot is frozen, nothing happens until the player does this (no time limit).
const GATE_PROMPTS := {
	1: "TUT_G1",
	2: "TUT_G2",
	4: "TUT_G4",
	5: "TUT_G5",
}
var gated := false
const GOLD := Color(1.0, 0.86, 0.2)
const GREEN := Color(0.45, 1.0, 0.45)
const RED := Color(1.0, 0.38, 0.25)
const INK := Color(0.1, 0.06, 0.04)

var gm: GameManager
var step := 0
var prompt: Label
var popup: Label
var skip: Button
var confirm: Control
var confirm_yes: Button
var confirm_no: Button
var done_card: Control
var play: Button
var t := 0.0
var _pop_t := 0.0
var _call_t := 0.0
var _call_target := &""
var _call_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = UIController.Z_MODAL
	visible = false
	prompt = gm.ui._label("", 46, GOLD, 12)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)
	popup = gm.ui._label("", 64, GREEN, 14)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.visible = false
	add_child(popup)
	_call_label = gm.ui._label("", 30, Color.WHITE, 9)
	_call_label.visible = false
	add_child(_call_label)
	skip = gm.ui._button(L.t("UI_SKIP"), Color(1, 0.95, 0.82))
	skip.add_theme_font_size_override("font_size", 22)
	skip.pressed.connect(func() -> void:
		move_child(confirm, get_child_count() - 1)
		confirm.visible = true)
	add_child(skip)
	confirm = _card(L.t("TUT_SKIP_Q"), [])
	confirm_no = _card_button(confirm, L.t("UI_NO"), Color(1, 0.95, 0.82))
	confirm_no.pressed.connect(func() -> void: confirm.visible = false)
	confirm_yes = _card_button(confirm, L.t("UI_YES"), Color(0.95, 0.6, 0.5))
	confirm_yes.pressed.connect(func() -> void:
		confirm.visible = false
		gm.finish_tutorial(false, true))
	done_card = _card(L.t("TUT_DONE"), [L.t("TUT_SUM_FEET"), L.t("TUT_SUM_BODY"), L.t("TUT_SUM_PARTS")])
	play = _card_button(done_card, L.t("UI_PLAY_EXCL"), GOLD)
	play.pressed.connect(func() -> void: gm.finish_tutorial(true, true))


## A centred paper card (stops input to the game while shown).
func _card(title: String, rows: Array) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	gm.ui._shade(root, 0.55)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var p := gm.ui._paper_panel()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.name = "Rows"
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var tl := gm.ui._gold_label(title, 54)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	for r in rows:
		var l := gm.ui._ink_label(String(r), 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var h := HBoxContainer.new()
	h.name = "Buttons"
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 22)
	v.add_child(h)
	return root


func _card_button(card: Control, text: String, col: Color) -> Button:
	var b := gm.ui._button(text, col)
	b.custom_minimum_size = Vector2(240, 80)
	b.add_theme_font_size_override("font_size", 34)
	card.find_child("Buttons", true, false).add_child(b)
	return b


func show_step(s: int, p_gated := false) -> void:
	step = s
	gated = p_gated
	var pkey: String = GATE_PROMPTS.get(s, PROMPTS.get(s, "")) if gated else PROMPTS.get(s, "")
	prompt.text = L.t(pkey) if pkey != "" else ""
	visible = true
	done_card.visible = false
	skip.visible = true
	layout()


func show_done() -> void:
	prompt.text = ""
	skip.visible = false
	confirm.visible = false
	done_card.visible = true


## Short reactive word near the robot (green = learned, red = try again).
func pop(text: String, good: bool) -> void:
	popup.text = text
	popup.add_theme_color_override("font_color", GREEN if good else RED)
	popup.visible = true
	_pop_t = 1.1


## Contextual one-off pointer at a HUD element: &"health" or &"modules".
func callout(target: StringName, text: String) -> void:
	_call_target = target
	_call_label.text = text
	_call_label.visible = true
	_call_t = 2.2


func layout() -> void:
	var m := gm.ui.safe_margins
	var vp := get_viewport_rect().size
	# v34: own band between the HP / charge bars (left) and the МЕНЮ button (right), under the part icons.
	# Long / translated prompts first wrap to two lines, then shrink (never below 28 px); never under МЕНЮ.
	var left := m.x + 345.0
	var right := vp.x - m.z - 20.0
	var menu_b: Button = gm.ui.abandon_button
	if menu_b and menu_b.is_visible_in_tree():
		right = minf(right, menu_b.get_global_rect().position.x - 14.0)
	var avail := maxf(right - left, 300.0)
	var fs := 44
	while fs > 28 and gm.ui.font.get_multiline_string_size(prompt.text, HORIZONTAL_ALIGNMENT_CENTER, avail, fs).y > fs * 2.6:
		fs -= 2
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", fs)
	prompt.add_theme_constant_override("outline_size", int(fs * 0.26))
	prompt.size = Vector2(avail, 0)
	prompt.position = Vector2(left, m.y + 104.0)
	skip.custom_minimum_size = Vector2(190, 52)
	skip.size = skip.custom_minimum_size
	skip.position = Vector2(vp.x - m.z - 206, vp.y - m.w - 70)


func _process(dt: float) -> void:
	if not visible:
		return
	t += dt / maxf(Engine.time_scale, 0.01)   # UI pulses at real speed even in slow motion
	_pop_t = maxf(_pop_t - dt / maxf(Engine.time_scale, 0.01), 0.0)
	_call_t = maxf(_call_t - dt / maxf(Engine.time_scale, 0.01), 0.0)
	popup.visible = _pop_t > 0.0
	_call_label.visible = _call_t > 0.0
	layout()
	if popup.visible and is_instance_valid(gm.robot):
		var p := get_viewport().get_canvas_transform() * gm.robot.global_position
		popup.size = Vector2(700, 80)
		popup.position = p + Vector2(-350, -230 - 30.0 * (1.1 - _pop_t))
		popup.position.y = clampf(popup.position.y, prompt.position.y + prompt.size.y + 10.0, get_viewport_rect().size.y - 260.0)
		popup.position.x = clampf(popup.position.x, 0.0, get_viewport_rect().size.x - 700.0)
	if _call_label.visible:
		var r := _target_rect()
		_call_label.size = _call_label.get_minimum_size()
		var right_half := r.get_center().x > get_viewport_rect().size.x * 0.5
		# below the prompt band, on the side of its target (never over the step prompt)
		var y := prompt.position.y + prompt.size.y + 8.0
		_call_label.position = Vector2(r.end.x - _call_label.size.x, y) if right_half else Vector2(r.position.x, y)
	queue_redraw()


func _target_rect() -> Rect2:
	if _call_target == &"health":
		return gm.ui.health_bar.get_global_rect()
	var out := Rect2()
	for k in gm.ui.module_icons:
		var c: Control = gm.ui.module_icons[k]
		out = c.get_global_rect() if out.size == Vector2.ZERO else out.merge(c.get_global_rect())
	return out


# ---------------- indicators ----------------

func _draw() -> void:
	if not visible or done_card.visible or gm.tutorial == null or not is_instance_valid(gm.robot):
		return
	var r := gm.robot
	var canvas := get_viewport().get_canvas_transform()
	var c := canvas * r.global_position
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	_progress()
	match step:
		0:
			# the finger taps the real flick bar
			var bar := gm.ui.flick_bar.get_global_rect() if gm.ui.flick_bar.visible else Rect2(c + Vector2(-60, 60), Vector2(120, 40))
			var tip := bar.get_center() + Vector2(0, bar.size.y * 0.35)
			_finger(tip + Vector2(0, 26.0 * pulse), pulse > 0.8)
		1:
			# counter-clockwise arrow around the robot + a holding finger in the free lower-left area
			_turn_arrow(c, 120.0, false, GREEN)
			var vp := get_viewport_rect().size
			_finger(Vector2(vp.x * 0.3, vp.y * 0.68), true)
		2, 5:
			# feet circles (bright when they point to the ground) + an arrow into the ground
			var aligned := (-r.global_transform.y.normalized()).dot(gm.terrain.normal_at(r.global_position.x)) >= cos(0.5)
			var col := GOLD if step == 5 else (GREEN if aligned else Color(1, 1, 1, 0.85))
			for leg in r.contacts.legs:
				if leg.attached:
					var foot := canvas * (r.global_transform * (leg.hip + Vector2(0, leg.reach(r.contact_config))))
					draw_arc(foot, 26.0 + 4.0 * pulse, 0, TAU, 24, INK, 9.0, true)
					draw_arc(foot, 26.0 + 4.0 * pulse, 0, TAU, 24, col, 5.0, true)
			var ground := canvas * Vector2(r.global_position.x, gm.terrain.height_at(r.global_position.x))
			_arrow(ground - Vector2(0, 110), ground - Vector2(0, 14), col)
			if step == 5:
				_outline(gm.ui.charge_bar.get_global_rect().grow(10), GOLD)
		3:
			_arrow(c + Vector2(0, 60), c + Vector2(0, -150 - 30.0 * pulse), GREEN)
		4:
			# clockwise arrow (the automatic spin) + the charge bar it fills
			_turn_arrow(c, 120.0, true, GOLD)
			_outline(gm.ui.charge_bar.get_global_rect().grow(10), GOLD)
	if gated and step in [2, 4, 5]:
		# the gate's initiating gesture: press-and-hold (steer) or a quick tap (charge) in the free lower area
		var vp2 := get_viewport_rect().size
		_finger(Vector2(vp2.x * 0.3, vp2.y * 0.68 + (0.0 if step != 4 else 18.0 * pulse)), step != 4 or pulse > 0.8)
	if _call_t > 0.0:
		var tr := _target_rect().grow(8)
		_outline(tr, RED)
		if tr.get_center().x > get_viewport_rect().size.x * 0.5:
			_arrow(tr.position + Vector2(tr.size.x * 0.5, tr.size.y + 40), tr.position + Vector2(tr.size.x * 0.5, tr.size.y + 6), RED)
		else:
			_arrow(tr.position + Vector2(tr.size.x + 36, tr.size.y * 0.5), tr.position + Vector2(tr.size.x + 6, tr.size.y * 0.5), RED)


func _progress() -> void:
	var vp := get_viewport_rect().size
	var n := 6
	var y := prompt.position.y - 12.0
	var cx := prompt.position.x + prompt.size.x * 0.5
	for i in n:
		var p := Vector2(cx + (i - (n - 1) * 0.5) * 34.0, y)
		draw_circle(p, 10.0, INK)
		draw_circle(p, 7.0, GOLD if i < step else (Color.WHITE if i == step else Color(1, 1, 1, 0.3)))


func _finger(tip: Vector2, pressed: bool) -> void:
	# cartoon glove (same white glove language as the launch hand): index finger pointing up at `tip`
	var palm := tip + Vector2(10, 92)
	if pressed:
		draw_arc(tip, 24.0, 0, TAU, 28, INK, 9.0, true)
		draw_arc(tip, 24.0, 0, TAU, 28, GOLD, 5.0, true)
	for pass_i in 2:
		var o := 4.0 if pass_i == 0 else 0.0
		var col := INK if pass_i == 0 else Color.WHITE
		draw_line(tip + Vector2(0, 10), palm + Vector2(-6, -24), col, 24.0 + o * 2.0, true)   # index finger
		draw_circle(tip + Vector2(0, 10), 12.0 + o, col)                                        # fingertip
		draw_line(palm + Vector2(-26, -6), palm + Vector2(-44, -30), col, 20.0 + o * 2.0, true)  # thumb
		draw_circle(palm, 34.0 + o, col)                                                         # fist
		draw_circle(palm + Vector2(22, 26), 18.0 + o, col)                                       # cuff
	draw_arc(palm + Vector2(4, 4), 20.0, 0.2, 2.2, 10, Color(0.75, 0.72, 0.68), 3.0, true)       # knuckle shading


func _turn_arrow(c: Vector2, rad: float, clockwise: bool, col: Color) -> void:
	var a0 := t * (2.2 if clockwise else -2.2)
	var span := PI * 1.2
	var from := a0
	var to := a0 + (span if clockwise else -span)
	draw_arc(c, rad, minf(from, to), maxf(from, to), 32, INK, 13.0, true)
	draw_arc(c, rad, minf(from, to), maxf(from, to), 32, col, 7.0, true)
	var tip := c + Vector2.from_angle(to) * rad
	var tangent := Vector2.from_angle(to + (PI * 0.5 if clockwise else -PI * 0.5))
	_arrow(tip - tangent * 30.0, tip, col)


func _arrow(from: Vector2, to: Vector2, col: Color) -> void:
	var d := (to - from).normalized()
	for pass_i in 2:
		var w := 13.0 if pass_i == 0 else 7.0
		var cc := INK if pass_i == 0 else col
		draw_line(from, to, cc, w, true)
		draw_line(to, to - d.rotated(0.6) * 26.0, cc, w, true)
		draw_line(to, to - d.rotated(-0.6) * 26.0, cc, w, true)


func _outline(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.border_color = col
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(14)
	draw_style_box(sb, r)
