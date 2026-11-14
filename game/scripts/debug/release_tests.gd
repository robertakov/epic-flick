extends Node
## Offline-only release validation and real physics distribution measurements. Never exported.
var gm: GameManager
var at: Node
var passed := 0
var failed := 0

func check(label: String, ok: bool, detail := "") -> void:
	passed += int(ok)
	failed += int(not ok)
	print("AT|test %s %s %s" % [label, "PASS" if ok else "FAIL", detail])

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func run_all(which: String) -> void:
	at.set("scenario_running", true)
	at.set("max_time", 1.0e9)
	if which == "campaign_distribution":
		await distribution()
	elif which == "ai_bands":
		await ai_band_tests()
	elif which == "feedback":
		await feedback_tests()
	elif which == "menu_layout":
		await menu_layout()
	print("AT|tests passed=%d failed=%d" % [passed, failed])

func menu_layout() -> void:
	gm.go_menu()
	var sizes := [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2340,1080), Vector2i(2400,1080), Vector2i(2520,1080), Vector2i(960,540), Vector2i(1920,1200)]
	for sz in sizes:
		for cut in [Vector4.ZERO, Vector4(90,20,34,20), Vector4(34,20,90,20), Vector4(170,20,60,20)]:
			DisplayServer.window_set_size(sz)
			await frames(6)
			gm.ui.debug_safe_margins = cut
			gm.ui.apply_safe_area()
			await frames(6)
			var vp := get_viewport().get_visible_rect().size
			var m := gm.ui.safe_margins
			var usable := Rect2(Vector2(m.x,m.y), vp - Vector2(m.x+m.z,m.y+m.w))
			var errors := []
			if gm.ui.menu_content != null:
				if not usable.grow(1).encloses(gm.ui.menu_content.get_global_rect()):
					errors.append("menu panel outside usable viewport")
				for ctl in gm.ui.menu_content.get_children():
					if ctl is Label and not usable.grow(1).encloses(ctl.get_global_rect()):
						errors.append("menu label outside usable viewport: " + ctl.text)
			var buttons := []
			for b in gm.ui._buttons:
				if b.is_visible_in_tree() and b.text in ["КАМПАНИЯ","СВОБОДНЫЙ ЗАБЕГ","СТАТИСТИКА","НАСТРОЙКИ"]:
					buttons.append(b)
					if not usable.grow(1).encloses(b.get_global_rect()):
						errors.append(b.text + " outside usable viewport")
					if b.size.x < 88 or b.size.y < 88 or not is_equal_approx(b.size.x, b.size.y) or b.get_theme_font_size("font_size") < 30:
						errors.append(b.text + " invalid circular size")
					if b.get_minimum_size().x > b.size.x+1:
						errors.append(b.text + " text clipped")
			for i in buttons.size():
				for j in range(i+1,buttons.size()):
					if buttons[i].get_global_rect().grow(-1).intersects(buttons[j].get_global_rect().grow(-1)):
						errors.append("buttons overlap")
			for i in range(gm.ui.menu_buttons.size() - 1):
				var c0 := gm.ui.menu_buttons[i].get_global_rect().get_center()
				var c1 := gm.ui.menu_buttons[i + 1].get_global_rect().get_center()
				if not (c0.x < c1.x and c0.y < c1.y):
					errors.append("buttons not descending diagonally")
			check("menu_%dx%d_%d" % [sz.x,sz.y,int(cut.x)], buttons.size()==4 and errors.is_empty(), "vp=%s safe=%s errors=%s" % [vp,m,errors])
			if at.get("shots_dir") != "":
				at.call("_shot", "menu_%dx%d_%d" % [sz.x,sz.y,int(cut.x)])
	gm.ui.debug_safe_margins = Vector4(-1,-1,-1,-1)
	gm.ui.apply_safe_area()

