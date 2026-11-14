class_name TerrainBuilder
extends Node2D
## Endless, seed-deterministic downhill track (v0.8).
##
## The track after the fixed launch ledge is stitched from 15 terrain TEMPLATES (see track_templates.gd). Each
## template is a list of [length, angle] segments; every template is tilted to the same overall descent
## (LevelConfig.slope_bias_deg + a per-template base angle), so variety comes from the SHAPE, not the slope.
## Templates come from a seeded shuffle-bag: all 15 appear in every round of 15 and never twice in a row.
## Transitions: angle jumps above MAX_TURN get blend segments; the control points are smoothed with centripetal
## Catmull-Rom (no overshoot hooks). Geometry is generated lazily AHEAD of the player; chunks far behind are
## freed. Collision = solid convex-decomposed polygon per chunk with a simplified outline (no sliver pieces).
## Colour palettes ("biomes") are blended per vertex across template boundaries, so changes are smooth.
## Same seed -> identical templates, geometry and decor.

const CHUNK := 1800.0
const DEPTH := 2600.0
const AHEAD := 12000.0          # geometry kept generated in front of the player
const BEHIND := 20000.0         # chunks further behind than this are freed
const MAX_TURN := 40.0          # max angle change between consecutive segments (deg)
const MIN_DEG := -28.0          # steepest allowed uphill after the bias
const MAX_DEG := 50.0          # steepest allowed downhill after the bias (spline stays under ~60)
const PALETTE_BLEND := 1500.0   # width of the colour cross-fade between templates (px)
const COLLISION_TOLERANCE := 1.5
const INK := Color(0.10, 0.07, 0.05)

var training := false
var cfg: LevelConfig
var seed := 0
var points := PackedVector2Array()   # surface samples, x strictly increasing
var finish_x := INF                  # endless track (kept for API compatibility)
var start_x := 0.0
var ledge_end_x := 0.0
## Generated template sections: {name, x0, palette} in order (telemetry, tests, future ghost replays).
var sections: Array[Dictionary] = []
var build_nodes := true              # false = geometry only (analysis / tests)
var last_chunk_usec := 0             # cost of the most recent chunk build (performance telemetry)
var chunk_count := 0

var _rng := RandomNumberGenerator.new()
var _ctrl := PackedVector2Array()
var _sampled := 0                    # next control segment to sample
var _chunk_from := 0                 # points index where the next chunk starts
var _chunks: Array = []              # [x0, x1, Node2D]
var _bag: Array[int] = []
var _last_template := -1
var _palette_marks: Array = []       # [x, palette_id] in increasing x
var _font: SystemFont
var _mat: PhysicsMaterial

## ---- v30 biomes (one biome for the whole track; Green Hills = the unchanged baseline) ----
var biome: BiomeDef = BiomeCatalog.get_def(BiomeCatalog.GREEN)
## Chasm gaps [x_lip, x_far, y_lip, y_far] (no collision, no visuals between x_lip and x_far).
var gaps: Array = []
## Liquid-chocolate pools [x0, x1] on the surface (chocolate biome).
var chocolate_pools: Array = []
## Cavern ceiling (v36 rework): ground->ceiling clearance (vertical px). The track is a chain of seeded sections:
##   narrow 1180..1280 (20 %), normal 1350..1700 (50 %), high hall 1950..2600 (30 %); a narrow section is always
##   followed by a spacious one; sections blend smoothly into each other, plus a small ripple.
## HARD minimum CEIL_MIN keeps the true (Euclidean, stalactites included) ground<->ceiling distance >= 2x the largest
## tumbling robot envelope (legs at max extension, ~500 px for Sumobot) - verified over many seeds by v36_all.
const CEIL_MIN := 1150.0
const CEIL_START := 2000.0
const CEIL_LAUNCH_END := 4600.0
const CEIL_KINDS := {"narrow": [1180.0, 1280.0], "normal": [1350.0, 1700.0], "hall": [1950.0, 2600.0]}
var _ceil_secs: Array = [[-100000.0, 2000.0, "normal"]]   # [x_start, clearance, kind] (lazy, deterministic per seed)
var _ceil_rng := RandomNumberGenerator.new()
const GAP_FALL := 650.0          # robot centre this far below the lower chasm rim = fell in (run ends)
var _ceil_phase := Vector3.ZERO


