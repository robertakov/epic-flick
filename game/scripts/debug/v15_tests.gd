extends Node
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
class FailingSettings:
	extends SettingsStore
	func save() -> bool: return false
func check(label: String, ok: bool, detail := "") -> void:
	passed+=int(ok); failed+=int(not ok)
	print("AT|test v15_%s %s %s" % [label,"PASS" if ok else "FAIL",detail])
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func run_all(which: String) -> void:
	at.set("scenario_running",true); at.set("max_time",1.0e9)
	if which=="v15_settings": settings()
	elif which=="v15_ui": await presentation()
	elif which=="v15_layout": await layout()
	elif which=="v15_report": report()
	print("AT|tests passed=%d failed=%d" % [passed,failed])
func settings() -> void:
	var expected := {"auto_rps":0.8,"manual_rps":1.0,"invuln_s":0.5,"shake":90,"vibration":70,"flick":200,"spin_accel":0.4,"recovery_s":0.5,"recovery_pct":25,"bounce_spin":40,"spring_power":150}
	var profile_before := FileAccess.get_file_as_bytes(gm.profile.path)
	var path := "user://test/v15_migration_fixture.json"
	var old := {"version":1,"auto_rps":0.5,"manual_rps":1.5,"invuln_s":1,"shake":0,"vibration":5,"flick":110,"spin_accel":0.1,"recovery_s":0.2,"recovery_pct":70,"bounce_spin":90,"spring_power":120,"language":"ru","accessibility":{"contrast":true}}
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(old)); file.close()
	var s := SettingsStore.new(path); s.load_data()
	for k in expected: check("migration_"+k,is_equal_approx(s.get_value(k),float(expected[k])))
	check("version_persisted",JSON.parse_string(FileAccess.get_file_as_string(path)).gameplay_tuning_version==1 and s.last_load_status=="migrated")
	check("unrelated_preserved",s.unrelated.language=="ru" and s.unrelated.accessibility.contrast)
	check("profile_bytes_untouched",profile_before==FileAccess.get_file_as_bytes(gm.profile.path))
	for k in expected: s.set_value(k,float(SettingsStore.SPEC[k][0]))
	s.set_value("spring_power",170); check("post_migration_save",s.save())
	var chosen := s.values.duplicate(true)
	var reload := SettingsStore.new(path); reload.load_data()
	check("idempotent_all_choices",reload.values==chosen and reload.last_load_status=="ok" and reload.get_value("spring_power")==170)
	reload.reset_to_defaults()
	for k in expected: check("reset_"+k,is_equal_approx(reload.get_value(k),float(expected[k])))
	check("spring_range_step",SettingsStore.SPEC.spring_power==[75.0,200.0,5.0,150.0] and SettingsStore.sanitize("spring_power",1000)==200)
	check("reset_preserves_unrelated",reload.unrelated==s.unrelated)
	file=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(old)); file.close()
	var fail := FailingSettings.new(path); fail.load_data()
	check("failure_reported",fail.last_load_status=="migration_save_failed" and fail.values==reload.values)
	check("failed_migration_retryable",not JSON.parse_string(FileAccess.get_file_as_string(path)).has("gameplay_tuning_version"))
	var retry := SettingsStore.new(path); retry.load_data(); check("retry_success",retry.last_load_status=="migrated" and retry.values==reload.values)
	for marker in [0,-1,"legacy",null]:
		old.gameplay_tuning_version=marker; old.version=0
		file=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(old)); file.close()
		var legacy := SettingsStore.new(path); legacy.load_data()
		check("older_marker_"+str(marker),legacy.values==reload.values and legacy.last_load_status=="migrated" and legacy.unrelated==reload.unrelated)

