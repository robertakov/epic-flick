extends Node
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
func check(label: String, ok: bool, detail := "") -> void:
	passed += int(ok)
	failed += int(not ok)
	print("AT|test %s %s %s" % [label,"PASS" if ok else "FAIL",detail])
func run_all(which: String) -> void:
	at.set("scenario_running",true)
	at.set("max_time",1.0e9)
	if which == "springs":
		await springs()
	elif which == "tutorial_layout":
		await tutorial_layout()
	elif which == "tutorial":
		await tutorials()
	elif which == "abandon":
		await abandons()
	elif which == "camera":
		await cameras()
	print("AT|tests passed=%d failed=%d" % [passed,failed])
func springs() -> void:
	# v34 (legit update): release physics are fixed - spring power 200 %, bounce rotation 0 %, auto 0.9 / manual 1.1 rev/s.
	# --pre_v34_physics re-applies the v33 defaults to prove the pinned v33 numbers still reproduce exactly.
	var old_physics := Array(OS.get_cmdline_user_args()).has("--pre_v34_physics")
	if old_physics:
		for kv in [["auto_rps", 0.8], ["manual_rps", 1.0], ["invuln_s", 0.5], ["recovery_s", 0.5], ["bounce_spin", 40.0], ["spring_power", 150.0]]:
			gm.set_setting(kv[0], kv[1])
	check("spring_default",gm.settings.get_value("spring_power")==(150.0 if old_physics else 200.0))
	check("spring_bounds",SettingsStore.sanitize("spring_power",-1)==75 and SettingsStore.sanitize("spring_power",999)==200 and SettingsStore.sanitize("spring_power",123)==125)
	var s := SettingsStore.new("user://test/spring_persistence.json")
	s.set_value("spring_power",135)      # v34: refused - spring power is a fixed release value
	check("spring_save",s.save())
	var loaded := SettingsStore.new(s.path)
	loaded.load_data()
	check("spring_persistence",loaded.get_value("spring_power")==200 and s.get_value("spring_power")==200)
	var constants := [gm.robot_config.torso_mass,gm.contact_config.spring_stiffness,gm.contact_config.bottom_out_stiffness,gm.contact_config.damping_ratio_compress,gm.launch_speed,gm.spin_config.charge_per_rotation,gm.damage_config.max_health,ProjectSettings.get_setting("physics/2d/default_gravity")]
	var outputs := []
	for power in [75,100,120,150,200]:
		gm.set_setting("spring_power",power)
		outputs.append(await bounce(0))
	check("spring_actual_monotonic",outputs[0]>0 and outputs[1]>outputs[0] and outputs[2]>outputs[1] and outputs[3]>outputs[2] and outputs[4]>outputs[3],str(outputs))
	gm.set_setting("spring_power",150)
	var charged: float = await bounce(0.7)
	check("spring_charge_boost",charged>outputs[3],"zero=%.2f charged=%.2f" % [outputs[3],charged])
	var min_floor := gm.contact_config.min_natural_rebound_speed * sqrt(1.5)
	var foot_reach: float = gm.robot._hips[&"leg_l"].y + gm.robot.contacts.legs[0].reach(gm.contact_config)
	var weak_5cm: float = await bounce(0.0, foot_reach + 5.0, Vector2(0, 10))
	var weak_20cm: float = await bounce(0.0, foot_reach + 20.0, Vector2(0, 20))
	var med_drop: float = await bounce(0.0, foot_reach + 140.0, Vector2(0, 50))
	var high_drop: float = await bounce(0.0, 1600.0, Vector2(0, 900))
	var max_norm_cap := gm.contact_config.max_release_normal_speed * sqrt(1.5)
	check("spring_weak_landing_gets_min_rebound", weak_5cm >= min_floor - 1.0 and weak_20cm >= min_floor - 1.0, "5cm=%.2f 20cm=%.2f floor=%.2f" % [weak_5cm, weak_20cm, min_floor])
	check("spring_stronger_landings_scale_above_min", med_drop > weak_5cm + 80.0 and outputs[3] > med_drop + 100.0 and high_drop > outputs[3] + 150.0, "weak=%.2f med=%.2f strong=%.2f high=%.2f" % [weak_5cm, med_drop, outputs[3], high_drop])
	# pinned rebounds: v33 values with --pre_v34_physics; v34 release physics (bounce rotation 0 %, auto 0.9) shift them +0.3 %
	var pin := [840.58, 988.63, 1283.34] if old_physics else [842.93, 991.72, 1285.15]
	check("spring_max_rebound_unchanged", absf(outputs[3] - pin[0]) < 0.1 and absf(outputs[4] - pin[1]) < 0.1 and high_drop <= max_norm_cap + 5.0 and gm.contact_config.max_release_normal_speed == 2050.0 and gm.contact_config.max_release_speed == 2900.0, "strong=%.2f p200=%.2f high=%.2f cap=%.2f" % [outputs[3], outputs[4], high_drop, max_norm_cap])
	check("spring_charged_behavior_unchanged", absf(charged - pin[2]) < 0.1, "charged=%.2f" % charged)
	var controller := SpinChargeController.new()
	controller.cfg=gm.spin_config
	var fast := Vector2(3300,-100)
	var boosted := controller.clamp_out(fast+controller.boost_vector(0.01,Vector2.UP,Vector2.UP,Vector2.RIGHT),Vector2.UP,0.01,gm.contact_config,sqrt(1.5))
	check("spring_charge_cap_cannot_reduce_fast_spring",boosted.length()>=fast.length(),"before=%.2f after=%.2f" % [fast.length(),boosted.length()])
	controller.free()
	check("spring_constants_unchanged",constants==[gm.robot_config.torso_mass,gm.contact_config.spring_stiffness,gm.contact_config.bottom_out_stiffness,gm.contact_config.damping_ratio_compress,gm.launch_speed,gm.spin_config.charge_per_rotation,gm.damage_config.max_health,ProjectSettings.get_setting("physics/2d/default_gravity")])
	gm.go_menu()