## Select the biome of the NEXT reset (GameManager does this before every run).
func set_biome(def: BiomeDef) -> void:
	biome = def if def != null else BiomeCatalog.get_def(BiomeCatalog.GREEN)


func build(p_cfg: LevelConfig, p_seed := -1) -> void:
	cfg = p_cfg
	reset(cfg.seed if p_seed < 0 else p_seed)


## Rebuild the track for a new seed (Retry / new run). Only the first window is generated now.
func reset(p_seed: int) -> void:
	training=false
	seed = p_seed
	for c in get_children():
		c.queue_free()
	_chunks.clear()
	points = PackedVector2Array()
	_ctrl = PackedVector2Array()
	sections.clear()
	_palette_marks.clear()
	_sampled = 0
	_chunk_from = 0
	_bag.clear()
	_last_template = -1
	chunk_count = 0
	gaps.clear()
	chocolate_pools.clear()
	_rng.seed = hash(seed)
	_brng.seed = hash([seed, "biome"])
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Impact", "Arial Black", "sans-serif"])
		L.apply_fallbacks(_font)
	# fresh material per track: only the jelly biome makes body / head hits bouncy (Green Hills: bounce 0)
	_mat = PhysicsMaterial.new()
	_mat.friction = 0.6
	_mat.bounce = biome.body_bounce
	var cr := RandomNumberGenerator.new()
	cr.seed = hash([seed, "ceiling"])
	_ceil_phase = Vector3(cr.randf() * TAU, cr.randf() * TAU, cr.randf() * TAU)
	_ceil_rng.seed = hash([seed, "ceiling_sections"])
	_ceil_secs = [[-100000.0, CEIL_START, "normal"]]
	_start_section()
	ensure_ahead(0.0)


## Make sure geometry (and chunks) exist up to x + AHEAD; free chunks far behind `behind_x`.
func ensure_ahead(x: float, behind_x := -INF) -> void:
	if training:
		return
	while _ctrl[_ctrl.size() - 1].x < x + AHEAD + CHUNK * 2.0:
		_append_template()
	_sample_ready()
	if build_nodes:
		_build_ready_chunks()
		if behind_x > -INF:
			_recycle(behind_x - BEHIND)


# ---------------- control points ----------------

func _start_section() -> void:
	start_x = -cfg.ledge_length
	# launch ledge, tilted slightly towards the cliff so nothing can come to rest on it
	var ls := 0.06
	_ctrl.append(Vector2(start_x - 600, (start_x - 860) * ls))
	_ctrl.append(Vector2(start_x, (start_x - 260) * ls))
	_ctrl.append(Vector2(-200, -460 * ls))
	_ctrl.append(Vector2(260, 0))
	ledge_end_x = 300.0
	# the lip and the cliff into the slope
	_ctrl.append(Vector2(420, 30))
	_ctrl.append(Vector2(560, cfg.cliff_drop * 0.55))
	_ctrl.append(Vector2(760, cfg.cliff_drop))
	_palette_marks.append([start_x - 600.0, 0])
	sections.append({"name": "start", "x0": start_x - 600.0, "palette": 0})
	_last_angle = rad_to_deg((_ctrl[6] - _ctrl[5]).angle())


var _last_angle := 0.0


