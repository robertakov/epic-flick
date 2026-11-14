class_name CampaignMapView
extends Control
## Campaign map: the node graph drawn as a winding path (drag / swipe or arrows to pan, tap a node to inspect).
## Completed = gold + check, available = pulsing orange, locked = grey + padlock, boss = big crowned node.
## Edges come from the graph (`next` lists), so future side branches draw without changes. Nodes of types that are
## not playable yet are drawn but cannot be started.

signal start_requested(node_id: String)
signal back_requested

const INK := UIController.INK
const STEP_X := 175.0
const R_NODE := 34.0
const R_BOSS := 48.0

var ui: UIController
var campaign: CampaignData
var profile: ProfileStore
var catalog: RobotCatalog
var skins: SkinCatalog
var base_config: RobotConfig = preload("res://config/robot_samurai.tres")
var selected := ""
var pan := 0.0                 # world x at the left edge of the map area
var _canvas: Control
var _enemy_layer: Node2D
var _node_badges := {}
var _positions := {}
var _drag_from := Vector2.ZERO
var _drag_pan := 0.0
var _dragging := false
var _moved := false
var _time := 0.0
var _title: Label
var _info_name: Label
var _info_body: Label
var _info_reward: Label
var _start: Button
var _coins: Label
var _star_info: Label


func build(p_ui: UIController) -> void:
	ui = p_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	ui._shade(self, 0.62)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 6)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	_title = ui._label(L.t("MENU_CAMPAIGN"), 54, UIController.GOLD, 12)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_coins = ui._label("", 40, UIController.GOLD, 10)
	head.add_child(_coins)
	# map area with pan arrows
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	var left := ui._button("◀", UIController.PAPER)
	left.custom_minimum_size = Vector2(80, 120)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_font_size_override("font_size", 50)
	left.pressed.connect(func() -> void: scroll_by(-STEP_X * 4.0))
	mid.add_child(left)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
	mid.add_child(_canvas)
	_enemy_layer = Node2D.new()
	_enemy_layer.name = "EnemyLayer"
	_enemy_layer.z_index = 2
	_canvas.add_child(_enemy_layer)
	var right := ui._button("▶", UIController.PAPER)
	right.custom_minimum_size = Vector2(80, 120)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_font_size_override("font_size", 50)
	right.pressed.connect(func() -> void: scroll_by(STEP_X * 4.0))
	mid.add_child(right)
	# info bar of the selected node
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 18)
	root.add_child(bottom)
	var back := ui._button(L.t("UI_BACK"), UIController.PAPER)
	back.custom_minimum_size = Vector2(200, 96)
	back.add_theme_font_size_override("font_size", 38)
	back.pressed.connect(func() -> void: back_requested.emit())
	bottom.add_child(back)
	var panel := ui._paper_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bottom.add_child(panel)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	panel.add_child(info)
	_info_name = ui._ink_label("", 30)
	_info_name.clip_text = true
	info.add_child(_info_name)
	_info_body = ui._ink_label("", 20, UIController.GREY)
	info.add_child(_info_body)
	_info_reward = ui._label("", 22, Color(0.75, 0.45, 0.0), 0)
	info.add_child(_info_reward)
	_star_info = ui._ink_label("", 19)
	_star_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_star_info)
	# long texts wrap inside the panel instead of widening the bar (START must stay on screen)
	for l in [_info_body, _info_reward]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(120, 0)
	panel.custom_minimum_size = Vector2(0, 0)
	panel.clip_contents = true
	_start = ui._button(L.t("UI_START"), Color(1.0, 0.6, 0.2))
	_start.custom_minimum_size = Vector2(240, 96)
	_start.add_theme_font_size_override("font_size", 46)
	_start.pressed.connect(press_start)
	bottom.add_child(_start)


func open(p_campaign: CampaignData, p_profile: ProfileStore, p_catalog: RobotCatalog, p_skins: SkinCatalog) -> void:
	campaign = p_campaign
	profile = p_profile
	catalog = p_catalog
	skins = p_skins
	_clear_enemy_badges()
	_layout()
	selected = frontier()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	await get_tree().process_frame
	center_on(selected)
	_refresh_info()
	_sync_enemy_badges()


