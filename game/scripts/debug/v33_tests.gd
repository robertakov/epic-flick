extends Node
## v33 tests (debug only, not exported).
##   --scenario=v33_all  : tutorial (real inputs + real gameplay events), profile persistence / replay, challenge
##                         variety + feet-streak scaling + feasibility, +15 HP, modal layering. Needs -Window and
##                         --auto_tutorial (new-profile entry) - run_regression.ps1 passes both.
##   --scenario=v33_qa   : screenshots (tutorial steps, feedback, retry, done card, settings over the menu robot)
## Prints "AT|test v33_<name> PASS|FAIL <details>".
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const HP := {"tin": 95.0, "hopper": 100.0, "heavy": 170.0, "rocket": 100.0, "samurai": 155.0}
const OLD_HP := {"tin": 80.0, "hopper": 85.0, "heavy": 250.0, "rocket": 85.0, "samurai": 140.0}
const FEET := ["GOOD_LANDING_STREAK", "TOTAL_GOOD_LANDINGS"]
const REMOVED := ["FINISH_WITHIN_ENEMY", "KEEP_ENEMY_IN_VIEW"]


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test v33_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run_all(which: String) -> void:
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	match which:
		"v33_qa":
			await qa()
		_:
			modal_layering()
			hp_tests()
			challenge_tests()
			await feasibility()
			# v34: the step-by-step tutorial tests moved to v34_tests.gd (freeze-gated pacing replaced v33's
			# slow-motion flow); entry / persistence / replay stay here
			await profile_tutorial_tests()
	Engine.time_scale = 1.0
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ======================================================================================================
# A. modal layering
# ======================================================================================================

static func eff_z(n: Node) -> int:
	var z := 0
	var c := n
	while c is CanvasItem:
		z += (c as CanvasItem).z_index
		if not (c as CanvasItem).z_as_relative:
			break
		c = c.get_parent()
	return z


func modal_layering() -> void:
	var ui := gm.ui
	var deco_max := -9999
	var pending: Array[Node] = [ui.menu]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if n is CanvasItem:
			deco_max = maxi(deco_max, eff_z(n))
	var bad := []
	for m in ui.modal_roots():
		if eff_z(m) <= deco_max:
			bad.append(m.name)
	check("modals_above_menu_and_robot", bad.is_empty() and ui.modal_roots().size() >= 9, "menu max z %d, modal z %d, bad %s" % [deco_max, UIController.Z_MODAL, bad])
	# a deliberately high local z on a menu decoration still stays under the modal band
	var probe := Node2D.new()
	probe.z_index = 60
	ui.menu_robot_preview.add_child(probe)
	var under := true
	for m in ui.modal_roots():
		under = under and eff_z(m) > eff_z(probe)
	probe.free()
	check("modal_band_beats_high_local_z", under)


# ======================================================================================================
# B. +15 HP
# ======================================================================================================

func hp_tests() -> void:
	var rows := []
	var ok := true
	var art := true
	for id in HP:
		var def := gm.catalog.get_by_id(id)
		# v33: +15 for every robot; v34 then fixed Sumobot at exactly 170 (phone balance)
		ok = ok and is_equal_approx(def.max_health, float(HP[id])) and (id == "heavy" or is_equal_approx(def.max_health - float(OLD_HP[id]), 15.0))
		var cf_on := def.make_configs(gm.robot_config, gm.contact_config, gm.damage_config, [SecretArtifact.module(def.base_stats(), gm.catalog)])
		art = art and is_equal_approx(cf_on.damage.max_health, float(HP[id]) + 15.0) and is_equal_approx(def.max_health, float(HP[id]))   # v36: +15 HP
		rows.append("%s %d->%d (artifact %.2f)" % [id, OLD_HP[id], HP[id], cf_on.damage.max_health])
	check("base_hp_plus_15_all_robots", ok, ", ".join(rows))
	check("artifact_hp_on_new_base_not_baked", art)
	var heavy := float(HP.heavy)
	var others := 0.0
	for id in HP:
		if id != "heavy":
			others = maxf(others, float(HP[id]))
	check("sumobot_still_clear_tank", heavy > others and is_equal_approx(heavy, 170.0), "%d vs %d" % [heavy, others])   # v34: 170 = highest base HP
	# damage / limb thresholds / death on the new maximum (real DamageController)
	var r := gm.build_robot(gm.catalog.get_by_id("tin"), InputRouter.new(), gm.fx)
	gm.dynamic.add_child(r)
	var lost := []
	r.damage.limb_lost.connect(func(l: StringName, _i: Dictionary) -> void: lost.append(l))
	var seq := []
	while r.damage.health > 0.0 and seq.size() < 20:
		r.damage.invulnerable_left = 0.0
		r.damage._apply(&"feet", {"point": Vector2.ZERO, "normal": Vector2.UP})
		seq.append([r.damage.health, lost.size()])
	# 95 HP, 15 per feet hit: 80 65(arm) 50 35(arm) 20(leg) 5 0(leg)
	check("feet_damage_and_limb_thresholds_on_new_hp", seq.size() == 7 and is_equal_approx(seq[0][0], 80.0) and int(seq[1][1]) == 1
		and int(seq[3][1]) == 2 and int(seq[4][1]) == 3 and r.damage.health == 0.0 and lost.size() == 4, str(seq))
	r.damage.health = 0.0
	r.damage.restore_for_continue(gm.economy.continue_hp_ratio, 1.0)
	check("continue_uses_new_max", is_equal_approx(r.damage.health, 95.0 * 0.8), "%.1f" % r.damage.health)
	r.free()