func distribution() -> void:
	var args: Dictionary = at.get("args")
	var first := int(args.get("round_first",1))
	var last := int(args.get("round_last",40))
	var count := int(args.get("samples",20))
	var seed_base := int(args.get("seed_base",61000))
	var mod := float(args.get("skill_mod",0))
	var total := 0
	gm.mode = &"campaign"
	for sample in count:
		for round_num in range(first,last+1):
			gm.state = GameManager.State.MENU
			gm._clear_dynamic()
			gm.track_seed = seed_base + sample*17
			gm.terrain.reset(gm.track_seed)
			gm._spawn_robot()
			gm.robot.visible = false
			gm.hand.visible = false
			var enemies: Array = gm.campaign.node("r%d" % round_num).enemies.duplicate(true)
			for e in enemies:
				for parameter in ["lean","greed","skill"]:
					if args.has(parameter+"_override"): e[parameter]=float(args[parameter+"_override"])
			if args.has("without_bands"):
				for e in enemies:
					e.erase("target_min_distance")
					e.erase("target_max_distance")
			gm.race.spawn(enemies,mod,gm.track_seed,gm.ai_config)
			# Reset only the AI RNG through its existing setup; paired before/after samples.
			for c in gm.race.competitors:
				var ai_seed := hash([gm.track_seed,round_num,c.index,9147])
				c.ai.setup(c.robot,c.control,gm.terrain,gm.ai_config,c.skill,float(enemies[c.index].lean),float(enemies[c.index].greed),ai_seed)
				if args.has("ai_perf"):
					c.ai.profile_plans = true
			await get_tree().physics_frame
			gm.race.launch(Vector2.RIGHT.rotated(-deg_to_rad(gm.launch_angle))*gm.launch_speed*gm.settings.get_value("flick")/100.0,gm.robot_config.clockwise_rotation_speed*TAU)
			var t := 0.0
			while not gm.race.all_finished() and t < 260:
				await get_tree().physics_frame
				t += 1.0/120.0
				var mx := gm.race.max_x()
				if is_finite(mx):
					var mn := gm.race.min_running_x()
					gm.terrain.ensure_ahead(mx,mn if is_finite(mn) else -INF)
				gm.race.step(1.0/120.0)
			for c in gm.race.competitors:
				total += 1
				print("AT|distribution " + JSON.stringify({"round":round_num,"index":c.index,"robot":c.robot_id,"base_skill":c.base_skill,"skill":c.skill,"form":c.ai.form,"seed":gm.track_seed,"distance":c.distance,"reason":c.reason,"flights":c.ai.flights,"blunders":c.ai.blunders,"elapsed":t,"plan_usec":c.ai.plan_usec,"plan_calls":c.ai.plan_calls}))
			gm.race.clear()
			gm._clear_dynamic()
			await frames(2)
	check("distribution_complete",total>0,"runs=%d" % total)


