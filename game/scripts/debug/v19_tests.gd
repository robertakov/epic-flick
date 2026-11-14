extends Node
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const IDS := ["devil","vampire","cowboy","tiger","shark"]
func check(label: String, ok: bool) -> void:
	passed+=int(ok);failed+=int(not ok)
	print("AT|test v19_%s %s"%[label,"PASS" if ok else "FAIL"])
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func run_all(_which: String) -> void:
	at.set("scenario_running",true);at.set("max_time",1.0e9)
	await gallery()
	await idle_animations_test()
	await campaign_map_opponents_test()
	await production()
	await pressure_smoke()
	print("AT|tests passed=%d failed=%d"%[passed,failed])
func gallery() -> void:
	var layer := CanvasLayer.new();layer.layer=100;gm.add_child(layer)
	var bg := ColorRect.new();bg.color=Color(.17,.20,.24);bg.size=Vector2(1280,720);bg.z_index=-100;layer.add_child(bg)
	var title := Label.new();title.position=Vector2(20,15);title.add_theme_font_size_override("font_size",24);layer.add_child(title)
	var robots: Array[RobotController]=[]
	for i in IDS.size():
		var r := gm.build_robot(gm.catalog.get_by_id("tin"),null,null)
		r.freeze=true;r.position=Vector2(128+i*256,330);layer.add_child(r)
		r.set_physics_process(false);r.visual.set_physics_process(false);r.visual.identity.set_process(false)
		var raw := r.visual.rig.raw.duplicate(true)
		var center := r.visual.head.center_local
		var mass_before := r.mass;var inertia_before := r.inertia;var mask := r.collision_mask
		var cap: float = r.visual.legs[&"leg_l"].cap_len;var boot: float = r.visual.legs[&"leg_l"].boot_len
		EnemyAppearance.install(r,IDS[i]);robots.append(r)
		check(IDS[i]+"_physical_parity",raw==r.visual.rig.raw and center==r.visual.head.center_local and mass_before==r.mass and inertia_before==r.inertia and mask==r.collision_mask and cap==r.visual.legs[&"leg_l"].cap_len and boot==r.visual.legs[&"leg_l"].boot_len)
		var label := Label.new();label.text=EnemyRoster.display_name(IDS[i]);label.position=Vector2(55+i*256,585);label.add_theme_font_size_override("font_size",25);layer.add_child(label)
	await frames(3)
	for state in ["idle","compression","release","airborne","fast_rotation","scared","happy"]:
		title.text="v19 enemies — "+state+" (visual fixture)"
		for i in robots.size():
			var r := robots[i];var v := r.visual
			r.rotation=1.7 if state=="fast_rotation" else (-.55 if state=="airborne" else 0.0)
			v.scale=Vector2.ONE*(.75 if state in ["airborne","fast_rotation"] else 1.0)
			v.squash=.32 if state=="compression" else (-.25 if state=="release" else 0.0)
			v.frame.gravity_local=Vector2(0,1800);v.frame.accel_local=Vector2.ZERO;v.frame.w=18 if state=="fast_rotation" else 0;v.frame.alpha=24 if state=="fast_rotation" else 0
			v.head.angle=0;v.head.offset_pos=Vector2.ZERO
			v.head.set_expression(StringName(state if state in ["scared","happy"] else "neutral"),100,7)
			v._apply_squash();v.art_torso._process(0);v.head.video_part._process(0)
			for side in v.legs:
				var l: LegVisual=v.legs[side]
				l.length=l.cfg.coil_min_length if state=="compression" else (l.cfg.coil_max_length if state=="release" else l.cfg.coil_rest_length)
				l.swing=.3 if state=="airborne" else 0.0;l.boot_tilt=0;l._apply()
			for side in v.arms:
				var a: ArmVisual=v.arms[side];a.p=a.exit+a.rest+(Vector2(18,-14) if state=="fast_rotation" else Vector2.ZERO);a._apply()
			v.head.step(0,v.frame);v._sync_art_joints()
			for side in v.arms:
				var a: ArmVisual=v.arms[side]
				check(IDS[i]+"_"+state+"_"+String(side),a.video_part.position.distance_to(v.art_profile.anchor("shoulder_l" if side==&"arm_l" else "shoulder_r",v.art_torso,v.torso))<.001)
			for side in v.legs:
				var l: LegVisual=v.legs[side]
				check(IDS[i]+"_"+state+"_"+String(side),l.video_part.position.distance_to(v.art_profile.anchor("hip_l" if side==&"leg_l" else "hip_r",v.art_torso,v.torso))<.001)
			check(IDS[i]+"_"+state+"_neck",(v.head.transform*v.head.video_part.position).distance_to(v.head.visual_neck)<.001)
		await frames(3);at.call("_shot","v19_assembled_"+state)
	for i in robots.size():
		var v := robots[i].visual
		for side in v.legs:
			var art: VideoRobotPart=v.legs[side].video_part
			art.fit_limb(Vector2.ZERO,Vector2(0,70),art.art_rig.limb_scale(String(side)),.3)
			var width := art.mesh.polygon[-1].distance_to(art.mesh.polygon[-2])
			art.fit_limb(Vector2.ZERO,Vector2(0,180),art.art_rig.limb_scale(String(side)),.3)
			check(IDS[i]+"_"+String(side)+"_rigid_terminal",is_equal_approx(width,art.mesh.polygon[-1].distance_to(art.mesh.polygon[-2])))
		var head := v.head.video_part;var pivot := head.position;var sc := head.scale
		for f in head.frames.size(): head._set_frame(f)
		check(IDS[i]+"_fixed_face_geometry",head.position==pivot and head.scale==sc)
	layer.queue_free();await frames(3)
