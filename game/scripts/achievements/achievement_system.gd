class_name AchievementSystem
extends Node
## Gameplay observer -> central evaluator -> atomic profile save -> signals.
## Future platform adapters subscribe to unlocked/changed or export snapshot(); no SDK belongs here.
signal unlocked(id: String, timestamp: int)
signal changed
var gm: GameManager
var profile: ProfileStore
var _epoch := -1
var _started := false
var _finished := false
var _robot: RobotController
var _connections: Array = []
var _pending: Array[String] = []
var _dirty := false
var _save_clock := 0.0
var _state_clock := 0.0
var _run_seconds := 0.0
var _streak := 0
var _turns := 0.0
var _turn_progress := 0.0
var _theta := 0.0
var _was_air := false
var _limb_at := -1.0
var _head_id := 0
var _head_x := 0.0
var _close_times := {}
const REST_SPEED := 35.0 # px/s = 0.35 m/s at the release scale
const REST_SPIN := 0.5
const REST_HOLD := 0.75
const CLOSE_METRES := 2.0
func setup(manager: GameManager) -> void:
	gm = manager
	gm.flicked.connect(_on_flick)
	bind_profile(gm.profile)
func bind_profile(store: ProfileStore) -> void:
	if store == profile: return
	end_navigation()
	profile = store
	_pending.clear()
	_dirty = false
	if gm and gm.ui.achievement_toast: gm.ui.achievement_toast.reset()
	if gm and gm.ui.achievements_view: gm.ui.achievements_view.visible = false
	if profile and profile.path != "": reconcile()
func snapshot() -> Dictionary:
	return profile.achievements.duplicate(true) if profile else AchievementState.defaults()
func _record(metric: String, value: float, additive := false) -> void:
	if profile == null or profile.path == "" or not is_finite(value) or value < 0.0: return
	var values: Dictionary = profile.achievements.values
	var old := float(values.get(metric, 0.0))
	var next := minf(old + value if additive else maxf(old, value), 1.0e9)
	if next <= old: return
	values[metric] = next
	_dirty = true
	for d in AchievementState.definitions():
		if d.metric == metric and next >= float(d.target) and not profile.achievements.unlocked.has(d.id):
			profile.achievements.unlocked[d.id] = maxi(int(Time.get_unix_time_from_system()), 1)
			_pending.append(String(d.id))
	if not _pending.is_empty(): flush()
func flush(notify := true) -> void:
	if not _dirty or profile == null: return
	if not profile.save(): return # keep dirty + pending; retry without losing/duplicating an unlock
	_dirty = false
	_save_clock = 0.0
	var awards := _pending.duplicate()
	_pending.clear()
	if not notify: return # Scene exit persists state without calling an already closing UI.
	changed.emit()
	for id in awards: unlocked.emit(id, int(profile.achievements.unlocked[id]))
func reconcile() -> void:
	if profile == null or profile.path == "": return
	# Only authoritative persistent facts. No historical landing/height/speed estimates.
	var completed := 0
	var bosses := 0
	if gm:
		for id in profile.campaign.completed:
			if not gm.campaign.nodes.has(id): continue
			completed += 1
			if String(gm.campaign.node(id).get("difficulty", "")) == "boss": bosses += 1
	_record("campaign", completed)
	_record("bosses", bosses)
	_record("robots", profile.owned.size())
	_record("mk2", profile.mk2_owned.size())
	if bool(profile.artifact.discovered): _record("artifact", 1)
	flush()
func _on_flick(_tier: String, _mult: float) -> void:
	if gm.tutorial != null or not gm._attempt_open or gm.mode not in [&"free", &"campaign"]: return
	bind_profile(gm.profile)
	_run_seconds = 0.0
	_epoch = gm._run_epoch
	_started = true
	_finished = false
	_head_id = 0
	_close_times.clear()
	_limb_at = -1
	_attach(gm.robot)
func _attach(r: RobotController) -> void:
	_disconnect()
	_robot = r
	_streak = 0
	_turns = 0
	_turn_progress = 0
	_was_air = false
	_theta = r.global_rotation
	for pair in [[r.landed, _landed.bind(r.get_instance_id(), _epoch)], [r.body_hit, _body_hit.bind(r.get_instance_id(), _epoch)], [r.limb_lost, _limb_lost.bind(r.get_instance_id(), _epoch)], [r.charge_changed, _charge.bind(r.get_instance_id(), _epoch)], [r.rocket_launched, _head_launched.bind(r.get_instance_id(), _epoch)]]:
		pair[0].connect(pair[1]); _connections.append(pair)
func _disconnect() -> void:
	if is_instance_valid(_robot):
		for pair in _connections:
			if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
	_connections.clear()
	_robot = null
func _eligible() -> bool:
	return _started and not _finished and gm != null and _epoch == gm._run_epoch and gm.tutorial == null \
		and gm._attempt_open and gm.state in [GameManager.State.RUN, GameManager.State.ROCKET] \
		and is_instance_valid(_robot) and _robot == gm.robot and _robot.launched
func _source_matches(source_id: int, epoch: int) -> bool:
	return _eligible() and epoch == _epoch and source_id == _robot.get_instance_id()
func _landed(info: Dictionary, source_id: int, epoch: int) -> void:
	if not _source_matches(source_id, epoch) or _robot.damage.rocket_fired: return
	var type := String(info.get("type", ""))
	if type in ["left", "right", "both"]:
		_streak += 1
		_record("feet_total", 1, true)
		_record("streak", _streak)
		if BiomeRuntime.id() == "moon": _record("moon_feet", 1)
		if BiomeRuntime.id() == "chocolate": _record("chocolate_feet", 1)
		if float(info.get("charge_ratio", 0)) >= 0.1 and String(info.get("charge_zone", "feet")) == "feet":
			_record("charged_total", 1, true)
	elif type in ["poor", "body"]: _streak = 0