func _next_template() -> int:
	if _bag.is_empty():
		for i in TrackTemplates.COUNT:
			_bag.append(i)
		# deterministic shuffle
		for i in range(_bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var t := _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = t
		if _bag[_bag.size() - 1] == _last_template:
			# never the same template twice in a row across bag refills (we pop from the back)
			var t2 := _bag[0]
			_bag[0] = _bag[_bag.size() - 1]
			_bag[_bag.size() - 1] = t2
	return _bag.pop_back()


func _append_template() -> void:
	var id := _next_template()
	_last_template = id
	var segs: Array = TrackTemplates.segments(id, _rng)
	# tilt the template to the common descent: shift its mean angle towards a target (bounded)
	var total := 0.0
	var mean := 0.0
	for s in segs:
		total += s[0]
		mean += s[0] * s[1]
	mean /= maxf(total, 1.0)
	# calibrated so the overall descent matches the previous single-profile track (~26 deg cliff-to-end)
	var target := _rng.randf_range(17.0, 19.5)
	var shift := clampf(target - mean, -6.0, 6.0)
	var p := _ctrl[_ctrl.size() - 1]
	var palette := TrackTemplates.palette_for(id, _rng)
	sections.append({"name": TrackTemplates.NAMES[id], "id": id, "x0": p.x, "palette": palette})
	_palette_marks.append([p.x, palette])
	for s in segs:
		var deg := clampf(float(s[1]) + shift + cfg.slope_bias_deg, MIN_DEG, MAX_DEG)
		# smooth transition: limit the turn between consecutive segments with short blend pieces
		while absf(deg - _last_angle) > MAX_TURN:
			var mid := _last_angle + signf(deg - _last_angle) * MAX_TURN
			p += Vector2.RIGHT.rotated(deg_to_rad(mid)) * 90.0
			_ctrl.append(p)
			_last_angle = mid
		var seg_len: float = s[0]
		var n := maxi(1, int(seg_len / 260.0))
		for i in n:
			p += Vector2.RIGHT.rotated(deg_to_rad(deg)) * (seg_len / n)
			_ctrl.append(p)
		_last_angle = deg
	_biome_features(sections[sections.size() - 1].x0, p)


## v30: per-template biome geometry (own RNG so the template / palette sequence of a seed never changes).
var _brng := RandomNumberGenerator.new()


func _biome_features(x0: float, p: Vector2) -> void:
	if biome.chocolate and p.x > 1400.0:
		# one or two liquid-chocolate pools inside this template (never on the launch area)
		var span := p.x - maxf(x0, 1400.0)
		var k := 1 if span < 1800.0 else 2
		for i in k:
			var w := _brng.randf_range(420.0, 900.0)
			var c := maxf(x0, 1400.0) + span * (i + 0.5) / k + _brng.randf_range(-span * 0.15, span * 0.15)
			chocolate_pools.append([c - w * 0.5, c + w * 0.5])
	if biome.chasms and p.x > 2200.0:
		# A real gap after the template: a small kicker lip, then the far rim lower than the lip so the
		# mandatory jump is short and downhill (width/drop calibrated for slow robots: see BiomeHazards docs).
		var lip := p + Vector2.RIGHT.rotated(deg_to_rad(-8.0)) * 150.0
		_ctrl.append(lip)
		var w := _brng.randf_range(250.0, 420.0)
		var drop := w * _brng.randf_range(0.9, 1.15) + 60.0
		var far := lip + Vector2(w, drop)
		_ctrl.append(far)
		gaps.append([lip.x, far.x, lip.y, far.y])
		p = far
		for i in 2:
			p += Vector2.RIGHT.rotated(deg_to_rad(24.0)) * 220.0
			_ctrl.append(p)
		_last_angle = 24.0


## Index of the chasm gap containing x (strictly between the rims) or -1.
func gap_index(x: float) -> int:
	for i in gaps.size():
		var g: Array = gaps[i]
		if x > float(g[0]) + 0.01 and x < float(g[1]) - 0.01:
			return i
		if float(g[0]) > x:
			break
	return -1


func is_chocolate(x: float) -> bool:
	for pool in chocolate_pools:
		if x >= float(pool[0]) and x <= float(pool[1]):
			return true
		if float(pool[0]) > x:
			break
	return false


## y below which the active robot counts as fallen (chasm: GAP_FALL under the lower rim; elsewhere the classic
## 1500 px under the surface).
func fall_limit_y(x: float) -> float:
	var gi := gap_index(x)
	if gi >= 0:
		var g: Array = gaps[gi]
		return maxf(float(g[2]), float(g[3])) + GAP_FALL
	return surface_y(x) + 1500.0


## Cavern: ground->ceiling clearance at x (smooth, deterministic per seed; generous on the launch area).
## Debug / A-B tests only (--legacy_ceiling): the pre-v36 clearance curve, for before/after measurements.
static var debug_legacy_ceiling := false


func _legacy_clearance(x: float) -> float:
	var c := 1120.0 + 240.0 * sin(x * 0.00083 + _ceil_phase.x) + 140.0 * sin(x * 0.0021 + _ceil_phase.y) \
		- 200.0 * maxf(0.0, sin(x * 0.00031 + _ceil_phase.z))
	if x < CEIL_LAUNCH_END:
		c = maxf(c, lerpf(1800.0, 800.0, clampf((x - 3200.0) / (CEIL_LAUNCH_END - 3200.0), 0.0, 1.0)))
	return maxf(c, 800.0)


func ceiling_clearance(x: float) -> float:
	if debug_legacy_ceiling:
		return _legacy_clearance(x)
	while float(_ceil_secs[-1][0]) <= x + 4000.0:
		_next_ceiling_section()
	var i := _ceil_secs.size() - 1
	while i > 0 and float(_ceil_secs[i][0]) > x:
		i -= 1
	var cur: Array = _ceil_secs[i]
	var nxt: Array = _ceil_secs[mini(i + 1, _ceil_secs.size() - 1)]
	var span := maxf(float(nxt[0]) - float(cur[0]), 1.0)
	var prev: Array = _ceil_secs[maxi(i - 1, 0)]
	# blend in from the previous section over the first 40 % of this one
	var k := smoothstep(0.0, 1.0, clampf((x - float(cur[0])) / (span * 0.4), 0.0, 1.0))
	var c := lerpf(float(prev[1]), float(cur[1]), k)
	c += 60.0 * sin(x * 0.0021 + _ceil_phase.y) + 35.0 * sin(x * 0.0057 + _ceil_phase.x)
	if x < CEIL_LAUNCH_END:
		# the launch arc and its first big bounce (~15-30 m) get a high vault: the first hit must never be a given
		c = maxf(c, lerpf(CEIL_START, CEIL_MIN, clampf((x - 3200.0) / (CEIL_LAUNCH_END - 3200.0), 0.0, 1.0)))
	return maxf(c, CEIL_MIN)


func _next_ceiling_section() -> void:
	var last: Array = _ceil_secs[-1]
	var x0 := maxf(float(last[0]), 0.0) + (_ceil_rng.randf_range(1800.0, 3400.0) if float(last[0]) > -1000.0 else CEIL_LAUNCH_END)
	var roll := _ceil_rng.randf()
	var kind := "narrow" if roll < 0.2 else ("normal" if roll < 0.7 else "hall")
	if String(last[2]) == "narrow" and kind == "narrow":
		kind = "hall" if _ceil_rng.randf() < 0.6 else "normal"
	var rng_c: Array = CEIL_KINDS[kind]
	_ceil_secs.append([x0, _ceil_rng.randf_range(float(rng_c[0]), float(rng_c[1])), kind])


## Section kind under x ("narrow" / "normal" / "hall") - tests and QA.
func ceiling_kind(x: float) -> String:
	ceiling_clearance(x)
	var i := _ceil_secs.size() - 1
	while i > 0 and float(_ceil_secs[i][0]) > x:
		i -= 1
	return String(_ceil_secs[i][2])


## Cavern ceiling y at x: below the lowest surface nearby minus the clearance, so the ceiling can never dip into
## the ground on a crest (v36: +-420 px window - also covers the robot width on slopes).
func ceiling_y(x: float) -> float:
	var top := surface_y(x)
	for o in ([-260.0, -130.0, 130.0, 260.0] if debug_legacy_ceiling else [-420.0, -280.0, -140.0, 140.0, 280.0, 420.0]):
		top = minf(top, surface_y(x + o))
	return top - ceiling_clearance(x)


# ---------------- sampling (centripetal Catmull-Rom: no overshoot loops / hooks) ----------------

func _sample_ready() -> void:
	while _sampled + 2 < _ctrl.size():
		var i := _sampled
		var p0 := _ctrl[maxi(i - 1, 0)]
		var p1 := _ctrl[i]
		var p2 := _ctrl[i + 1]
		var p3 := _ctrl[i + 2]
		var n := maxi(2, int(p1.distance_to(p2) / cfg.sample_step))
		for j in n:
			var v := _centripetal(p0, p1, p2, p3, float(j) / n)
			if points.is_empty() or v.x > points[points.size() - 1].x + 0.5:
				points.append(v)
		_sampled += 1


static func _centripetal(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 0.001)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 0.001)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 0.001)
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - tt) / (t2 - t0)) + a2 * ((tt - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - tt) / (t3 - t1)) + a3 * ((tt - t1) / (t3 - t1))
	return b1 * ((t2 - tt) / (t2 - t1)) + b2 * ((tt - t1) / (t2 - t1))


