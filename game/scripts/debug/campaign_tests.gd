extends Node
## Debug-only campaign / AI / economy / skins tests (not exported).
##   --scenario=campaign : unit + flow tests          --scenario=ai_sim [--sim_seeds=N] : AI distance statistics
## Prints "AT|test <name> PASS|FAIL <details>" and "AT|sim ..." lines.

var gm: GameManager
var at: Node
var passed := 0
var failed := 0


func _check(name: String, ok: bool, details: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("AT|test %s %s %s" % [name, "PASS" if ok else "FAIL", details])


func run_all(which: String) -> void:
	if which == "campaign":
		_economy_tests()
		_profile_tests()
		_skin_tests()
		_adaptive_tests()
		_campaign_data_tests()
		await _race_tests()
		await _flow_tests()
	elif which == "ai_sim":
		await _ai_sim()
	elif which == "campaign_shots":
		await _shots()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ---------------- economy ----------------

func _economy_tests() -> void:
	var e := gm.economy
	var cases := {0.0: 0, 4.9: 0, 5.0: 1, 9.99: 1, 10.0: 2, 14.0: 2, 500.0: 100, 1000.0: 200, 1004.9: 200}
	var bad := []
	for m in cases:
		if e.free_run_coins(m) != cases[m]:
			bad.append("%s->%d" % [m, e.free_run_coins(m)])
	_check("free_run_coins_floor_div5", bad.is_empty(), "bad=%s" % [bad])
	var rw := []
	for i in 6:
		rw.append(e.replay_reward(100, i))
	_check("replay_reward_decays_to_zero", rw[0] == 10 and rw[1] == 5 and rw[2] == 2 and rw[4] == 0 and rw[5] == 0, "first_clear=100 -> replay wins %s" % [rw])
	# farming check: best possible replay income of round 1 (all replays) vs one ordinary Free Run attempt (~400 m)
	var r1 := int(gm.campaign.node("r1").reward_first)
	var farm := 0
	for i in 50:
		farm += e.replay_reward(r1, i)
	_check("no_early_round_farming", farm < e.free_run_coins(400.0), "50 replay wins of r1 pay %d coins in total, one 400 m Free Run pays %d" % [farm, e.free_run_coins(400.0)])


# ---------------- profile / save migration ----------------

func _profile_tests() -> void:
	var path := "user://test/campaign_profile.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# v1 file (v0.9 format) -> v2 keeps coins / robots / selection
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "coins": 1234, "owned": ["tin", "hopper"], "selected": "hopper"}))
	f.close()
	var p := ProfileStore.new(path, gm.catalog, gm.skins)
	p.load_data()
	_check("migration_v1_keeps_profile", p.coins == 1234 and p.owned.has("hopper") and p.owned.has("tin") and p.selected == "hopper"
		and p.loaded_version == 1 and p.campaign.completed.is_empty() and p.owned_skins.is_empty(),
		"coins=%d owned=%s selected=%s status=%s" % [p.coins, p.owned, p.selected, p.last_load_status])
	p.ensure_campaign_start("r1")
	p.save()
	var p2 := ProfileStore.new(path, gm.catalog, gm.skins)
	p2.load_data()
	_check("migration_saved_as_current", p2.loaded_version == ProfileStore.VERSION and p2.coins == 1234 and p2.is_unlocked("r1"),
		"version=%d status=%s" % [p2.loaded_version, p2.last_load_status])
	# progression: locked / unlock / complete / first-clear once
	_check("locked_until_unlocked", p2.is_unlocked("r1") and not p2.is_unlocked("r2"), "")
	var first := p2.complete("r1", ["r2"])
	var again := p2.complete("r1", ["r2"])
	var paid1 := p2.claim_first_clear("r1", 45)
	var paid2 := p2.claim_first_clear("r1", 45)
	_check("first_clear_once", first and not again and paid1 and not paid2 and p2.coins == 1234 + 45 and p2.is_unlocked("r2"),
		"first=%s again=%s paid=%s/%s coins=%d" % [first, again, paid1, paid2, p2.coins])
	var p3 := ProfileStore.new(path, gm.catalog, gm.skins)
	p3.load_data()
	_check("campaign_progress_persists", p3.is_completed("r1") and p3.is_unlocked("r2") and p3.campaign.claimed.has("r1")
		and not p3.claim_first_clear("r1", 45), "completed=%s unlocked=%s" % [p3.campaign.completed, p3.campaign.unlocked])
	# broken field repair keeps the rest
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2, "coins": 50, "owned": ["tin"], "selected": "tin", "campaign": {"completed": "bad", "unlocked": ["r1", 7]},
		"owned_skins": ["no_such_skin", "tin_copper"], "equipped_skins": {"tin": "tin_copper", "hopper": "tin_copper"}}))
	f.close()
	var p4 := ProfileStore.new(path, gm.catalog, gm.skins)
	p4.load_data()
	_check("repair_bad_fields", p4.coins == 50 and p4.is_unlocked("r1") and p4.campaign.completed.is_empty() and p4.owned_skins == ["tin_copper"]
		and p4.equipped_skin("tin") == "tin_copper" and p4.equipped_skin("hopper") == "hopper_default" and p4.last_load_status == "repaired",
		"skins=%s eq=%s status=%s" % [p4.owned_skins, p4.equipped_skins, p4.last_load_status])


