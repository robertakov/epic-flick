class_name RaceManager
extends Node
## Campaign opponents ("shadow competitors"). Each enemy is a normal RobotController with its own InputRouter
## (real input disabled) driven by an EnemyAI. Enemies:
##   * collide with the TERRAIN only (robots are on layer 2 and mask only the ground layer 1) - they cannot touch,
##     push, block or damage the player or each other;
##   * start at the same flick, on the same track seed, with the same rules (settings, damage, charge, finish rules);
##   * are tracked exactly like the player (max x of robot / jet head, stuck / no-progress / fall / head landed).
## Nothing here moves a robot: RaceManager only measures.

signal competitor_finished(c: Competitor)

const GHOST_TINTS := [Color(0.72, 0.86, 1.0, 0.62), Color(1.0, 0.74, 0.92, 0.62), Color(0.78, 1.0, 0.72, 0.62)]
const TAG_COLORS := [Color(0.55, 0.8, 1.0), Color(1.0, 0.6, 0.85), Color(0.6, 1.0, 0.55)]

class Competitor:
	extends RefCounted
	var index := 0
	var name := ""
	var robot_id := ""
	var appearance_id := ""
	var pressure := false
	var robot: RobotController
	var control: InputRouter
	var ai: EnemyAI
	var rocket: RocketHead
	var tag: Node2D
	var color := Color.WHITE
	var start_x := 0.0
	var max_x := 0.0
	var distance := 0.0
	var finished := false
	var reason := ""
	var base_skill := 0.5
	var skill := 0.5
	var _stuck := 0.0
	var watch := MotionWatch.new()   # v36: same stuck rules as the player

	func piece() -> Node2D:
		if is_instance_valid(rocket):
			return rocket
		return robot if is_instance_valid(robot) else null


var gm: GameManager
var competitors: Array[Competitor] = []
var race_time := 0.0
## Safety net: a race never runs longer than this (s); the measured distance so far counts.
@export var max_race_time := 240.0
## Debug / tests only: ghost rivals (no roster appearance) normally mix the wall clock into their AI seed for
## variety; deterministic A/B tests need the same AI decisions in both runs.
var deterministic_ai := false


func clear() -> void:
	competitors.clear()
	race_time = 0.0


## enemies: node["enemies"] entries. skill_mod: hidden adaptive modifier. seed: attempt seed for the AI RNGs.
func spawn(enemies: Array, skill_mod: float, attempt_seed: int, ai_cfg: AIConfig) -> void:
	clear()
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		var def := gm.catalog.get_by_id(String(e.get("robot", "tin")))
		if def == null:
			def = gm.catalog.robots[0]
		var c := Competitor.new()
		c.index = i
		c.name = String(e.get("name", L.t("RACE_RIVAL_N") % (i + 1)))
		c.robot_id = def.id
		var presentation := EnemyRoster.slot(gm.node_id,i)
		c.appearance_id=String(presentation.get("id",""))
		c.pressure=bool(presentation.get("pressure",false))
		if c.appearance_id!="": c.name=EnemyRoster.display_name(c.appearance_id)
		c.color = TAG_COLORS[i % TAG_COLORS.size()]
		c.control = InputRouter.new()
		c.control.name = "AIInput"
		c.control.set_process_unhandled_input(false)   # only the AI drives it
		var skin_id := String(e.get("skin", ""))
		# "mk2": debug balance simulations only (campaign data never sets it - rivals are always base robots)
		var r := gm.build_robot(def, c.control, null, skin_id if skin_id != "" else SkinDefinition.default_id(def.id), bool(e.get("mk2", false)))
		r.name = "Enemy%d" % i
		r.add_child(c.control)
		var k: float = r.config.rig_scale / 0.42
		var x := -80.0 - 95.0 * (i + 1)
		r.position = Vector2(x, gm.terrain.height_at(x) - (35.7 * k + (13.3 + 54.0) * k + r.contact_config.coil_rest_length) + 4.0)
		r.z_index = -1 - i            # behind the player
		gm.dynamic.add_child(r)
		r.damage.invulnerability_time = gm.settings.get_value("invuln_s")
		if c.appearance_id!="":
			EnemyAppearance.install(r,c.appearance_id)
			r.visual.modulate=Color.WHITE
		else:
			r.visual.modulate = GHOST_TINTS[i % GHOST_TINTS.size()]
		c.robot = r
		c.start_x = r.position.x
		c.max_x = c.start_x
		c.watch = MotionWatch.new(gm.no_progress_time)
		c.watch.reset(r.position)
		c.base_skill = float(e.get("skill", 0.5))
		c.skill = clampf(c.base_skill + skill_mod, 0.0, 1.0)
		c.ai = EnemyAI.new()
		c.ai.name = "EnemyAI"
		c.ai.setup(r, c.control, gm.terrain, EnemyRoster.decision_config(ai_cfg,c.pressure), c.skill, float(e.get("lean", ai_cfg.default_lean)),
			float(e.get("greed", 0.5)), hash([attempt_seed, i]) if (c.appearance_id!="" or deterministic_ai) else hash([attempt_seed, i, Time.get_ticks_usec()]))
		c.ai.configure_band(float(e.get("target_min_distance",0)),float(e.get("target_max_distance",0)),gm.level_config.px_per_meter)
		r.add_child(c.ai)
		c.tag = _make_tag(c)
		gm.dynamic.add_child(c.tag)
		var cc := c
		r.rocket_launched.connect(func(head: RigidBody2D) -> void:
			cc.rocket = head as RocketHead
			cc.rocket.modulate = Color.WHITE if cc.appearance_id!="" else GHOST_TINTS[cc.index % GHOST_TINTS.size()]
			cc.rocket.finished.connect(func(_h: RocketHead) -> void: _finish(cc, "Голова приземлилась")))
		competitors.append(c)