# ---------------- queries ----------------

func _index_at(x: float) -> int:
	var lo := 0
	var hi := points.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if points[mid].x <= x:
			lo = mid
		else:
			hi = mid
	return lo


## Solid ground under x for gameplay queries (AI touchdown prediction, ballistic checks): inside a chasm gap there is
## no ground, so it returns a point far below the rims. Use surface_y() for the continuous visual surface line.
func height_at(x: float) -> float:
	if not gaps.is_empty():
		var gi := gap_index(x)
		if gi >= 0:
			var g: Array = gaps[gi]
			return maxf(float(g[2]), float(g[3])) + 6000.0
	return surface_y(x)


## Continuous track surface (rim-to-rim interpolation over chasm gaps): camera, heights above ground, decor.
func surface_y(x: float) -> float:
	if points.is_empty():
		return 0.0
	if x <= points[0].x:
		return points[0].y
	if x >= points[points.size() - 1].x:
		return points[points.size() - 1].y
	var i := _index_at(x)
	var a := points[i]
	var b := points[i + 1]
	return lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.001))


func normal_at(x: float) -> Vector2:
	var i := clampi(_index_at(x), 0, points.size() - 2)
	var d := (points[i + 1] - points[i]).normalized()
	return Vector2(d.y, -d.x)