# ---------------- skins ----------------

func _skin_tests() -> void:
	var path := "user://test/skin_profile.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var p := ProfileStore.new(path, gm.catalog, gm.skins)
	p.load_data()
	var g1 := p.grant_skin("samurai_shogun")
	var g2 := p.grant_skin("samurai_shogun")
	var wrong := p.equip_skin("tin", "samurai_shogun")
	var locked := p.equip_skin("tin", "tin_copper")
	var ok := p.equip_skin("samurai", "samurai_shogun")
	var p2 := ProfileStore.new(path, gm.catalog, gm.skins)
	p2.load_data()
	_check("skin_grant_once_equip_persist", g1 and not g2 and not wrong and not locked and ok and p2.owns_skin("samurai_shogun")
		and p2.equipped_skin("samurai") == "samurai_shogun" and p2.equipped_skin("tin") == "tin_default",
		"grant=%s/%s wrong_robot=%s not_owned=%s equip=%s reload_eq=%s" % [g1, g2, wrong, locked, ok, p2.equipped_skin("samurai")])
	# cosmetic only: every gameplay number identical with every skin of every archetype
	var diffs := []
	for d in gm.catalog.robots:
		var ref := _physics_signature(d, SkinDefinition.default_id(d.id))
		for s in gm.skins.for_robot(d.id):
			var sig := _physics_signature(d, s.id)
			if sig != ref:
				diffs.append("%s/%s" % [d.id, s.id])
	_check("skins_are_cosmetic_only", diffs.is_empty() and gm.skins.skins.size() >= 9, "skins=%d differing=%s" % [gm.skins.skins.size(), diffs])
	var sk_mat := 0
	for s in gm.skins.skins:
		if s.source == "campaign" and s.make_material() != null:
			sk_mat += 1
	# v36: + Chronobot "Серебряный хронометр"; every campaign scheme has repainted art for BASE and MK2 (fallback palette kept)
	var art_ok := gm.skins.skins.all(func(s: SkinDefinition) -> bool: return s.source != "campaign" or (s.has_art(gm.catalog.get_by_id(s.robot_id), false) and s.has_art(gm.catalog.get_by_id(s.robot_id), true)))
	_check("boss_skins_defined", sk_mat == 5 and art_ok, "campaign skins with a palette=%d, repainted art for both versions=%s" % [sk_mat, art_ok])


func _physics_signature(d: RobotDefinition, skin_id: String) -> String:
	var r := gm.build_robot(d, gm.input, null, skin_id)
	var rc := r.config
	var cc := r.contact_config
	var out := [rc.torso_mass, rc.head_mass, rc.arm_mass, rc.leg_mass, rc.rotation_response, rc.rig_scale, rc.inertia_radius,
		rc.charge_rate, rc.energy_boost_multiplier, rc.max_speed, rc.clockwise_rotation_speed, cc.spring_stiffness,
		cc.coil_rest_length, cc.gain_both_flat, r.damage_config.max_health]
	r.free()
	return str(out)


