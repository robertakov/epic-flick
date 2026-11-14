extends Node
## v35 MK2 tests (debug only, not exported). Prints "AT|test mk2_<name> PASS|FAIL <details>".
##   --scenario=mk2_all   unlock / economy / selection / profile isolation / collision invariance / gameplay function
##   --scenario=mk2_qa    visual QA shots (needs -Window --shots=<dir>)
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
const IDS := ["tin", "hopper", "heavy", "rocket", "samurai"]


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test mk2_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


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
		"mk2_qa":
			await qa()
		"mk2_spec":
			await specialty()
		_:
			await unlock_economy_tests()
			await selection_tests()
			await collision_tests()
			await gameplay_tests()
			await visual_tests()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ---------------- helpers ----------------

func _grant(id: String, mk2: bool) -> void:
	var p := gm.profile
	if not p.owned.has(id):
		p.owned.append(id)
	if mk2:
		if not p.mk2_owned.has(id):
			p.mk2_owned.append(id)
		p.mk2_selected[id] = true
	else:
		p.mk2_selected[id] = false
	p.selected = id


## Free-run robot of `id` (base or MK2) skipping the flick, launched at v0 on a fixed seed.
func start_robot(id: String, mk2: bool, seed := 4242, v0 := Vector2(700, -350)) -> RobotController:
	gm.go_menu()
	await frames(2)
	_grant(id, mk2)
	gm.mode = &"free"
	gm.debug_track_seed = seed
	gm.ui.biome_intro.instant = true
	gm.start_run()
	await frames(3)
	gm.hand.playing = false
	gm.hand.visible = false
	gm.ui.flick_bar.hide_immediate()
	gm.state = GameManager.State.RUN
	gm.camera.follow(gm.robot)
	gm.debug_track_seed = -1
	gm.robot.launch(v0, 0.0)
	return gm.robot


# ---------------- A/B. unlock + economy ----------------