func end_x() -> float:
	return points[points.size() - 1].x if not points.is_empty() else 0.0


## Template section at x (telemetry).
func section_at(x: float) -> Dictionary:
	var best: Dictionary = sections[0]
	for s in sections:
		if s.x0 <= x:
			best = s
		else:
			break
	return best


## Palette blend at x: [palette_a, palette_b, weight_b]. Cross-fade centred on each template boundary.
func palette_at(x: float) -> Array:
	var cur: int = _palette_marks[0][1]
	for i in range(1, _palette_marks.size()):
		var mx: float = _palette_marks[i][0]
		var pid: int = _palette_marks[i][1]
		if x < mx - PALETTE_BLEND * 0.5:
			break
		if x < mx + PALETTE_BLEND * 0.5:
			return [cur, pid, smoothstep(mx - PALETTE_BLEND * 0.5, mx + PALETTE_BLEND * 0.5, x)]
		cur = pid
	return [cur, cur, 0.0]


func color_at(x: float, key: String) -> Color:
	if not biome.palette.is_empty():
		# special biome: its own palette, with a very small brightness drift between templates
		var c: Color = biome.palette.get(key, Color.MAGENTA)
		var drift: float = [0.0, 0.035, -0.035, 0.02, -0.02][int(palette_at(x)[0]) % 5]
		return c.lightened(drift) if drift > 0.0 else c.darkened(-drift)
	var b := palette_at(x)
	var ca: Color = TrackTemplates.PALETTES[b[0]][key]
	if b[0] == b[1]:
		return ca
	return ca.lerp(TrackTemplates.PALETTES[b[1]][key], b[2])


# ---------------- chunks ----------------

func _build_ready_chunks() -> void:
	while true:
		var i := _chunk_from
		if i >= points.size() - 1:
			return
		var j := i
		var x0 := points[i].x
		while j < points.size() - 1 and points[j].x - x0 < CHUNK:
			j += 1
		# only complete chunks (the surface after them must already exist for a seamless join)
		if points[j].x - x0 < CHUNK or j >= points.size() - 2:
			return
		var t0 := Time.get_ticks_usec()
		_build_chunk(points.slice(i, j + 1), chunk_count)
		last_chunk_usec = Time.get_ticks_usec() - t0
		chunk_count += 1
		_chunk_from = j


## Frees chunks that end before before_x. The launch-ledge chunk (start of the list) is always kept, so the
## scan skips it instead of stopping there (that stop once meant no chunk was ever freed).
func _recycle(before_x: float) -> void:
	var i := 0
	while i < _chunks.size():
		var ch: Array = _chunks[i]
		if ch[1] >= before_x:
			break
		if ch[0] > ledge_end_x:
			(ch[2] as Node).queue_free()
			_chunks.remove_at(i)
		else:
			i += 1


func _build_chunk(surf: PackedVector2Array, index: int) -> void:
	var root := Node2D.new()
	root.name = "Chunk%d" % index
	var bottom := 0.0
	for p in surf:
		bottom = maxf(bottom, p.y)
	bottom += DEPTH
	if gaps.is_empty():
		_build_run(root, surf, bottom, index, false, false)
	else:
		# chasm biome: only the solid runs between gaps get collision and visuals; the gaps stay empty
		var run := PackedVector2Array()
		var starts_at_rim := false
		for k in surf.size():
			var p := surf[k]
			if gap_index(p.x) >= 0:
				if run.size() >= 2:
					_build_run(root, run, bottom, index, starts_at_rim, true)
				run = PackedVector2Array()
				starts_at_rim = true
				continue
			run.append(p)
		if run.size() >= 2:
			_build_run(root, run, bottom, index, starts_at_rim, false)
		for g in gaps:
			if float(g[1]) >= surf[0].x and float(g[0]) <= surf[surf.size() - 1].x:
				BiomeProps.chasm(root, g, self)
	if biome.ceiling:
		_build_ceiling(root, surf)
	BiomeProps.chunk_extras(root, surf, index, self)
	add_child(root)
	_chunks.append([surf[0].x, surf[surf.size() - 1].x, root])


