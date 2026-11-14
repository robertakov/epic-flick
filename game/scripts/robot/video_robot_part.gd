class_name VideoRobotPart
extends Sprite2D
## Shared atlas player. Limb meshes deform only the spring; connector and terminal stay rigid.
var spec: Dictionary = {}
var clips: Dictionary = {}
var clip := "idle"
var fps := 10.0
var clock := 0.0
var frames: Array[AtlasTexture] = []
var base_scale := Vector2.ONE
var personality: RobotIdentityProfile
var response := 0.0
var response_time := 0.0
var part_name := ""
var art_rig: VisualRigProfile
var geometry: Dictionary = {}
var art_coil: SpringCoil
var mesh: Polygon2D
var source_vertices := PackedVector2Array()
var mesh_start := Vector2.ZERO
var mesh_end := Vector2.ZERO
var mesh_unit := 1.0
var terminal_rotation := 0.0
var frame_index := -1

func setup(rig: RigData, part: String) -> bool:
	if not rig.art.has("parts") or not rig.art.parts.has(part):
		return false
	part_name = part
	spec = rig.art.parts[part]
	clips = spec.clips
	fps = float(rig.art.fps)
	personality = RobotIdentityProfile.for_robot(rig.robot_id)
	art_rig = VisualRigProfile.new(rig)
	geometry = art_rig.part(part)
	centered = false
	offset = -RigData._v(geometry.get("pivot", spec.pivot))
	var size := RigData._v(spec.frame_size)
	for i in int(spec.count):
		var t := AtlasTexture.new()
		t.atlas = RobotArtLibrary.atlas(rig.visual_id, part)   # v35: by visual id (base -> base dir, MK2 -> <id>_mk2)
		t.region = Rect2(Vector2(i % int(spec.columns), i / int(spec.columns)) * size, size)
		frames.append(t)
	if part == "head":
		base_scale = Vector2.ONE * rig.s * 254.0 / maxf(size.y - 12.0, 1.0)
		if art_rig.enabled():
			base_scale *= RigData._v(art_rig.data.head_scale)
	elif part == "torso":
		process_priority = -10
		base_scale = Vector2.ONE * 262.0 / size.x
		if art_rig.enabled():
			base_scale *= RigData._v(art_rig.data.torso_scale)
			position = RigData._v(art_rig.data.torso_offset)
	if art_rig.data.get("png_modular",false):
		var unit := float(geometry.unit_scale)*rig.s/.42
		if part=="torso":
			base_scale=Vector2.ONE*unit/rig.s
		elif part=="head":
			base_scale=Vector2.ONE*unit
		if part=="torso" and art_rig.data.has("tail"):
			var detail := Sprite2D.new()
			detail.name="SourceTail";detail.centered=false
			detail.texture=RobotArtLibrary.atlas(rig.visual_id,"tail")
			detail.position=RigData._v(art_rig.data.tail.offset)-RigData._v(geometry.pivot)
			detail.z_index=int(art_rig.data.tail.z);detail.use_parent_material=true
			add_child(detail)
	scale = base_scale
	z_index = int(geometry.get("z", 0))
	if geometry.has("spring_rows"):
		_build_mesh()
	_set_frame(int(clips.idle[0]))
	name = "Video_" + part
	return true

func _build_mesh() -> void:
	mesh = Polygon2D.new()
	mesh.name = "ArtSpringMesh"
	mesh.texture = frames[0].atlas
	mesh.use_parent_material = true
	add_child(mesh)
	self_modulate = Color(1, 1, 1, 0) # Only the Sprite2D; children retain their own opacity.
	var w := float(spec.frame_size[0])
	var rows: Array[float] = [0.0]
	var lo := float(geometry.spring_rows[0])
	var hi := float(geometry.spring_rows[1])
	rows.append(lo)
	for i in range(1, 9):
		rows.append(lerpf(lo, hi, float(i) / 8.0))
	if geometry.has("rigid_middle_rows"):
		for y in geometry.rigid_middle_rows: rows.append(float(y))
		rows.sort()
	rows.append(float(spec.frame_size[1]))
	for y in rows:
		source_vertices.append(Vector2(0, y))
		source_vertices.append(Vector2(w, y))
	var quads: Array[PackedInt32Array] = []
	for i in rows.size() - 1:
		quads.append(PackedInt32Array([i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2]))
	if geometry.has("ring_region"):
		art_coil = SpringCoil.new()
		var t := AtlasTexture.new()
		t.atlas = frames[0].atlas
		var region: Array = geometry.ring_region
		t.region = Rect2(region[0], region[1], region[2], region[3])
		art_coil.ring = t
		art_coil.ring_count = int(geometry.ring_count)
		art_coil.visible = false
		add_child(art_coil)
		move_child(art_coil, 0)
	mesh.polygons = quads
	mesh.polygon = source_vertices

func _frame_shift() -> Vector2:
	var offsets: Array = geometry.get("frame_offsets", [])
	return RigData._v(offsets[frame_index]) if frame_index >= 0 and frame_index < offsets.size() else Vector2.ZERO

