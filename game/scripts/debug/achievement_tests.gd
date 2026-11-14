extends Node
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
var system: AchievementSystem
func check(label: String, ok: bool, detail := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test achievements_%s %s %s" % [label, "PASS" if ok else "FAIL", detail])
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func physics(n: int) -> void:
	for i in n: await get_tree().physics_frame
func has(id: String) -> bool:
	return gm.profile.achievements.unlocked.has(id)
func start(biome := "green_hills") -> void:
	gm.go_menu(); gm.mode = &"free"; gm.debug_biome = biome; gm.debug_track_seed = 4242
	gm.profile.tutorial.handled = true
	gm.start_run(); await frames(3)
	if gm.ui.awareness.visible: gm.ui.awareness.confirm.pressed.emit()
	gm.ui.biome_intro.cancel(); gm.hand.playing = false
	gm._on_flick(Vector2.ZERO)
	gm.ui.flick_bar.hide_immediate()
func run_all(which: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	at.set("scenario_running", true); at.set("max_time", 1e9)
	gm.auto_tutorial_new_profile = false
	system = gm.achievements
	if which == "achievements_qa":
		if gm.profiles: gm.activate_slot(1)
		await visual_qa()
		print("AT|tests passed=%d failed=%d" % [passed, failed])
		return
	if which in ["achievements_restart_seed", "achievements_restart_verify"]:
		restart_probe(which)
		print("AT|tests passed=%d failed=%d" % [passed, failed])
		return
	if gm.profiles:
		if not gm.profiles.root.begins_with("user://test/"):
			check("refuse_non_test_profile_root", false)
			print("AT|tests passed=%d failed=%d" % [passed, failed])
			return
		gm.go_menu()
		for slot in [1,2,3]:
			if gm.profiles.exists(slot): gm.delete_slot(slot)
		gm.activate_slot(1)
	check("registry_38", AchievementState.definitions().size() == 38)
	var ids := {}; var hidden := 0
	for d in AchievementState.definitions():
		ids[d.id] = true; hidden += int(d.hidden)
	check("unique_ids_four_hidden", ids.size() == 38 and hidden == 4)
	storage()
	await profile_slots()
	await game_events()
	await physical_heads()
	await ui_and_rng()
	gm.debug_biome = ""; gm.debug_track_seed = -1; gm.go_menu(); system.flush()
	await frames(4)
	print("AT|tests passed=%d failed=%d" % [passed, failed])
func storage() -> void:
	var path := "user://test/v365_unit/old.json"
	var old := ProfileStore.new(path, gm.catalog)
	old.coins = 4321; old.owned.append("hopper"); old.selected = "hopper"
	old.mk2_owned.append("hopper"); old.mk2_selected.hopper = true
	old.campaign.completed = ["r1", "r10"]; old.campaign.unlocked = ["r1", "r2", "r10"]
	old.artifact = {"discovered": true, "equipped": true}; old.tutorial.handled = true
	old.save()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)); raw.erase("achievements")
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string(JSON.stringify(raw)); f.close()
	var loaded := ProfileStore.new(path, gm.catalog); loaded.load_data()
	check("old_save_empty_achievements", loaded.achievements == AchievementState.defaults())
	loaded.save()
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)); after.erase("achievements")
	check("old_save_preserves_every_existing_field", raw == after)
	var model := AchievementSystem.new(); model.gm = gm; model.bind_profile(loaded)
	check("authoritative_state_reconciled", loaded.achievements.unlocked.has("campaign_1") and loaded.achievements.unlocked.has("boss_1") and loaded.achievements.unlocked.has("robots_2") and loaded.achievements.unlocked.has("mk2_owner") and loaded.achievements.unlocked.has("artifact_discovery"))
	loaded.campaign.completed = gm.campaign.order.duplicate()
	loaded.owned.assign(gm.catalog.robots.map(func(r: RobotDefinition) -> String: return r.id))
	model.reconcile()
	check("campaign_100_ten_bosses_five_robots", loaded.achievements.unlocked.has("campaign_100") and loaded.achievements.unlocked.has("campaign_50") and loaded.achievements.unlocked.has("campaign_10") and loaded.achievements.unlocked.has("boss_10") and loaded.achievements.unlocked.has("robots_5"))
	check("no_fabricated_history", not loaded.achievements.unlocked.has("distance_100") and not loaded.achievements.values.has("feet_total"))
	model._record("feet_total", 40, true); model.flush()
	var reloaded := ProfileStore.new(path, gm.catalog); reloaded.load_data()
	check("progress_and_unlock_persist", reloaded.achievements.values.feet_total == 40 and reloaded.achievements.unlocked.has("feet_1"))
	var stamp: int = loaded.achievements.unlocked.feet_1
	var awards: Array = []
	model.unlocked.connect(func(id: String, _time: int) -> void: awards.append(id))
	model._record("feet_total", 1, true); model.flush()
	check("no_duplicate_unlock_timestamp", awards.is_empty() and loaded.achievements.unlocked.feet_1 == stamp and stamp > 0)
	model._notification(NOTIFICATION_APPLICATION_PAUSED)
	var reload_pause := ProfileStore.new(path, gm.catalog); reload_pause.load_data()
	check("background_flush", reload_pause.achievements.values.feet_total == 41)
	var bad := AchievementState.sanitize({"values": {"distance": -2, "height": "bad", "speed": INF, "future_metric": 8}, "unlocked": {"bad": -1, "future_id": 12}})
	check("malformed_and_forward_compatible", bad.values == {"future_metric": 8.0} and bad.unlocked == {"future_id": 12})
	model._record("height",5)
	model._exit_tree()
	var exit_reload := ProfileStore.new(path, gm.catalog); exit_reload.load_data()
	check("exit_flush_without_ui_callbacks", exit_reload.achievements.values.get("height",0)==5)
	model.free()