func production() -> void:
	var seen := {}
	for round_id in EnemyRoster.data().rounds:
		var needs := false
		for slot in EnemyRoster.data().rounds[round_id]:
			if not seen.has(slot.id): needs=true
		if not needs: continue
		gm.mode=&"campaign";gm.node_id=round_id;gm.profile.ensure_campaign_start(round_id);at.call("start_seen_run");await frames(20);gm.hand.playing=false
		check(round_id+"_player_untouched",not gm.robot.visual.has_meta("enemy_identity"))
		for c in gm.race.competitors:
			check(round_id+"_"+c.appearance_id+"_assigned",c.robot.visual.get_meta("enemy_identity","")==c.appearance_id and c.robot.config.robot_id==c.robot_id)
			if seen.has(c.appearance_id): continue
			seen[c.appearance_id]=true;c.ai.set_physics_process(false);c.robot.freeze=true
			var r: RobotController=c.robot;var v := r.visual
			var arm: ArmVisual=v.arms[&"arm_l"];var leg: LegVisual=v.legs[&"leg_l"];var head := v.head
			var info := {"event":98761,"impact":1000.0,"point":r.global_position,"normal":Vector2.UP}
			r._on_limb_lost(&"arm_l",info);await frames(20)
			check(c.appearance_id+"_actual_arm_detach",arm.get_parent() is DetachablePart and arm.video_part is EnemyArtPart)
			r._on_limb_lost(&"leg_l",info);await frames(20)
			check(c.appearance_id+"_actual_leg_detach",leg.get_parent() is DetachablePart and leg.video_part.art_coil!=null)
			r._launch_rocket(info);await frames(20)
			check(c.appearance_id+"_actual_head_launch",head.get_parent() is RocketHead and head.video_part is EnemyArtPart and not head.visual_anchor_enabled)
		gm.go_menu();await frames(3)
	check("all_five_production",seen.size()==5)
	for id in ["r10","r20","r30","r40"]:
		gm.mode=&"campaign";gm.node_id=id;gm.profile.ensure_campaign_start(id);at.call("start_seen_run");await frames(10);gm.hand.playing=false
		for c in gm.race.competitors: check(id+"_boss_preserved",c.appearance_id=="" and not c.pressure and not c.robot.visual.has_meta("enemy_identity"))
		gm.go_menu();await frames(3)
	var cfg := AIConfig.new();var enhanced := EnemyRoster.decision_config(cfg,true)
	check("ordinary_config_identity",EnemyRoster.decision_config(cfg,false)==cfg)
	check("pressure_private_config",enhanced!=cfg and enhanced.angle_error_deg<cfg.angle_error_deg and enhanced.timing_error<cfg.timing_error)
	for prop in cfg.get_property_list():
		var key: String=prop.name
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not EnemyRoster.data().pressure_decisions.has(key):
			check("pressure_preserves_"+key,cfg.get(key)==enhanced.get(key))