func _body_hit(_info: Dictionary, source_id: int, epoch: int) -> void:
	if _source_matches(source_id, epoch): _streak = 0
func _limb_lost(_id: StringName, _part: RigidBody2D, source_id: int, epoch: int) -> void:
	if _source_matches(source_id, epoch) and _limb_at < 0: _limb_at = gm.distance_m
func _charge(value: float, source_id: int, epoch: int) -> void:
	if _source_matches(source_id, epoch) and not _robot.damage.rocket_fired:
		_record("charge", floorf(clampf(value / maxf(_robot.spin_config.max_charge, .0001), 0, 1) * 100))
func _head_launched(head: RigidBody2D, source_id: int, epoch: int) -> void:
	if not _source_matches(source_id, epoch) or not is_instance_valid(head) or not head is RocketHead: return
	_head_id = head.get_instance_id()
	_head_x = head.global_position.x
	_record("rocket", 1)
func finish_attempt() -> void:
	if not _eligible(): return
	_sample_motion(0.0)
	if not gm._continue_used and not _robot.damage.rocket_fired and _robot.damage.health > 0 and gm.distance_m >= 50:
		if _robot.damage.health / _robot.damage.max_health <= .10: _record("low_hp_finish", 1)
		if _robot.damage.limbs_remaining.size() < 4: _record("limping_finish", 1)
	_finished = true
	_disconnect()
	flush()
func end_navigation() -> void:
	flush()
	_started = false
	_finished = false
	_epoch = -1
	_head_id = 0
	_close_times.clear()
	_disconnect()
func _physics_process(dt: float) -> void:
	if gm == null: return
	if profile != gm.profile: bind_profile(gm.profile)
	_save_clock += dt
	_state_clock += dt
	if _state_clock >= .5:
		_state_clock = 0
		reconcile()
	if _started and _epoch == gm._run_epoch and gm.tutorial == null:
		if not _finished and is_instance_valid(gm.robot) and gm.robot != _robot:
			_attach(gm.robot) # Continue: new body, fresh streak/flight, same attempt
			_limb_at = -1
			_head_id = 0
			_close_times.clear()
		if _eligible(): _sample_motion(dt)
		# Deliberately survives WAIT / RESULT and does not consult frozen race counters or done flags.
		if gm.mode == &"campaign": sample_heads(gm.rocket, gm.race.competitors.map(func(c: RaceManager.Competitor) -> Variant: return c.rocket), dt, gm.level_config.px_per_meter)
	if _dirty and _save_clock >= .5: flush()
func _sample_motion(dt: float) -> void:
	_run_seconds += dt
	_record("distance", floorf(gm.distance_m))
	var piece: RigidBody2D = gm.rocket if is_instance_valid(gm.rocket) else _robot
	if is_instance_valid(gm.rocket) and gm.rocket.get_instance_id() != _head_id:
		_head_id = gm.rocket.get_instance_id()
		_head_x = gm.rocket.global_position.x
		_record("rocket", 1)
	if is_instance_valid(gm.rocket):
		_record("head_distance", floorf(maxf(0, (gm.rocket.global_position.x - _head_x) / gm.level_config.px_per_meter)))
	if _run_seconds >= 1.0: _record("speed", floorf(piece.linear_velocity.length() * 3.6 / gm.level_config.px_per_meter))
	# Never use the fake gap bottom as altitude. Jelly is excluded centrally, for EVERY height goal.
	if BiomeRuntime.id() != "jelly" and gm.terrain.gap_index(piece.global_position.x) < 0:
		_record("height", floorf(maxf(0, (gm.terrain.surface_y(piece.global_position.x) - piece.global_position.y) / gm.level_config.px_per_meter)))
	if _limb_at >= 0 and not _robot.damage.rocket_fired:
		_record("limb_travel", floorf(maxf(0, gm.distance_m - _limb_at)))
	var air := not _robot.contacts.any_contact and not _robot.damage.rocket_fired
	if air and _was_air and dt > 0:
		# Count complete physical revolutions; reversing a partial turn cancels it, so wiggling cannot farm turns.
		_turn_progress += wrapf(_robot.global_rotation - _theta, -PI, PI)
		while absf(_turn_progress) >= TAU - .0001:
			_turns += 1
			_turn_progress -= signf(_turn_progress) * TAU
		_record("turns", _turns)
	elif not air:
		_turns = 0
		_turn_progress = 0
	_was_air = air
	_theta = _robot.global_rotation
func sample_heads(player: RocketHead, enemies: Array, dt: float, ppm: float) -> void:
	if not is_instance_valid(player) or not _resting(player) or not is_finite(dt) or dt <= 0 or ppm <= 0:
		_close_times.clear(); return
	var seen := {}
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is RocketHead or enemy == player: continue
		var id: int = enemy.get_instance_id()
		seen[id] = true
		if _resting(enemy) and player.global_position.distance_to(enemy.global_position) <= CLOSE_METRES * ppm:
			_close_times[id] = float(_close_times.get(id, 0)) + dt
			if float(_close_times[id]) >= REST_HOLD: _record("heads_close", 1)
		else: _close_times.erase(id)
	for id in _close_times.keys():
		if not seen.has(id): _close_times.erase(id)
func _resting(head: RocketHead) -> bool:
	return not head.burning and not head.freeze and head.get_contact_count() > 0 \
		and head.linear_velocity.is_finite() and head.global_position.is_finite() \
		and head.linear_velocity.length() <= REST_SPEED and absf(head.angular_velocity) <= REST_SPIN
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]: flush()
func _exit_tree() -> void:
	flush(false)
	_disconnect()
