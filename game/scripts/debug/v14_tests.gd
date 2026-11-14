extends Node
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
class FailingProfile:
	extends ProfileStore
	func save() -> bool:
		return false

func check(label: String, ok: bool, detail := "") -> void:
	passed += int(ok)
	failed += int(not ok)
	print("AT|test v14_%s %s %s" % [label, "PASS" if ok else "FAIL", detail])

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func run_all(which: String) -> void:
	at.set("scenario_running", true)
	at.set("max_time", 1.0e9)
	if which == "currency":
		currency()
	elif which == "free_challenges":
		generation()
		await free_flow()
	elif which == "free_layout":
		await layout()
	elif which == "free_report":
		rate_report()
	elif which == "free_calibration":
		await calibration()
	print("AT|tests passed=%d failed=%d" % [passed, failed])

func currency() -> void:
	var path := "user://test/v14_wallet_fixture.json"
	var p := ProfileStore.new(path, gm.catalog, gm.skins)
	p.save()
	check("campaign_wallet_grant", p.earn_star("r1", 0, 20).new and p.star_wallet.earned == 1 and p.star_wallet.available == 1 and p.star_wallet.spent == 0 and p.coins == 20)
	check("campaign_once", not p.earn_star("r1", 0, 999).new and p.star_wallet.earned == 1 and p.coins == 20)
	check("spend_and_keep_campaign", p.spend_stars(1, "test") and p.has_star("r1", 0) and p.total_stars() == 1 and p.star_wallet.available == 0 and p.star_wallet.spent == 1)
	var before := p.star_wallet.duplicate(true)
	check("insufficient_no_mutation", not p.spend_stars(2, "test") and before == p.star_wallet)
	check("invalid_amounts", not p.spend_stars(0, "test") and not p.spend_stars(-1, "test") and not p.earn_stars(0, "TEST") and not p.earn_stars(-1, "TEST") and not p.earn_stars(1, "") and p.star_wallet == before)
	check("multiple_extensible_sources", p.earn_stars(2, ProfileStore.SOURCE_FREE_RUN) and p.earn_stars(3, "TEST_SOURCE") and p.star_wallet.sources == {"CAMPAIGN":1,"FREE_RUN":2,"TEST_SOURCE":3} and p.star_wallet.earned == 6 and p.star_wallet.available == 5)
	var q := ProfileStore.new(path, gm.catalog, gm.skins)
	q.load_data()
	check("wallet_reload", q.star_wallet == p.star_wallet and q.has_star("r1", 0) and q.loaded_version == 5)
	check("spend_all_never_negative", q.spend_stars(5, "all") and q.star_wallet.available == 0 and q.star_wallet.spent == 6 and not q.spend_stars(1, "again") and q.has_star("r1", 0))
	q.load_data()
	check("spent_reload_not_historical_regrant", q.star_wallet.available == 0 and q.star_wallet.earned == 6 and q.star_wallet.spent == 6)
	for version in [1, 2, 3, 4]:
		var old := {"version":version,"coins":321,"owned":["tin","hopper"],"selected":"hopper","owned_skins":["tin_copper"],"equipped_skins":{"tin":"tin_copper"},"tutorial":{"handled":true,"completed":true},
			"adaptive":{"ema":0.12,"samples":5}, "star_wallet":{"earned":999999,"available":999999},
			"campaign":{"unlocked":["r1","r2"],"completed":["r1"],"claimed":["r1"],"replay_wins":{"r1":3},"attempts":{"r2":7},"stars":{"r1":[true,false,false],"r101":[true,true,true]},"star_claimed":{"r1":[false,false,true]}}}
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(old))
		f.close()
		q.load_data()
		check("migration_v%d_wallet" % version, q.star_wallet.earned == 2 and q.star_wallet.available == 2 and q.star_wallet.spent == 0 and q.star_wallet.sources == {"CAMPAIGN":2} and q.total_stars() == 2)
		check("migration_v%d_progress_preserved" % version, q.coins == 321 and q.selected == "hopper" and q.is_owned("hopper") and q.owns_skin("tin_copper") and q.equipped_skin("tin") == "tin_copper" and q.tutorial.completed and q.is_completed("r1") and q.is_unlocked("r2") and q.attempts_on("r2") == 7 and q.replay_wins("r1") == 3 and q.adaptive.samples == 5)
		q.spend_stars(1, "migration spend")
		for i in 3:
			q.load_data()
		check("migration_v%d_idempotent" % version, q.loaded_version == 5 and q.star_wallet.available == 1 and q.star_wallet.earned == 2 and q.star_wallet.spent == 1 and not q.earn_star("r1", 2, 99).new)
	var blocker := "user://test/v14_save_directory"
	DirAccess.make_dir_recursive_absolute(blocker)
	p.path = blocker
	before = p.star_wallet.duplicate(true)
	check("earn_save_failure_rollback", not p.earn_stars(8, "TEST") and before == p.star_wallet)
	check("spend_save_failure_rollback", not p.spend_stars(1, "TEST") and before == p.star_wallet)
	var cp := p.campaign.duplicate(true)
	var coins := p.coins
	check("campaign_save_failure_rollback", not p.earn_star("r2", 0, 30).saved and p.campaign == cp and p.star_wallet == before and p.coins == coins)
	p.path = path
	p.star_wallet.available = -4
	p.star_wallet.spent = 100
	p.save()
	q.load_data()
	check("malformed_wallet_nonnegative", q.star_wallet.available >= 0 and q.star_wallet.earned == q.star_wallet.available + q.star_wallet.spent)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw.erase("star_wallet")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw)); f.close()
	q.load_data()
	check("v5_missing_wallet_no_regrant", q.star_wallet.earned == 0 and q.has_star("r1", 0))
	f = FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify({"version":4,"coins":80,"campaign":{"stars":{"r1":[true,true,false]}}})); f.close()
	var broken := FailingProfile.new(path,gm.catalog,gm.skins)
	for i in 3: broken.load_data()
	check("migration_failure_retains_old_disk_no_accumulation", broken.last_load_status == "migration_save_failed" and broken.star_wallet.earned == 2 and broken.star_wallet.available == 2 and int(JSON.parse_string(FileAccess.get_file_as_string(path)).version) == 4)
	check("migration_failure_spend_and_earn_rollback", not broken.spend_stars(1,"test") and not broken.earn_stars(1,"TEST") and broken.star_wallet.available == 2)
	q.load_data(); q.load_data()
	check("migration_retry_success_once", q.loaded_version == 5 and q.coins == 80 and q.star_wallet.earned == 2 and q.star_wallet.available == 2)