func profile_slots() -> void:
	if gm.profiles == null:
		check("profiles_mode_required", false); return
	for slot in [1,2,3]:
		gm.go_menu(); check("activate_%d" % slot, gm.activate_slot(slot))
		check("fresh_slot_%d" % slot, gm.profile.achievements.unlocked.is_empty())
		system._record("feet_total", slot * 7, true); system.flush()
	for slot in [3,1,2,1]:
		gm.go_menu(); gm.activate_slot(slot)
		check("isolated_slot_%d" % slot, gm.profile.achievements.values.feet_total == slot * 7)
	gm.profile.achievements = AchievementState.defaults(); gm.profile.save()
	check("fresh_no_unlocks", system.snapshot().unlocked.is_empty())
func emit_landing(info: Dictionary) -> void:
	var data := {"quality": &"normal", "impact": 0.0, "speed_in": 0.0, "normal": Vector2.UP, "point": gm.robot.global_position}
	data.merge(info, true)
	gm.robot.landed.emit(data)
func hidden_presentation(id: String) -> Dictionary:
	return AchievementState.presentation(gm.profile.achievements, AchievementState.definition(id))
func game_events() -> void:
	check("hidden_masked", hidden_presentation("moon_feet").name == "???" and hidden_presentation("moon_feet").progress == 0 and hidden_presentation("moon_feet").description != L.t("ACH_MOON_DESC"))
	await start()
	var old_callback: Callable = system._connections[0][1]
	await start("moon")
	var previous_feet := float(gm.profile.achievements.values.get("feet_total",0))
	old_callback.call({"type": &"both"})
	check("old_robot_callback_rejected", float(gm.profile.achievements.values.get("feet_total",0)) == previous_feet)
	check("moon_entry_not_unlock", not has("moon_feet"))
	emit_landing({"type": &"body"}); emit_landing({"type": &"poor"}); emit_landing({"type": &"soft"})
	check("moon_bad_contacts_not_unlock", not has("moon_feet"))
	emit_landing({"type": &"both", "charge_ratio": 0.0})
	check("moon_feet_event", has("moon_feet"))
	check("hidden_reveals_exact_name", hidden_presentation("moon_feet").name == L.t("ACH_MOON_NAME") and hidden_presentation("moon_feet").description == L.t("ACH_MOON_DESC"))
	await start("chocolate")
	check("chocolate_entry_not_unlock", not has("chocolate_feet"))
	emit_landing({"type": &"left"}); check("chocolate_feet_event", has("chocolate_feet"))
	for i in 4: emit_landing({"type": &"right"})
	check("streak_five", has("streak_3") and has("streak_5"))
	gm.robot.body_hit.emit({"kind": &"head", "impact": 0.0, "normal": Vector2.UP, "point": gm.robot.global_position}); check("body_breaks_streak", system._streak == 0)
	emit_landing({"type": &"both", "charge_ratio": .1, "charge_zone": &"torso"})
	check("wrong_charge_zone_no_unlock", not has("charged_1"))
	emit_landing({"type": &"both", "charge_ratio": .1, "charge_zone": &"feet"})
	check("charged_landing", has("charged_1"))
	for i in 9: emit_landing({"type": &"both", "charge_ratio": 1.0, "charge_zone": &"feet"})
	check("charged_total_ten", has("charged_10"))
	gm.robot.charge_changed.emit(gm.robot.spin_config.max_charge * .995)
	check("not_max_at_99_5", not has("full_charge"))
	gm.robot.charge_changed.emit(gm.robot.spin_config.max_charge)
	check("real_max_charge_event", has("full_charge"))
	for n in [100,300,500,800,1000]:
		gm.distance_m = n; system._sample_motion(0)
		check("distance_%d" % n, has("distance_%d" % n))
	var height_before := float(gm.profile.achievements.values.get("height",0))
	await start("jelly")
	gm.robot.global_position.y = gm.terrain.surface_y(gm.robot.global_position.x) - 4000
	system._sample_motion(0)
	check("jelly_all_height_excluded", not has("height_10") and not has("height_25") and float(gm.profile.achievements.values.get("height",0)) == height_before)
	await start()
	gm.robot.global_position.y = gm.terrain.surface_y(gm.robot.global_position.x) - 2600
	system._sample_motion(0)
	check("normal_height", has("height_10") and has("height_25"))
	check("launch_speed_not_auto_award", not has("speed_50"))
	system._run_seconds = 2; gm.robot.linear_velocity = Vector2(2800,0); system._sample_motion(0)
	check("speed_milestones", has("speed_50") and has("speed_80") and has("speed_100"))
	gm.robot.contacts.any_contact = false; gm.robot.damage.rocket_fired = false
	system._was_air = true; system._theta = 0; system._turns = 0; system._turn_progress = 0
	gm.robot.global_rotation = 0
	for i in 80:
		gm.robot.global_rotation += PI/8 if i%2==0 else -PI/8
		system._sample_motion(1.0/120)
	check("air_wiggles_not_full_rotations", not has("air_turns_3") and not has("air_turns_6"))
	for i in 48:
		gm.robot.global_rotation -= PI / 4; system._sample_motion(1.0/120)
	check("air_rotations", has("air_turns_3") and has("air_turns_6"))
	gm.distance_m = 100; gm.robot.limb_lost.emit(&"arm_l", null)
	gm.distance_m = 125; system._sample_motion(0)
	check("limb_travel", has("limb_travel_25"))
	gm.robot.damage.health = gm.robot.damage.max_health * .09; gm.robot.damage.limbs_remaining.erase(&"arm_l")
	system.finish_attempt()
	check("low_hp_and_limping_finish", has("low_hp_finish") and has("limping_finish"))
	await start()
	var before: float = gm.profile.achievements.values.feet_total
	gm.go_menu(); emit_landing({"type": &"both"})
	check("menu_signals_ineligible", gm.profile.achievements.values.feet_total == before)
	await start()
	# Observe an actual physics landing, without fabricating a landed signal.
	var physical_before: float = gm.profile.achievements.values.feet_total
	gm.robot.global_position = Vector2(500, gm.terrain.surface_y(500)-500)
	gm.robot.global_rotation = 0; gm.robot.linear_velocity = Vector2(0,300); gm.robot.angular_velocity = 0
	for i in 360:
		await get_tree().physics_frame
		if gm.profile.achievements.values.feet_total > physical_before: break
		gm.robot.angular_velocity = 0
	check("actual_physics_feet_landing", gm.profile.achievements.values.feet_total > physical_before)
	# A real detached head event, then positional head-only progress.
	gm.robot.damage.health = 0; gm.robot.damage.limbs_remaining.clear(); gm.robot.damage.on_resting_torso({"point": gm.robot.global_position, "normal": Vector2.UP, "zone": &"torso"})
	await physics(4)
	check("real_rocket_created", is_instance_valid(gm.rocket))
	if is_instance_valid(gm.rocket):
		system._sample_motion(0)
		check("rocket_launch", has("rocket_launch"))
		gm.rocket.position.x = system._head_x + 101 * gm.level_config.px_per_meter
		system._sample_motion(0)
		check("head_only_distance", has("head_25") and has("head_100"))
	gm.go_menu()
	var before_tutorial: float = gm.profile.achievements.values.feet_total
	gm.begin_tutorial(&"settings")
	if gm.ui.awareness.visible: gm.ui.awareness.confirm.pressed.emit()
	await frames(3)
	emit_landing({"type": &"both", "charge_ratio": 1.0})
	check("tutorial_not_counted", gm.profile.achievements.values.feet_total == before_tutorial)
	gm.finish_tutorial(false, false)
