class_name AchievementsView
extends Control
var ui: UIController
var system: AchievementSystem
var heading: Label
var summary: Label
var rows: VBoxContainer
var close_button: Button
var panel: PanelContainer
var scroll: ScrollContainer
func build(controller: UIController) -> void:
	ui = controller
	name = "AchievementsView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	ui._shade(self, .6)
	panel = ui._paper_panel()
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	heading = ui._gold_label(L.t("ACH_TITLE"), 40)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(heading)
	summary = ui._ink_label("", 23)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(summary)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	close_button = ui._button(L.t("UI_CLOSE"), UIController.GOLD)
	close_button.custom_minimum_size.y = 66
	close_button.pressed.connect(func() -> void: visible = false)
	v.add_child(close_button)
	visible = false
func open(achievement_system: AchievementSystem) -> void:
	system = achievement_system
	refresh()
	visible = true
	_layout()
func refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child); child.queue_free()
	if system == null: return
	var state := system.snapshot()
	var defs := AchievementState.definitions()
	var count := 0
	for d in defs:
		var p := AchievementState.presentation(state, d)
		count += int(p.unlocked)
		var card := ui._paper_panel()
		card.name = String(d.id)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		card.add_child(h)
		var badge := AchievementBadge.new()
		badge.hidden_badge = p.hidden; badge.earned = p.unlocked; badge.badge_font = ui.font
		h.add_child(badge)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(text)
		var title := ui._ink_label(p.name, 27)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(title)
		var description := ui._ink_label(p.description, 22)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(description)
		var status := ui._ink_label(L.t("ACH_EARNED") if p.unlocked else L.t("ACH_LOCKED"), 19)
		text.add_child(status)
		if not p.hidden and not p.unlocked:
			var progress := ui._ink_label(L.f("ACH_PROGRESS", {"have": int(p.progress), "total": int(p.target)}), 19)
			text.add_child(progress)
			var bar := ProgressBar.new()
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.max_value = p.target; bar.value = p.progress; bar.show_percentage = false
			bar.custom_minimum_size.y = 10
			text.add_child(bar)
	summary.text = L.f("ACH_SUMMARY", {"have": count, "total": defs.size()})
func _layout() -> void:
	var area := get_viewport_rect().size
	var m := ui.safe_margins
	var available := area - Vector2(m.x + m.z + 24, m.y + m.w + 24)
	var desired_width := minf(1000, available.x)
	# Derive the row constraint from the viewport, never from the container's growing minimum.
	rows.custom_minimum_size.x = maxf(desired_width - 160, 100)
	panel.size = Vector2(desired_width, available.y)
	panel.position = Vector2(m.x + 12, m.y + 12) + (available - panel.size) * .5
	# Keep wrapping constrained by the screen, not the minimum width of the labels.
	rows.custom_minimum_size.x = maxf(desired_width - 160, 100)
func _process(_dt: float) -> void:
	if visible: _layout()