func _make_tag(c: Competitor) -> Node2D:
	var n := Node2D.new()
	n.top_level = true
	n.z_index = 25
	var l := Label.new()
	l.text = c.name
	l.add_theme_font_override("font", gm.ui.font)
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", c.color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.04))
	l.add_theme_constant_override("outline_size", 8)
	l.position = Vector2(-120, -260)
	l.size = Vector2(240, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_child(l)
	return n


## Same initial flick as the player.
func launch(velocity: Vector2, spin: float) -> void:
	for c in competitors:
		c.robot.launch(velocity, spin)


func step(dt: float) -> void:
	race_time += dt
	for c in competitors:
		var p := c.piece()
		if c.tag and p:
			c.tag.global_position = p.global_position
		if c.finished or p == null:
			continue
		var x := _sane_x(p)
		if is_nan(x):
			continue   # glitched step: ignore it (the robot / head safety nets restore the body)
		c.max_x = maxf(c.max_x, x)
		c.distance = maxf(0.0, (c.max_x - c.start_x) / gm.level_config.px_per_meter)
		if p.global_position.y > gm.terrain.fall_limit_y(x):
			_finish(c, "Провалился")
			continue
		if race_time > max_race_time:
			_finish(c, "Время вышло")
			continue
		if is_instance_valid(c.rocket):
			continue   # the jet head finishes through its own `finished` signal
		var r := c.robot
		c._stuck = c.watch.stopped(dt, r.linear_velocity.length(), r.angular_velocity, gm.stuck_speed)
		if c._stuck > gm.stuck_time:
			_end_or_final(c, "Остановился")
		elif c.watch.step(dt, r.global_position):
			_end_or_final(c, "Застрял")


## Same rule as the player: a wrecked robot resting on its torso fires its jet head instead of stopping.
func _end_or_final(c: Competitor, reason: String) -> void:
	var r := c.robot
	if r.damage.health <= 0.0 and r.damage.limbs_remaining.is_empty():
		r.notify_resting()
		if r.damage.rocket_fired:
			return
	_finish(c, reason)


func _finish(c: Competitor, reason: String) -> void:
	if c.finished:
		return
	c.finished = true
	c.reason = reason
	if is_instance_valid(c.robot):
		c.control.set_virtual_hold(false)
	competitor_finished.emit(c)


func all_finished() -> bool:
	for c in competitors:
		if not c.finished:
			return false
	return true


func best_distance() -> float:
	var b := 0.0
	for c in competitors:
		b = maxf(b, c.distance)
	return b


func running() -> Array[Competitor]:
	return competitors.filter(func(c: Competitor) -> bool: return not c.finished)


## Furthest still-running piece (camera target while the player waits for the opponents).
func leader_running() -> Node2D:
	var best: Node2D = null
	var bx := -INF
	for c in running():
		var p := c.piece()
		if p and p.global_position.x > bx:
			bx = p.global_position.x
			best = p
	return best


## Only sane positions may drive terrain streaming (a broken solver step can report ~1e22 for one frame:
## streaming towards it would try to generate the track up to there).
func _sane_x(p: Node2D) -> float:
	var x := p.global_position.x
	if not is_finite(x) or not is_finite(p.global_position.y):
		return NAN
	return x if x < gm.terrain.end_x() + 6000.0 else NAN


func max_x() -> float:
	var m := -INF
	for c in competitors:
		var p := c.piece()
		if p:
			var x := _sane_x(p)
			if not is_nan(x):
				m = maxf(m, x)
	return m


func min_running_x() -> float:
	var m := INF
	for c in running():
		var p := c.piece()
		if p:
			var x := _sane_x(p)
			if not is_nan(x):
				m = minf(m, x)
	return m