func presentation() -> void:
	gm.profile.tutorial.handled=false
	var snapshot := gm.profile.star_wallet.duplicate(true)
	gm.request_mode(&"campaign")
	check("explicit_tutorial_entry",gm.ui.awareness.visible and gm.ui.awareness.kind=="tutorial" and gm.tutorial==null and not gm.profile.tutorial.handled)
	gm.ui.awareness.skip.pressed.emit(); await frames(3)
	check("conscious_skip",gm.profile.tutorial.handled and gm.tutorial==null and gm.ui.campaign_map.visible and gm.profile.star_wallet==snapshot)
	gm.go_menu(); gm.begin_tutorial(&"settings")
	check("manual_same_entry",gm.ui.awareness.visible and gm.tutorial==null)
	gm.ui.awareness.confirm.pressed.emit(); await frames(3)
	check("explicit_start_practice",gm.tutorial!=null and gm.ui.tutorial_overlay.visible and gm.ui.tutorial_overlay.banner.text.begins_with("ОБУЧЕНИЕ"))
	gm.finish_tutorial(false,true); gm.ui.close_settings(); gm.go_menu()
	gm.mode=&"campaign"; gm.node_id="r1"; gm.profile.ensure_campaign_start("r1"); gm.profile.earn_star("r1",0,15)
	gm.start_run(); await frames(3)
	check("campaign_card_three",gm.ui.awareness.visible and gm.ui.awareness.icons.size()==3 and gm.ui.awareness.descriptions.size()==3)
	check("campaign_owned_visual",gm.ui.awareness.icons[0].gold and not gm.ui.awareness.icons[1].gold and not gm.ui.awareness.icons[2].gold and not gm.ui.awareness.descriptions[0].text.is_empty())
	gm._on_flick(Vector2.ZERO)
	check("launch_waits_for_ack",gm.state==GameManager.State.INTRO and not gm.hand.playing)
	gm.ui.awareness.confirm.pressed.emit()
	check("ack_starts_hand",not gm.ui.awareness.visible and gm.hand.playing)
	gm.hand.playing=false; gm._on_flick(Vector2.ZERO)
	check("ack_can_launch",gm.state==GameManager.State.RUN)
	gm.go_menu()
	var saved_stats := gm.stats.data.duplicate(true)
	var saved_adaptive := gm.adaptive.state.duplicate(true)
	gm.start_run()
	gm._last_back_ms = -100000   # separate physical press (v36.9 Back debounce)
	gm._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check("campaign_card_back_clean",gm.ui.campaign_map.visible and not gm.ui.awareness.visible and gm.tutorial==null and gm.stats.data==saved_stats and gm.adaptive.state==saved_adaptive)
	gm.go_menu()
	gm.begin_tutorial(&"settings")
	gm._last_back_ms = -100000   # separate physical press (v36.9 Back debounce)
	gm._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check("tutorial_card_back_skip",gm.ui.is_settings_open() and not gm.ui.awareness.visible and gm.tutorial==null)
	gm.ui.close_settings(); gm.go_menu()
	var c := gm.ui.campaign_result.ceremony
	gm.ui.campaign_result.visible=true
	c.present([true,false,false],[1,2],13,5)
	check("three_slots_before",c.badges.size()==3 and c.badges[0].gold and not c.badges[1].gold and not c.badges[2].gold and c.counter.text.contains("11/300") and c.counter.text.ends_with("3"))
	await get_tree().create_timer(0.4).timeout
	check("first_new_only",c.animated==[1] and c.badges[1].gold and not c.badges[2].gold)
	await get_tree().create_timer(0.4).timeout
	check("sequential_final",c.animated==[1,2] and c.badges[2].gold and c.complete.text.contains("ВСЕ ИСПЫТАНИЯ") and c.counter.text.contains("13/300") and c.counter.text.ends_with("5"))
	c.present([true,true,true],[],13,3)
	await get_tree().create_timer(0.9).timeout
	check("owned_no_replay",c.animated.is_empty() and c.sequence==null)
	c.present([false,false,false],[0,1,2],16,6)
	gm.ui.campaign_result.visible=false
	await get_tree().create_timer(0.9).timeout
	check("fast_continue_cancels",c.animated.is_empty() and c.sequence==null)
	gm.go_menu()
