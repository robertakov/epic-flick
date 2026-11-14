class_name AchievementToast
extends Panel
## Passive overlay. Every descendant ignores input; no sound, pause, RNG or gameplay writes.
var ui: UIController
var pending: Array[String] = []
var title: Label
var caption: Label
var remaining := 0.0
func build(controller: UIController) -> void:
	ui = controller
	name = "AchievementToast"
	z_index = UIController.Z_MODAL + 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	var style := StyleBoxFlat.new()
	style.bg_color = UIController.PAPER
	style.border_color = UIController.INK
	style.set_border_width_all(4); style.set_corner_radius_all(18)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 12)
	add_theme_stylebox_override("panel", style)
	caption = ui._ink_label(L.t("ACH_UNLOCKED"), 18)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)
	title = ui._ink_label("", 25)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	_ignore(self)
	visible = false
func _ignore(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children(): _ignore(child)
func enqueue(id: String, _timestamp := 0) -> void:
	pending.append(id)
func reset() -> void:
	pending.clear(); remaining = 0; visible = false
func blocked() -> bool:
	for modal in ui.modal_roots():
		if modal.visible: return true
	return (ui.biome_intro and ui.biome_intro.blocking()) or (ui.flick_bar and ui.flick_bar.visible)
func _process(dt: float) -> void:
	if ui == null: return
	if blocked():
		visible = false
		return
	if remaining <= 0 and not pending.is_empty():
		var d := AchievementState.definition(pending.pop_front())
		title.text = L.f(d.name_key, {"n": int(d.target)})
		remaining = 3.2
	visible = remaining > 0
	if not visible: return
	remaining -= dt / maxf(Engine.time_scale, .001)
	var area := get_viewport_rect().size
	var m := ui.safe_margins
	var width := minf(430, area.x - m.x - m.z - 24)
	size = Vector2(width, 110)
	caption.position = Vector2(12, 8)
	caption.size = Vector2(width - 24, 24)
	title.position = Vector2(12, 36)
	title.size = Vector2(width - 24, 64)
	position = Vector2(clampf(area.x * .45 - size.x * .5, m.x + 12, area.x - m.z - size.x - 12), m.y + 12)
