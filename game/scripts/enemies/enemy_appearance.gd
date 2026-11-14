class_name EnemyAppearance
extends RefCounted
## Called ONLY for non-boss AI opponents, after their normal physical rig has been built.
static func install(robot: RobotController, enemy_id: String) -> void:
	var visual := robot.visual
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemies/%s/rig.json"%enemy_id))
	var profile := VisualRigProfile.new(visual.rig)
	profile.data=data
	visual.art_profile=profile
	visual.set_meta("enemy_identity",enemy_id)
	visual.material=null
	if visual.art_torso:
		visual.art_torso.hide();visual.art_torso.set_process(false);visual.art_torso.queue_free()
	var body := EnemyArtPart.new();body.configure(visual.rig,profile,"torso",enemy_id)
	visual.torso.texture=null;visual.torso.add_child(body);visual.art_torso=body
	for side in visual.arms:
		var arm: ArmVisual = visual.arms[side]
		if arm.video_part:
			arm.video_part.hide();arm.video_part.set_process(false);arm.video_part.queue_free()
		arm.shoulder.hide();arm.fist.hide();arm.coil.hide()
		var part := EnemyArtPart.new();part.configure(visual.rig,profile,String(side),enemy_id)
		arm.add_child(part);arm.video_part=part
	for side in visual.legs:
		var leg: LegVisual = visual.legs[side]
		if leg.video_part:
			leg.video_part.hide();leg.video_part.set_process(false);leg.video_part.queue_free()
		leg.cap.hide();leg.boot.hide();leg.coil.hide()
		# Leave every existing SpringLeg cap/boot length, socket, collision and mass untouched.
		var part := EnemyArtPart.new();part.configure(visual.rig,profile,String(side),enemy_id)
		leg.add_child(part);leg.video_part=part
	var head := visual.head
	if head.video_part:
		head.video_part.hide();head.video_part.set_process(false);head.video_part.queue_free()
	head.sprite.hide()
	var face := EnemyArtPart.new();face.configure(visual.rig,profile,"head",enemy_id)
	head.add_child(face);head.video_part=face
	visual._sync_art_joints()