func pressure_smoke() -> void:
	# Twelve short real-physics runs. Measures stability and decision activity, not win-rate balance.
	for round_id in ["r5","r24"]:
		for seed in [19001,19002,19003]:
			for pressure in [false,true]:
				gm.mode=&"campaign";gm.node_id=round_id;gm.profile.ensure_campaign_start(round_id);at.call("start_seen_run");await frames(3);gm.hand.playing=false
				var c: RaceManager.Competitor=gm.race.competitors[0]
				c.ai.setup(c.robot,c.control,gm.terrain,EnemyRoster.decision_config(gm.ai_config,pressure),c.skill,18,.5,seed)
				c.ai.configure_band(float(gm.campaign.node(round_id).enemies[0].target_min_distance),float(gm.campaign.node(round_id).enemies[0].target_max_distance),gm.level_config.px_per_meter)
				gm._on_flick(Vector2.ZERO);await frames(300)
				var piece := c.piece()
				check("physics_%s_%d_%s"%[round_id,seed,pressure],piece!=null and is_finite(piece.position.x) and is_finite(piece.position.y) and c.ai.flights>0)
				print("AT|v19_smoke round=%s seed=%d pressure=%s flights=%d distance=%.2f"%[round_id,seed,pressure,c.ai.flights,c.distance])
				gm.go_menu();await frames(3)

func idle_animations_test() -> void:
	var layer := CanvasLayer.new();layer.layer=100;gm.add_child(layer)
	var bg := ColorRect.new();bg.color=Color(.15,.18,.22);bg.size=Vector2(1280,720);bg.z_index=-100;layer.add_child(bg)
	var title := Label.new();title.position=Vector2(20,15);title.add_theme_font_size_override("font_size",24);layer.add_child(title)
	var previews: Array[RobotPreview] = []
	var trajectories := {}
	var sample_times := [0.0, 0.22, 0.44, 0.68, 0.92, 1.18, 1.45]
	for i in IDS.size():
		var id: String = IDS[i]
		var pr := RobotPreview.new()
		pr.position = Vector2(128 + i * 256, 330)
		layer.add_child(pr)
		pr.show_enemy(id, gm.catalog.get_by_id("tin"), gm.robot_config)
		pr.set_process(false)
		previews.append(pr)
		var label := Label.new();label.text=EnemyRoster.display_name(id);label.position=Vector2(55+i*256,585);label.add_theme_font_size_override("font_size",25);layer.add_child(label)
		var samples := []
		var min_y := INF;var max_y := -INF;var min_ang := INF;var max_ang := -INF
		var joints_ok := true
		for t in sample_times:
			var pose := EnemyIdleAnimator.compute_pose(id, float(t))
			pr._layout_enemy(pose)
			min_y = minf(min_y, pose.body_pos.y)
			max_y = maxf(max_y, pose.body_pos.y)
			min_ang = minf(min_ang, float(pose.head_angle))
			max_ang = maxf(max_ang, float(pose.head_angle))
			samples.append(Vector3(pose.body_pos.x, pose.body_pos.y, float(pose.head_angle) * 40.0) + Vector3(pose.arm_l_offset.x, pose.arm_r_offset.y, float(pose.body_rot) * 50.0))
			for side in pr.arms:
				var a: ArmVisual = pr.arms[side]
				if a.video_part.position.distance_to(pr.art_profile.anchor("shoulder_l" if side==&"arm_l" else "shoulder_r", pr.art_torso, pr.torso)) > 0.01:
					joints_ok = false
			for side in pr.legs:
				var L: Dictionary = pr.legs[side]
				var art: VideoRobotPart = L.art
				if art.position.distance_to(pr.art_profile.anchor("hip_l" if side==&"leg_l" else "hip_r", pr.art_torso, pr.torso)) > 0.01:
					joints_ok = false
			if (pr.head.transform * pr.head.video_part.position).distance_to(pr.head.visual_neck) > 0.01:
				joints_ok = false
		trajectories[id] = samples
		check(id + "_idle_motion_active", (max_y - min_y) > 2.5 and (max_ang - min_ang) > 0.04)
		check(id + "_idle_joints_connected", joints_ok)
	for i in IDS.size():
		for j in range(i + 1, IDS.size()):
			var a_samples: Array = trajectories[IDS[i]]
			var b_samples: Array = trajectories[IDS[j]]
			var diff := 0.0
			for k in a_samples.size():
				diff += (a_samples[k] as Vector3).distance_to(b_samples[k] as Vector3)
			check("idle_distinct_%s_vs_%s" % [IDS[i], IDS[j]], diff > 15.0)
	title.text = "v19 enemy idle animations — phase A (t = 0.14s)"
	for i in IDS.size():
		previews[i]._layout_enemy(EnemyIdleAnimator.compute_pose(IDS[i], 0.14))
	await frames(3);at.call("_shot", "v19_idle_phase_a")
	title.text = "v19 enemy idle animations — phase B (t = 0.54s)"
	for i in IDS.size():
		previews[i]._layout_enemy(EnemyIdleAnimator.compute_pose(IDS[i], 0.54))
	await frames(3);at.call("_shot", "v19_idle_phase_b")
	layer.queue_free();await frames(3)