func bounce(charge: float, height := 420.0, v0 := Vector2(0, 50)) -> float:
	gm._spawn_robot()
	gm.state = GameManager.State.INTRO
	gm.hand.visible = false
	await get_tree().physics_frame
	var r := gm.robot
	# v32: these locks measure the SPRING system alone; the (approved, separately tested) momentum layer would add a
	# forward push to speed_out on a clean landing
	r.contacts.cfg.momentum_gain = 0.0
	r.global_position = Vector2(-1900,gm.terrain.height_at(-1900)-height)
	r.rotation = 0
	var res := [0.0]
	r.landed.connect(func(i: Dictionary) -> void:
		if res[0]==0 and i.type!=&"soft":
			res[0]=i.speed_out)
	r.launch(v0,0)
	r.rotation_ctl.enabled=false
	r.spin_charge.charge=charge
	for i in 420:
		await get_tree().physics_frame
		if res[0]>0:
			break
	return res[0]

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func cameras() -> void:
	gm.go_menu()
	var c := gm.camera
	var original := DisplayServer.window_get_size()
	for sz in [Vector2i(1920,1200),Vector2i(2340,1080),Vector2i(1920,720),Vector2i(960,540)]:
		DisplayServer.window_set_size(sz)
		await frames(8)
		gm.ui.debug_safe_margins = Vector4(60,20,30,20)
		gm.ui.apply_safe_area()
		c.safe_margins = gm.ui.safe_margins
		var usable := c.usable_size()
		var result := []
		for altitude in [100.0,500.0,1200.0,4000.0]:
			var z := c.responsive_zoom(altitude,usable,Vector2(sz))
			# v34: the whole follow curve is scaled by FRAMING_SCALE (modest zoom-out requested by testers)
			var legacy := maxf(clampf(usable.y*0.82/(altitude+420),c.min_zoom,c.base_zoom) * CameraController.FRAMING_SCALE, c.min_zoom)
			result.append(z)
			check("camera_formula_%d_%d" % [sz.y,int(altitude)], z>=legacy - 0.0001 and z<=c.base_zoom * CameraController.FRAMING_SCALE + 0.0001 and (sz.y<1080 or is_equal_approx(z,legacy)),"legacy=%.3f new=%.3f" % [legacy,z])
		gm.robot.freeze = true
		gm.robot.global_position = Vector2(-1300,gm.terrain.height_at(-1300)-1200)
		c.follow(gm.robot)
		var before := c.zoom.x
		await frames(1)
		check("camera_smooth_%d" % sz.y,absf(c.zoom.x-before)<0.025)
		await frames(240)
		var point := get_viewport().get_canvas_transform()*gm.robot.global_position
		var m := gm.ui.safe_margins
		var rect := Rect2(Vector2(m.x,m.y),usable)
		check("camera_target_safe_%d" % sz.y,rect.grow(-10).has_point(point),str(point))
		if at.get("shots_dir")!="":
			at.call("_shot","camera_%d" % sz.y)
	var vp := get_viewport().get_visible_rect().size
	var big := c.responsive_zoom(4000,vp,Vector2(1920,1080))*1080/vp.y
	var small := c.responsive_zoom(4000,vp,Vector2(960,540))*540/vp.y
	check("camera_small_rendered_readability",small>=big*0.85,"render scale large=%.3f small=%.3f" % [big,small])
	DisplayServer.window_set_size(original)
	gm.ui.debug_safe_margins = Vector4(-1,-1,-1,-1)
	gm.ui.apply_safe_area()
	gm.go_menu()

