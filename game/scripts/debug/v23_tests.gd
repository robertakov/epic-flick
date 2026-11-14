extends Node
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const IDS := ["tin","hopper","heavy","rocket","samurai"]  # v27: Samurobot is PNG-modular too
func check(label: String,ok: bool) -> void:
	passed+=int(ok);failed+=int(not ok);print("AT|test v23_%s %s"%[label,"PASS" if ok else "FAIL"])
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func run_all(which: String) -> void:
	at.set("scenario_running",true);at.set("max_time",1.0e9)
	await gallery()
	if which!="v23_gallery": await lifecycle()
	print("AT|tests passed=%d failed=%d"%[passed,failed])
func gallery() -> void:
	var layer := CanvasLayer.new();layer.layer=100;gm.add_child(layer)
	var bg := ColorRect.new();bg.size=Vector2(1280,720);bg.color=Color(.13,.16,.20);bg.z_index=-100;layer.add_child(bg)
	var previews: Array[RobotPreview]=[]
	for i in IDS.size():
		var p := RobotPreview.new();layer.add_child(p);p.show_robot(gm.catalog.get_by_id(IDS[i]),gm.robot_config)
		p.set_process(false);p._layout_player(PlayerIdleAnimator._png_reference_pose(p.def.effective_visual_id(),0,"",0,1))
		var bounds := p.art_bounds();var fit := minf(240.0/bounds.size.x,590.0/bounds.size.y)
		p.scale=Vector2.ONE*fit;p.position=Vector2(128+i*256,345)-bounds.get_center()*fit;previews.append(p)
		var label := Label.new();label.text=p.def.display_name;label.position=Vector2(30+i*256,660);label.add_theme_font_size_override("font_size",26);layer.add_child(label)
		check(IDS[i]+"_png_profile",p.art_profile.data.get("png_modular",false))
	await frames(3);at.call("_shot","v23_gallery_neutral")
	for t in [1.0,2.5,5.0,8.0]:
		for p in previews:
			p._layout_player(PlayerIdleAnimator._png_reference_pose(p.def.effective_visual_id(),t,"",0,1))
		await frames(3);at.call("_shot","v23_gallery_t"+str(t))
	for p in previews:
		# Stretch/rotate springs: rigid shoulders, gloves, boots and Chronobot knees keep their dimensions.
		for part in [p.arms[&"arm_l"].video_part,p.arms[&"arm_r"].video_part,p.legs[&"leg_l"].art,p.legs[&"leg_r"].art]:
			var v: VideoRobotPart=part
			v.fit_limb(v.mesh_start,v.mesh_end+Vector2(12,-9),v.mesh_unit,.35)
			var rigid := true
			for row in range(0,v.source_vertices.size(),2):
				var y: float=v.source_vertices[row].y
				var g: Dictionary=v.geometry
				if y<=g.spring_rows[0] or y>=g.spring_rows[1] or (g.has("rigid_middle_rows") and y>=g.rigid_middle_rows[0] and y<=g.rigid_middle_rows[1]):
					rigid=rigid and absf(v.mesh.polygon[row].distance_to(v.mesh.polygon[row+1])-float(v.spec.frame_size[0])*v.mesh_unit)<.01
			check(p.def.id+"_rigid_"+v.part_name,rigid)
		p._layout_player(PlayerIdleAnimator._png_reference_pose(p.def.effective_visual_id(),0,"",0,1))
		var head := p.head.video_part;var old := head.position;var sc := head.scale
		for i in head.frames.size():head._set_frame(i)
		check(p.def.id+"_fixed_head_frames",head.position==old and head.scale==sc)
		for side in p.arms:
			var arm: ArmVisual=p.arms[side]
			check(p.def.id+"_"+String(side)+"_socket",arm.video_part.position.distance_to(p.art_profile.anchor("shoulder_l" if side==&"arm_l" else "shoulder_r",p.art_torso,p.torso))<.001)
		for side in p.legs:
			var l: VideoRobotPart=p.legs[side].art
			check(p.def.id+"_"+String(side)+"_hip",l.position.distance_to(p.art_profile.anchor("hip_l" if side==&"leg_l" else "hip_r",p.art_torso,p.torso))<.001)
		check(p.def.id+"_neck",(p.head.transform*p.head.video_part.position).distance_to(p.head.visual_neck)<.001)
	layer.queue_free();await frames(3)
	for id in IDS:
		if not gm.profile.owned.has(id):gm.profile.owned.append(id)
		gm.profile.select(id);gm.go_menu();gm._refresh_menu_robot();await frames(55);at.call("_shot","v23_menu_"+id)
		gm.open_robot_select();await frames(55);at.call("_shot","v23_select_"+id)
		check(id+"_real_selection",gm.ui.robot_select.current().id==id)
		gm._close_select();await frames(2)
func lifecycle() -> void:
	for id in ["tin","hopper","heavy","rocket","samurai"]:
		if not gm.profile.owned.has(id):gm.profile.owned.append(id)
		gm.profile.select(id);gm.mode=&"free";at.call("start_seen_run");await frames(5);gm.hand.playing=false
		var r := gm.robot;var v := r.visual;r.freeze=true
		check(id+"_persistent_id",r.config.robot_id==id)
		# v27: Samurobot was rebuilt as a complete PNG-modular master, so all five share the same checks
		if true:
			check(id+"_gameplay_png",v.art_profile.data.get("png_modular",false))
			for side in v.legs:
				var l: LegVisual=v.legs[side];check(id+"_"+String(side)+"_physical_lengths",l.cap_len==l.leg.cap_len and l.boot_len==l.leg.boot_len)
			for amount in [.0,.32,-.25]:
				v.squash=amount;v._apply_squash();v._sync_art_joints()
				check(id+"_rigid_torso_"+str(amount),is_equal_approx(v.torso.scale.x*v.art_torso.scale.x,v.torso.scale.y*v.art_torso.scale.y))
		await frames(3);at.call("_shot","v23_gameplay_"+id)
		r.freeze=false;gm._on_flick(Vector2.ZERO);await frames(90)
		check(id+"_real_motion",is_finite(r.position.x) and is_finite(r.rotation) and r.position.distance_to(gm.robot_start)>10)
		r.freeze=true
		var arm: ArmVisual=v.arms[&"arm_l"];var leg: LegVisual=v.legs[&"leg_l"];var head := v.head
		var info := {"event":9981,"impact":1000.0,"point":r.global_position,"normal":Vector2.UP}
		r._on_limb_lost(&"arm_l",info);await frames(20)
		check(id+"_arm_detach",arm.get_parent() is DetachablePart);at.call("_shot","v23_arm_detach_"+id)
		r._on_limb_lost(&"leg_l",info);await frames(20)
		check(id+"_leg_detach",leg.get_parent() is DetachablePart);at.call("_shot","v23_leg_detach_"+id)
		r._launch_rocket(info);await frames(20)
		check(id+"_head_phase",head.get_parent() is RocketHead and not head.visual_anchor_enabled);at.call("_shot","v23_head_phase_"+id)
		gm.go_menu();await frames(3)
		check(id+"_cleanup",not is_instance_valid(r))
	gm.profile.save();var selected := gm.profile.selected;gm.profile.load_data()
	check("selection_save_reload",gm.profile.selected==selected)