# ---------------- adaptive ----------------

func _res(player: float, enemy: float, won: bool, att := 3) -> Dictionary:
	return {"player_m": player, "best_enemy_m": enemy, "won": won, "attempts": att, "hp_ratio": 0.5, "difficulty": "normal"}


func _adaptive_tests() -> void:
	var cfg := gm.adaptive_config
	var a := AdaptiveDifficulty.new(cfg, {})
	var one := a.record(_res(900, 300, true, 1))
	_check("one_result_small_change", absf(one) < 0.02, "after one crushing win modifier=%+.3f" % one)
	var b := AdaptiveDifficulty.new(cfg, {})
	var close := []
	for i in 12:
		close.append(snappedf(b.record(_res(290, 300, false, 3)), 0.001))
	_check("close_losses_do_not_ease", close.all(func(v: float) -> bool: return v == 0.0), "12 close losses (-3%%) -> %s" % [close.slice(-3)])
	var c := AdaptiveDifficulty.new(cfg, {})
	var down := []
	for i in 12:
		down.append(snappedf(c.record(_res(120, 400, false, 3)), 0.001))
	_check("big_losses_ease_gradually", down[0] == 0.0 and down[11] < -0.04 and down[11] >= -cfg.max_down and _monotonic(down, -1),
		"modifier after each heavy loss: %s" % [down])
	var d := AdaptiveDifficulty.new(cfg, {})
	var up := []
	for i in 12:
		up.append(snappedf(d.record(_res(700, 300, true, 1)), 0.001))
	_check("dominant_wins_raise_gradually", up[0] < 0.02 and up[11] > 0.04 and up[11] <= cfg.max_up and _monotonic(up, 1),
		"modifier after each dominant win: %s" % [up])
	var e := AdaptiveDifficulty.new(cfg, {})
	var mn := 0.0
	var mx := 0.0
	for i in 400:
		var m := e.record(_res(1000, 50, true, 1) if i < 200 else _res(10, 900, false, 9))
		mn = minf(mn, m)
		mx = maxf(mx, m)
	_check("modifier_bounded", mx <= cfg.max_up + 0.0001 and mn >= -cfg.max_down - 0.0001, "range seen [%+.3f, %+.3f] bounds [-%.2f, +%.2f]" % [mn, mx, cfg.max_down, cfg.max_up])
	# effective skill keeps the round order: round 5 can never reach round 40, nor 40 drop to 5
	var s5 := float(gm.campaign.node("r5").enemies[0].skill)
	var s40 := float(gm.campaign.node("r40").enemies[0].skill)
	_check("adaptive_keeps_round_order", s5 + cfg.max_up < s40 - cfg.max_down, "r5 max %.2f < r40 min %.2f" % [s5 + cfg.max_up, s40 - cfg.max_down])


func _monotonic(arr: Array, dir: int) -> bool:
	for i in range(1, arr.size()):
		if (arr[i] - arr[i - 1]) * dir < -0.00001:
			return false
	return true


# ---------------- campaign data ----------------