## The most advanced available, not yet completed node (else the last completed).
func frontier() -> String:
	var last := campaign.start_id
	for id in campaign.order:
		if profile.is_unlocked(id):
			last = id
			if not profile.is_completed(id) and campaign.is_playable(id):
				return id
	return last


func _layout() -> void:
	_positions.clear()
	var i := 0
	for id in campaign.order:
		var n := campaign.node(id)
		if n.has("pos"):
			_positions[id] = Vector2(n.pos[0], n.pos[1])
		else:
			# winding path; y as a fraction of the map height (resolved when drawing), leaving headroom for opponent rigs above nodes
			_positions[id] = Vector2(110.0 + i * STEP_X, 0.57 + 0.21 * sin(i * 0.72))
		i += 1


func _pos(id: String) -> Vector2:
	var p: Vector2 = _positions.get(id, Vector2.ZERO)
	var y := p.y * _canvas.size.y if p.y <= 1.0 else p.y
	return Vector2(p.x - pan, y)


func _pedestal_pos(id: String) -> Vector2:
	var p := _pos(id)
	var n := campaign.node(id)
	var boss: bool = n.get("difficulty", "") == "boss"
	var r := R_BOSS if boss else R_NODE
	return p + Vector2(0.0, -r - (34.0 if boss else 15.0))


func round_opponents(id: String) -> Array[Dictionary]:
	return EnemyRoster.resolve_round_opponents(campaign, catalog, id)


func node_previews(id: String) -> Array[RobotPreview]:
	var badge := _ensure_node_badge(id)
	var out: Array[RobotPreview] = []
	for pr in badge.get("previews", []):
		if pr is RobotPreview:
			out.append(pr)
	return out


func _clear_enemy_badges() -> void:
	if _enemy_layer == null:
		return
	for ch in _enemy_layer.get_children():
		ch.queue_free()
	_node_badges.clear()


func _ensure_node_badge(id: String) -> Dictionary:
	if _node_badges.has(id) and is_instance_valid(_node_badges[id].root):
		return _node_badges[id]
	var opps := round_opponents(id)
	var root := Node2D.new()
	root.name = "Badge_" + id
	if _enemy_layer != null:
		_enemy_layer.add_child(root)
	var previews: Array[RobotPreview] = []
	var idx := maxi(0, campaign.order.find(id)) if campaign else 0
	for i in opps.size():
		var o: Dictionary = opps[i]
		var def := catalog.get_by_id(String(o.robot_id)) if catalog else null
		if def == null and catalog and not catalog.robots.is_empty():
			def = catalog.robots[0]
		if def == null:
			continue
		var pr := RobotPreview.new()
		pr.name = "Opponent_%d" % i
		pr.phase_offset = float(idx) * 0.73 + float(i) * 1.45
		var eid := String(o.get("enemy_id", ""))
		if eid != "":
			pr.show_enemy(eid, def, base_config)
		else:
			var sk_id := String(o.get("skin_id", ""))
			var sk := skins.get_by_id(sk_id) if skins and sk_id != "" else null
			pr.show_robot(def, base_config, sk)
		root.add_child(pr)
		previews.append(pr)
	var entry := {"root": root, "previews": previews, "opponents": opps}
	_node_badges[id] = entry
	_position_node_badge(id, entry)
	return entry


