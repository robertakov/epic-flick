class_name EnemyArtPart
extends VideoRobotPart
## Static source-art body modules; only the interior face textures animate.
func configure(rig: RigData, profile: VisualRigProfile, key: String, enemy_id: String) -> void:
	part_name=key;art_rig=profile;geometry=profile.part(key)
	name="Enemy_"+key;centered=false;z_index=int(geometry.z)
	var path := "res://assets/enemies/%s/%s.png"%[enemy_id,key]
	var image := load(path) as Texture2D
	var size := image.get_size()
	if key=="head":
		var face: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemies/%s/face.json"%enemy_id))
		spec=face.duplicate(true);spec.pivot=geometry.pivot;clips=face.clips;fps=float(face.fps)
		size=RigData._v(face.frame_size)
		for i in int(face.count):
			var frame_texture := AtlasTexture.new();frame_texture.atlas=image
			frame_texture.region=Rect2(Vector2(i%int(face.columns),i/int(face.columns))*size,size)
			frames.append(frame_texture)
	else:
		spec={"frame_size":[size.x,size.y],"pivot":geometry.pivot}
		clips={"idle":[0]}
		var frame_texture := AtlasTexture.new();frame_texture.atlas=image;frame_texture.region=Rect2(Vector2.ZERO,size)
		frames.append(frame_texture)
	base_scale=Vector2.ONE*float(geometry.unit_scale)*rig.s/.42
	if key=="torso": base_scale=Vector2.ONE*float(geometry.unit_scale)/.42
	scale=base_scale
	if geometry.has("spring_rows"):
		_build_mesh()
		if art_coil:
			art_coil.visible = false
			var full_quads: Array[PackedInt32Array] = []
			for i in int(source_vertices.size() / 2) - 1:
				full_quads.append(PackedInt32Array([i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2]))
			mesh.polygons = full_quads
	_set_frame(0)
	process_priority=-20
	set_process(key in ["head","torso"])

func sync_scale() -> void:
	var parent := get_parent() as Node2D
	if parent:
		# Counter the legacy rig's decorative squash: armor and the head shell remain rigid.
		var unit := float(geometry.unit_scale)*art_rig.rig.s/.42
		scale=Vector2(unit,unit)/parent.scale

func _process(dt: float) -> void:
	sync_scale()
	if part_name!="head": return
	clock+=dt
	var sequence: Array = clips[clip]
	_set_frame(int(sequence[int(clock*fps)%sequence.size()]))
	# Never scale, translate or rotate the shell in response to a facial frame.

func react(_strength: float, _duration: float) -> void:
	pass # Existing Godot torso squash/head wobble already follows the authoritative rig.