func _campaign_data_tests() -> void:
	var c := gm.campaign
	var races := c.order.filter(func(id: String) -> bool: return c.is_playable(id))
	var chain_ok := true
	for i in c.order.size() - 1:
		chain_ok = chain_ok and c.main_next(c.order[i]) == c.order[i + 1]
	var bosses := c.order.filter(func(id: String) -> bool: return c.node(id).difficulty == "boss")
	_check("campaign_40_rounds_chain", races.size() == 100 and chain_ok and c.main_next("r100") == "" and bosses == ["r10", "r20", "r30", "r40", "r50", "r60", "r70", "r80", "r90", "r100"],
		"races=%d bosses=%s" % [races.size(), bosses])
	var avg := func(a: int, b: int) -> float:
		var s := 0.0
		var n := 0
		for i in range(a, b + 1):
			for e in c.node("r%d" % i).enemies:
				s += float(e.skill)
				n += 1
		return s / n
	var early: float = avg.call(1, 10)
	var mid: float = avg.call(15, 25)
	var late: float = avg.call(31, 40)
	var top := 0.0
	for id in c.order:
		for e in c.node(id).enemies:
			top = maxf(top, float(e.skill))
	_check("difficulty_rises", early < mid and mid < late and float(c.node("r40").enemies[0].skill) >= top,
		"avg skill r1-10=%.2f r15-25=%.2f r31-40=%.2f r40=%.2f" % [early, mid, late, float(c.node("r40").enemies[0].skill)])
	var rw_ok := true
	for i in range(1, 40):
		var a := c.node("r%d" % i)
		var b := c.node("r%d" % (i + 1))
		if a.difficulty == "normal" and b.difficulty == "normal" and int(b.reward_first) < int(a.reward_first):
			rw_ok = false
	var boss_bigger: bool = int(c.node("r10").reward_first) > 2 * int(c.node("r9").reward_first)
	var skins_ok := bosses.all(func(id: String) -> bool: return gm.skins.get_by_id(String(c.node(id).get("reward_skin", ""))) != null)
	_check("rewards_rise_bosses_special", rw_ok and boss_bigger and skins_ok, "r1=%d r9=%d r10=%d r39=%d r40=%d" % [c.node("r1").reward_first,
		c.node("r9").reward_first, c.node("r10").reward_first, c.node("r39").reward_first, c.node("r40").reward_first])
	var two := c.order.filter(func(id: String) -> bool: return c.node(id).enemies.size() == 2)
	_check("one_and_two_enemy_rounds", two.size() >= 4 and c.node("r1").enemies.size() == 1, "two-opponent rounds=%s" % [two])
	# future node types: a non-race node is drawn but not playable, branches are allowed
	var g := CampaignData.new()
	g.from_dict({"start": "a", "nodes": [{"id": "a", "next": ["b", "x"]}, {"id": "x", "type": "bonus", "next": ["b"]}, {"id": "b"}]})
	_check("graph_supports_branches_and_types", g.main_next("a") == "b" and not g.is_playable("x") and g.next_ids("a").size() == 2 and g.edges().size() == 3, "")


# ---------------- race (physics) ----------------

func _start_race(node: String, seed := 77) -> void:
	gm.mode = &"campaign"
	gm.node_id = node
	gm.profile.ensure_campaign_start(node)
	await get_tree().process_frame
	at.call("start_seen_run")
	gm.hand.rush()