func abandons() -> void:
	var snapshot := {"coins":gm.profile.coins,"stats":gm.stats.data.duplicate(true),"campaign":gm.profile.campaign.duplicate(true),"adaptive":gm.adaptive.state.duplicate(true)}
	for mode in [&"free", &"campaign"]:
		gm.mode = mode
		gm.node_id = "r1"
		at.call("start_seen_run")
		gm.hand.playing = false
		gm._on_flick(Vector2.ZERO)
		await get_tree().physics_frame
		var old := gm.robot
		gm.camera.shake(20,1)
		gm.abandon_run()
		await frames(3)
		check("abandon_%s_destination" % mode,gm.state==GameManager.State.MENU and (gm.ui.campaign_map.visible if mode==&"campaign" else gm.ui.menu.visible))
		check("abandon_%s_no_rewards_results" % mode,gm.profile.coins==snapshot.coins and gm.stats.data==snapshot.stats and gm.profile.campaign==snapshot.campaign and gm.adaptive.state==snapshot.adaptive)
		check("abandon_%s_cleanup" % mode,not is_instance_valid(old) and gm.race.competitors.is_empty() and gm.race.race_time==0 and gm.star_tracker==null and gm.rocket==null and gm.attempt==null and gm.camera.target==null and gm.camera._shake==0 and not gm.input.holding and Engine.time_scale==1)
		at.call("start_seen_run")
		check("abandon_%s_retry" % mode,gm.state==GameManager.State.INTRO and gm.attempt.duration_s==0 and gm.robot.damage.health==gm.robot.damage.max_health)
		gm.abandon_run()
	gm.mode = &"campaign"
	at.call("start_seen_run")
	# Earn a genuinely completed tracker objective through its distance metric; abandon must retain it.
	gm.star_tracker._m["distance"] = 100000.0
	gm.star_tracker.sample(0.1,100000,gm.robot.global_position.x,false,true,50,false)
	var earned := gm.profile.stars_of("r1").duplicate()
	var coins := gm.profile.coins
	gm.abandon_run()
	check("abandon_immediate_stars",earned.any(func(v: bool) -> bool: return v) and gm.profile.stars_of("r1")==earned and gm.profile.coins==coins)
	gm.mode = &"free"
	gm.go_menu()
	at.call("start_seen_run")
	await frames(3)
	var vp := get_viewport().get_visible_rect().size
	var m := gm.ui.safe_margins
	var safe := Rect2(Vector2(m.x,m.y),vp-Vector2(m.x+m.z,m.y+m.w))
	check("abandon_buttons_safe",safe.encloses(gm.ui.abandon_button.get_global_rect()) and safe.encloses(gm.ui.restart_button.get_global_rect()) and not gm.ui.abandon_button.get_global_rect().intersects(gm.ui.restart_button.get_global_rect()),"menu=%s retry=%s" % [gm.ui.abandon_button.get_global_rect(),gm.ui.restart_button.get_global_rect()])
	gm.go_menu()

## v33: the old tutorial prototype (lessons MANUAL / AUTO / DAMAGE / AIM / ROCKET, air gate, text panels) was replaced
## by the interactive tutorial. Its tests live in v33_tests.gd (--scenario=v33_all --auto_tutorial).
func tutorials() -> void:
	check("tutorial_superseded_by_v33_all", true, "run --scenario=v33_all --auto_tutorial")


func tutorial_layout() -> void:
	check("tutorial_layout_superseded_by_v33_all", true, "run --scenario=v33_qa / v33_all")
