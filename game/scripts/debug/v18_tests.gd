extends Node
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
func check(label: String, value: bool) -> void:
	passed+=int(value); failed+=int(not value)
	print("AT|test v18_%s %s"%[label,"PASS" if value else "FAIL"])
func total(family: String) -> int: return int(gm.audio.counts.get(family,0))
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func run_all(_which: String) -> void:
	at.scenario_running=true;at.max_time=1e9
	var a := gm.audio
	a.test_silent=true;a.rng.seed=180018
	for id in ["tin","hopper","heavy","rocket","samurai"]:
		check("shared_energy_"+id,a.resolve(id,"energy")=="common/energy")
		check("shared_flight_"+id,a.resolve(id,"flight")=="common/flight")
		var all_slots_ok := true
		for ev in ["launch","spring","body","head","limb","voice","head_launch","rolling"]:
			if a.resolve(id, ev) != id + "/" + ev:
				all_slots_ok = false
		check("identity_"+id, all_slots_ok)
	check("component_override",a.resolve("samurai","body",{"body":{"body":"test/body"}})=="test/body")
	check("component_head_isolated",a.resolve("samurai","head",{"body":{"body":"test/body"}})=="samurai/head")
	check("missing_profile",a.resolve("future","head")=="")
	check("missing_pool",a.choose("missing").is_empty())
	check("missing_asset",a.stream({"path":"res://assets/audio/not_present.ogg"})==null)
	for family in a.bank.banks:
		var clips: Array = a.bank.banks[family]
		for clip in clips: check("asset_"+String(clip.path).get_file(),ResourceLoader.exists(clip.path))
		var previous := ""
		var unique := {}
		var no_repeat := true
		for i in 16:
			var clip := a.choose(family)
			if clips.size()>1: no_repeat=no_repeat and String(clip.path)!=previous
			previous=clip.path;unique[previous]=true
		check("pool_"+family,no_repeat and (unique.size()>1 if clips.size()>1 else unique.size()==1))
	check("cooldown_first",a.accept("fixture",.2))
	check("cooldown_repeat",not a.accept("fixture",.2))
	a.clock+=.3;check("cooldown_resumes",a.accept("fixture",.2))
	for name in GameAudio.COMMON_EVENTS: check("common_"+name,a.bank.banks.has("common/"+name))
	var button := Button.new();button.text="НАЗАД"
	check("back_route",a.ui_event(button)=="back")
	button.text="КУПИТЬ";check("purchase_not_generic",a.ui_event(button)=="")
	button.set_meta("audio_event","browse");check("browse_route",a.ui_event(button)=="browse")
	button.free()
	check("ui_bound_once",gm.ui.robot_select._left.get_meta("audio_bound",false))
	gm.profile.owned.append("samurai");gm.profile.selected="samurai"
	# v37 (legit update): Samurobot now has its own RobotSoundSet (tested in v37_audio_tests); these adapter checks
	# exercise the v27 bank-profile path that the other four robots still use, so this robot is built without the set
	RobotSoundSet.debug_disabled=true
	at.start_seen_run();await frames(5)
	RobotSoundSet.debug_disabled=false
	gm.hand.playing=false
	gm._on_flick(Vector2.ZERO)
	await frames(3)
	gm.robot.freeze=true
	var r := gm.robot
	var feedback := r.get_node("AudioFeedback") as RobotAudioFeedback
	check("actual_launch",total("samurai/launch")==1)
	check("profile_actual_samurai",feedback.robot_id=="samurai")
	await frames(4);check("launch_one_shot",total("samurai/launch")==1)
	r.landed.emit({"type":"both","quality":"sweet","impact":1200})
	r.landed.emit({"type":"both","quality":"sweet","impact":1200})
	check("feet_dedup",total("samurai/spring")==1)
	feedback.landing({"type":"body","impact":1200})
	check("bad_no_spring",total("samurai/spring")==1)
	feedback.impact({"kind":"torso","impact":1200});feedback.impact({"kind":"head","impact":900})
	await frames(2)
	check("head_priority",total("samurai/head")==1 and total("samurai/body")==0)
	var part := RigidBody2D.new();gm.dynamic.add_child(part)
	feedback.limb(&"arm_l",part);feedback.limb(&"arm_l",part)
	check("limb_unique",total("samurai/limb")==1)
	part.queue_free()
	check("charge_cadence",feedback.charge_interval(.1)>feedback.charge_interval(.9) and feedback.charge_interval(1)>.3)
	check("rolling_airborne_initial",feedback.rolling_strength(false,500,false,false,.04)==0)
	check("rolling_contact_debounce",feedback.rolling_strength(true,500,false,false,.02)==0)
	check("rolling_contact_resume",feedback.rolling_strength(true,500,false,false,.06)>0)
	check("rolling_contact_grace",feedback.rolling_strength(false,500,false,false,.03)>0)
	check("rolling_airborne_fade",feedback.rolling_strength(false,500,false,false,.12)==0)
	check("rolling_rest",feedback.rolling_strength(true,10,false,false,.2)==0)
	check("rolling_burning",feedback.rolling_strength(true,500,true,false,.2)==0)
	check("rolling_done",feedback.rolling_strength(true,500,false,true,.2)==0)
	var low := a.choose("common/energy",.1)
	check("charge_intensity",float(low.tier)<=.4)
	var energy_before := total("common/energy")
	feedback.discharge(.9);await get_tree().create_timer(.05,true,false,true).timeout
	check("discharge_two_layers",total("common/energy")==energy_before+2)
	# v27 Wilhelm: 30 m above the local ground, ONE 10% roll per crossing, re-arm only below 20 m (hysteresis)
	var ppm := gm.level_config.px_per_meter
	feedback.wilhelm.reset();feedback.launched=true
	check("wilhelm_player_only",feedback.is_player)
	check("wilhelm_constants",is_equal_approx(WilhelmTrigger.HEIGHT_M,30.0) and is_equal_approx(WilhelmTrigger.PROBABILITY,0.07)
		and is_equal_approx(feedback.wilhelm.height_m,30.0) and is_equal_approx(feedback.wilhelm.probability,0.07) and WilhelmTrigger.REARM_M<30.0)
	var rolls := feedback.wilhelm.rolls
	feedback.wilhelm_step(29.5*ppm)
	check("wilhelm_below",feedback.wilhelm.rolls==rolls)
	for i in 600:   # five seconds above the threshold at 120 Hz
		feedback.wilhelm_step((30.0+float(i%40))*ppm)
	check("wilhelm_not_every_frame",feedback.wilhelm.rolls==rolls+1)
	for alt in [26.0,22.0,31.0,29.0,35.0]:   # a dip that stays above 20 m is the same jump: no new roll
		feedback.wilhelm_step(alt*ppm)
	check("wilhelm_hysteresis",feedback.wilhelm.rolls==rolls+1)
	feedback.wilhelm_step(12.0*ppm);feedback.wilhelm_step(31.0*ppm)
	check("wilhelm_reset_after_descent",feedback.wilhelm.rolls==rolls+2)
	# statistics of the roll itself (private RNG): 10% over many separate jumps
	var t := WilhelmTrigger.new();var rng := RandomNumberGenerator.new();rng.seed=27
	for i in 4000:
		t.step(31.0,rng);t.step(5.0,rng)
	check("wilhelm_seven_percent",t.rolls==4000 and absf(t.screams/4000.0-0.07)<0.015)   # v36: 5% -> 7%
	# forced scream plays the authentic asset; physics state is never touched by the trigger
	var r_pos := r.global_position;var r_vel := r.linear_velocity;var r_rot := r.rotation;var r_w := r.angular_velocity
	feedback.wilhelm.probability=1.0;feedback.wilhelm.reset()
	var screams := total("common/wilhelm")
	check("wilhelm_immediate",feedback.wilhelm_step(31.0*ppm) and total("common/wilhelm")==screams+1)
	check("wilhelm_no_physics",r.global_position==r_pos and r.linear_velocity==r_vel and r.rotation==r_rot and r.angular_velocity==r_w)
	feedback.wilhelm.probability=WilhelmTrigger.PROBABILITY
	var src := FileAccess.get_file_as_string("res://scripts/audio/wilhelm_trigger.gd")+FileAccess.get_file_as_string("res://scripts/audio/robot_audio_feedback.gd")
	check("wilhelm_source_readonly",not ["linear_velocity =","global_position =","angular_velocity =","apply_impulse","apply_force","gravity_scale ="].any(func(s: String) -> bool: return src.contains(s)))
	var wb: Array=a.bank.banks.get("common/wilhelm",[])
	check("wilhelm_asset_present",wb.size()>=1 and wb.all(func(c: Dictionary) -> bool: return ResourceLoader.exists(String(c.path))))
	a.loop_target("test_loop","common/flight",.8,r.global_position)
	check("loop_started",a.loops.has("test_loop"))
	a.loop_target("test_loop","common/flight",0,r.global_position)
	a._process(.5)
	check("loop_faded",not a.loops.has("test_loop"))
	check("bounded_players",a.voices.size()==12 and a.cache.size()<=16)
	a.set_volume(0);check("sfx_mute",AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	a.set_volume(75)
	gm.ui.sfx_slider.value=40
	check("settings_sfx_saved",float(gm.settings.unrelated.sfx_volume)==40)
	var settings := SettingsStore.new(gm.settings.path); settings.load_data()
	check("settings_sfx_reload",float(settings.unrelated.sfx_volume)==40)
	gm.ui.show_settings_page(2);gm.ui.open_settings();await frames(3)
	# v34: release physics are fixed - the Settings page has no physics sliders at all (legit test update)
	check("audio_tab_visible",gm.ui.sfx_row.is_visible_in_tree() and not gm.ui._sliders.has("auto_rps"))
	gm.ui.close_settings();gm.ui.show_settings_page(0)
	# Real detachment/rocket transition; controller physics and ownership are unchanged.
	r.freeze=false;r._launch_rocket({})
	await frames(3)
	check("head_launch_actual",total("samurai/head_launch")==1)
	if is_instance_valid(feedback.head):
		feedback.head_launch(feedback.head)
		check("head_launch_one_shot",total("samurai/head_launch")==1)
		feedback.head.burning=true;feedback.head.done=false
		feedback._process(.1)
		check("flight_burning",a.loops.has(feedback.owner_key+"flight"))
		feedback.head.burning=false;feedback._process(.1);a._process(.5)
		check("flight_end",not a.loops.has(feedback.owner_key+"flight"))
	else: check("head_exists",false)
	gm.go_menu();await frames(3)
	check("cleanup",a.loops.is_empty())
	gm.mode=&"campaign";gm.node_id="r1";gm.profile.ensure_campaign_start("r1")
	at.start_seen_run();await frames(3);gm.hand.playing=false
	var stars := total("common/star");var all_stars := total("common/all_stars")
	for i in 3:
		a.clock+=.2;gm._earn_star(i)
	check("new_stars_real",total("common/star")==stars+2 and total("common/all_stars")==all_stars+1)
	a.clock+=.2;gm._earn_star(2)
	check("owned_star_silent",total("common/star")==stars+2 and total("common/all_stars")==all_stars+1)
	gm.go_menu();await frames(3)
	gm.profile.coins=100000
	var purchases := total("common/purchase")
	gm._on_buy("heavy")
	check("purchase_real",total("common/purchase")==purchases+1)
	gm._on_buy("heavy")
	check("purchase_not_owned_repeat",total("common/purchase")==purchases+1)
	gm.open_robot_select();a.clock+=.2
	var browse := total("common/browse");gm.ui.robot_select._left.pressed.emit()
	check("browse_once_real",total("common/browse")==browse+1)
	gm._close_select()
	for size in [Vector2i(960,540),Vector2i(2340,1080),Vector2i(1920,1200)]:
		DisplayServer.window_set_size(size);await frames(6)
		for margins in [Vector4.ZERO,Vector4(170,20,60,20),Vector4(60,20,170,20)]:
			gm.ui.debug_safe_margins=margins;gm.ui.apply_safe_area()
			gm.ui.open_settings();gm.ui.show_settings_page(2);await frames(6)
			var m := gm.ui.safe_margins
			var safe := Rect2(Vector2(m.x,m.y),get_viewport().get_visible_rect().size-Vector2(m.x+m.z,m.y+m.w))
			check("sfx_layout_%d_%d"%[size.y,int(margins.x)],safe.grow(1).encloses(gm.ui.sfx_slider.get_global_rect()) and gm.ui.sfx_slider.get_global_rect().size.y>=44)
			gm.ui.close_settings()
	gm.ui.debug_safe_margins=Vector4(-1,-1,-1,-1);gm.ui.apply_safe_area();gm.ui.show_settings_page(0)
	# Exercise the real player/decoder once; automated regressions otherwise stay quiet.
	a.test_silent=false;a.clock+=1
	a.play("common/click",1,"decoder_smoke",0,"UI")
	# v27 bank = 16-bit WAV masters imported as QOA (AudioStreamWAV); the real decoder must be playing it
	check("real_player_decoder",a.voices.any(func(p: AudioStreamPlayer) -> bool: return p.playing and p.stream is AudioStreamWAV))
	a.test_silent=true
	print("AT|tests passed=%d failed=%d"%[passed,failed])