func _race_tests() -> void:
	await _start_race("r8")
	var r := gm.race
	var cs := r.competitors
	var player := gm.robot
	var layers_ok := cs.size() == 2
	for c in cs:
		layers_ok = layers_ok and c.robot.collision_mask == RobotController.LAYER_GROUND and c.robot.collision_layer == RobotController.LAYER_ROBOT \
			and c.robot.collision_mask & RobotController.LAYER_ROBOT == 0
	layers_ok = layers_ok and player.collision_mask & RobotController.LAYER_ROBOT == 0
	_check("no_robot_robot_collision", layers_ok, "player mask=%d enemy layer/mask=%d/%d" % [player.collision_mask, cs[0].robot.collision_layer, cs[0].robot.collision_mask])
	_check("two_enemy_round_spawned", cs.size() == 2 and cs[0].ai != null and cs[1].ai != null and cs[0].control != gm.input, "")
	# wait for the launch and watch the race: positions only change by physics (no jumps)
	var t := 0.0
	while gm.state == GameManager.State.INTRO and t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	var prev := []
	for c in cs:
		prev.append(c.robot.global_position)
	var max_jump := 0.0
	var overlap_frames := 0
	var ground_contacts := 0
	t = 0.0
	while t < 10.0 and gm.state != GameManager.State.RESULT:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		for i in cs.size():
			var c: RaceManager.Competitor = cs[i]
			if not is_instance_valid(c.robot):
				continue
			var p := c.robot.global_position
			var allowed: float = c.robot.config.max_speed / 120.0 * 1.5 + 2.0
			max_jump = maxf(max_jump, p.distance_to(prev[i]) / allowed)
			prev[i] = p
			if c.robot.contacts.any_contact:
				ground_contacts += 1
			if is_instance_valid(player) and p.distance_to(player.global_position) < 80.0:
				overlap_frames += 1
	_check("enemies_touch_terrain", ground_contacts > 30, "enemy ground-contact frames=%d" % ground_contacts)
	_check("ai_no_teleport", max_jump <= 1.0, "max per-step displacement / (max_speed*dt*1.5)=%.2f" % max_jump)
	# the AI never writes physics state: only InputRouter.set_virtual_hold
	var src := FileAccess.get_file_as_string("res://scripts/ai/enemy_ai.gd")
	var forbidden := ["global_position =", "linear_velocity =", "angular_velocity =", "rotation =", "position =", ".apply_impulse", ".apply_force", ".apply_torque", "distance ="]
	var hits := forbidden.filter(func(s: String) -> bool: return src.contains(s))
	_check("ai_only_uses_input", hits.is_empty() and src.contains("set_virtual_hold"), "forbidden writes found=%s" % [hits])
	var dys := cs.map(func(c: RaceManager.Competitor) -> String: return "x=%.0f dy=%.0f vy=%.0f state=%s" % [c.robot.global_position.x, c.robot.global_position.y - gm.terrain.height_at(c.robot.global_position.x), c.robot.linear_velocity.y, str(c.robot.contacts.any_contact)])
	# v34 (legit update): with the approved 200 % springs an airborne rival can legitimately be ~25 m up; "same track" =
	# never further below the surface than 2500 px, and never higher than the 30 m flight cap (+10 m margin)
	var ceiling_px: float = (StarChallenges.MAX_HEIGHT_CAP_M + 10.0) * gm.level_config.px_per_meter
	_check("same_track_for_all", cs.all(func(c: RaceManager.Competitor) -> bool:
		var dy := c.robot.global_position.y - gm.terrain.height_at(c.robot.global_position.x)
		return dy < 2500.0 and dy > -ceiling_px), "seed=%d %s" % [gm.track_seed, dys])
	# variation: same round, same forced seed, two attempts -> different AI decisions / results
	var runs := []
	for k in 2:
		await _start_race("r5")
		var first_holds := []
		var tt := 0.0
		while gm.state != GameManager.State.RUN and tt < 6.0:
			await get_tree().physics_frame
			tt += 1.0 / 120.0
		while tt < 12.0:
			await get_tree().physics_frame
			tt += 1.0 / 120.0
			if gm.race.competitors[0].control.holding:
				first_holds.append(int(tt * 20))
		runs.append([snappedf(gm.race.competitors[0].robot.global_position.x, 1.0), first_holds.size(), gm.race.competitors[0].ai.form])
	_check("ai_varies_between_attempts", runs[0] != runs[1], "attempt A [x, hold frames, form]=%s attempt B=%s" % [runs[0], runs[1]])


# ---------------- flow ----------------