func make_head(pos: Vector2) -> RocketHead:
	var head := RocketHead.new(); head.burning = false; head.done = true; head.cfg = gm.rocket_config
	head.contact_monitor = true; head.max_contacts_reported = 4; head.collision_layer = 4; head.collision_mask = 1
	head.can_sleep = false; head.position = pos
	var cs := CollisionShape2D.new(); var shape := CircleShape2D.new(); shape.radius = 16; cs.shape = shape; head.add_child(cs)
	gm.dynamic.add_child(head)
	return head
func physical_heads() -> void:
	gm.go_menu(); await frames(3)
	var floor_body := StaticBody2D.new(); floor_body.collision_layer = 1
	var shape := RectangleShape2D.new(); shape.size = Vector2(3000,40)
	var cs := CollisionShape2D.new(); cs.shape = shape; floor_body.add_child(cs); floor_body.position = Vector2(900,-2000); gm.dynamic.add_child(floor_body)
	var player := make_head(Vector2(600,-2100)); var enemy := make_head(Vector2(790,-2100))
	await physics(120)
	check("physical_heads_really_at_rest", system._resting(player) and system._resting(enemy))
	# Isolated synthetic post-scoring observation: both actual physics bodies remain present, score is irrelevant.
	gm.distance_m = 1000; gm.player_final_m = 2; gm.state = GameManager.State.RESULT
	system._close_times.clear()
	enemy.linear_velocity = Vector2(800,0)
	system.sample_heads(player,[enemy],1.0,100)
	check("transient_close_pass_rejected", not has("heads_close"))
	enemy.linear_velocity = Vector2.ZERO; enemy.angular_velocity = 0
	system.sample_heads(player,[enemy],.4,100)
	check("rest_hold_required", not has("heads_close"))
	enemy.position.x = player.position.x+210; await physics(1)
	system.sample_heads(player,[enemy],1.0,100)
	check("over_two_metres_rejected", not has("heads_close"))
	enemy.position.x = player.position.x+190; enemy.linear_velocity=Vector2.ZERO; await physics(2)
	# Drive the REAL automatic observer in RESULT with frozen, deliberately misleading score counters.
	gm.mode = &"campaign"; gm.rocket = player; gm.ui.debug_enabled = false
	var competitor := RaceManager.Competitor.new()
	competitor.robot = gm.robot; competitor.control = gm.input; competitor.rocket = enemy
	competitor.finished = true; competitor.distance = 9000; competitor.max_x = 900000
	gm.race.competitors.append(competitor)
	system._epoch = gm._run_epoch; system._started = true; system._finished = true
	system._close_times.clear()
	for i in 100: await get_tree().physics_frame
	check("physical_close_after_scoring", has("heads_close"), "separation=%.2fm"%(player.global_position.distance_to(enemy.global_position)/100))
	gm.go_menu()