func feedback_tests() -> void:
	var path := "user://test/v12_feedback_settings.json"
	var f := FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify({"version":SettingsStore.VERSION,"gameplay_tuning_version":SettingsStore.GAMEPLAY_TUNING_VERSION,"shake":0,"flick":125,"manual_rps":0.85,"bounce_spin":45}))
	f.close()
	var store := SettingsStore.new(path)
	store.load_data()
	check("vibration_old_settings_additive_default",store.get_value("vibration")==70 and store.get_value("shake")==0 and store.get_value("flick")==125 and is_equal_approx(store.get_value("manual_rps"),0.85) and store.get_value("bounce_spin")==45)
	store.set_value("vibration",35)
	check("vibration_settings_saved",store.save())
	var reload := SettingsStore.new(path)
	reload.load_data()
	check("vibration_persists",reload.get_value("vibration")==35 and reload.get_value("shake")==0)
	check("vibration_invalid_clamped",SettingsStore.sanitize("vibration",-5)==0 and SettingsStore.sanitize("vibration",150)==100 and SettingsStore.sanitize("vibration",NAN)==70)
	var k := HapticFeedback.strengths(0.8,0,0.7)
	check("shake_zero_vibration_active",k.x==0 and is_equal_approx(k.y,0.56))
	k = HapticFeedback.strengths(0.8,0.6,0)
	check("vibration_zero_shake_active",is_equal_approx(k.x,0.48) and k.y==0)
	check("vibration_recipe_off",HapticFeedback.recipe(1,0).duration_ms==0)
	var weak := HapticFeedback.recipe(0.1,0.7)
	var strong := HapticFeedback.recipe(1,0.7)
	check("vibration_short_scaled_pulses",weak.duration_ms>=12 and strong.duration_ms<=70 and weak.duration_ms<strong.duration_ms and weak.amplitude<strong.amplitude)
	var h := HapticFeedback.new()
	add_child(h)
	h.set_process(false)
	var sent := [0]
	h.pulse_sent.connect(func(_d:int,_a:float)->void: sent[0]+=1)
	h.submit(0.2,1000)
	h.submit(1,1010)
	check("vibration_waits_merges_burst",h.flush(1020).is_empty())
	var pulse := h.flush(1030)
	check("vibration_strongest_single_pulse",not pulse.is_empty() and is_equal_approx(pulse.amplitude,0.7) and h.flush(1031).is_empty())
	h.submit(1,1040)
	check("vibration_rate_limit",h.flush(1070).is_empty())
	h.submit(1,1200)
	h.vibration_scale=0
	check("vibration_disabled_pending_cancelled",h.flush(1230).is_empty())
	check("vibration_unsupported_no_os_call",HapticFeedback.supported() or sent[0]==0,"platform=%s supported=%s" % [OS.get_name(),HapticFeedback.supported()])
	var fx := Fx.new()
	add_child(fx)
	var events := []
	fx.physical_feedback.connect(func(k:float)->void: events.append(k))
	fx.shake(38,0.2)
	check("visual_shake_does_not_vibrate",events.is_empty())
	var info := {"impact":300.0,"point":Vector2.ZERO,"normal":Vector2.UP,"time":7391}
	fx.spring_touchdown(info)
	for i in 20:
		fx.spring_touchdown(info)
	check("same_continuous_contact_not_repeated",events.size()==1)
	info.time=7392
	fx.spring_touchdown(info)
	check("new_contact_generates_feedback",events.size()==2)
	fx.impact_feedback(38,0.6)
	check("shared_intensity_normalized",events.back()==1 and events.all(func(v:float)->bool:return v>=0 and v<=1))
	gm.set_setting("shake",0)
	gm.set_setting("vibration",70)
	check("live_settings_independent",gm.camera.shake_scale==0 and gm.haptics.vibration_scale==0.7 and gm.ui._sliders.vibration.value==70)
	gm.set_setting("vibration",0)
	gm.set_setting("shake",60)
	check("live_vibration_zero",gm.haptics.vibration_scale==0 and gm.camera.shake_scale==0.6)
	gm.reset_settings()
	gm.haptics.submit(1,10000)
	gm.notification(NOTIFICATION_APPLICATION_PAUSED)
	gm.notification(NOTIFICATION_APPLICATION_RESUMED)
	check("pause_discards_stale_haptics",gm.haptics.flush(10030).is_empty())
	var methods := Input.get_method_list().filter(func(m:Dictionary)->bool:return m.name=="vibrate_handheld")
	check("engine_supports_amplitude_api",methods.size()==1 and methods[0].args.size()==2,"engine=%s" % Engine.get_version_info().string)
	h.queue_free()
	fx.queue_free()
	await frames(2)