## Cavern: a real, solid rock ceiling above the chunk (StaticBody2D in the "ground" group -> the normal
## collision / damage / limb rules apply when a robot hits it). Stalactites are part of the collision line.
func _build_ceiling(root: Node2D, surf: PackedVector2Array) -> void:
	var x0 := surf[0].x
	var x1 := surf[surf.size() - 1].x
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, int(x0), "ceil"])
	var line := PackedVector2Array()
	var x := x0
	while x < x1:
		line.append(Vector2(x, ceiling_y(x)))
		var step := r.randf_range(70.0, 130.0)
		if r.randf() < 0.22 and x > 1600.0:
			# stalactite: a short hanging spike (real geometry, kept short so the clearance stays fair)
			var tip := Vector2(x + step * 0.5, ceiling_y(x + step * 0.5) + r.randf_range(45.0, 110.0))
			line.append(tip)
		x += step
	line.append(Vector2(x1, ceiling_y(x1)))
	var top := 0.0
	for p in line:
		top = minf(top, p.y)
	top -= 2400.0
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.physics_material_override = _mat
	body.add_to_group(&"ground")
	body.set_meta(&"ceiling", true)
	var cp := CollisionPolygon2D.new()
	cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
	var poly := line.duplicate()
	poly.append(Vector2(x1, top))
	poly.append(Vector2(x0, top))
	cp.polygon = poly
	body.add_child(cp)
	root.add_child(body)
	BiomeProps.ceiling_visual(root, line, top, self, r)


func _build_run(root: Node2D, surf: PackedVector2Array, bottom: float, index: int, left_rim: bool, right_rim: bool) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.physics_material_override = _mat
	body.add_to_group(&"ground")
	var cp := CollisionPolygon2D.new()
	cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
	# simplified outline: near-collinear samples make the convex decomposition produce sliver pieces that
	# return bogus contacts (seen as a body teleported to ~1e20 on the steep track)
	var col := _simplify(surf, COLLISION_TOLERANCE)
	col.append(Vector2(surf[surf.size() - 1].x, bottom))
	col.append(Vector2(surf[0].x, bottom))
	cp.polygon = col
	body.add_child(cp)
	root.add_child(body)

	# fill + strata as vertical bands with per-vertex palette colours (smooth biome cross-fade)
	var n := surf.size()
	var fill_pts := PackedVector2Array()
	var fill_cols := PackedColorArray()
	var band_pts := PackedVector2Array()
	var band_cols := PackedColorArray()
	for p in surf:
		fill_pts.append(p)
		fill_cols.append(color_at(p.x, "dirt"))
		band_pts.append(p + Vector2(0, 70))
		band_cols.append(color_at(p.x, "dirt_dark"))
	for k in range(n - 1, -1, -1):
		fill_pts.append(Vector2(surf[k].x, bottom))
		fill_cols.append(color_at(surf[k].x, "dirt").darkened(0.12))
		band_pts.append(surf[k] + Vector2(0, 150))
		band_cols.append(color_at(surf[k].x, "dirt_dark"))
	var fill_poly := _band_polygon(fill_pts, fill_cols, n)
	var band_poly := _band_polygon(band_pts, band_cols, n)
	if biome.props == "":
		# Green Hills: hand-painted gouache brushwork multiplied over the palette colours (visual only)
		var detail := _gh_prop("ground_detail")
		if detail:
			for poly in [fill_poly, band_poly]:
				poly.texture = detail
				poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
				poly.texture_scale = Vector2(0.75, 0.75)
	root.add_child(fill_poly)
	root.add_child(band_poly)
	# v0.9.1: sparse decoration inside the green fill (visual only, own RNG: geometry / surface decor unchanged)
	var gd := GroundDecor.new()
	gd.style = biome.props
	var dr := RandomNumberGenerator.new()
	dr.seed = hash([seed, index, 7]) if not left_rim else hash([seed, index, 7, int(surf[0].x)])
	gd.generate(surf, dr, surface_y, color_at, start_x)
	root.add_child(gd)
	if left_rim or right_rim:
		BiomeProps.cliff_edges(root, surf, bottom, left_rim, right_rim)
	# outline + top layer (grass) + highlight, coloured with a gradient along the line
	root.add_child(_line(surf, 34.0, null))
	root.add_child(_line(_offset(surf, 2.0), 24.0, _gradient(surf, "top")))
	root.add_child(_line(_offset(surf, -4.0), 6.0, _gradient(surf, "hl")))
	_decor(root, surf, index)