func ignores_tree(node: Node) -> bool:
	if node is Control and (node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE): return false
	for c in node.get_children():
		if not ignores_tree(c): return false
	return true
func ui_and_rng() -> void:
	for locale_row in L.LOCALES:
		var locale: String = locale_row[0]
		L.apply(locale)
		var ok := true
		for d in AchievementState.definitions():
			var p := AchievementState.presentation(gm.profile.achievements,d)
			ok = ok and not p.name.begins_with("ACH_") and not p.description.begins_with("ACH_")
		check("locale_%s"%locale,ok)
	L.apply("ru")
	gm.go_menu(); gm.ui.open_stats(); await frames(3)
	gm.ui.achievements_button.pressed.emit(); await frames(5)
	check("stats_entry_and_38_cards", gm.ui.achievements_view.visible and gm.ui.achievements_view.rows.get_child_count()==38 and not gm.ui.stats_view.visible)
	at.call("_shot", "achievements_ru")
	gm._last_back_ms = -100000   # separate physical press (v36.9 Back debounce)
	gm._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check("android_back_closes", not gm.ui.achievements_view.visible and gm.state==GameManager.State.MENU)
	await start()
	var toast := gm.ui.achievement_toast
	toast.reset(); toast.enqueue("distance_100"); toast._process(.1)
	check("toast_recursive_input_ignore", ignores_tree(toast))
	check("toast_small_and_inside_viewport", toast.size.y <= 120 and get_viewport().get_visible_rect().encloses(toast.get_global_rect()))
	var pos := toast.get_global_rect().get_center()
	check("toast_visible_no_ui_block", toast.visible and not gm.ui.blocks_point(pos))
	var touch := InputEventScreenTouch.new(); touch.position=pos; touch.pressed=true; Input.parse_input_event(touch)
	await frames(1); check("toast_touch_reaches_gameplay", gm.input.holding)
	touch=InputEventScreenTouch.new(); touch.position=pos; touch.pressed=false; Input.parse_input_event(touch); await frames(1)
	check("release_clears_hold", not gm.input.holding)
	gm.ui.continue_card.show_offer(600,1000,""); toast._process(.1)
	check("toast_yields_to_modal", not toast.visible)
	gm.ui.continue_card.cancel(); toast.reset(); toast.enqueue("distance_100"); toast._process(.1); toast._process(4); toast._process(.1)
	check("toast_auto_dismiss", not toast.visible)
	seed(365365); var expected:=randi(); seed(365365)
	var velocity:=gm.robot.linear_velocity; var pose:=gm.robot.global_transform
	system._sample_motion(0); system.reconcile(); toast.enqueue("feet_1"); toast._process(.1)
	check("no_rng_perturbation", randi()==expected)
	check("observer_no_physics_writes", gm.robot.linear_velocity==velocity and gm.robot.global_transform==pose)
	gm.go_menu(); gm.ui.achievement_toast.reset()