func _position_node_badge(id: String, b: Dictionary) -> void:
	var root: Node2D = b.root
	var previews: Array = b.previews
	var ped := _pedestal_pos(id)
	var n := campaign.node(id)
	var boss: bool = n.get("difficulty", "") == "boss"
	var st := _state_of(id)
	var is_sel := (id == selected)
	root.visible = true
	root.position = ped
	root.z_index = 4 if is_sel else 1
	if st == "open":
		root.modulate = Color.WHITE
	elif st == "done":
		root.modulate = Color(0.98, 0.98, 0.96, 0.96)
	else:
		root.modulate = Color(0.70, 0.68, 0.74, 0.86)
	var count := previews.size()
	var base_s := 0.35 if count <= 1 else 0.28
	if boss:
		base_s = 0.37
	if is_sel:
		base_s *= 1.10
	if _canvas and _canvas.size.y > 0.0:
		var max_h := maxf(54.0, ped.y - 10.0)
		base_s = minf(base_s, max_h / 285.0)
	for i in count:
		var pr: RobotPreview = previews[i]
		pr.set_process(visible)
		var slot_off := Vector2.ZERO
		if count == 2:
			slot_off = Vector2(-24.0, 2.0) if i == 0 else Vector2(24.0, -3.0)
			pr.z_index = 2 if i == 0 else 1
		else:
			pr.z_index = 1
		pr.scale = Vector2.ONE * base_s
		pr.position = slot_off + Vector2(0.0, -pr.floor_offset() * base_s)


func _sync_enemy_badges() -> void:
	if campaign == null or _canvas == null or _enemy_layer == null:
		return
	for id in campaign.order:
		var p := _pos(id)
		var in_view := p.x >= -150.0 and p.x <= _canvas.size.x + 150.0
		if not in_view and id != selected:
			if _node_badges.has(id) and is_instance_valid(_node_badges[id].root):
				var hidden_b: Dictionary = _node_badges[id]
				hidden_b.root.visible = false
				for pr in hidden_b.previews:
					pr.set_process(false)
			continue
		var b := _ensure_node_badge(id)
		_position_node_badge(id, b)


func _max_pan() -> float:
	return maxf(0.0, 110.0 + (campaign.order.size() - 1) * STEP_X + 110.0 - _canvas.size.x)


func scroll_by(dx: float) -> void:
	pan = clampf(pan + dx, 0.0, _max_pan())
	_sync_enemy_badges()
	_canvas.queue_redraw()


func center_on(id: String) -> void:
	var p: Vector2 = _positions.get(id, Vector2.ZERO)
	pan = clampf(p.x - _canvas.size.x * 0.5, 0.0, _max_pan())
	_sync_enemy_badges()
	_canvas.queue_redraw()


func select_node(id: String) -> void:
	if campaign.nodes.has(id):
		selected = id
		_refresh_info()
		_sync_enemy_badges()
		_canvas.queue_redraw()


func press_start() -> void:
	if can_start(selected):
		start_requested.emit(selected)


func can_start(id: String) -> bool:
	return profile.is_unlocked(id) and campaign.is_playable(id)


func _process(dt: float) -> void:
	if visible:
		_time += dt
		_sync_enemy_badges()
		_canvas.queue_redraw()


func _on_canvas_input(e: InputEvent) -> void:
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pressed = e.pressed
		released = not e.pressed
		pos = e.position
	elif e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_DOWN or e.button_index == MOUSE_BUTTON_WHEEL_UP):
		scroll_by(120.0 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -120.0)
		return
	elif e is InputEventMouseMotion and _dragging:
		var dx: float = e.position.x - _drag_from.x
		if absf(dx) > 12.0:
			_moved = true
		if _moved:
			pan = clampf(_drag_pan - dx, 0.0, _max_pan())
			_sync_enemy_badges()
			_canvas.queue_redraw()
		return
	else:
		return
	if pressed:
		_dragging = true
		_moved = false
		_drag_from = pos
		_drag_pan = pan
	elif released and _dragging:
		_dragging = false
		if not _moved:
			_tap(pos)


func _tap(pos: Vector2) -> void:
	var best := ""
	var bd := INF
	for id in campaign.order:
		var d := _pos(id).distance_to(pos)
		var r := (R_BOSS if campaign.node(id).difficulty == "boss" else R_NODE) + 14.0
		if d < r and d < bd:
			bd = d
			best = id
	if best == "":
		for id in campaign.order:
			var p := _pos(id)
			var ped := _pedestal_pos(id)
			if absf(pos.x - p.x) <= 46.0 and pos.y >= ped.y - 108.0 and pos.y <= p.y:
				var d := Vector2(p.x, ped.y - 44.0).distance_to(pos)
				if d < bd:
					bd = d
					best = id
	if best != "":
		select_node(best)