## Band polygon (top row then bottom row reversed) split into explicit quads so colours interpolate along x.
func _band_polygon(pts: PackedVector2Array, cols: PackedColorArray, n: int) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.vertex_colors = cols
	var quads := []
	for i in n - 1:
		quads.append(PackedInt32Array([i, i + 1, 2 * n - 2 - i, 2 * n - 1 - i]))
	poly.polygons = quads
	return poly


func _gradient(surf: PackedVector2Array, key: String) -> Gradient:
	var g := Gradient.new()
	var x0 := surf[0].x
	var span := maxf(surf[surf.size() - 1].x - x0, 1.0)
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	var stops := 8
	for k in stops + 1:
		var x := x0 + span * k / stops
		offs.append(float(k) / stops)
		cols.append(color_at(x, key))
	g.offsets = offs
	g.colors = cols
	return g


func _line(pts: PackedVector2Array, w: float, g: Gradient) -> Line2D:
	var l := Line2D.new()
	l.points = pts
	l.width = w
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	if g:
		l.gradient = g
	else:
		l.default_color = INK
	return l


## Ramer-Douglas-Peucker: keeps the end points, drops points closer than tol (px) to the simplified line.
func _simplify(pts: PackedVector2Array, tol: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts.duplicate()
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep.fill(0)
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack := [[0, pts.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var a: int = seg[0]
		var b: int = seg[1]
		var best := -1.0
		var idx := -1
		for i in range(a + 1, b):
			var d := _dist_to_segment(pts[i], pts[a], pts[b])
			if d > best:
				best = d
				idx = i
		if idx >= 0 and best > tol:
			keep[idx] = 1
			stack.append([a, idx])
			stack.append([idx, b])
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i]:
			out.append(pts[i])
	return out


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


func _offset(pts: PackedVector2Array, dy: float) -> PackedVector2Array:
	var o := PackedVector2Array()
	for p in pts:
		o.append(p + Vector2(0, dy))
	return o


# ---------------- decor (deterministic per chunk) ----------------

func _decor(root: Node2D, surf: PackedVector2Array, index: int) -> void:
	var x0 := surf[0].x
	var x1 := surf[surf.size() - 1].x
	# distance posts every 25 m
	var step := 25.0 * cfg.px_per_meter
	var px := ceilf(maxf(x0, 1.0) / step) * step
	while px < x1:
		_post(root, px, L.t("UNIT_M_N") % int(round(px / cfg.px_per_meter)))
		px += step
	if x1 < ledge_end_x + 400.0:
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, index])
	if biome.props != "":
		# special biome: its own surface props instead of grass tufts / grey rocks (visual only, no collision)
		r.seed = hash([seed, index, int(x0)])
		BiomeProps.decorate(root, surf, r, self)
		return
	var x := maxf(x0, ledge_end_x + 400.0)
	while true:
		x += r.randf_range(180, 520)
		if x >= x1:
			break
		var y := height_at(x)
		var pal: Dictionary = TrackTemplates.PALETTES[palette_at(x)[0]]
		if r.randf() < pal.rock_chance:
			_rock(root, Vector2(x, y + 6), r.randf_range(14, 30) * pal.rock_scale, r, color_at(x, "rock"))
		else:
			_tuft(root, Vector2(x, y), r, color_at(x, "tuft"))


