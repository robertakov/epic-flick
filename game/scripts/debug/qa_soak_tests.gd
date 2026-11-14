extends Node
## Final pre-release QA soak (debug only, not exported). Prints "AT|soak {json}" per run and "AT|test qa_<name>".
##   --scenario=qa_soak [--soak_runs=60] [--soak_speed=3]
## Real game flow: campaign node -> start_run -> flick -> automatic play -> _finish -> next node (all biomes, all five
## robots, BASE / MK2 alternating, rivals), plus Free Runs, mid-run Continue respawns and mid-effect restarts.
## Records node / orphan / object / resource counts, static memory, active 2D physics bodies, dynamic children,
## GameAudio players / loops / cooldown map, FX children and real frame time - growth across runs = a leak.
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const IDS := ["tin", "hopper", "heavy", "rocket", "samurai"]


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test qa_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func metrics(tag: String, extra: Dictionary) -> Dictionary:
	var m := {"tag": tag,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"phys2d": int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"dynamic": gm.dynamic.get_child_count(),
		"audio_children": gm.audio.get_child_count(),
		"audio_loops": gm.audio.loops.size(),
		"audio_cooldowns": gm.audio.cooldowns.size(),
		"audio_cache": gm.audio.cache.size(),
		"fx": gm.fx.get_child_count() if gm.fx else -1,
		"hazards": gm.hazards.get_child_count(),
		"terrain": gm.terrain.get_child_count(),
		"rivals": gm.race.competitors.size(),
		"timers": _count_timers(get_tree().root)}
	m.merge(extra, true)
	print("AT|soak " + JSON.stringify(m))
	return m


func _count_timers(n: Node) -> int:
	var c := int(n is Timer)
	for ch in n.get_children():
		c += _count_timers(ch)
	return c


func _grant_all() -> void:
	var p := gm.profile
	for id in IDS:
		if not p.owned.has(id):
			p.owned.append(id)
		if not p.mk2_owned.has(id):
			p.mk2_owned.append(id)


## One real attempt. Returns {reason, t, frame_ms, ...}.
var force_biome := ""


func run_once(k: int, node: String, robot: String, mk2: bool, campaign: bool, action: String, speed: int) -> Dictionary:
	gm.profile.selected = robot
	gm.profile.mk2_selected[robot] = mk2
	gm.mode = &"campaign" if campaign else &"free"
	gm.node_id = node if campaign else ""
	gm.debug_biome = force_biome if not campaign else ""
	var finished := [false]
	var cb := func(_d: float) -> void: finished[0] = true
	gm.run_finished.connect(cb)
	at.call("start_seen_run")      # confirms the first-run awareness card like a player
	await frames(4)
	gm.hand.playing = false
	gm._on_flick(Vector2.ZERO)
	await frames(2)
	GameManager.set_sim_speed(speed)
	var t := 0.0
	var did_action := false
	var ft := []
	var last_us := Time.get_ticks_usec()
	var max_t := 240.0
	while not finished[0] and t < max_t:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ft.append((now - last_us) / 1000.0)
		last_us = now
		t += get_process_delta_time() * speed
		if not did_action and t > 8.0:
			did_action = true
			if action == "continue" and gm.state == GameManager.State.RUN and is_instance_valid(gm.robot):
				gm._respawn_after_continue()
			elif action == "restart":
				gm.restart_attempt()
				if gm.ui.awareness.visible: gm.ui.awareness.confirm.pressed.emit()
				await frames(4)
				gm.hand.playing = false
				gm._on_flick(Vector2.ZERO)
				GameManager.set_sim_speed(speed)
	gm.run_finished.disconnect(cb)
	GameManager.set_sim_speed(1)
	ft.sort()
	var med: float = ft[ft.size() / 2] if ft.size() > 0 else 0.0
	var p95: float = ft[int(ft.size() * 0.95)] if ft.size() > 0 else 0.0
	var res := {"k": k, "node": node, "robot": robot, "mk2": mk2, "campaign": campaign, "action": action,
		"biome": String(gm.biome.id) if gm.biome else "", "finished": finished[0], "sim_t": snappedf(t, 0.1),
		"frame_ms_med": snappedf(med, 0.01), "frame_ms_p95": snappedf(p95, 0.01), "state": int(gm.state)}
	await frames(30)                   # result screen settles, deferred frees run
	return res


## Device finding (Galaxy S23, v36.8): new player -> auto tutorial -> skip -> campaign map -> Android Back quit the
## app. Exact reproduction of that path; quit_handler records instead of quitting.
func back_after_tutorial_skip() -> void:
	var quits := [0]
	gm.quit_handler = func() -> void: quits[0] += 1
	gm.auto_tutorial_new_profile = true
	gm.go_menu()
	await frames(5)
	var slot := 3
	if gm.profiles.exists(slot):
		gm.profiles.delete(slot)
	var ok := gm.activate_slot(slot)
	await frames(30)
	var in_tut: bool = gm.tutorial != null
	gm.ui.tutorial_overlay.confirm.visible = true
	gm.finish_tutorial(false, true)          # what the skip card's "YES" button does
	await frames(30)
	var vis := {"map": gm.ui.is_campaign_map_open(), "profiles": gm.ui.is_profiles_open(), "select": gm.ui.is_robot_select_open(),
		"stats": gm.ui.is_stats_open(), "settings": gm.ui.is_settings_open(), "awareness": gm.ui.awareness.visible,
		"ach": gm.ui.achievements_view.visible if gm.ui.achievements_view else false, "state": int(gm.state), "slot": gm.active_slot}
	print("AT|back_probe before " + JSON.stringify(vis))
	gm._last_back_ms = -100000
	# Android 16 delivers ONE press as two go-back requests (same frame): must act once
	gm.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	gm.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(10)
	var after := {"map": gm.ui.is_campaign_map_open(), "menu": gm.ui.menu.visible, "state": int(gm.state)}
	print("AT|back_probe after " + JSON.stringify(after) + " quits=%d" % quits[0])
	check("back_after_tutorial_skip_goes_to_menu", ok and in_tut and bool(vis.map) and quits[0] == 0 and not bool(after.map) and bool(after.menu),
		"before %s after %s quits %d" % [vis, after, quits[0]])
	# a separate, later press in the menu still quits (designed behaviour)
	gm._last_back_ms = -100000
	gm.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	check("back_double_delivery_single_action_then_menu_quits", quits[0] == 1, "quits %d" % quits[0])