func _state_of(id: String) -> String:
	if profile.is_completed(id):
		return "done"
	if profile.is_unlocked(id) and campaign.is_playable(id):
		return "open"
	return "locked"


func _draw_ellipse(c: Control, center: Vector2, rx: float, ry: float, fill: Color, stroke: Color, width := 3.0) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	c.draw_polyline(pts, stroke, width, true)


func _draw_map() -> void:
	var c := _canvas
	# edges
	for e in campaign.edges():
		var a := _pos(e[0])
		var b := _pos(e[1])
		if maxf(a.x, b.x) < -60.0 or minf(a.x, b.x) > c.size.x + 60.0:
			continue
		var done := profile.is_completed(e[0])
		c.draw_line(a, b, INK, 14.0, true)
		c.draw_line(a, b, UIController.GOLD if done else Color(0.55, 0.5, 0.45), 8.0, true)
	# nodes
	for id in campaign.order:
		var p := _pos(id)
		if p.x < -80.0 or p.x > c.size.x + 80.0:
			continue
		var n := campaign.node(id)
		var boss: bool = n.difficulty == "boss"
		var r := R_BOSS if boss else R_NODE
		var st := _state_of(id)
		var fill := Color(0.55, 0.52, 0.5)
		if st == "done":
			fill = UIController.GOLD
		elif st == "open":
			fill = Color(1.0, 0.6, 0.2)
		var ped := _pedestal_pos(id)
		var opp_count: int = n.get("enemies", []).size()
		var ped_rx := 32.0 if boss else (46.0 if opp_count >= 2 else 28.0)
		var ped_ry := 8.5 if (boss or opp_count >= 2) else 7.5
		var ped_fill := Color(0.46, 0.43, 0.41, 0.85)
		if st == "done":
			ped_fill = Color(0.95, 0.78, 0.22, 0.92)
		elif st == "open":
			ped_fill = Color(1.0, 0.62, 0.22, 0.95)
		c.draw_line(p + Vector2(0, -r), ped, INK, 6.0, true)
		c.draw_line(p + Vector2(0, -r), ped, ped_fill, 2.5, true)
		if id == selected:
			_draw_ellipse(c, ped, ped_rx + 4.0, ped_ry + 2.0, Color(1.0, 0.95, 0.82, 0.35), UIController.CREAM, 2.5)
		_draw_ellipse(c, ped, ped_rx, ped_ry, ped_fill, INK, 3.5)
		if st == "open":
			var pulse := 0.5 + 0.5 * sin(_time * 5.0)
			c.draw_circle(p, r + 10.0 + 6.0 * pulse, Color(1.0, 0.8, 0.3, 0.35 + 0.25 * pulse))
		if id == selected:
			c.draw_arc(p, r + 9.0, 0.0, TAU, 40, UIController.CREAM, 6.0, true)
		c.draw_circle(p, r + 5.0, INK)
		c.draw_circle(p, r, fill)
		if n.difficulty == "hard" and st != "locked":
			c.draw_arc(p, r - 6.0, 0.0, TAU, 32, Color(0.85, 0.2, 0.15), 4.0, true)
		if boss:
			_crown(c, p + Vector2(0, -r - 16.0), st != "locked")
		var label := str(int(n.get("round", 0)))
		var fs := 34 if boss else 28
		var tw := ui.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := p + Vector2(-tw * 0.5, fs * 0.36)
		c.draw_string_outline(ui.font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, INK)
		c.draw_string(ui.font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIController.CREAM)
		for i in 3:
			_star(c, p + Vector2((i - 1) * 23, r + 22), profile.has_star(id, i))
		if st == "done":
			c.draw_polyline(PackedVector2Array([p + Vector2(r * 0.25, r * 0.55), p + Vector2(r * 0.5, r * 0.8), p + Vector2(r * 0.95, r * 0.25)]), Color(0.2, 0.6, 0.15), 6.0)
		elif st == "locked":
			_lock(c, p + Vector2(r * 0.62, r * 0.55))