func _post(root: Node2D, x: float, text: String) -> void:
	var y := height_at(x)
	var n := Node2D.new()
	n.position = Vector2(x, y)
	var pole := Polygon2D.new()
	pole.polygon = PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(5, -150), Vector2(-5, -150)])
	pole.color = Color(0.45, 0.28, 0.15)
	n.add_child(pole)
	var board := Polygon2D.new()
	board.polygon = PackedVector2Array([Vector2(-70, -210), Vector2(70, -205), Vector2(66, -140), Vector2(-66, -146)])
	board.color = Color(0.98, 0.9, 0.62)
	var edge := Line2D.new()
	edge.points = board.polygon
	edge.closed = true
	edge.width = 6.0
	edge.default_color = INK
	board.add_child(edge)
	n.add_child(board)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color(0.25, 0.12, 0.05))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(140, 60)
	l.position = Vector2(-70, -206)
	n.add_child(l)
	n.z_index = -1
	root.add_child(n)


## Hand-painted Green Hills surface props (Google Flow, tools/flow/make_layers.py). Visual only; the decor RNG is
## consumed exactly as before, the sprite variant comes from the x position. Missing textures -> old vector props.
const GH_PROP_DIR := "res://assets/flow/green_hills/"
const GH_PLANTS := ["tuft_0", "tuft_1", "tuft_2", "tuft_3", "tuft_0", "flower_0", "flower_1", "flower_2", "bush_0", "bush_1"]
const GH_ROCKS := ["rock_0", "rock_1", "rock_2"]
static var _gh_tex := {}
static var _sway_mat: ShaderMaterial


static func _gh_prop(pname: String) -> Texture2D:
	if not _gh_tex.has(pname):
		var path := GH_PROP_DIR + pname + ".png"
		_gh_tex[pname] = load(path) if ResourceLoader.exists(path) else null
	return _gh_tex[pname]


## Sprite standing on the surface point p (bottom centre slightly buried under the thick ink outline).
func _gh_sprite(root: Node2D, tex: Texture2D, p: Vector2, height: float, flip: bool, sway: bool) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
	var k := height / tex.get_height()
	s.scale = Vector2(-k if flip else k, k)
	s.position = p + Vector2(0, 10)
	s.z_index = 1
	if sway:
		if _sway_mat == null:
			_sway_mat = ShaderMaterial.new()
			_sway_mat.shader = load("res://shaders/sway.gdshader")
		s.material = _sway_mat
	root.add_child(s)


func _rock(root: Node2D, p: Vector2, r: float, rng: RandomNumberGenerator, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var a := PI + PI * i / 6.0
		pts.append(p + Vector2(cos(a) * r * rng.randf_range(0.9, 1.3), sin(a) * r * rng.randf_range(0.6, 1.0)))
	var vi := posmod(int(p.x * 0.37), GH_ROCKS.size())
	var tex := _gh_prop(GH_ROCKS[vi])
	if tex:
		_gh_sprite(root, tex, p, r * 1.9, posmod(int(p.x), 2) == 0, false)
		return
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = col
	var e := Line2D.new()
	e.points = pts
	e.closed = true
	e.width = 4.0
	e.default_color = INK
	poly.add_child(e)
	poly.z_index = 1
	root.add_child(poly)


func _tuft(root: Node2D, p: Vector2, rng: RandomNumberGenerator, col: Color) -> void:
	var h := rng.randf_range(16, 30)
	var pname: String = GH_PLANTS[posmod(int(p.x * 0.37), GH_PLANTS.size())]
	var tex := _gh_prop(pname)
	if tex:
		var k := 1.7 if pname.begins_with("bush") else 1.0
		_gh_sprite(root, tex, p, h * 3.9 * k, posmod(int(p.x), 2) == 0, not pname.begins_with("bush"))
		return
	var l := Line2D.new()
	l.points = PackedVector2Array([p + Vector2(-10, 0), p + Vector2(-6, -h), p + Vector2(0, -2), p + Vector2(5, -h * 1.2),
		p + Vector2(8, 0)])
	l.width = 5.0
	l.default_color = col
	l.z_index = 1
	root.add_child(l)


## Isolated gently tilted practice court, using the same solid chunk/collision builder.
func build_training() -> void:
	training=true
	for child in get_children():
		child.queue_free()
	_chunks.clear()
	points=PackedVector2Array()
	sections=[{"name":"tutorial","x0":-6000.0,"palette":0}]
	_palette_marks=[[-6000.0,0]]
	start_x=-6000
	ledge_end_x=8000
	_chunk_from=0
	chunk_count=0
	for x in range(-6000,9001,20):
		points.append(Vector2(x,x*0.06))
	_build_ready_chunks()