func generation() -> void:
	var cfg := FreeChallenges.config()
	var seen := {}
	for robot_id in ["tin","hopper","heavy","rocket","samurai"]:
		var good := true
		for seed_value in 400:
			var value := FreeChallenges.generate(robot_id, seed_value, seed_value+1, cfg)
			good = good and FreeChallenges.valid_set(value)
			for ch in value.challenges:
				seen[ch.type] = true
				good = good and not cfg.robot_overrides.get(robot_id, {}).get(ch.type, {}).get("exclude", false)
		check("generation_400_triplets_%s" % robot_id, good)
	check("shared_all_15_types", seen.size() == 15)
	check("reject_duplicate_and_redundant", not FreeChallenges.compatible([{"type":"DISTANCE","m":100,"reward":0},{"type":"DISTANCE","m":180,"reward":0}]) and not FreeChallenges.compatible([{"type":"CLEAN_START","m":70,"reward":0},{"type":"SURVIVAL_HP","m":80,"hp":25,"reward":0}]))
	check("avoid_implied_distance", not FreeChallenges.compatible([{ "type":"DISTANCE", "m":100, "reward":0 },{ "type":"CLEAN_SECTION", "m":120, "reward":0 }]))
	check("shared_incompatibilities", not FreeChallenges.compatible([{"type":"GOOD_LANDING_STREAK","n":2,"reward":0},{"type":"CHARGED_LANDING_STREAK","n":2,"pct":20,"reward":0}]))
	var p := ProfileStore.new("user://test/v14_set_fixture.json",gm.catalog)
	var value := p.prepare_free_set("tin",cfg)
	var before := p.free_run.duplicate(true)
	check("persist_initial_set", FreeChallenges.valid_set(value))
	check("robot_change_no_reroll", p.prepare_free_set("heavy",cfg) == value and p.free_run == before)
	var limited := cfg.duplicate(true)
	limited.reward_per_objective = 2
	limited.max_rewarded_objectives_per_set = 1
	p.free_run = {"sequence":0,"set":{}}
	value = p.prepare_free_set("hopper",limited)
	for i in 3: p.earn_free_star(int(value.id),i)
	check("data_driven_reward_cap", p.star_wallet.earned == 2 and p.free_run.set.completed == [true,true,true])
	check("obsolete_receipt_never_pays", not p.earn_free_star(999,0).new and not p.earn_free_star(int(value.id),0).new)
	var next := p.prepare_free_set("heavy",cfg)
	check("refresh_after_all_completed", next.id == value.id+1 and next.completed == [false,false,false] and p.star_wallet.earned == 2)
	check("old_set_id_replay_blocked", not p.earn_free_star(int(value.id),1).new)
	var saved_path := p.path
	p.free_run.sequence = 0; p.save()
	var restored := ProfileStore.new(saved_path,gm.catalog); restored.load_data()
	check("sequence_repaired_without_receipt_reset", restored.free_run.sequence == int(next.id) and restored.free_run.set.completed == next.completed)
	var malformed := next.duplicate(true); malformed.id = 1.5
	check("fractional_receipt_refused", not FreeChallenges.valid_set(malformed))
	p.path = "user://test/v14_save_directory"
	DirAccess.make_dir_recursive_absolute(p.path)
	before = p.free_run.duplicate(true)
	var wallet := p.star_wallet.duplicate(true)
	check("free_reward_save_failure_rollback", not p.earn_free_star(int(next.id),0).saved and before == p.free_run and wallet == p.star_wallet)
	p.free_run = {"sequence":0,"set":{}}
	check("set_creation_failure_no_new_receipt", p.prepare_free_set("tin",cfg).is_empty() and p.free_run.sequence == 0 and p.free_run.set.is_empty())