func _set_frame(index: int) -> void:
	if index == frame_index:
		return
	frame_index = index
	texture = frames[index]
	if mesh:
		var origin := frames[index].region.position
		var uv := PackedVector2Array()
		for p in source_vertices:
			uv.append(origin + p)
		mesh.uv = uv
		_update_mesh()
	else:
		offset = -RigData._v(geometry.get("pivot", spec.pivot)) - _frame_shift()

func select(expression: String) -> void:
	var next := expression if clips.has(expression) else "idle"
	if clip != next:
		clip = next
		clock = 0.0
		_set_frame(int(clips[clip][0]))
func react(strength: float, duration: float) -> void:
	response = maxf(response, clampf(strength, 0.0, 1.0))
	response_time = maxf(response_time, duration)

func fit_limb(start: Vector2, finish: Vector2, unit: float, end_rotation := 0.0) -> void:
	mesh_start = start
	mesh_end = finish
	mesh_unit = unit
	terminal_rotation = end_rotation
	position = start
	rotation = 0.0
	base_scale = Vector2.ONE
	scale = Vector2.ONE
	_update_mesh()

func _update_mesh() -> void:
	if not mesh:
		return
	var pivot := RigData._v(geometry.pivot)
	var end := RigData._v(geometry.end)
	var shift := _frame_shift()
	var lo := float(geometry.spring_rows[0])
	var hi := float(geometry.spring_rows[1])
	var vertices := PackedVector2Array()
	for pixel in source_vertices:
		var source := pixel - shift
		var upper := (source - pivot).rotated(0.0 if art_rig.data.get("png_modular",false) else terminal_rotation * 0.5) * mesh_unit
		var lower := (source - end).rotated(terminal_rotation) * mesh_unit + mesh_end - mesh_start
		# Exact rigid transforms outside the spring, continuous blend inside it.
		if geometry.has("rigid_middle_rows"):
			var m0 := float(geometry.rigid_middle_rows[0]);var m1 := float(geometry.rigid_middle_rows[1])
			var center := Vector2((pivot.x+end.x)*.5,(m0+m1)*.5)
			var middle := (source-center).rotated(terminal_rotation*.5)*mesh_unit+(center-pivot)*mesh_unit+(mesh_end-mesh_start-(end-pivot)*mesh_unit)*.5
			vertices.append(upper.lerp(middle,clampf((source.y-lo)/(m0-lo),0,1)) if source.y<m0 else middle.lerp(lower,clampf((source.y-m1)/(hi-m1),0,1)))
		else:
			vertices.append(upper.lerp(lower, clampf((source.y - lo) / (hi - lo), 0.0, 1.0)))
	mesh.polygon = vertices
	if art_coil:
		var upper := RigData._v(geometry.spring_centers[0])
		var lower := RigData._v(geometry.spring_centers[1])
		art_coil.ring_scale = mesh_unit * float(geometry.coil_scale)
		art_coil.rest_length = (lower - upper).length() * mesh_unit
		art_coil.set_line((upper - pivot) * mesh_unit, (lower - end).rotated(terminal_rotation) * mesh_unit + mesh_end - mesh_start)

func fit_between(start: Vector2, finish: Vector2) -> void:
	if mesh:
		fit_limb(start, finish, art_rig.limb_scale(part_name))
		return
	position = start
	var reference := RigData._v(spec.distal)
	var target := finish - start
	rotation = reference.angle_to(target)
	base_scale = Vector2.ONE * target.length() / maxf(reference.length(), 1.0)
	scale = base_scale

func visual_bounds() -> Rect2:
	if not mesh:
		return get_rect()
	var bounds := Rect2(mesh.polygon[0], Vector2.ZERO)
	for point in mesh.polygon:
		bounds = bounds.expand(point)
	return bounds

func sync_png_scale() -> void:
	if not art_rig or not art_rig.data.get("png_modular",false) or part_name not in ["head","torso"]: return
	var parent := get_parent() as Node2D
	if parent:
		var unit := float(geometry.unit_scale)*art_rig.rig.s/.42
		scale=Vector2.ONE*unit/parent.scale

func _process(dt: float) -> void:
	clock += dt
	var sequence: Array = clips[clip]
	_set_frame(int(sequence[int(clock * fps) % sequence.size()]))
	if art_rig.data.get("png_modular",false):
		sync_png_scale()
		return
	response_time = maxf(response_time - dt, 0.0)
	response = move_toward(response, 0.0, dt * personality.recovery)
	var stepped := floorf(clock * fps) / fps
	var tremor := sin(stepped * personality.cadence) * personality.rattle
	if part_name == "torso" or part_name == "head":
		var settle := sin(response_time * personality.settle_hz) * response * personality.squash
		scale = base_scale * Vector2(1.0 + settle * 0.45, 1.0 - settle)
		# Keep the torso sockets stable; rattle on a head rotates around its actual neck.
		rotation = tremor * (0.25 + response) if part_name == "head" else 0.0