func ai_band_tests() -> void:
	var errors := []
	var opponents := 0
	for id in gm.campaign.order:
		for e in gm.campaign.node(id).enemies:
			opponents += 1
			if not e.has("target_min_distance") or not e.has("target_max_distance") or e.target_min_distance<=0 or e.target_max_distance<=e.target_min_distance:
				errors.append(id)
	check("all_40_rounds_48_opponents_load_bands",opponents==48 and errors.is_empty() and gm.campaign.load_error=="",str(errors))
	var fixture := CampaignData.new()
	fixture.from_dict({"nodes":[{"id":"two","enemies":[{"target_min_distance":100,"target_max_distance":200},{"target_min_distance":130,"target_max_distance":220}]}]})
	check("two_opponents_own_ranges",fixture.load_error=="" and fixture.node("two").enemies[0].target_min_distance==100 and fixture.node("two").enemies[1].target_min_distance==130)
	for bad in [{"target_min_distance":-1,"target_max_distance":100},{"target_min_distance":100,"target_max_distance":50},{"target_min_distance":10},{"target_min_distance":"100","target_max_distance":200}]:
		fixture = CampaignData.new()
		fixture.from_dict({"nodes":[{"id":"bad","enemies":[bad]}]})
		check("invalid_range_rejected_%d" % passed,fixture.load_error!="")
	var before := EnemyAI.band_weights(0,100,200)
	var inside := EnemyAI.band_weights(150,100,200)
	var after := EnemyAI.band_weights(1000,100,200)
	check("bands_before_inside_after",before==Vector2(1,0) and inside==Vector2.ZERO and after==Vector2(0,1))
	check("legacy_without_bands_normal",EnemyAI.band_weights(0,0,0)==Vector2.ZERO)
	var smooth := true
	var prev := before
	for i in 1000:
		var w := EnemyAI.band_weights(i*0.5,100,200)
		smooth = smooth and w.x<=prev.x+0.0001 and w.y>=prev.y-0.0001 and w.distance_to(prev)<0.03
		prev=w
	check("band_curves_smooth_monotonic_bounded",smooth and before.x==1 and after.y==1)
	var r := gm.build_robot(gm.catalog.get_by_id("samurai"),gm.input,null,"samurai_default")
	gm.dynamic.add_child(r)
	var ai := EnemyAI.new()
	ai.setup(r,gm.input,gm.terrain,gm.ai_config,0.7,18,0.6,71819)
	ai.configure_band(100,200,100)
	ai._protect=1
	var lower := []
	var higher := []
	for d in [0,90,150,210,300]:
		var w := EnemyAI.band_weights(d,100,200)
		ai._protect=w.x
		ai._fatigue=w.y
		ai.skill=0.7-gm.adaptive_config.max_down
		lower.append(ai.eff_skill())
		ai.skill=0.7+gm.adaptive_config.max_up
		higher.append(ai.eff_skill())
	var ordered := true
	for i in lower.size():
		ordered = ordered and lower[i]<higher[i] and lower[i]>=0 and higher[i]<=1
	check("adaptive_remains_bounded_and_effective",ordered,"low=%s high=%s" % [lower,higher])
	var ai2 := EnemyAI.new()
	ai.setup(r,gm.input,gm.terrain,gm.ai_config,0.7,18,0.6,71819)
	ai2.setup(r,gm.input,gm.terrain,gm.ai_config,0.7,18,0.6,71819)
	ai._protect=1
	ai._fatigue=0
	ai2._protect=1
	ai2._fatigue=0
	var same := ai.form==ai2.form
	for i in 40:
		ai._new_flight()
		ai2._new_flight()
		same = same and ai._lean_err==ai2._lean_err and ai._tau_bias==ai2._tau_bias and ai._blunder==ai2._blunder and ai._greedy==ai2._greedy
	check("ai_equal_seeds_equal_decisions",same)
	var src := FileAccess.get_file_as_string("res://scripts/ai/enemy_ai.gd")
	var forbidden := []
	for property in ["position","global_position","linear_velocity","angular_velocity","rotation","global_rotation","gravity_scale","health","mass"]:
		var regex := RegEx.new()
		regex.compile("robot\\."+property+"\\s*[+*/-]?=(?!=)")
		if regex.search(src):
			forbidden.append(property)
	check("stabilized_ai_input_only_no_physics_writes",forbidden.is_empty(),str(forbidden))
	var initial_position := r.global_position
	var initial_velocity := r.linear_velocity
	var initial_hp := r.damage.health
	var tick := Time.get_ticks_usec()
	var checksum := 0.0
	for i in 100000:
		checksum += EnemyAI.band_weights(float(i % 1000),100,200).x
	var micros := Time.get_ticks_usec()-tick
	check("band_scalars_100k_under_500ms",micros<500000 and checksum>0,"100k=%dus" % micros)
	check("quality_queries_leave_body_unchanged",r.global_position==initial_position and r.linear_velocity==initial_velocity and r.damage.health==initial_hp)
	ai.free()
	ai2.free()
	r.queue_free()
	gm.mode=&"campaign"
	gm.node_id="r8"
	gm.profile.ensure_campaign_start("r8")
	at.call("start_seen_run")
	await frames(2)
	var applied := gm.race.competitors.size()==2
	for c in gm.race.competitors:
		var e:Dictionary=gm.campaign.node("r8").enemies[c.index]
		applied = applied and c.ai.band_min_m==e.target_min_distance and c.ai.band_max_m==e.target_max_distance
	check("race_spawns_each_configured_band",applied)
	gm.go_menu()