func fixture() -> Dictionary:
	var value := FreeChallenges.generate("tin",123,1,FreeChallenges.config())
	value.challenges = [{"type":"DISTANCE","m":100,"reward":0},{"type":"TOTAL_GOOD_LANDINGS","n":3,"reward":0},{"type":"CHARGE_TARGET","pct":70,"reward":0}]
	return value

func free_flow() -> void:
	gm.go_menu()
	gm.mode = &"free"
	gm.profile.free_run = {"sequence":1,"set":fixture()}
	gm.profile.save()
	var cp := gm.profile.campaign.duplicate(true)
	var adaptive := gm.profile.adaptive.duplicate(true)
	var coins := gm.profile.coins
	var wallet := gm.profile.star_wallet.duplicate(true)
	at.call("start_seen_run")
	gm.hand.playing = false
	check("free_three_shared_tracker", gm.star_tracker != null and gm.star_tracker.challenges.size() == 3 and gm.ui.star_hud.free_mode and gm.ui.star_hud.visible)
	check("free_intro_visible", gm.ui.star_hud.expanded and gm.ui.star_hud.rows[0].visible)
	var t := gm.star_tracker
	t.sample(.1,100,10000,false,false,0)
	check("free_partial_one_immediate", gm.profile.free_run.set.completed == [true,false,false] and gm.profile.star_wallet.available == wallet.available+1 and gm.profile.coins == coins)
	var reload := ProfileStore.new(gm.profile.path,gm.catalog,gm.skins)
	reload.load_data()
	check("crash_relaunch_atomic_receipt", JSON.parse_string(JSON.stringify(reload.free_run)) == JSON.parse_string(JSON.stringify(gm.profile.free_run)) and reload.star_wallet == gm.profile.star_wallet and not reload.earn_free_star(1,0).new)
	gm._last_restart_ms = -100000
	check("restart_same_partial_set", gm.restart_attempt() and gm.profile.free_run.set.id == 1 and gm.star_tracker.owned == [true,false,false] and gm.star_tracker.metrics().distance == 0)
	t.sample(.1,10000,1000000,false,false,0)
	check("old_tracker_disconnected", not t.active and gm.profile.star_wallet.available == wallet.available+1)
	gm.star_tracker.sample(.1,200,20000,false,false,0)
	check("repeat_rewarded_objective_no_pay", gm.profile.star_wallet.available == wallet.available+1)
	gm.abandon_run()
	check("abandon_preserves_set_and_receipt", gm.state == GameManager.State.MENU and gm.profile.free_run.set.id == 1 and gm.profile.free_run.set.completed == [true,false,false] and gm.star_tracker == null)
	at.call("start_seen_run")
	gm.hand.playing = false
	gm._on_flick(Vector2.ZERO)
	# v34: the Free Run list stays open during the run (no collapse), compact rows show the progress
	check("run_compact_list_open", gm.ui.star_hud.expanded and gm.ui.star_hud.compact and gm.ui.star_hud.rows[0].visible)
	gm.star_tracker.on_charge(.8)
	check("cross_attempt_partial_two", gm.profile.free_run.set.completed == [true,false,true] and gm.profile.star_wallet.available == wallet.available+2)
	for i in 3: gm.star_tracker.on_landed({"type":"both","charge_ratio":.2})
	check("all_complete_reward_once", gm.profile.free_run.set.completed == [true,true,true] and gm.profile.star_wallet.available == wallet.available+3)
	check("completed_challenges_do_not_end_run", gm.state == GameManager.State.RUN and not gm._attempt_saved)
	check("free_campaign_adaptive_untouched", cp == gm.profile.campaign and adaptive == gm.profile.adaptive and gm.profile.coins == coins)
	gm.distance_m = 104.9
	gm._finish("test")
	check("free_coin_rule_unchanged", gm.profile.coins == coins+20 and gm.last_result.coins_earned == 20)
	at.call("start_seen_run")
	gm.hand.playing = false
	check("next_attempt_refreshes_once", gm.profile.free_run.set.id == 2 and gm.profile.free_run.set.completed == [false,false,false])
	var current := gm.profile.free_run.duplicate(true)
	gm.abandon_run(); at.call("start_seen_run"); gm.hand.playing = false
	check("abandon_restart_no_reroll", gm.profile.free_run == current)
	gm.go_menu()
	gm.profile.free_run = {"sequence":7,"set":fixture()}
	gm.profile.free_run.set.id = 7
	gm.profile.free_run.set.challenges[0] = {"type":"CLEAN_START","m":70,"reward":0}
	gm.profile.save(); at.call("start_seen_run"); gm.hand.playing = false
	var available: int = gm.profile.star_wallet.available
	gm.star_tracker.on_limb(10); gm.star_tracker.sample(.1,100,10000,false,false,0)
	check("failed_uncompleted_no_reward", gm.star_tracker.status[0] == -1 and gm.profile.star_wallet.available == available and gm.profile.free_run.set.completed == [false,false,false])
	gm.abandon_run(); at.call("start_seen_run"); gm.hand.playing = false
	check("failed_objective_retries_same_set", gm.profile.free_run.set.id == 7 and gm.star_tracker.status[0] == 0)
	gm.go_menu()