# ======================================================================================================
# 11-15 / C. challenges
# ======================================================================================================

func _rounds() -> Array:
	var out := []
	for id in gm.campaign.order:
		var types := []
		for ch in gm.campaign.node(id).get("stars", []):
			types.append(String(ch.type))
		out.append(types)
	return out


func challenge_tests() -> void:
	var c := gm.campaign
	check("stars_load_and_validate", c.load_error == "" and c.order.size() == 100, c.load_error)
	var rounds := _rounds()
	var early_feet := 0
	for i in 5:
		early_feet += int(rounds[i].any(func(t: String) -> bool: return t in FEET))
	check("feet_not_on_every_early_level", early_feet <= 2, "%d of r1-r5" % early_feet)
	var consecutive := []
	var fam_consecutive := []
	for i in range(1, rounds.size()):
		for t in rounds[i]:
			if t in rounds[i - 1]:
				consecutive.append("r%d %s" % [i + 1, t])
		var feet_now: bool = rounds[i].any(func(t: String) -> bool: return t in FEET)
		var feet_prev: bool = rounds[i - 1].any(func(t: String) -> bool: return t in FEET)
		if feet_now and feet_prev:
			fam_consecutive.append("r%d" % (i + 1))
	check("no_type_on_consecutive_levels", consecutive.is_empty(), str(consecutive))
	check("feet_variants_count_as_same_behaviour", fam_consecutive.is_empty(), str(fam_consecutive))
	var mixed := true
	for rw in rounds:
		mixed = mixed and not (rw.has("GOOD_LANDING_STREAK") and rw.has("TOTAL_GOOD_LANDINGS"))
		mixed = mixed and not (rw.has("CHARGED_LANDING") and rw.has("CHARGED_LANDING_STREAK"))
	check("one_level_different_behaviours", mixed)
	var first10 := {}
	for i in 10:
		for t in rounds[i]:
			first10[t] = true
	check("r1_r10_variety", first10.size() >= 12, "%d distinct types" % first10.size())
	var count := {}
	for rw in rounds:
		for t in rw:
			count[t] = int(count.get(t, 0)) + 1
	var top := 0
	for t in count:
		top = maxi(top, int(count[t]))
	check("no_type_dominates_r1_r100", top <= 20 and count.size() >= 20, "max %d of 300, %d types" % [top, count.size()])
	var removed_found := false
	for t in count:
		removed_found = removed_found or t in REMOVED
	check("removed_types_absent", not removed_found)
	# feet streak scaling + biome adjustment never raises it
	var stage_ok := true
	var biome_ok := true
	var no_touch_ok := true
	var caps_ok := true
	for i in c.order.size():
		var node: Dictionary = c.node(c.order[i])
		var r := i + 1
		for j in node.stars_base.size():
			var base: Dictionary = node.stars_base[j]
			var adj: Dictionary = node.stars[j]
			# v36: a slot may hold a biome replacement (BiomeChallenges.resolve) - authored rules are checked on the
			# authored challenge, caps on the resolved one by ITS type, and "never raised" only for the same type
			var same_type := String(adj.type) == String(base.type)
			if String(base.type) == "GOOD_LANDING_STREAK":
				var want := 3 if r <= 33 else (4 if r <= 66 else 5)
				stage_ok = stage_ok and int(base.n) == want
				biome_ok = biome_ok and (not same_type or (int(adj.n) <= int(base.n) and int(adj.n) >= 1))
			if String(base.type) == "TOTAL_GOOD_LANDINGS":
				stage_ok = stage_ok and int(base.n) <= 5
				biome_ok = biome_ok and (not same_type or int(adj.n) <= int(base.n))
			if String(base.type) == "NO_TOUCH_AND_WIN":
				no_touch_ok = no_touch_ok and is_equal_approx(float(base.s), 3.5)
			if String(adj.type) == "NO_TOUCH_AND_WIN":
				no_touch_ok = no_touch_ok and is_equal_approx(float(adj.s), 3.5)
			if String(adj.type) == "MAX_HEIGHT_M":
				caps_ok = caps_ok and float(adj.m) <= 30.0
			if String(adj.type) == "SPEED_TARGET":
				caps_ok = caps_ok and float(adj.kmh) <= 100.0
	check("feet_streak_3_4_5_by_stage", stage_ok)
	check("biome_adjust_never_raises_feet_goals", biome_ok)
	check("no_touch_still_3_5_and_caps", no_touch_ok and caps_ok)
	var again := CampaignData.load_file(gm.campaign_path)
	var same := true
	for id in c.order:
		same = same and JSON.stringify(again.node(id).stars) == JSON.stringify(c.node(id).stars) and again.node(id).biome == c.node(id).biome
	check("generation_deterministic", same)
	# v32 rocket-head exclusion intact
	var st := StarTracker.new([{"type": "NO_TOUCH_AND_WIN", "s": 3.5}])
	st.sample_no_touch(3.4, false)
	st.sample_no_touch(1.0, false, true)
	st.on_race_result(true, 120.0, 100.0)
	check("no_touch_rocket_exclusion_intact", st.status[0] != 1)