func _flow_tests() -> void:
	# fresh progress for the flow
	gm.profile.campaign = ProfileStore.default_campaign()
	gm.profile.ensure_campaign_start(gm.campaign.start_id)
	gm.go_menu()
	await get_tree().process_frame
	gm.open_campaign_map()
	await get_tree().process_frame
	await get_tree().process_frame
	var map := gm.ui.campaign_map
	map.select_node("r3")
	var locked_refused := not map.can_start("r3")
	map.press_start()
	var stayed := map.visible and not gm.ui.robot_select.visible
	map.select_node("r1")
	map.press_start()
	var to_select := gm.ui.robot_select.visible and gm.node_id == "r1"
	_check("map_locked_and_start", locked_refused and stayed and to_select, "locked r3 refused=%s map stayed=%s r1 -> robot select=%s" % [locked_refused, stayed, to_select])
	gm.ui.robot_select.play_requested.emit(gm.profile.selected)
	await get_tree().process_frame
	_check("start_from_select", gm.state == GameManager.State.INTRO and gm.race.competitors.size() == 1, "state=%d" % gm.state)
	# play it out with the bot; force a WIN deterministically by finishing the race through the real rules:
	# the player's distance is real; the result flow is checked whichever way it goes
	var coins0 := gm.profile.coins
	gm.hand.rush()
	var res: Dictionary = await _wait_result(200.0)
	var won: bool = res.get("won", false)
	var unlocked := gm.profile.is_unlocked("r2")
	_check("round_result_flow", not res.is_empty() and gm.ui.campaign_result.visible and (won == unlocked)
		and (not won or (gm.profile.coins == coins0 + int(gm.campaign.node("r1").reward_first) + int(res.get("star_coins", 0)) and res.coins_kind == "first")),
		"won=%s player=%.0f best_enemy=%.0f coins %d->%d next_unlocked=%s next_button=%s" % [won, res.get("player_m", 0.0), res.get("best_enemy_m", 0.0),
		coins0, gm.profile.coins, unlocked, gm.ui.campaign_result.next_button.visible])
	# retry -> same node again, result screen gone
	gm.ui.campaign_result.retry_requested.emit()
	await get_tree().process_frame
	_check("retry_same_round", gm.state == GameManager.State.INTRO and gm.node_id == "r1" and not gm.ui.campaign_result.visible and gm.race.competitors.size() == 1, "")
	# back to the map from a run
	gm.open_campaign_map()
	await get_tree().process_frame
	_check("return_to_map", gm.ui.campaign_map.visible and gm.state == GameManager.State.MENU and gm.race.competitors.is_empty(), "")
	# next round (unlock r2 if the bot lost, through the profile API the result would use)
	gm.profile.complete("r1", ["r2"])
	gm.node_id = "r1"
	gm.ui.campaign_result.next_requested.emit()
	await get_tree().process_frame
	_check("next_round_starts", gm.node_id == "r2" and gm.state == GameManager.State.INTRO, "node=%s state=%d" % [gm.node_id, gm.state])
	# boss first clear -> skin once
	gm.profile.campaign.unlocked.append("r10")
	var before := gm.profile.owned_skins.duplicate()
	var paid := gm.profile.claim_first_clear("r10", 300) and gm.profile.grant_skin("tin_copper")
	var twice := gm.profile.claim_first_clear("r10", 300) or gm.profile.grant_skin("tin_copper")
	_check("boss_reward_and_skin_once", paid and not twice and not before.has("tin_copper") and gm.profile.owns_skin("tin_copper"), "")
	# replaying a cleared round: full race, but the hidden adaptive rating must not move
	# Ensure the fixture represents an already REWARDED clear even if the first physical race was lost.
	gm.profile.complete("r1", ["r2"])
	gm.profile.claim_first_clear("r1", int(gm.campaign.node("r1").reward_first))
	var samples0 := int(gm.adaptive.state.samples)
	var ema0 := float(gm.adaptive.state.ema)
	gm.go_menu()
	await _start_race("r1")
	var rep: Dictionary = await _wait_result(200.0)
	_check("replay_does_not_move_adaptive", not rep.is_empty() and not rep.frontier and int(gm.adaptive.state.samples) == samples0
		and is_equal_approx(float(gm.adaptive.state.ema), ema0) and rep.coins_kind != "first",
		"won=%s kind=%s coins=%d samples %d->%d" % [rep.get("won", false), rep.get("coins_kind", ""), rep.get("coins", 0), samples0, int(gm.adaptive.state.samples)])
	# Free Run still pays floor(m / 5) end-to-end
	gm.go_menu()
	gm.mode = &"free"
	var c0 := gm.profile.coins
	at.call("start_seen_run")
	gm.hand.rush()
	var t := 0.0
	while gm.state != GameManager.State.RESULT and t < 120.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	_check("free_run_coins_end_to_end", gm.profile.coins - c0 == int(floor(gm.distance_m / 5.0)) and gm.race.competitors.is_empty(),
		"distance=%.1f coins +%d" % [gm.distance_m, gm.profile.coins - c0])


func _wait_result(max_s: float) -> Dictionary:
	var t := 0.0
	while gm.state != GameManager.State.RESULT and t < max_s:
		await get_tree().physics_frame
		t += 1.0 / 120.0 * Engine.time_scale
	return gm.campaign_result if gm.state == GameManager.State.RESULT else {}


# ---------------- AI simulation (balance tool) ----------------