func layout() -> void:
	for resolution in [Vector2i(1280,720),Vector2i(960,540),Vector2i(1920,1200)]:
		for cut in [Vector4.ZERO,Vector4(170,20,60,20),Vector4(60,20,170,20)]:
			DisplayServer.window_set_size(resolution)
			await frames(6)
			gm.ui.debug_safe_margins = cut; gm.ui.apply_safe_area()
			gm.mode = &"free"; at.call("start_seen_run"); gm.hand.playing = false
			await frames(6)
			var m := gm.ui.safe_margins
			var usable := Rect2(Vector2(m.x,m.y),get_viewport().get_visible_rect().size-Vector2(m.x+m.z,m.y+m.w))
			var hud := gm.ui.star_hud
			var okay := usable.encloses(hud.get_global_rect()) and hud.toggle.size.y >= 48 and hud.rows[0].get_theme_font_size("font_size") >= 20
			for b in [gm.ui.restart_button,gm.ui.abandon_button]:
				okay = okay and usable.encloses(b.get_global_rect()) and not b.get_global_rect().intersects(hud.get_global_rect())
			okay = okay and not gm.ui.charge_bar.get_global_rect().intersects(hud.get_global_rect())
			check("intro_layout_%s_%d" % [resolution,int(cut.x)],okay,str(hud.get_global_rect()))
			if at.get("shots_dir") != "": at.call("_shot","free_intro_%dx%d_%d" % [resolution.x,resolution.y,int(cut.x)])
			hud.compact = true; hud.collapse_free()
			await frames(5)
			# v34: no collapse any more - the list stays open and the header counter takes no input
			check("open_run_layout_%s_%d" % [resolution,int(cut.x)], usable.encloses(hud.get_global_rect()) and hud.rows[0].visible and hud.toggle.visible and not gm.ui.blocks_point(hud.toggle.get_global_rect().get_center()))
			check("expanded_run_layout_%s_%d" % [resolution,int(cut.x)],usable.encloses(hud.get_global_rect()) and hud.rows.all(func(row: Label) -> bool: return row.visible and row.size.x <= 420))
			var text_sets := [
				[{"type":"DISTANCE","m":450},{"type":"BAD_LANDING_LIMIT","m":160,"n":2},{"type":"CHARGE_TARGET","pct":55}],
				[{"type":"CLEAN_START","m":65},{"type":"GOOD_LANDING_STREAK","n":5},{"type":"CHARGED_LANDING","pct":40}],
				[{"type":"LIMB_LIMIT","m":200,"n":2},{"type":"RECOVERY","n":1},{"type":"CHARGED_LANDING_STREAK","n":2,"pct":25}],
				[{"type":"SURVIVAL_HP","m":120,"hp":55},{"type":"CLEAN_SECTION","m":120},{"type":"AIR_TIME","s":3.2}],
				[{"type":"DISTANCE","m":450},{"type":"TOTAL_GOOD_LANDINGS","n":9},{"type":"LONG_JUMP","m":55}],
				[{"type":"CLEAN_START","m":65},{"type":"RECOVERY","n":1},{"type":"SPEED_TARGET","kmh":100}]]
			for case_index in text_sets.size():
				hud.setup(StarTracker.new(text_sets[case_index]),true)
				await frames(5)
				var robot_point := get_viewport().get_canvas_transform()*gm.robot.global_position
				var robot_rect := Rect2(robot_point-Vector2(80,100),Vector2(160,200))
				var fits := usable.encloses(hud.get_global_rect()) and not hud.get_global_rect().intersects(robot_rect)
				for row in hud.rows:
					fits = fits and usable.encloses(row.get_global_rect()) and row.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and row.get_theme_font_size("font_size") >= 20
				check("all_types_text_%s_%d_%d" % [resolution,int(cut.x),case_index],fits,"panel=%s robot=%s" % [hud.get_global_rect(),robot_rect])
				if case_index==2 and at.get("shots_dir") != "": at.call("_shot","free_long_text_%dx%d_%d" % [resolution.x,resolution.y,int(cut.x)])
			gm.go_menu(); await frames(6)
			check("wallet_meta_%s_%d" % [resolution,int(cut.x)],usable.encloses(gm.ui.coins_label_menu.get_global_rect()) and gm.ui.coins_label_menu.text.contains("Звёзды доступны"))
	gm.ui.debug_safe_margins = Vector4(-1,-1,-1,-1); gm.ui.apply_safe_area()