func unlock_economy_tests() -> void:
	var p := gm.profile
	var prices := {}
	var bosses := {}
	for id in IDS:
		var d := gm.catalog.get_by_id(id)
		prices[id] = d.mk2_price
		bosses[id] = d.mk2_boss_node
	# release (owner-authorised): Rastabot MK2 6000, derived from the existing MK2 economy (AI_HANDOFF); others unchanged
	check("prices_exact", prices == {"tin": 6000, "hopper": 1200, "heavy": 2400, "rocket": 4000, "samurai": 8000}
		and gm.catalog.get_by_id("tin").price == 0
		and gm.catalog.get_by_id("hopper").mk2_price == 2 * gm.catalog.get_by_id("hopper").price
		and gm.catalog.get_by_id("samurai").mk2_price == 2 * gm.catalog.get_by_id("samurai").price, str(prices))
	# the boss of each MK2 is the first campaign boss whose rival is that archetype (derived from campaign data)
	var derived := {}
	for nid in gm.campaign.order:
		var n: Dictionary = gm.campaign.node(nid)
		if String(n.get("difficulty", "")) == "boss":
			var rid := String(n.enemies[0].robot)
			if not derived.has(rid):
				derived[rid] = nid
	check("boss_mapping_from_campaign", bosses == derived, "%s" % [bosses])
	var hopper := gm.catalog.get_by_id("hopper")
	var tin := gm.catalog.get_by_id("tin")
	p.owned = ["tin"] as Array[String]
	p.mk2_owned = [] as Array[String]
	p.mk2_selected = {}
	p.coins = 10000
	p.campaign = ProfileStore.default_campaign()
	p.ensure_campaign_start(gm.campaign.start_id)
	# locked: boss not beaten (base owned)
	p.owned.append("hopper")
	var c0 := p.coins
	var r_locked := p.buy_mk2(hopper)
	check("locked_until_boss", not p.mk2_eligible(hopper) and r_locked == "locked" and p.coins == c0 and not p.owns_mk2("hopper"), r_locked)
	# boss beaten -> eligible, but NOT owned
	p.campaign.completed.append(hopper.mk2_boss_node)
	check("boss_makes_eligible_not_owned", p.mk2_eligible(hopper) and not p.owns_mk2("hopper") and not p.mk2_active("hopper"))
	# not enough coins
	p.coins = 1199
	var r_coins := p.buy_mk2(hopper)
	check("insufficient_funds", r_coins == "coins" and p.coins == 1199 and not p.owns_mk2("hopper"), r_coins)
	# purchase: exactly once, even with rapid repeats
	p.coins = 5000
	var r1 := p.buy_mk2(hopper)
	var r2 := p.buy_mk2(hopper)
	var r3 := p.buy_mk2(hopper)
	check("purchase_charges_exactly_once", r1 == "ok" and r2 == "owned" and r3 == "owned" and p.coins == 5000 - 1200 and p.owns_mk2("hopper"),
		"%s/%s/%s coins %d" % [r1, r2, r3, p.coins])
	# needs the base robot
	p.campaign.completed.append(gm.catalog.get_by_id("heavy").mk2_boss_node)
	var heavy := gm.catalog.get_by_id("heavy")
	var r_base := p.buy_mk2(heavy)
	check("needs_base_robot", r_base == "base" and p.coins == 3800, r_base)
	# Rastabot MK2 (price 6000): locked before its boss, insufficient funds, then bought exactly once
	var r_tin_locked := p.buy_mk2(tin)
	p.campaign.completed.append(tin.mk2_boss_node)
	var r_tin_coins := p.buy_mk2(tin)
	check("rastabot_mk2_locked_then_needs_coins", r_tin_locked == "locked" and r_tin_coins == "coins" and p.coins == 3800 and not p.owns_mk2("tin"),
		"%s / %s" % [r_tin_locked, r_tin_coins])
	p.coins = 6000 + 3800
	var rt1 := p.buy_mk2(tin)
	var rt2 := p.buy_mk2(tin)
	check("rastabot_mk2_purchase_exactly_once", tin.mk2_purchasable() and rt1 == "ok" and rt2 == "owned" and p.coins == 3800 and p.owns_mk2("tin")
		and p.is_owned("tin"), "%s/%s coins %d" % [rt1, rt2, p.coins])
	# UI path: rapid presses on the select screen's buy button -> one request -> one charge
	p.coins = 5000
	p.owned.append("rocket")
	p.campaign.completed.append(gm.catalog.get_by_id("rocket").mk2_boss_node)
	gm.open_robot_select()
	await frames(3)
	var rs := gm.ui.robot_select
	rs.index = gm.catalog.index_of("rocket")
	rs._refresh(true)
	rs.set_view_mk2(true)
	await frames(2)
	var shown_lock := rs._mk2_note.text
	rs._action.pressed.emit()
	rs._action.pressed.emit()
	rs._action.pressed.emit()
	await frames(3)
	check("ui_rapid_taps_single_charge", p.owns_mk2("rocket") and p.coins == 1000 and rs._mk2_note.text != shown_lock, "coins %d note '%s'" % [p.coins, rs._mk2_note.text])
	rs._refresh(false)
	# persistence
	p.save()
	var re := ProfileStore.new(p.path, gm.catalog, gm.skins)
	re.load_data()
	check("ownership_persists", re.owns_mk2("hopper") and re.owns_mk2("rocket") and re.owns_mk2("tin") and re.coins == p.coins, str(re.mk2_owned))
	# profile isolation: another slot's store knows nothing of this purchase
	var other := ProfileStore.new("user://test/mk2_other_slot/profile.json", gm.catalog, gm.skins)
	other.load_data()
	check("rastabot_mk2_profile_specific", not other.owns_mk2("tin") and not other.owns_mk2("hopper"), str(other.mk2_owned))
	# old save without MK2 keys loads cleanly with no MK2
	var old_path := "user://test/mk2_old_save.json"
	var f := FileAccess.open(old_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": ProfileStore.VERSION, "coins": 321, "owned": ["tin", "hopper"], "selected": "hopper"}))
	f.close()
	var old := ProfileStore.new(old_path, gm.catalog, gm.skins)
	old.load_data()
	check("old_save_loads_without_mk2", old.coins == 321 and old.owned.has("hopper") and old.selected == "hopper" and old.mk2_owned.is_empty()
		and old.mk2_selected.is_empty() and old.last_load_status in ["ok", "repaired"], old.last_load_status)
	# tampered save: MK2 of a robot not owned is dropped
	f = FileAccess.open(old_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": ProfileStore.VERSION, "coins": 5, "owned": ["tin"], "selected": "tin", "mk2_owned": ["samurai", "nope", 3], "mk2_selected": {"samurai": true}}))
	f.close()
	old = ProfileStore.new(old_path, gm.catalog, gm.skins)
	old.load_data()
	check("tampered_save_sanitized", old.mk2_owned.is_empty() and old.mk2_selected.is_empty() and old.last_load_status == "repaired")
	gm.ui.close_robot_select()


# ---------------- C. selection + profile isolation ----------------

func selection_tests() -> void:
	var p := gm.profile
	p.coins = 0
	_grant("hopper", true)
	check("variants_selectable_independently", p.set_mk2_selected("hopper", false) and not p.mk2_active("hopper")
		and p.set_mk2_selected("hopper", true) and p.mk2_active("hopper") and not p.set_mk2_selected("samurai", true))
	p.set_mk2_selected("hopper", true)
	p.save()
	var re := ProfileStore.new(p.path, gm.catalog, gm.skins)
	re.load_data()
	check("variant_survives_reload", re.mk2_active("hopper") and re.selected == p.selected)
	# spawned robot follows the choice
	p.select("hopper")
	gm.go_menu()
	await frames(3)
	var mk_vis := gm.robot.visual.rig.visual_id
	p.set_mk2_selected("hopper", false)
	gm.go_menu()
	gm._spawn_robot()
	await frames(3)
	var base_vis := gm.robot.visual.rig.visual_id
	check("spawn_uses_selected_variant", mk_vis == "kenguru_mk2" and base_vis == "kenguru", "%s / %s" % [mk_vis, base_vis])
	# profiles: MK2 state is per player
	var root := "user://test/mk2_profiles/"
	for fn in DirAccess.get_files_at(root):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root + fn))
	var pm := ProfileManager.new(root)
	pm.create(1)
	pm.create(2)
	var p1 := ProfileStore.new(pm.profile_path(1), gm.catalog, gm.skins)
	p1.load_data()
	p1.owned.append("heavy")
	p1.mk2_owned.append("heavy")
	p1.mk2_selected["heavy"] = true
	p1.save()
	var p2 := ProfileStore.new(pm.profile_path(2), gm.catalog, gm.skins)
	p2.load_data()
	check("profile_isolation", not p2.owns_mk2("heavy") and not p2.mk2_active("heavy") and p2.mk2_owned.is_empty(), "")
	var p1b := ProfileStore.new(pm.profile_path(1), gm.catalog, gm.skins)
	p1b.load_data()
	check("profile_restores_own_selection", p1b.mk2_active("heavy"))
	var sf := FileAccess.get_file_as_string(gm.settings.path)
	check("mk2_not_in_global_settings", not sf.contains("mk2"))


