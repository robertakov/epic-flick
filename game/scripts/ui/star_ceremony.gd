class_name StarCeremony
extends VBoxContainer
signal star_shown(index: int)
var badges: Array[StarBadge]=[]
var counter: Label
var complete: Label
var sequence: Tween
var animated: Array=[]
var fresh: Array=[]
var available := 0
var campaign_total := 0
var all_complete := false
func build(ui: UIController) -> void:
	var slots := HBoxContainer.new()
	slots.alignment=BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation",36)
	add_child(slots)
	for i in 3:
		var badge := StarBadge.new()
		badge.custom_minimum_size=Vector2(100,100)
		slots.add_child(badge); badges.append(badge)
	counter=ui._ink_label("",24)
	counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	add_child(counter)
	complete=ui._ink_label("",25,Color(0.75,0.4,0))
	complete.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	add_child(complete)
func present(before: Array, newly: Array, total: int, wallet: int) -> void:
	cancel()
	animated=[]; fresh=newly.duplicate(); available=wallet; campaign_total=total
	all_complete=true
	for i in 3:
		badges[i].gold=bool(before[i])
		badges[i].scale=Vector2.ONE
		all_complete=all_complete and (bool(before[i]) or fresh.has(i))
	complete.text=L.t("STAR_ALL_DONE") if all_complete and fresh.is_empty() else ""
	refresh_counter()
	if not fresh.is_empty():
		sequence=create_tween()
		sequence.tween_interval(0.35)
		for index in fresh:
			sequence.tween_callback(reveal.bind(int(index)))
			sequence.tween_interval(0.4)
func reveal(index: int) -> void:
	if not is_visible_in_tree() or animated.has(index): return
	animated.append(index)
	badges[index].pop()
	refresh_counter()
	star_shown.emit(index)
	if animated.size()==fresh.size() and all_complete:
		complete.text="★★★  " + L.t("STAR_ALL_DONE")
func refresh_counter() -> void:
	var waiting := fresh.size()-animated.size()
	counter.text=L.f("STAR_COUNTER", {"total": campaign_total-waiting, "avail": maxi(0,available-waiting)})
func cancel() -> void:
	if sequence: sequence.kill()
	sequence=null
	for badge in badges:
		if badge.animation: badge.animation.kill()