func calibration() -> void:
	var args: Dictionary = at.get("args")
	var count := int(args.get("samples",8))
	var total := 0
	for robot_id in ["tin","hopper","heavy","rocket","samurai"]:
		for sample in count:
			gm.go_menu(); gm.mode = &"free"
			if not gm.profile.owned.has(robot_id):
				gm.profile.owned.append(robot_id)
			gm.profile.selected = robot_id
			at.call("start_seen_run"); gm.hand.playing = false
			gm.track_seed = int(args.get("seed_base",140000)) + sample*17
			gm.terrain.reset(gm.track_seed)
			await frames(20) # Settle the real launch ledge, like the normal hand intro.
			at.set("bot", "smart" if sample < count/2 else "charger")
			gm._on_flick(Vector2.ZERO)
			var tracked := StarTracker.new()
			tracked.attach(gm.robot,gm.level_config.px_per_meter)
			var elapsed := 0.0
			while gm.state in [GameManager.State.RUN,GameManager.State.ROCKET] and elapsed < 180:
				at.set("_t",elapsed)
				gm.input.set_virtual_hold(at.call("_decide",gm.robot) if gm.state == GameManager.State.RUN else false)
				await get_tree().physics_frame
				elapsed += 1.0/120.0
				tracked.step(1.0/120.0,gm.distance_m)
			tracked.finalize_contact(); tracked.step(0.0,gm.distance_m); tracked.stop()
			var metrics := tracked.metrics()
			print("AT|free_sample " + JSON.stringify({"robot":robot_id,"bot":at.get("bot"),"seed":gm.track_seed,"elapsed":elapsed,"finished":gm.state==GameManager.State.RESULT,"metrics":metrics}))
			total += 1
			gm.go_menu(); await frames(2)
	check("calibration_complete",total == 5*count,"actual physical player runs=%d" % total)