func restart_probe(which: String) -> void:
	if gm.profiles == null or not gm.profiles.root.begins_with("user://test/"):
		check("restart_test_root_required", false); return
	gm.go_menu()
	if which == "achievements_restart_seed":
		for slot in [1,2,3]:
			if gm.profiles.exists(slot): gm.delete_slot(slot)
		for slot in [1,2,3]:
			gm.activate_slot(slot)
			system._record("feet_total", 10 + slot)
			if slot == 1: system._record("distance", 300)
			system.flush()
			check("restart_seed_%d"%slot, gm.profile.save())
	else:
		for slot in [1,2,3]:
			gm.activate_slot(slot)
			check("process_restart_progress_%d"%slot, gm.profile.achievements.values.get("feet_total",0) == 10 + slot)
			check("process_restart_unlock_%d"%slot, has("distance_300") == (slot == 1) and has("feet_1"))

func visual_qa() -> void:
	gm.go_menu(); gm.ui.debug_safe_margins = Vector4(45,18,25,30); gm.ui.apply_safe_area()
	var view := gm.ui.achievements_view
	for locale_row in L.LOCALES:
		var locale: String = locale_row[0]
		L.apply(locale)
		view.heading.text = L.t("ACH_TITLE"); view.close_button.text = L.t("UI_CLOSE")
		gm.profile.achievements = AchievementState.defaults()
		system._record("distance", 150); system._record("feet_total", 40)
		view.open(system); view.scroll.scroll_vertical = 0
		await frames(8)
		var m := gm.ui.safe_margins; var area := get_viewport().get_visible_rect().size
		var safe := Rect2(Vector2(m.x,m.y),area-Vector2(m.x+m.z,m.y+m.w))
		var bounds := view.panel.get_global_rect()
		check("safe_layout_%s"%locale, safe.encloses(bounds), str(bounds))
		var no_tofu := true
		for label in view.find_children("*", "Label", true, false):
			var font: Font=label.get_theme_font("font")
			for i in label.text.length():
				if label.text.unicode_at(i)>32 and not font.has_char(label.text.unicode_at(i)): no_tofu=false
		check("glyphs_%s"%locale,no_tofu)
		if locale in ["ru","de","zh_CN","ja","ko"]: at.call("_shot","achievements_%s_progress"%locale)
		view.scroll.scroll_vertical = int(view.scroll.get_v_scroll_bar().max_value)
		await frames(5)
		check("hidden_card_mask_%s"%locale, view.rows.get_node("moon_feet").find_children("*","Label",true,false)[0].text=="???")
		if locale in ["ru","de","zh_CN","ja","ko"]: at.call("_shot","achievements_%s_hidden"%locale)
		system._record("moon_feet",1); view.refresh(); view.scroll.scroll_vertical=int(view.scroll.get_v_scroll_bar().max_value)
		await frames(4)
		check("hidden_card_reveals_%s"%locale, view.rows.get_node("moon_feet").find_children("*","Label",true,false)[0].text==L.t("ACH_MOON_NAME"))
	var width := view.panel.size.x
	await frames(90)
	check("panel_width_stable_over_time", absf(view.panel.size.x-width)<1)
	view.visible=false; gm.ui.debug_safe_margins=Vector4(-1,-1,-1,-1); gm.ui.apply_safe_area(); L.apply("ru")
	await start()
	gm.ui.achievement_toast.reset(); gm.ui.achievement_toast.enqueue("moon_feet"); await frames(3)
	at.call("_shot","achievement_toast_gameplay")
	gm.go_menu()