## Real physics: the starter robot (Растабот, 95 HP) lands cleanly on its feet again and again (a skilled player is
## simulated by keeping it upright); every feet contact costs real damage. The longest streak before it breaks must
## cover the late requirement (5).
func feasibility() -> void:
	var results := {}
	for id in ["tin", "hopper"]:
		gm.go_menu()
		await frames(2)
		if not gm.profile.owned.has(id):
			gm.profile.owned.append(id)
		gm.profile.selected = id
		gm.mode = &"free"
		gm.debug_track_seed = 4242
		gm.ui.biome_intro.instant = true
		gm.start_run()
		gm.debug_track_seed = -1
		await frames(3)
		gm.hand.playing = false
		gm.hand.visible = false
		gm.ui.flick_bar.hide_immediate()
		gm.state = GameManager.State.RUN
		var r := gm.robot
		r.launch(Vector2(600, -350), 0.0)
		var streak := [0, 0]
		r.landed.connect(func(i: Dictionary) -> void:
			if String(i.type) in ["left", "right", "both"]:
				streak[0] += 1
				streak[1] = maxi(streak[1], streak[0])
			elif String(i.type) != "soft":
				streak[0] = 0)
		for k in 120 * 14:
			await get_tree().physics_frame
			if not is_instance_valid(r) or gm.state != GameManager.State.RUN or r.damage.health <= 0.0:
				break
			r.angular_velocity = 0.0
			r.rotation = 0.0
		results[id] = [streak[1], r.damage.health if is_instance_valid(r) else 0.0]
	check("feet_streak_feasible_starter_robot", int(results.tin[0]) >= 5, "longest clean feet streak: %s" % results)


# ======================================================================================================
# 14. tutorial (real inputs, real gameplay events)
# ======================================================================================================