func campaign_map_opponents_test() -> void:
	gm.profile.campaign.completed = ["r1", "r2", "r3", "r4"]
	gm.profile.campaign.unlocked = ["r1", "r2", "r3", "r4", "r5"]
	gm.profile.campaign.claimed = ["r1", "r2", "r3", "r4"]
	gm.profile.campaign.stars = {"r1": [true, true, false], "r2": [true, true, true], "r3": [true, false, false], "r4": [true, true, false]}
	gm.open_campaign_map()
	await frames(6)
	var map := gm.ui.campaign_map
	var mapping_ok := true
	var duo_ok := true
	var boss_ok := true
	for id in gm.campaign.order:
		var opps := map.round_opponents(id)
		var node_enemies: Array = gm.campaign.node(id).get("enemies", [])
		if opps.size() != node_enemies.size():
			mapping_ok = false
		var previews := map.node_previews(id)
		if previews.size() != opps.size():
			mapping_ok = false
		for i in opps.size():
			var slot := EnemyRoster.slot(id, i)
			var expected_eid := String(slot.get("id", ""))
			if String(opps[i].enemy_id) != expected_eid:
				mapping_ok = false
			if previews[i].enemy_id != expected_eid:
				mapping_ok = false
			if expected_eid != "" and String(opps[i].name) != EnemyRoster.display_name(expected_eid):
				mapping_ok = false
		if node_enemies.size() == 2 and previews.size() != 2:
			duo_ok = false
		if gm.campaign.node(id).get("difficulty", "") == "boss" and (not bool(opps[0].boss) or previews[0].enemy_id != ""):
			boss_ok = false
	check("map_all_40_rounds_match_roster", mapping_ok)
	check("map_multi_enemy_rounds_spawn_duos", duo_ok)
	check("map_boss_rounds_preserved", boss_ok)
	map.select_node("r4")
	await frames(4)
	check("map_info_shows_roster_names_r4", map._info_body.text.contains("Тигр") and map._info_body.text.contains("Вампир"))
	map.select_node("r5")
	map.center_on("r3")
	await frames(6)
	at.call("_shot", "v19_map_early")
	gm.profile.campaign.completed = ["r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9"]
	gm.profile.campaign.unlocked = ["r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9", "r10"]
	map.select_node("r10")
	map.center_on("r10")
	await frames(6)
	at.call("_shot", "v19_map_boss_and_duo")
	map.select_node("r27")
	map.center_on("r27")
	await frames(6)
	at.call("_shot", "v19_map_late_sharks")
	gm.go_menu()
	await frames(3)