# ---------------- D. collision invariance ----------------

## Every collision shape of a robot: owner node path relative to the robot + shape class + geometry + transform.
func _shape_sig(r: RobotController) -> Array:
	var out := []
	var stack: Array[Node] = [r]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is CollisionShape2D or n is CollisionPolygon2D:
			var row := [_index_path(r, n), n.get_class(), n.position.snapped(Vector2(0.001, 0.001)), snappedf(n.rotation, 0.0001),
				n.scale.snapped(Vector2(0.001, 0.001)), n.disabled if n is CollisionShape2D else false]
			if n is CollisionShape2D and n.shape:
				var s: Shape2D = n.shape
				row.append(s.get_class())
				for prop in ["radius", "height", "size", "a", "b", "points"]:
					if prop in s:
						var v = s.get(prop)
						row.append(v.snapped(Vector2(0.001, 0.001)) if v is Vector2 else (snappedf(v, 0.001) if v is float else v))
			elif n is CollisionPolygon2D:
				row.append(n.polygon)
			out.append(row)
	out.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	return out


## Structural path (child indices), independent of auto-generated node names.
func _index_path(root: Node, n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	while cur != root and cur != null:
		parts.push_front("%s#%d" % [cur.get_class(), cur.get_index()])
		cur = cur.get_parent()
	return "/".join(parts)


func _bodies_sig(r: RobotController) -> Array:
	var out := [["root", r.mass, r.collision_layer, r.collision_mask, r.center_of_mass.snapped(Vector2(0.001, 0.001)), r.inertia]]
	for c in r.get_children():
		if c is PhysicsBody2D:
			out.append([_index_path(r, c), c.get_class(), (c as RigidBody2D).mass if c is RigidBody2D else 0.0])
	return out


func collision_tests() -> void:
	var all_ok := true
	var details := []
	for id in IDS:
		var d := gm.catalog.get_by_id(id)
		var base := gm.build_robot(d, gm.input, null, "", false)
		var mk := gm.build_robot(d, gm.input, null, "", true)
		add_child(base)
		add_child(mk)
		await physics(2)
		var s_base := _shape_sig(base)
		var s_mk := _shape_sig(mk)
		var b_base := _bodies_sig(base)
		var b_mk := _bodies_sig(mk)
		var same := s_base == s_mk and b_base == b_mk and not s_base.is_empty()
		if not same:
			for i in mini(s_base.size(), s_mk.size()):
				if s_base[i] != s_mk[i]:
					print("AT|diff shape %s | base %s | mk2 %s" % [id, s_base[i], s_mk[i]])
			if b_base != b_mk:
				print("AT|diff bodies %s | base %s | mk2 %s" % [id, b_base, b_mk])
		var cfg_same := is_equal_approx(base.config.rig_scale, mk.config.rig_scale) and is_equal_approx(base.config.torso_mass, mk.config.torso_mass) \
			and is_equal_approx(base.config.torso_hit_scale, mk.config.torso_hit_scale) and is_equal_approx(base.contact_config.foot_half_width, mk.contact_config.foot_half_width) \
			and is_equal_approx(base.contact_config.coil_rest_length, mk.contact_config.coil_rest_length) and base.config.rig_json == mk.config.rig_json
		var vis_diff := base.config.visual_id != mk.config.visual_id and mk.config.visual_id == d.mk2_visual_id
		check("collision_identical_%s" % id, same and cfg_same and vis_diff, "%d shapes, %d bodies, visual %s -> %s" % [s_base.size(), b_base.size(), base.config.visual_id, mk.config.visual_id])
		all_ok = all_ok and same and cfg_same
		details.append("%s:%d" % [id, s_base.size()])
		# the MK2 module can never carry a physical key
		var m := d.mk2_module()
		var phys := false
		for k in RobotDefinition.MK2_FORBIDDEN:
			phys = phys or m.stat_multipliers.has(k) or m.stat_offsets.has(k)
		check("module_has_no_physical_keys_%s" % id, not phys, str(m.stat_multipliers) + str(m.stat_offsets))
		base.queue_free()
		mk.queue_free()
		await frames(2)
	check("collision_invariance_all_robots", all_ok, str(details))
	# identities survive the upgrade (MK2 = better at its own thing, weaknesses kept)
	var mk := {}
	var bs := {}
	for id in IDS:
		var d := gm.catalog.get_by_id(id)
		bs[id] = d.base_stats()
		mk[id] = ModuleDefinition.apply_all(d.base_stats(), [d.mk2_module()])
	var hp_mk := IDS.map(func(i: String) -> float: return float(mk[i].max_health))
	var ident: bool = float(mk.heavy.max_health) == hp_mk.max() and float(mk.tin.max_health) == hp_mk.min() \
		and float(mk.rocket.momentum_gain) > 2.0 * IDS.filter(func(i: String) -> bool: return i != "rocket").map(func(i: String) -> float: return float(mk[i].momentum_gain)).max() \
		and float(mk.heavy.momentum_gain) == float(bs.heavy.momentum_gain) and float(mk.heavy.momentum_max) == float(bs.heavy.momentum_max) \
		and float(mk.heavy.momentum_gain) < float(bs.rocket.momentum_gain) \
		and float(mk.hopper.rebound_power) == IDS.map(func(i: String) -> float: return float(mk[i].rebound_power)).max()
	var no_change_physical := true
	for id in IDS:
		for k in ["size", "mass_multiplier", "spring_strength", "bounce"]:
			no_change_physical = no_change_physical and is_equal_approx(float(mk[id][k]), float(bs[id][k]))
	check("identities_preserved", ident and no_change_physical,
		"HP mk2 %s, momentum_gain mk2 %s" % [str(hp_mk), str(IDS.map(func(i: String) -> int: return int(mk[i].momentum_gain)))])
	# decorative MK2 art adds no physics: the cape / tail are plain sprites inside the torso visual
	var rk := gm.build_robot(gm.catalog.get_by_id("rocket"), gm.input, null, "", true)
	add_child(rk)
	await physics(2)
	var cape: Node = rk.find_child("SourceTail", true, false)
	var cape_ok := cape != null and cape is Sprite2D and cape.get_children().filter(func(c: Node) -> bool: return c is CollisionObject2D or c is CollisionShape2D).is_empty()
	var torso_part: Node = cape.get_parent() if cape else null
	check("chrono_cape_is_torso_sprite_no_physics", cape_ok and torso_part is VideoRobotPart and (torso_part as VideoRobotPart).part_name == "torso",
		"cape parent %s" % [torso_part.name if torso_part else "-"])
	rk.queue_free()
	await frames(2)


# ---------------- E. gameplay function ----------------

func gameplay_tests() -> void:
	for id in IDS:
		var r := await start_robot(id, true)
		await physics(60)
		var hp_ok := is_equal_approx(r.damage.max_health, float(ModuleDefinition.apply_all(gm.catalog.get_by_id(id).base_stats(), [gm.catalog.get_by_id(id).mk2_module()]).max_health))
		# limbs detach as real debris and the rest keeps working
		var lost := []
		r.limb_lost.connect(func(l: StringName, _p: RigidBody2D) -> void: lost.append(l))
		r._on_limb_lost(&"arm_l", {"normal": Vector2.UP})
		r._on_limb_lost(&"leg_r", {"normal": Vector2.UP})
		await physics(30)
		var debris := gm.dynamic.get_children().filter(func(c: Node) -> bool: return c is DetachablePart).size()
		# body destruction -> rocket head (head art of the MK2)
		var vis := r.visual.rig.visual_id
		r._launch_rocket({"point": r.global_position, "normal": Vector2.UP})
		await physics(10)
		var rocket_ok := is_instance_valid(gm.rocket) and gm.state == GameManager.State.ROCKET
		var t := 0.0
		while gm.state == GameManager.State.ROCKET and t < 30.0:
			gm.skip_rocket()
			await get_tree().process_frame
			t += get_process_delta_time()
		# (the run goes on after the forced losses: later crashes may take more limbs - that is normal play)
		check("gameplay_%s" % id, hp_ok and lost.size() >= 2 and lost.slice(0, 2) == [&"arm_l", &"leg_r"] and debris >= 2 and rocket_ok and vis.ends_with("_mk2") and gm.state == GameManager.State.RESULT,
			"hp %.0f lost %s debris %d rocket %s visual %s end %s" % [r.damage.max_health if is_instance_valid(r) else -1.0, lost, debris, rocket_ok, vis, GameManager.State.keys()[gm.state]])
	# continue restores 80 % of the MK2's max HP (artifact rules unchanged)
	gm.continue_offers_enabled = true
	var r2 := await start_robot("heavy", true)
	var max_hp := r2.damage.max_health
	gm.profile.coins = 5000
	await physics(20)
	gm._finish("Робот остановился")
	await frames(2)
	var offered := gm.state == GameManager.State.OFFER
	gm.accept_continue()
	await physics(3)
	check("continue_mk2_80_percent", offered and is_equal_approx(gm.robot.damage.health, max_hp * 0.8) and gm.robot.visual.rig.visual_id == "sumo_mk2",
		"max %.0f -> %.1f" % [max_hp, gm.robot.damage.health])
	gm._finish("Робот остановился")
	gm.continue_offers_enabled = false
	gm.go_menu()
	await frames(2)
	# artifact stacks on top of MK2 (both modules)
	gm.profile.artifact = {"discovered": true, "equipped": true}
	var r3 := await start_robot("samurai", true)
	var d := gm.catalog.get_by_id("samurai")
	var pre := ModuleDefinition.apply_all(d.base_stats(), [d.mk2_module()])
	var want := float(ModuleDefinition.apply_all(d.base_stats(), [d.mk2_module(), SecretArtifact.module(pre, gm.catalog)]).max_health)
	check("artifact_stacks_on_mk2", is_equal_approx(r3.damage.max_health, want), "%.2f vs %.2f" % [r3.damage.max_health, want])
	gm.profile.artifact = {"discovered": false, "equipped": false}
	gm.go_menu()
	await frames(2)


# ---------------- F. balance: controlled specialty metrics (base vs MK2) ----------------

## Upright robot dropped / launched in the controlled practice slope; returns {dist, apex, speed_out_charged}.
func _slope_run(id: String, mk2: bool, v0: Vector2, seconds: float, charge := 0.0) -> Dictionary:
	var r := await start_robot(id, mk2, 4242, Vector2.ZERO)
	gm.terrain.build_training()
	await physics(2)
	r.global_position = Vector2(-1300.0, gm.terrain.height_at(-1300.0) - 300.0)
	r.rotation = 0.0
	r.linear_velocity = Vector2.ZERO
	r.launch(v0, 0.0)
	r.spin_charge.charge = charge
	var x0 := r.global_position.x
	var apex := 0.0
	var landed := [0]
	var first_out := [0.0]
	r.landed.connect(func(i: Dictionary) -> void:
		landed[0] += 1
		if landed[0] == 1:
			first_out[0] = float(i.speed_out))
	for i in int(120 * seconds):
		await get_tree().physics_frame
		if not is_instance_valid(r) or gm.state != GameManager.State.RUN:
			break
		r.angular_velocity = 0.0
		r.rotation = 0.0
		if landed[0] >= 1:
			apex = maxf(apex, gm.terrain.height_at(r.global_position.x) - r.global_position.y)
	return {"dist": (r.global_position.x - x0) / gm.level_config.px_per_meter if is_instance_valid(r) else 0.0, "apex": apex, "out": first_out[0]}


func specialty() -> void:
	var res := {}
	for id in IDS:
		var row := {}
		for mk2 in [false, true]:
			var key := "mk2" if mk2 else "base"
			var dist := 0.0
			for v0 in [Vector2(500, -300), Vector2(700, -350), Vector2(900, -400), Vector2(650, -650)]:
				dist += float((await _slope_run(id, mk2, v0, 6.0)).dist) / 4.0
			var jump: Dictionary = await _slope_run(id, mk2, Vector2(0, 600), 3.0)
			var charged: Dictionary = await _slope_run(id, mk2, Vector2(0, 600), 1.5, 0.8)
			var plain: Dictionary = await _slope_run(id, mk2, Vector2(0, 600), 1.5, 0.0)
			row[key] = {"slope_dist_6s": dist, "rebound_apex": jump.apex, "charged_boost": float(charged.out) - float(plain.out)}
		res[id] = row
		print("AT|spec %s %s" % [id, JSON.stringify(row)])
	check("spec_measured", res.size() == IDS.size())


# ---------------- G. visual requirements (automated part) ----------------

func _alpha_count(img: Image, rect: Rect2i, a_min := 0.1) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > a_min:
				n += 1
	return n


func visual_tests() -> void:
	# Samurobot MK2: the stray blade above the helmet (master x 600..690, y 55..97) is gone in every face frame
	var sh: Image = (load("res://assets/robots/samurai_mk2/head.png") as Texture2D).get_image()
	var mf: Dictionary = RobotArtLibrary.manifest("samurai_mk2")
	var fw := int(mf.parts.head.frame_size[0])
	var left := 0
	for i in 7:
		left += _alpha_count(sh, Rect2i(i * fw + 128, 22, 46, 19))   # v36: rows above the restored dome arc (master y < 93)
	check("samurai_helmet_protrusion_removed", left == 0, "%d opaque px left in the blade area" % left)
	# Kengurobot MK2 tail: no glove pixels, no hand-shaped hole (one solid piece)
	var tail: Image = (load("res://assets/robots/hopper_mk2/tail.png") as Texture2D).get_image()
	# a glove fragment is a SOLID white blob (7x7 fully white); the tail's own specular highlight band is not
	var w := tail.get_width()
	var h := tail.get_height()
	var is_white := PackedByteArray()
	is_white.resize(w * h)
	for y in h:
		for x in w:
			var c := tail.get_pixel(x, y)
			is_white[y * w + x] = 1 if (c.a > 0.5 and c.r > 0.93 and c.g > 0.93 and c.b > 0.9) else 0
	var solid := 0
	for y in range(3, h - 3):
		for x in range(3, w - 3):
			var all := true
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					all = all and is_white[(y + dy) * w + x + dx] == 1
			solid += int(all)
	check("kengurobot_mk2_tail_clean", solid == 0, "%d solid glove-white px (thin highlight ignored)" % solid)
	# Rastabot: base head still has no joint / smoke; MK2 is built from the approved (joint-free) master
	var rm: Dictionary = RobotArtLibrary.manifest("rasta_mk2")
	check("rastabot_mk2_from_approved_master", String(rm.source.file) == "rastabot mk2.png" and String(rm.source.sha256).length() == 64, String(rm.source.sha256).left(12))
	# Chronobot nozzle (base + MK2): visual only, readable at gameplay zoom, flame starts at the nozzle mouth
	for mk2 in [false, true]:
		var r := await start_robot("rocket", mk2, 31337, Vector2(500, -500))
		await physics(30)
		var nozzles := []
		for lv in r.visual.legs.values():
			var leg := lv as LegVisual
			if leg and leg.nozzle:
				var px := ChronoNozzle.BELL * leg.nozzle.get_global_transform_with_canvas().get_scale().x
				var aligned := leg.exhaust.position.distance_to(leg.nozzle.mouth()) < 0.5
				nozzles.append([px, aligned])
		var ok := nozzles.size() == 2
		for n in nozzles:
			ok = ok and float(n[0]) >= 12.0 and bool(n[1])
		check("chrono_nozzle_readable_flame_aligned_%s" % ("mk2" if mk2 else "base"), ok and is_equal_approx(ChronoNozzle.NOZZLE_SCALE, 1.9), str(nozzles))
	gm.go_menu()
	await frames(2)


# ---------------- visual QA ----------------

func qa() -> void:
	var ui := gm.ui
	for id in IDS:
		_grant(id, true)
	gm.profile.coins = 9999
	for nid in ["r10", "r20", "r30", "r40", "r50"]:
		if not gm.profile.campaign.completed.has(nid):
			gm.profile.campaign.completed.append(nid)
	gm.open_robot_select()
	await frames(5)
	var rs := ui.robot_select
	for id in IDS:
		rs.index = gm.catalog.index_of(id)
		rs._refresh(true)
		rs.set_view_mk2(false)
		await frames(20)
		at.call("_shot", "mk2_select_%s_base" % id)
		rs.set_view_mk2(true)
		await frames(20)
		at.call("_shot", "mk2_select_%s_mk2" % id)
	# locked / buyable states (Kengurobot): not owned + boss not beaten, then beaten
	gm.profile.mk2_owned.erase("hopper")
	gm.profile.campaign.completed.erase("r10")
	rs.index = gm.catalog.index_of("hopper")
	rs._refresh(true)
	rs.set_view_mk2(true)
	await frames(15)
	at.call("_shot", "mk2_select_hopper_locked")
	gm.profile.campaign.completed.append("r10")
	rs._refresh(false)
	await frames(10)
	at.call("_shot", "mk2_select_hopper_buyable")
	gm.profile.mk2_owned.append("hopper")
	ui.close_robot_select()
	gm.go_menu()
	await frames(20)
	at.call("_shot", "mk2_menu")
	# gameplay at phone gameplay scale + close-ups, parts detached, rocket head
	for id in IDS:
		var r := await start_robot(id, true, 31337, Vector2(500, -500))
		await get_tree().create_timer(1.2).timeout
		at.call("_shot", "mk2_play_%s" % id)
		gm.camera.base_zoom = 1.6
		var z0 := gm.camera.min_zoom
		gm.camera.min_zoom = 1.6
		await get_tree().create_timer(0.6).timeout
		at.call("_shot", "mk2_close_%s" % id)
		r._on_limb_lost(&"arm_r", {"normal": Vector2.UP})
		r._on_limb_lost(&"leg_l", {"normal": Vector2.UP})
		await get_tree().create_timer(0.5).timeout
		at.call("_shot", "mk2_detached_%s" % id)
		r._launch_rocket({"point": r.global_position, "normal": Vector2.UP})
		await get_tree().create_timer(0.5).timeout
		at.call("_shot", "mk2_rocket_%s" % id)
		gm.camera.base_zoom = 0.88
		gm.camera.min_zoom = z0
	# base Chronobot nozzle (enlarged, visual only) vs MK2 nozzle, gameplay scale and close
	for mk2 in [false, true]:
		var r := await start_robot("rocket", mk2, 31337, Vector2(500, -500))
		await get_tree().create_timer(1.2).timeout
		at.call("_shot", "mk2_nozzle_%s_play" % ("mk2" if mk2 else "base"))
		gm.camera.base_zoom = 1.8
		gm.camera.min_zoom = 1.8
		await get_tree().create_timer(0.6).timeout
		at.call("_shot", "mk2_nozzle_%s_close" % ("mk2" if mk2 else "base"))
		gm.camera.base_zoom = 0.88
		gm.camera.min_zoom = 0.34
	gm.go_menu()
	check("qa_done", true)