## Races many AI robots at once (they never interact) over several seeds and prints distance statistics per
## skill / robot. Usage: --scenario=ai_sim [--sim_seeds=8] [--sim_skills=0.1,0.3,0.5,0.7,0.9] [--sim_robot=tin]
func _ai_sim() -> void:
	var args: Dictionary = at.get("args")
	var seeds := int(args.get("sim_seeds", "6"))
	var skills: Array = Array(String(args.get("sim_skills", "0.1,0.3,0.5,0.7,0.9")).split(",")).map(func(s: String) -> float: return float(s))
	var robot := String(args.get("sim_robot", "tin"))
	var data := {}
	for sk in skills:
		data[sk] = []
	gm.mode = &"campaign"
	var cfg: AIConfig = gm.ai_config.duplicate()
	if args.has("sim_zero_error"):
		for k in ["angle_error_deg", "timing_error", "blunder_chance", "naive_slope_mix", "form_spread"]:
			cfg.set(k, Vector2.ZERO)
		cfg.reaction_delay = Vector2(0.0, 0.0)
		cfg.replan_interval = Vector2(0.01, 0.01)
	for s in seeds:
		var enemies := []
		for sk in skills:
			enemies.append({"name": "AI %.2f" % sk, "robot": robot, "skill": sk, "lean": 18, "greed": 0.3 + 0.45 * sk})
			if args.has("sim_mk2"):
				# v35 paired A/B: the same pilot skill on the same track with the MK2 build
				enemies.append({"name": "AI %.2f MK2" % sk, "robot": robot, "skill": sk, "lean": 18, "greed": 0.3 + 0.45 * sk, "mk2": true})
		gm.state = GameManager.State.MENU
		gm.track_seed = int(args.get("sim_seed_base", "1000")) + s * 17
		gm.terrain.reset(gm.track_seed)
		gm._spawn_robot()
		gm.robot.visible = false
		gm.hand.visible = false
		gm.race.spawn(enemies, 0.0, gm.track_seed, cfg)
		var trackers := []
		for c in gm.race.competitors:
			var objectives := []
			for id in gm.campaign.order:
				objectives.append_array(gm.campaign.node(id).get("stars", []))
			var tracker := StarTracker.new(objectives)
			tracker.attach(c.robot, gm.level_config.px_per_meter)
			trackers.append(tracker)
		await get_tree().physics_frame
		gm.race.launch(Vector2.RIGHT.rotated(-deg_to_rad(gm.launch_angle)) * gm.launch_speed * gm.settings.get_value("flick") / 100.0, gm.robot_config.clockwise_rotation_speed * TAU)
		var t := 0.0
		while not gm.race.all_finished() and t < 260.0:
			await get_tree().physics_frame
			t += 1.0 / 120.0
			var mx := gm.race.max_x()
			if is_finite(mx):
				var mn := gm.race.min_running_x()
				gm.terrain.ensure_ahead(mx, mn if is_finite(mn) else -INF)
			gm.race.step(1.0 / 120.0)
			for i in trackers.size():
				var c: RaceManager.Competitor = gm.race.competitors[i]
				var tracker: StarTracker = trackers[i]
				if tracker.active:
					tracker.step(1.0 / 120.0, c.distance)
					if c.finished:
						tracker.finalize_contact()
						tracker.stop()
		for c in gm.race.competitors:
			var r := c.robot
			var tracker: StarTracker = trackers[c.index]
			var metrics := tracker.metrics()
			var achieved := {}
			for id in gm.campaign.order:
				achieved[id] = gm.campaign.node(id).get("stars", []).map(func(ch: Dictionary) -> bool: return StarTracker.evaluate(ch, metrics))
			print("AT|simrun " + JSON.stringify({"robot": robot, "mk2": c.name.ends_with("MK2"), "name": c.name, "dist": c.distance, "hp_ratio": r.damage.health_ratio() if is_instance_valid(r) else 0.0, "skill": c.base_skill, "seed": gm.track_seed, "metrics": metrics, "achieved": achieved, "live_status": tracker.status}))
			tracker.stop()
			data[c.base_skill].append({"d": c.distance, "survived": is_instance_valid(r) and not r.damage.rocket_fired,
				"hp": r.damage.health_ratio() if is_instance_valid(r) else 0.0,
				"limbs": r.damage.limbs_remaining.size() if is_instance_valid(r) else 0,
				"flights": c.ai.flights if is_instance_valid(c.ai) else 0, "blunders": c.ai.blunders if is_instance_valid(c.ai) else 0})
		print("AT|sim_seed %d time=%.0fs %s" % [s, t, gm.race.competitors.map(func(c: RaceManager.Competitor) -> String: return "%.2f:%.0fm" % [c.base_skill, c.distance])])
	var means := []
	for sk in skills:
		var arr: Array = data[sk]
		var ds: Array = arr.map(func(x: Dictionary) -> float: return x.d)
		ds.sort()
		var mean: float = ds.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / ds.size()
		var var_ := 0.0
		for v in ds:
			var_ += (v - mean) * (v - mean)
		var std := sqrt(var_ / ds.size())
		var med: float = ds[ds.size() / 2]
		var surv := arr.filter(func(x: Dictionary) -> bool: return x.survived).size() / float(arr.size())
		var hp: float = arr.reduce(func(a: float, x: Dictionary) -> float: return a + x.hp, 0.0) / arr.size()
		var limbs: float = arr.reduce(func(a: float, x: Dictionary) -> float: return a + x.limbs, 0.0) / arr.size()
		var bins := {}
		for v in ds:
			var b := int(v / 100.0) * 100
			bins[b] = bins.get(b, 0) + 1
		means.append(mean)
		print("AT|sim robot=%s skill=%.2f n=%d mean=%.0f median=%.0f std=%.0f min=%.0f max=%.0f survival=%.0f%% hp=%.2f limbs=%.1f hist100m=%s" % [
			robot, sk, ds.size(), mean, med, std, ds[0], ds[ds.size() - 1], surv * 100.0, hp, limbs, bins])
	_check("ai_skill_monotonic_overall", means[means.size() - 1] > means[0], "means by skill=%s" % [means.map(func(v: float) -> int: return int(v))])

