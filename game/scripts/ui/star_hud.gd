class_name StarHud
extends VBoxContainer

var tracker: StarTracker
var free_mode := false
var expanded := true
var toggle: Button
var compact := false
var rows: Array[Label] = []
var toast: Label
var _toast_time := 0.0
var _paid: Array = []

func build(ui: UIController) -> void:
	position = Vector2(34, 206)
	custom_minimum_size = Vector2(420, 0)
	size = Vector2(420, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	toggle = Button.new()
	toggle.text = L.t("STAR_HUD_TOGGLE") % 0
	toggle.tooltip_text = L.t("STAR_HUD_TIP")
	toggle.custom_minimum_size = Vector2(420, 52)
	toggle.add_theme_font_override("font", ui.font)
	toggle.add_theme_font_size_override("font_size", 22)
	# v34: the Free Run list is always open - the header is an info counter, not a collapse button (takes no input)
	toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle.focus_mode = Control.FOCUS_NONE
	add_child(toggle)
	for i in 3:
		var row := ui._label("", 20, UIController.CREAM, 5)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(420, 0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		rows.append(row)
	toast = ui._label("", 24, UIController.GOLD, 6)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(toast)
	visible = false

func setup(t: StarTracker, is_free := false) -> void:
	tracker = t
	free_mode = is_free
	expanded = true
	toggle.visible = free_mode
	compact = false
	_paid = []
	_toast_time = 0.0
	toast.text = ""
	_refresh()

func earned(i: int, coins: int) -> void:
	_paid.append(i)
	toast.text = L.pf("STAR_TOAST_FREE", coins) if free_mode else L.pf("STAR_TOAST_CAMP", coins)
	_toast_time = 1.8
	toast.pivot_offset=toast.size*0.5
	toast.scale=Vector2(0.85,0.85)
	toast.create_tween().tween_property(toast,"scale",Vector2.ONE,0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh()

## v34: kept for callers; the Free Run challenge list no longer collapses.
func collapse_free() -> void:
	expanded = true
	_refresh()

func _process(dt: float) -> void:
	if not visible or tracker == null:
		return
	_toast_time = maxf(0.0, _toast_time - dt)
	toast.visible = _toast_time > 0.0
	_refresh()

func _refresh() -> void:
	if tracker == null:
		return
	if free_mode:
		toggle.text = L.t("STAR_HUD_TOGGLE") % tracker.owned.count(true)
	for i in rows.size():
		rows[i].visible = i < tracker.challenges.size() and (not free_mode or expanded)
		if not rows[i].visible:
			continue
		var ch: Dictionary = tracker.challenges[i]
		var text := StarChallenges.short(ch) if compact else StarChallenges.describe(ch)
		var prefix := "☆ "
		var color := UIController.CREAM
		if tracker.owned[i]:
			prefix = "★ "
			color = UIController.GOLD
		elif tracker.status[i] == 1:
			prefix = "★ " if _paid.has(i) else "✓ "
			color = UIController.GOLD if _paid.has(i) else Color(0.4, 1.0, 0.5)
		elif tracker.status[i] == -1:
			prefix = "× "
			color = Color(0.65, 0.65, 0.65)
		elif compact:
			text += " · " + tracker.progress(i)
		rows[i].text = prefix + text
		rows[i].add_theme_color_override("font_color", color)