func _press_at(pos: Vector2, hold_frames := 2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await frames(hold_frames)
	var u := e.duplicate() as InputEventMouseButton
	u.pressed = false
	Input.parse_input_event(u)
	await frames(2)


func _hold(on: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = on
	var p := Vector2(220, 520)
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)
	await frames(1)


## Tap the real flick bar like a player who waits for the green / yellow zone.
func _tap_flick() -> void:
	for k in 600:
		if gm.ui.flick_bar.active and not gm.ui.flick_bar.locked and gm.ui.flick_bar.locked_tier in ["NORMAL", "STRONG"]:
			break
		await frames(1)
	await _press_at(_free_spot())


func _free_spot() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	return Vector2(vp.x * 0.5, vp.y * 0.72)


func _start_tutorial() -> TutorialDirector:
	gm.go_menu()
	await frames(2)
	gm.begin_tutorial(&"campaign")
	if gm.ui.awareness.visible:
		gm.ui.awareness.confirm.pressed.emit()
	await frames(4)
	return gm.tutorial


## Keep the robot upright until its next feet landing (a skilled player's correction).
func _land_upright(td: TutorialDirector, until_step: int, max_s := 6.0) -> void:
	for k in int(120 * max_s):
		await get_tree().physics_frame
		if td.step != until_step or not td.active:
			return
		if is_instance_valid(gm.robot):
			gm.robot.angular_velocity = 0.0
			gm.robot.rotation = 0.0


func _wait_step(td: TutorialDirector, s: int, max_s: float) -> bool:
	var t := 0.0
	while t < max_s:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if td.step == s:
			return true
	return td.step == s


func tutorial_tests() -> void:
	gm.profile.tutorial = {"handled": false, "completed": false}
	var td := await _start_tutorial()
	check("tutorial_starts_on_flick", td != null and td.step == TutorialDirector.Step.FLICK and gm.ui.flick_bar.active and gm.mode == &"tutorial"
		and gm.terrain.training)
	# time alone never completes a step
	await physics(120 * 3)
	check("flick_not_completed_by_time", td.step == TutorialDirector.Step.FLICK and gm.state == GameManager.State.INTRO)
	# an unrelated touch (on the skip button) does not flick; it only opens the deliberate confirmation
	var sk := gm.ui.tutorial_overlay.skip
	await _press_at(sk.get_global_rect().get_center())
	check("unrelated_touch_no_flick_skip_needs_confirm", td.step == TutorialDirector.Step.FLICK and gm.state == GameManager.State.INTRO
		and gm.ui.tutorial_overlay.confirm.visible and gm.tutorial == td)
	gm.ui.tutorial_overlay.confirm_no.pressed.emit()
	# a weak (МИН) flick -> retry the flick, not the tutorial
	var bar := gm.ui.flick_bar
	bar.lock_tier("MINIMUM")
	gm.hand.release_flick()
	await physics(4)
	var weak_retry := await _wait_step(td, TutorialDirector.Step.FLICK, 2.0) and td.retries >= 1
	await frames(130)
	check("weak_flick_retries_flick_only", weak_retry and td.step == TutorialDirector.Step.FLICK and gm.state == GameManager.State.INTRO and bar.active)
	# the real tap on the flick bar launches -> FLICK learned, ROTATE next
	await _tap_flick()
	await _wait_step(td, TutorialDirector.Step.ROTATE, 4.0)
	check("valid_flick_completes_flick_only", td.step == TutorialDirector.Step.ROTATE and gm.state == GameManager.State.RUN
		and td.completions == ["FLICK"], str(td.completions))
	# rotation needs a real hold that really turns the robot counter-clockwise
	await physics(120)
	check("rotation_not_from_time", td.step == TutorialDirector.Step.ROTATE)
	await _hold(true)
	var learned := await _wait_step(td, TutorialDirector.Step.FEET, 3.0)
	await _hold(false)
	check("rotation_needs_hold_and_ccw_turn", learned and td.completions.has("ROTATE"))
	# body / head contact is not a feet landing
	var r := gm.robot
	r.global_position = Vector2(-1000, gm.terrain.height_at(-1000) - 260)
	r.rotation = PI
	r.angular_velocity = 0.0
	r.linear_velocity = Vector2(100, 200)
	var bad := false
	for k in 120 * 2:
		await get_tree().physics_frame
		r.rotation = PI
		r.angular_velocity = 0.0
		if r.contacts.any_body_contact:
			bad = true
		if bad and k > 40:
			break
	check("body_or_head_contact_not_feet", bad and td.step == TutorialDirector.Step.FEET)
	# a real feet landing -> FEET learned; the rebound itself completes REBOUND
	td.practice_throw()
	await physics(2)
	await _land_upright(td, TutorialDirector.Step.FEET)
	var reb := await _wait_step(td, TutorialDirector.Step.CHARGE, 3.0)
	check("feet_landing_then_spring_rebound", reb and td.completions.has("FEET") and td.completions.has("REBOUND"), str(td.completions))
	# charge: real airborne clockwise spin (not holding) must fill the charge
	var charged := await _wait_step(td, TutorialDirector.Step.CHARGED, 8.0)
	check("charge_step_needs_real_charge", charged and td.completions.has("CHARGE"))
	# charged contact on the feet (real charge_released on zone "feet")
	await _land_upright(td, TutorialDirector.Step.CHARGED, 8.0)
	await physics(4)
	var done := td.step == TutorialDirector.Step.DONE
	if not done:
		# missed the charged landing (e.g. it came down before charging): a retry is offered at CHARGE, never a restart
		check("charged_miss_returns_to_charge_only", td.step in [TutorialDirector.Step.CHARGE, TutorialDirector.Step.CHARGED] and td.active)
		await _wait_step(td, TutorialDirector.Step.CHARGED, 8.0)
		await _land_upright(td, TutorialDirector.Step.CHARGED, 8.0)
		await physics(4)
		done = td.step == TutorialDirector.Step.DONE
	check("charged_feet_landing_finishes", done and gm.ui.tutorial_overlay.done_card.visible, str(td.completions))
	# retries: a stalled robot gets a new practice throw and keeps the step
	var retries := td.retries
	var coins := gm.profile.coins
	var camp := JSON.stringify(gm.profile.campaign)
	gm.ui.tutorial_overlay.play.pressed.emit()
	await frames(3)
	check("tutorial_finish_cleanly_to_campaign", gm.tutorial == null and bool(gm.profile.tutorial.completed) and gm.ui.is_campaign_map_open()
		and is_equal_approx(Engine.time_scale, 1.0) and not gm.terrain.training)
	check("tutorial_keeps_profile_state", gm.profile.coins == coins and JSON.stringify(gm.profile.campaign) == camp)
	await retry_tests()
	await physics_restored()


func retry_tests() -> void:
	gm.ui.campaign_map.visible = false
	gm.go_menu()
	await frames(2)
	var td := await _start_tutorial()
	print("AT|diag before tap state=%s bar_active=%s locked=%s hand_playing=%s blocked=%s awareness=%s" % [GameManager.State.keys()[gm.state],
		gm.ui.flick_bar.active, gm.ui.flick_bar.locked, gm.hand.playing, gm.ui.blocks_point(_free_spot()), gm.ui.awareness.visible])
	await _tap_flick()
	print("AT|diag after tap state=%s locked=%s hand_playing=%s" % [GameManager.State.keys()[gm.state], gm.ui.flick_bar.locked, gm.hand.playing])
	await _wait_step(td, TutorialDirector.Step.ROTATE, 4.0)   # the hand finishes its wind-up, then flicks
	# stop the robot on the ground: the tutorial gives a new throw and stays on the same step
	var step := td.step
	var r := gm.robot
	r.linear_velocity = Vector2.ZERO
	r.angular_velocity = 0.0
	r.global_position = Vector2(-1000, gm.terrain.height_at(-1000) - 150)
	r.rotation = 0.0
	var rt := td.retries
	for k in 120 * 4:
		await get_tree().physics_frame
		if td.retries > rt:
			break
		if is_instance_valid(gm.robot) and gm.robot == r:
			r.linear_velocity = Vector2.ZERO
	check("retry_after_mistake_same_step", td.retries > rt and td.step == step and td.active, "step %s" % TutorialDirector.Step.keys()[td.step])
	# skip needs ДА; it ends the tutorial without completing it
	gm.ui.tutorial_overlay.skip.pressed.emit()
	await frames(2)
	var still := gm.tutorial == td
	gm.ui.tutorial_overlay.confirm_yes.pressed.emit()
	await frames(3)
	check("skip_deliberate", still and gm.tutorial == null and bool(gm.profile.tutorial.handled))
	gm.ui.campaign_map.visible = false
	gm.go_menu()
	await frames(2)


func physics_restored() -> void:
	gm.go_menu()
	await frames(2)
	var ok := is_equal_approx(Engine.time_scale, 1.0) and not gm.terrain.training and gm.mode != &"tutorial" \
		and is_equal_approx(gm.robot.config.clockwise_rotation_speed, gm.settings.get_value("auto_rps")) \
		and is_equal_approx(float(ProjectSettings.get_setting("physics/2d/default_gravity")), 1800.0) \
		and gm.robot_def.id != "samurai" or gm.profile.selected == "samurai"
	check("normal_physics_unchanged_after_tutorial", ok)


# ======================================================================================================
# 7. profile-specific tutorial, persistence, replay
# ======================================================================================================

func _wipe(dir_path: String) -> void:
	var abs := ProjectSettings.globalize_path(dir_path)
	var d := DirAccess.open(abs)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_wipe(dir_path.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(abs)


func profile_tutorial_tests() -> void:
	var root := "user://test/v33/profiles/"
	_wipe(root)
	gm.go_menu()
	await frames(2)
	gm.auto_tutorial_new_profile = true
	gm.profiles = ProfileManager.new(root)
	gm.profiles.migrate_legacy()
	gm._use_placeholder_profile()
	gm._bind_profile_ui()
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(4)
	check("new_profile_enters_tutorial", gm.tutorial != null and gm.active_slot == 1 and gm.tutorial.step == TutorialDirector.Step.FLICK)
	gm.tutorial.active = false
	gm.finish_tutorial(true, false)   # completed (the step-by-step path is covered above)
	await frames(2)
	var p1 := ProfileStore.new(gm.profiles.profile_path(1), gm.catalog)
	p1.load_data()
	check("completion_persists", bool(p1.tutorial.completed) and bool(p1.tutorial.handled))
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[1].pressed.emit()
	await frames(4)
	check("p1_completion_does_not_complete_p2", gm.active_slot == 2 and gm.tutorial != null and not bool(gm.profile.tutorial.completed))
	gm.tutorial.active = false
	gm.finish_tutorial(false, false)
	await frames(2)
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(4)
	check("returning_player_not_forced", gm.active_slot == 1 and gm.tutorial == null and bool(gm.profile.tutorial.completed))
	# replay from Settings
	gm.ui.tutorial_pressed.emit()
	await frames(2)
	if gm.ui.awareness.visible:
		gm.ui.awareness.confirm.pressed.emit()
	await frames(4)
	check("replay_from_settings", gm.tutorial != null and gm.tutorial.step == TutorialDirector.Step.FLICK)
	gm.tutorial.active = false
	gm.finish_tutorial(false, false)
	await frames(2)
	check("replay_keeps_completion", bool(gm.profile.tutorial.completed))
	gm.profiles = null
	gm.active_slot = 0
	gm._open_stats()
	gm._open_profile()
	gm.auto_tutorial_new_profile = false


# ======================================================================================================
# 16. visual QA
# ======================================================================================================

func qa() -> void:
	gm.go_menu()
	await frames(10)
	gm.ui.open_settings()
	await frames(60)
	at.call("_shot", "v33_settings_over_menu_robot")
	gm.ui.close_settings()
	gm.ui.open_stats()
	await frames(60)
	at.call("_shot", "v33_stats_over_menu_robot")
	gm.ui.close_stats()
	gm.profile.tutorial = {"handled": false, "completed": false}
	gm.request_mode(&"campaign")
	await frames(6)
	at.call("_shot", "v33_tutorial_offer_card")
	var td := await _start_tutorial()
	await frames(40)
	at.call("_shot", "v33_t1_flick")
	await _tap_flick()
	await physics(30)
	at.call("_shot", "v33_t2_rotate")
	await _hold(true)
	await _wait_step(td, TutorialDirector.Step.FEET, 3.0)
	await frames(2)
	at.call("_shot", "v33_t2_success_pop")
	await _hold(false)
	await physics(20)
	at.call("_shot", "v33_t3_feet")
	var r := gm.robot
	r.rotation = PI
	for k in 120 * 2:
		await get_tree().physics_frame
		if is_instance_valid(r):
			r.rotation = PI
			r.angular_velocity = 0.0
			if r.contacts.any_body_contact:
				await frames(3)
				at.call("_shot", "v33_t3_body_fail")
				break
	td.practice_throw()
	await frames(6)
	at.call("_shot", "v33_retry_throw")
	await _land_upright(td, TutorialDirector.Step.FEET)
	await frames(3)
	at.call("_shot", "v33_t4_rebound")
	await _wait_step(td, TutorialDirector.Step.CHARGE, 3.0)
	await physics(25)
	at.call("_shot", "v33_t5_charge")
	await _wait_step(td, TutorialDirector.Step.CHARGED, 8.0)
	await frames(3)
	at.call("_shot", "v33_t6_charged")
	await _land_upright(td, TutorialDirector.Step.CHARGED, 8.0)
	await frames(10)
	at.call("_shot", "v33_t7_done")
	gm.ui.tutorial_overlay.skip.pressed.emit()
	await frames(4)
	at.call("_shot", "v33_skip_confirm")
	gm.ui.tutorial_overlay.confirm_yes.pressed.emit()
	await frames(4)
	check("qa_done", true)