# ---------------- screenshots (windowed) ----------------

func _shot(n: String) -> void:
	at.call("_shot", n)


func _secs(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shots() -> void:
	gm.profile.coins = 1530
	gm.profile.campaign.completed = ["r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9"]
	gm.profile.campaign.unlocked = ["r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9", "r10"]
	gm.profile.campaign.claimed = gm.profile.campaign.completed.duplicate()
	gm.profile.grant_skin("tin_copper")
	gm.go_menu()
	await _secs(0.6)
	_shot("c_menu")
	gm.open_campaign_map()
	await _secs(0.8)
	_shot("c_map_boss")
	var mv := gm.ui.campaign_map
	print("AT|mapdbg view pos=%s size=%s anchors=%s,%s,%s,%s modulate=%s children=%s" % [mv.position, mv.size, mv.anchor_left, mv.anchor_top, mv.anchor_right, mv.anchor_bottom, mv.modulate,
		mv.get_children().map(func(ch: Node) -> String: return "%s:%s" % [ch.get_class(), (ch as Control).size if ch is Control else Vector2.ZERO])])
	gm.ui.campaign_map.select_node("r11")
	await _secs(0.3)
	_shot("c_map_locked")
	gm.ui.campaign_map.select_node("r8")
	await _secs(0.3)
	_shot("c_map_done_two")
	gm.ui.campaign_map.select_node("r10")
	gm.ui.campaign_map.press_start()
	await _secs(0.6)
	_shot("c_select")
	gm.ui.robot_select.step_skin(1)
	await _secs(0.4)
	_shot("c_select_skin")
	gm.ui.robot_select.step_skin(-1)
	gm.ui.robot_select.play_requested.emit(gm.profile.selected)
	gm.hand.rush()
	at.set("scenario_running", false)
	var t := 0.0
	var k := 0
	while gm.state != GameManager.State.RESULT and t < 240.0:
		await _secs(1.0)
		t += 1.0 * Engine.time_scale
		if k < 8 and int(t) % 3 == 0:
			_shot("c_race_%02d" % k)
			k += 1
		if gm.state == GameManager.State.WAIT and k < 20:
			_shot("c_wait_%02d" % k)
			k = 20
	await _secs(1.0)
	_shot("c_result")