func layout() -> void:
	var sizes := [Vector2i(960,540),Vector2i(2340,1080),Vector2i(1920,1200)]
	for sz in sizes:
		DisplayServer.window_set_size(sz); await frames(6)
		for cut in [Vector4.ZERO,Vector4(170,20,60,20),Vector4(60,20,170,20)]:
			gm.ui.debug_safe_margins=cut; gm.ui.apply_safe_area()
			var m := gm.ui.safe_margins
			var safe := Rect2(Vector2(m.x,m.y),get_viewport().get_visible_rect().size-Vector2(m.x+m.z,m.y+m.w))
			for id in gm.campaign.order:
				gm.ui.awareness.show_campaign(int(gm.campaign.node(id).round),gm.campaign.node(id).stars,[true,false,false]); await frames(3)
				var errors := []
				for ctl in [gm.ui.awareness.panel,gm.ui.awareness.title,gm.ui.awareness.subtitle,gm.ui.awareness.confirm,gm.ui.awareness.skip]+gm.ui.awareness.descriptions+gm.ui.awareness.icons:
					if not safe.grow(1).encloses(ctl.get_global_rect()): errors.append(str(ctl.get_global_rect()))
				check("card_layout_%d_%d_%s" % [sz.y,int(cut.x),id],errors.is_empty(),str(errors))
				if id in ["r1","r40"] and at.get("shots_dir")!="": at.call("_shot","v15_campaign_%s_%d_%d" % [id,sz.y,int(cut.x)])
			gm.ui.awareness.visible=false
			gm.ui.campaign_result.show_result({"won":true,"title":"Босс: Сёгун Судьбы","player_m":850,"enemies":[{"name":"Генерал Чугун","m":750,"color":Color.BLUE},{"name":"Капитан Комета","m":700,"color":Color.RED}],"coins":1500,"coins_kind":"first","skin_name":"Сёгун","has_next":true,"stars_before":[true,false,false],"stars_new":[1,2],"stars_total":120,"stars_available":100})
			await frames(70)
			var result := gm.ui.campaign_result
			var result_errors := []
			for ctl in [result._panel,result._title,result._reward,result._skin,result.next_button,result.ceremony.counter,result.ceremony.complete]+result.ceremony.badges:
				if not safe.grow(1).encloses(ctl.get_global_rect()): result_errors.append(str(ctl.get_global_rect()))
			check("result_safe_area",result_errors.is_empty(),str(result_errors))
			if at.get("shots_dir")!="": at.call("_shot","v15_result_%d_%d" % [sz.y,int(cut.x)])
			result.visible=false
			gm.ui.awareness.show_tutorial(); await frames(3)
			check("tutorial_card_layout",safe.grow(1).encloses(gm.ui.awareness.panel.get_global_rect()))
			if at.get("shots_dir")!="": at.call("_shot","v15_intro_%d_%d" % [sz.y,int(cut.x)])
	gm.ui.debug_safe_margins=Vector4(-1,-1,-1,-1); gm.ui.apply_safe_area(); gm.go_menu()

func report() -> void:
	var rows: Array=JSON.parse_string(FileAccess.get_file_as_string("G:/Godot/EpicShalban/reports/v15_physics_samples.json"))
	var comparisons := 0
	for id in gm.campaign.order:
		var cs: Array=gm.campaign.node(id).stars
		var by_robot := {}
		for rid in ["tin","hopper","heavy","rocket","samurai"]:
			var counts := [0,0,0,0]
			for row in rows:
				if row.robot!=rid: continue
				var completed := 0
				for j in 3:
					var achieved := StarTracker.evaluate(cs[j],row.metrics)
					counts[j]+=int(achieved); completed+=int(achieved); comparisons+=1
				counts[3]+=int(completed==3)
			by_robot[rid]=counts
		print("AT|v15_objective_rate "+JSON.stringify({"round":id,"challenges":cs,"robot_counts":by_robot,"samples_per_robot":16}))
	check("shared_evaluator_9600",rows.size()==80 and comparisons==9600)