func rate_report() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("G:/Godot/EpicShalban/reports/v14_free_samples.json"))
	var cfg := FreeChallenges.config()
	for robot_id in ["tin","hopper","heavy","rocket","samurai"]:
		var samples: Array = rows.filter(func(row: Dictionary) -> bool: return row.robot == robot_id)
		for type in StarChallenges.TYPES:
			var values: Dictionary = cfg.thresholds[type].duplicate(true)
			values.merge(cfg.robot_overrides.get(robot_id, {}).get(type, {}), true)
			for level in 3:
				var ch := {"type":type,"reward":0}
				for key in StarChallenges.TYPES[type].params:
					var pool: Array = values[key]
					ch[key] = pool[mini(level,pool.size()-1)]
				var done := 0
				for row in samples:
					done += int(StarTracker.evaluate(ch,row.metrics))
				print("AT|free_rate " + JSON.stringify({"robot":robot_id,"level":level,"challenge":ch,"completed":done,"samples":samples.size(),"excluded":values.get("exclude",false)}))
	var start := Time.get_ticks_usec()
	var evaluated := 0
	for row in rows:
		for seed_value in 100:
			var value := FreeChallenges.generate(row.robot,seed_value,seed_value+1,cfg)
			var completions := 0
			for ch in value.challenges:
				completions += int(StarTracker.evaluate(ch,row.metrics)); evaluated += 1
			print("AT|free_set_sample " + JSON.stringify({"robot":row.robot,"seed":row.seed,"bot":row.bot,"set_seed":seed_value,"completed":completions}))
	print("AT|free_eval_perf evaluations=%d elapsed_usec=%d" % [evaluated,Time.get_ticks_usec()-start])
	var test_tracker := StarTracker.new(fixture().challenges)
	start = Time.get_ticks_usec()
	for i in 10000: test_tracker.sample(0.0,20,2000,false,true,20)
	var tracker_usec := Time.get_ticks_usec()-start
	start = Time.get_ticks_usec()
	for i in 1000: FreeChallenges.generate("tin",i,i+1,cfg)
	var generation_usec := Time.get_ticks_usec()-start
	print("AT|free_microbench samples=10000 tracker_usec=%d generations=1000 generation_usec=%d" % [tracker_usec,generation_usec])
	check("shared_evaluator_report",rows.size()==40 and evaluated==12000)