func run_all(_which: String) -> void:
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	if (at.get("args") as Dictionary).has("back_probe"):
		await back_after_tutorial_skip()
		print("AT|tests passed=%d failed=%d" % [passed, failed])
		return
	var args: Dictionary = at.get("args")
	var runs := int(args.get("soak_runs", "60"))
	var speed := int(args.get("soak_speed", "3"))
	force_biome = String(args.get("soak_biome", ""))   # all Free Runs in one biome (leak hunting)
	gm.go_menu()
	await frames(10)
	_grant_all()
	var order: Array = gm.campaign.order
	var rows := []
	var stuck := []
	var base := metrics("start", {})
	for k in runs:
		var campaign := k % 6 != 5 and force_biome == ""   # every 6th attempt is a Free Run
		var node: String = order[(k * 7) % order.size()] if campaign else ""
		var robot: String = IDS[k % IDS.size()]
		var mk2 := (k / IDS.size()) % 2 == 1
		var action := "continue" if k % 5 == 2 else ("restart" if k % 7 == 3 else "")
		var r := await run_once(k, node, robot, mk2, campaign, action, speed)
		if not r.finished:
			stuck.append(r)
		rows.append(metrics("run", r))
	gm.go_menu()
	await frames(60)
	var end := metrics("end_menu", {})
	if args.has("soak_orphans"):
		print("AT|orphans_begin")
		Node.print_orphan_nodes()
		print("AT|orphans_end")
	# growth analysis: compare runs 5..14 with the last 10 (warm-up excluded)
	var a := rows.slice(5, 15)
	var b := rows.slice(rows.size() - 10)
	var avg := func(lst: Array, key: String) -> float:
		var s := 0.0
		for x in lst:
			s += float(x[key])
		return s / maxf(lst.size(), 1)
	var g := {}
	for key in ["nodes", "orphans", "objects", "resources", "mem_mb", "phys2d", "dynamic", "audio_children", "audio_loops", "audio_cooldowns", "fx", "hazards", "terrain", "timers", "frame_ms_med", "frame_ms_p95"]:
		g[key] = [snappedf(avg.call(a, key), 0.1), snappedf(avg.call(b, key), 0.1)]
	print("AT|soak_growth " + JSON.stringify(g))
	check("soak_all_runs_finish", stuck.is_empty(), "%d / %d unfinished %s" % [stuck.size(), runs, stuck])
	check("soak_no_node_growth", float(g.nodes[1]) <= float(g.nodes[0]) * 1.05 + 50, "%s" % [g.nodes])
	# QA fix guard: BiomeProps used to leave one orphan PropLayer per Zone / empty chunk (54 per Zone level)
	check("soak_no_orphan_growth", float(g.orphans[1]) <= float(g.orphans[0]) + 2, "%s" % [g.orphans])
	check("soak_no_orphans_at_end", int(end.orphans) <= int(base.orphans) + 2, "start %d end %d" % [base.orphans, end.orphans])
	check("soak_no_object_growth", float(g.objects[1]) <= float(g.objects[0]) * 1.05 + 200, "%s" % [g.objects])
	check("soak_no_memory_growth", float(g.mem_mb[1]) <= float(g.mem_mb[0]) * 1.08 + 8, "%s MB" % [g.mem_mb])
	check("soak_no_physics_growth", float(g.phys2d[1]) <= float(g.phys2d[0]) * 1.1 + 5, "%s" % [g.phys2d])
	check("soak_audio_bounded", float(g.audio_children[1]) <= 12 + GameAudio.MAX_LOOPS and float(g.audio_cooldowns[1]) <= 160, "children %s cooldowns %s" % [g.audio_children, g.audio_cooldowns])
	check("soak_no_timer_growth", float(g.timers[1]) <= float(g.timers[0]) + 3, "%s" % [g.timers])
	check("soak_no_frame_time_degradation", float(g.frame_ms_p95[1]) <= float(g.frame_ms_p95[0]) * 1.25 + 1.0, "p95 ms %s" % [g.frame_ms_p95])
	check("soak_menu_returns_clean", int(end.dynamic) <= int(base.dynamic) + 1 and int(end.audio_loops) == 0 and int(end.rivals) == 0,
		"dynamic %d->%d loops %d rivals %d" % [base.dynamic, end.dynamic, end.audio_loops, end.rivals])
	print("AT|tests passed=%d failed=%d" % [passed, failed])