func _crown(c: Control, p: Vector2, lit: bool) -> void:
	var pts := PackedVector2Array([p + Vector2(-22, 10), p + Vector2(-22, -8), p + Vector2(-11, 2), p + Vector2(0, -14),
		p + Vector2(11, 2), p + Vector2(22, -8), p + Vector2(22, 10)])
	c.draw_colored_polygon(pts, UIController.GOLD if lit else Color(0.6, 0.58, 0.55))
	pts.append(pts[0])
	c.draw_polyline(pts, INK, 3.0)


func _lock(c: Control, p: Vector2) -> void:
	c.draw_arc(p + Vector2(0, -6), 7.0, PI, TAU, 10, INK, 4.0)
	c.draw_rect(Rect2(p + Vector2(-10, -6), Vector2(20, 15)), INK)
	c.draw_rect(Rect2(p + Vector2(-7, -3), Vector2(14, 9)), Color(0.8, 0.75, 0.6))


func _robot_name(id: String) -> String:
	var d := catalog.get_by_id(id)
	return L.data(d.display_name) if d else id


func _refresh_info() -> void:
	var max_stars := campaign.order.size() * 3 if campaign else 300
	_coins.text = L.pf("MAP_COINS_LINE", profile.coins, {"stars": profile.total_stars(), "max": max_stars})
	var n := campaign.node(selected)
	if n.is_empty():
		return
	var diff: String = {"normal": "", "hard": L.t("MAP_DIFF_HARD"), "boss": L.t("MAP_DIFF_BOSS")}.get(n.difficulty, "")
	_info_name.text = "%s%s" % [L.data(String(n.get("title", selected))), diff]
	var opp := []
	for o in round_opponents(selected):
		opp.append("%s (%s)" % [L.data(String(o.name)), _robot_name(String(o.robot_id))])
	var st := _state_of(selected)
	var status: String = {"done": L.t("MAP_DONE"), "open": L.t("MAP_OPEN"), "locked": L.t("MAP_LOCKED")}[st]
	if not campaign.is_playable(selected):
		status = L.t("MAP_SOON")
	var att := profile.attempts_on(selected)
	_info_body.text = L.f("MAP_RIVAL_MANY" if opp.size() > 1 else "MAP_RIVAL_ONE", {"list": ", ".join(opp), "status": status}) \
		+ ((L.t("MAP_ATTEMPTS") % att) if att > 0 and st != "done" else "")
	var rw := L.pf("MAP_REWARD_FIRST", int(n.reward_first))
	var skin_id := String(n.get("reward_skin", ""))
	if skin_id != "" and skins:
		var s := skins.get_by_id(skin_id)
		if s:
			rw += L.f("MAP_SKIN_REWARD", {"skin": L.data(s.display_name), "robot": _robot_name(s.robot_id)})
	if profile.campaign.claimed.has(selected):
		rw = L.t("MAP_CLAIMED")
	_info_reward.text = rw
	var objectives := []
	var stars: Array = n.get("stars", [])
	for i in stars.size():
		objectives.append(("★ " if profile.has_star(selected, i) else "☆ ") + StarChallenges.describe(stars[i]) + L.t("MAP_STAR_REWARD") % StarChallenges.reward(stars[i]))
	_star_info.text = "\n".join(objectives)
	_start.modulate = Color.WHITE if can_start(selected) else Color(1, 1, 1, 0.45)


func _star(c: Control, p: Vector2, lit: bool) -> void:
	var points := PackedVector2Array()
	for i in 10:
		points.append(p + Vector2.UP.rotated(i * PI / 5.0) * (10.0 if i % 2 == 0 else 4.5))
	c.draw_colored_polygon(points, UIController.GOLD if lit else Color(0.35, 0.33, 0.3))
	points.append(points[0])
	c.draw_polyline(points, UIController.INK, 1.5, true)
