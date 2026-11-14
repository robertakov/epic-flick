extends Node
## v31 player profile tests (debug only, not exported). Need --profiles_root=<test dir> (except profiles_prep).
##   --scenario=profiles           : 3 slots, independence, delete, re-create, legacy migration (once), cycles, UI flow
##   --scenario=profiles_prep      : (no --profiles_root) writes a pre-v31 single-file save into --legacy_root
##   --scenario=profiles_restart_a : 1st real boot on that root: migration at boot, edit P1, create P2, store expectations
##   --scenario=profiles_restart_b : 2nd real boot: everything restored, legacy not re-imported
## Prints "AT|test profiles_<name> PASS|FAIL <details>".
var gm: GameManager
var at: Node
var passed := 0
var failed := 0


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test profiles_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _arg(key: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def


func run_all(which: String) -> void:
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	match which:
		"profiles_prep":
			prep()
		"profiles_restart_a":
			await restart_a()
		"profiles_restart_b":
			await restart_b()
		"profiles_qa":
			await qa()
		_:
			await all_tests()
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ---------------- helpers ----------------

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


func _fresh_root(name: String) -> String:
	var base := _arg("profiles_root", "user://test/v31/profiles/")
	var r := base.path_join("cases").path_join(name) + "/"
	_wipe(r)
	DirAccess.make_dir_recursive_absolute(r)
	return r


## Point the running game at another profiles root, exactly like a fresh boot does (migration + placeholder).
func _gm_use(root: String) -> void:
	gm.go_menu()
	gm.profiles = ProfileManager.new(root)
	gm.profiles.migrate_legacy()
	gm._use_placeholder_profile()
	gm._bind_profile_ui()
	gm.open_profiles()


func snap(p: ProfileStore, s: StatsStore) -> String:
	return JSON.stringify({"coins": p.coins, "owned": p.owned, "selected": p.selected,
		"unlocked": p.campaign.unlocked, "completed": p.campaign.completed, "claimed": p.campaign.claimed,
		"stars": p.campaign.stars, "wallet": p.star_wallet.available, "skins": p.owned_skins,
		"equipped": p.equipped_skins, "tutorial": p.tutorial, "best_m": s.best_m(), "attempts": int(s.data.attempts),
		"total_m": float(s.data.total_m)}, "", true)


func gm_snap() -> String:
	return snap(gm.profile, gm.stats)


## Snapshot of a slot read back from disk (as a new launch would see it).
func disk_snap(mgr: ProfileManager, slot: int) -> String:
	var p := ProfileStore.new(mgr.profile_path(slot), gm.catalog)
	p.load_data()
	p.ensure_campaign_start(gm.campaign.start_id)
	var s := StatsStore.new(mgr.stats_path(slot))
	s.load_data()
	return snap(p, s)


func empty_snap() -> String:
	var p := ProfileStore.new("", gm.catalog)
	p.ensure_campaign_start(gm.campaign.start_id)
	return snap(p, StatsStore.new(""))


func _buyable(k: int) -> RobotDefinition:
	var starters := gm.catalog.starter_ids()
	var list: Array = []
	for d in gm.catalog.robots:
		if not starters.has(d.id):
			list.append(d)
	return list[k % list.size()] if not list.is_empty() else null


## Gives the ACTIVE player recognisable progress: coins, campaign, stars, a robot, a record, statistics, tutorial.
func play_progress(k: int) -> void:
	var p := gm.profile
	p.add_coins(1000 * k + 37)
	p.complete("r1", ["r2"])
	p.claim_first_clear("r1", 50)
	if k >= 2:
		p.complete("r2", ["r3"])
	p.earn_star("r1", k % 3, 25)
	var d := _buyable(k)
	if d:
		p.coins += d.price
		p.buy(d)
		p.select(d.id)
	gm.stats.record_attempt({"id": "pt_%d_%d" % [k, randi()], "distance_m": 100.0 * k + 7.0, "duration_s": 12.0, "good": k})
	p.tutorial.handled = true
	p.save()


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


# ---------------- main suite ----------------

func all_tests() -> void:
	# 0. a real boot in profile mode lands on the profile screen with nothing active
	check("boot_shows_profile_screen", gm.ui.is_profiles_open() and gm.active_slot == 0 and gm.profile.path == ""
		and not gm.ui.profiles_view.back_button.visible)
	# 1. clean install: three empty slots
	var root := _fresh_root("main")
	_gm_use(root)
	var m := gm.profiles
	var empties := true
	for s in range(1, 4):
		empties = empties and not m.exists(s) and not bool(m.summary(s).exists)
	check("clean_install_3_empty_slots", empties and m.last_migration == "nothing", m.last_migration)
	check("empty_cards_offer_new_game", gm.ui.profiles_view.lines[0].text == "НОВАЯ ИГРА" and gm.ui.profiles_view.lines[2].text == "НОВАЯ ИГРА"
		and not gm.ui.profiles_view.delete_buttons[1].visible)
	# placeholder never writes: menu actions without a player create nothing
	gm.profile.add_coins(5)
	gm.stats.save()
	check("placeholder_never_writes", not m.exists(1) and not FileAccess.file_exists(m.profile_path(1)))

	# 2. PLAYER 1: new game from the empty card (real button), progress, save, reload from disk
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(2)
	check("empty_slot_starts_new_game", gm.active_slot == 1 and m.exists(1) and not gm.ui.is_profiles_open()
		and gm_snap() == empty_snap(), "active=%d" % gm.active_slot)
	play_progress(1)
	var p1 := gm_snap()
	check("p1_persists_after_reload", disk_snap(m, 1) == p1)
	check("menu_chip_shows_player", gm.ui.profile_chip.visible and gm.ui.profile_chip.text == "PLAYER 1")

	# 3. PLAYER 2 starts completely clean
	check("open_profiles_from_menu", gm.open_profiles() and gm.ui.profiles_view.back_button.visible)
	gm.ui.profiles_view.play_buttons[1].pressed.emit()
	await frames(2)
	check("p2_starts_clean", gm.active_slot == 2 and gm_snap() == empty_snap() and gm.best_m == 0.0)
	check("p2_robot_defaults", gm.profile.owned == gm.catalog.starter_ids() and gm.profile.selected == gm.catalog.starter_ids()[0])
	# 4. PLAYER 2 changes do not touch PLAYER 1
	var p1_bytes := _bytes(m.profile_path(1)) + _bytes(m.stats_path(1))
	play_progress(2)
	var p2 := gm_snap()
	check("p2_changes_leave_p1", disk_snap(m, 1) == p1 and _bytes(m.profile_path(1)) + _bytes(m.stats_path(1)) == p1_bytes)
	# 5. back to PLAYER 1: exactly its data
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(2)
	check("p1_restored_on_switch", gm.active_slot == 1 and gm_snap() == p1)
	check("p1_record_restored", is_equal_approx(gm.best_m, 107.0) and gm.ui.best_label_menu.text == "РЕКОРД: 107 м", gm.ui.best_label_menu.text)
	# 6. PLAYER 3 independent too
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[2].pressed.emit()
	await frames(2)
	check("p3_starts_clean", gm.active_slot == 3 and gm_snap() == empty_snap())
	play_progress(3)
	var p3 := gm_snap()
	check("p3_independent", disk_snap(m, 1) == p1 and disk_snap(m, 2) == p2 and p3 != p1 and p3 != p2)
	# 12-15. per-category independence (stars / coins / robots / records + statistics)
	var a := ProfileStore.new(m.profile_path(1), gm.catalog); a.load_data()
	var b := ProfileStore.new(m.profile_path(2), gm.catalog); b.load_data()
	var c := ProfileStore.new(m.profile_path(3), gm.catalog); c.load_data()
	var sa := StatsStore.new(m.stats_path(1)); sa.load_data()
	var sb := StatsStore.new(m.stats_path(2)); sb.load_data()
	var sc := StatsStore.new(m.stats_path(3)); sc.load_data()
	check("stars_independent", a.has_star("r1", 1) and not a.has_star("r1", 2) and b.has_star("r1", 2) and not b.has_star("r1", 1)
		and c.has_star("r1", 0) and a.total_stars() == 1 and b.total_stars() == 1)
	check("campaign_independent", not a.is_completed("r2") and b.is_completed("r2") and c.is_completed("r2") and a.is_unlocked("r2") and not a.is_unlocked("r3"))
	check("coins_independent", a.coins == 1037 + 50 + 25 and b.coins == 2037 + 50 + 25 and c.coins == 3037 + 50 + 25, "%d %d %d" % [a.coins, b.coins, c.coins])
	check("robots_independent", a.selected != b.selected and a.owned.size() == gm.catalog.starter_ids().size() + 1
		and not a.owned.has(b.selected) and not b.owned.has(a.selected), "%s %s %s" % [a.selected, b.selected, c.selected])
	check("records_stats_independent", is_equal_approx(sa.best_m(), 107.0) and is_equal_approx(sb.best_m(), 207.0) and is_equal_approx(sc.best_m(), 307.0)
		and int(sa.data.attempts) == 1 and int(sb.data.good_landings) == 2)
	check("tutorial_flag_per_player", a.tutorial.handled and b.tutorial.handled)

	# 7. deleting PLAYER 2: one tap is not enough, cancel keeps it, confirm deletes ONLY it
	gm.open_profiles()
	var pv := gm.ui.profiles_view
	var keep1 := _bytes(m.profile_path(1)) + _bytes(m.stats_path(1))
	var keep3 := _bytes(m.profile_path(3)) + _bytes(m.stats_path(3))
	pv.delete_buttons[1].pressed.emit()
	check("delete_needs_confirmation", m.exists(2) and pv.confirm_open() and pv.confirm_title.text == "УДАЛИТЬ PLAYER 2?")
	pv.confirm_no.pressed.emit()
	check("delete_cancel_keeps_slot", m.exists(2) and not pv.confirm_open())
	pv.delete_buttons[1].pressed.emit()
	pv.confirm_yes.pressed.emit()
	await frames(2)
	check("delete_p2_only", not m.exists(2) and not FileAccess.file_exists(m.profile_path(2)) and not FileAccess.file_exists(m.stats_path(2))
		and _bytes(m.profile_path(1)) + _bytes(m.stats_path(1)) == keep1 and _bytes(m.profile_path(3)) + _bytes(m.stats_path(3)) == keep3)
	check("deleted_card_is_new_game", pv.visible and pv.lines[1].text == "НОВАЯ ИГРА" and gm.active_slot == 3)
	# 8. re-created slot 2 is really clean
	pv.play_buttons[1].pressed.emit()
	await frames(2)
	check("recreated_slot_clean", gm.active_slot == 2 and gm_snap() == empty_snap() and disk_snap(m, 2) == empty_snap())
	# deleting the ACTIVE player leaves it to the profile screen and nothing recreates its files
	gm.open_profiles()
	pv.delete_buttons[1].pressed.emit()
	pv.confirm_yes.pressed.emit()
	await frames(2)
	gm.profile.add_coins(3)
	gm.stats.save()
	check("delete_active_exits_to_profiles", gm.active_slot == 0 and gm.ui.is_profiles_open() and not pv.back_button.visible
		and not m.exists(2) and not FileAccess.file_exists(m.profile_path(2)) and not gm.ui.profile_chip.visible)
	# never mid-run: the profile screen and switching are refused during a run
	pv.play_buttons[0].pressed.emit()
	await frames(2)
	gm.start_run()
	await frames(3)
	var refused := not gm.open_profiles() and not gm.activate_slot(3) and not gm.delete_slot(3) and gm.active_slot == 1
	gm.go_menu()
	await frames(2)
	check("no_switch_mid_run", refused and disk_snap(m, 3) == p3)

	# 16. many save/load/switch cycles: no leakage
	var expected := {1: gm_snap(), 3: p3}
	for cyc in 4:
		for slot in [1, 3]:
			gm.open_profiles()
			pv.play_buttons[slot - 1].pressed.emit()
			await frames(1)
			gm.profile.add_coins(slot)
			gm.stats.record_attempt({"id": "cyc_%d_%d" % [cyc, slot], "distance_m": 1.0})
			expected[slot] = gm_snap()
	var cyc_ok: bool = disk_snap(m, 1) == expected[1] and disk_snap(m, 3) == expected[3] and not m.exists(2)
	gm.open_profiles(); pv.play_buttons[0].pressed.emit(); await frames(1)
	cyc_ok = cyc_ok and gm_snap() == expected[1]
	check("switch_cycles_no_leak", cyc_ok)
	check("last_slot_is_app_level", m.last_slot() == 1 and FileAccess.file_exists(m.dir_path() + "/index.json")
		and not ProfileManager._read_json(m.profile_path(1)).has("last_slot"))

	await legacy_tests()
	gm.go_menu()


# ---------------- legacy migration ----------------

## A pre-v31 single-file save exactly as the v30 game wrote it (same ProfileStore / StatsStore code and format).
func write_legacy(root: String, k: int) -> String:
	var p := ProfileStore.new(root + "profile.json", gm.catalog)
	p.load_data()
	p.ensure_campaign_start(gm.campaign.start_id)
	p.add_coins(4321 + k)
	for i in range(1, 6):
		p.complete("r%d" % i, ["r%d" % (i + 1)])
		p.earn_star("r%d" % i, 0, 10)
	var d := _buyable(k)
	if d:
		p.coins += d.price
		p.buy(d)
		p.select(d.id)
	p.tutorial.handled = true
	p.save()
	var s := StatsStore.new(root + "stats.json")
	s.record_attempt({"id": "legacy_%d" % k, "distance_m": 555.0 + k, "duration_s": 30.0, "good": 9})
	s.save()
	return snap(p, s)


func legacy_tests() -> void:
	# 9. legacy save -> PLAYER 1 (same progress), 2 and 3 empty, originals untouched
	var root := _fresh_root("legacy")
	var legacy := write_legacy(root, 1)
	var orig := _bytes(root + "profile.json") + _bytes(root + "stats.json")
	_gm_use(root)
	var m := gm.profiles
	check("legacy_migrated_to_p1", m.last_migration == "migrated" and m.exists(1) and disk_snap(m, 1) == legacy and not m.exists(2) and not m.exists(3), m.last_migration)
	check("legacy_files_untouched", _bytes(root + "profile.json") + _bytes(root + "stats.json") == orig)
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(2)
	check("legacy_p1_plays_with_old_progress", gm.active_slot == 1 and gm_snap() == legacy and gm.profile.is_completed("r5")
		and gm.profile.total_stars() == 5 and is_equal_approx(gm.best_m, 556.0))
	var card: Dictionary = m.summary(1)
	check("summary_from_existing_data", int(card.round) == 6 and int(card.stars) == 5 and int(card.coins) == gm.profile.coins, str(card))
	# 10. one-time: a second launch does nothing, even with the legacy files still there and P1 changed
	gm.profile.add_coins(1)
	var changed := gm_snap()
	var m2 := ProfileManager.new(root)
	check("legacy_migration_once", m2.migrate_legacy() == "already" and disk_snap(m2, 1) == changed)
	# 11. delete PLAYER 1 -> the old save never comes back (index marker), not even if index.json is lost
	gm.open_profiles()
	gm.ui.profiles_view.delete_buttons[0].pressed.emit()
	gm.ui.profiles_view.confirm_yes.pressed.emit()
	await frames(2)
	var m3 := ProfileManager.new(root)
	var no_return := m3.migrate_legacy() == "already" and not m3.exists(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m3.dir_path() + "/index.json"))
	var m4 := ProfileManager.new(root)
	no_return = no_return and m4.migrate_legacy() == "already" and not m4.exists(1)
	check("deleted_p1_never_reimports_legacy", no_return and FileAccess.file_exists(root + "profile.json"))
	# older formats: v1 profile (coins/owned/selected only) and the v0.1 progress.cfg best distance
	var r2 := _fresh_root("legacy_v1")
	var f := FileAccess.open(r2 + "profile.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "coins": 777, "owned": gm.catalog.starter_ids(), "selected": gm.catalog.starter_ids()[0]}))
	f.close()
	var cf := ConfigFile.new()
	cf.set_value("progress", "best_m", 88.5)
	cf.save(r2 + "progress.cfg")
	var m5 := ProfileManager.new(r2)
	m5.migrate_legacy()
	var p5 := ProfileStore.new(m5.profile_path(1), gm.catalog); p5.load_data()
	var s5 := StatsStore.new(m5.stats_path(1)); s5.load_data()
	check("legacy_old_formats", m5.exists(1) and p5.coins == 777 and is_equal_approx(s5.best_m(), 88.5), "%d %.1f" % [p5.coins, s5.best_m()])
	# no legacy at all + a legacy file appearing later is not imported (the marker was set on the first launch)
	var r3 := _fresh_root("legacy_late")
	var m6 := ProfileManager.new(r3)
	var first := m6.migrate_legacy()
	write_legacy(r3, 2)
	check("no_legacy_then_never", first == "nothing" and ProfileManager.new(r3).migrate_legacy() == "already" and not ProfileManager.new(r3).exists(1))
	# a slot 1 that already exists is never overwritten by a migration
	var r4 := _fresh_root("legacy_slot_kept")
	var m7 := ProfileManager.new(r4)
	m7.create(1)
	var mine := _bytes(m7.slot_dir(1) + "/slot.json")
	write_legacy(r4, 3)
	check("migration_never_overwrites_slot", m7.migrate_legacy() == "slot1_kept" and _bytes(m7.slot_dir(1) + "/slot.json") == mine
		and not FileAccess.file_exists(m7.profile_path(1)))
	await frames(1)


# ---------------- visual QA ----------------

func qa() -> void:
	var root := _fresh_root("qa")
	_gm_use(root)
	await frames(10)
	at.call("_shot", "pq_empty")
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(2)
	play_progress(2)
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[2].pressed.emit()
	await frames(2)
	play_progress(1)
	gm.open_profiles()
	await frames(10)
	at.call("_shot", "pq_mixed")
	gm.ui.profiles_view.delete_buttons[0].pressed.emit()
	await frames(10)
	at.call("_shot", "pq_confirm")
	gm.ui.profiles_view.cancel_delete()
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[2].pressed.emit()   # reload P3 so the menu shows its fresh record / coins
	await frames(20)
	at.call("_shot", "pq_menu_chip")
	check("qa_done", true)


# ---------------- real restarts (separate processes) ----------------

func prep() -> void:
	var root := _arg("legacy_root")
	_wipe(root)
	DirAccess.make_dir_recursive_absolute(root)
	var legacy := write_legacy(root, 7)
	var f := FileAccess.open(root + "expect_legacy.json", FileAccess.WRITE)
	f.store_string(legacy)
	f.close()
	check("prep_legacy_written", FileAccess.file_exists(root + "profile.json") and FileAccess.file_exists(root + "stats.json"))


func restart_a() -> void:
	var root := _arg("profiles_root")
	var m := gm.profiles
	var legacy := FileAccess.get_file_as_string(root + "expect_legacy.json")
	check("upgrade_boot_migrated", m != null and m.last_migration == "migrated" and gm.ui.is_profiles_open() and gm.active_slot == 0,
		m.last_migration if m else "no manager")
	check("upgrade_p1_equals_old_save", disk_snap(m, 1) == legacy and not m.exists(2) and not m.exists(3))
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(2)
	gm.profile.add_coins(11)
	gm.stats.record_attempt({"id": "restart_a_1", "distance_m": 900.0})
	var e1 := gm_snap()
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[1].pressed.emit()
	await frames(2)
	play_progress(4)
	var e2 := gm_snap()
	gm.open_profiles()   # leaving to the profile screen saves the active player
	var f := FileAccess.open(root + "expect_restart.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"p1": e1, "p2": e2}))
	f.close()
	check("restart_a_written", m.exists(1) and m.exists(2) and not m.exists(3))


func restart_b() -> void:
	var root := _arg("profiles_root")
	var m := gm.profiles
	var e: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root + "expect_restart.json"))
	check("restart_no_reimport", m.last_migration == "already" and gm.ui.is_profiles_open() and gm.active_slot == 0, m.last_migration)
	check("restart_last_slot_app_level", m.last_slot() == 2)
	gm.ui.profiles_view.play_buttons[0].pressed.emit()
	await frames(2)
	check("restart_p1_restored", gm_snap() == String(e.p1))
	gm.open_profiles()
	gm.ui.profiles_view.play_buttons[1].pressed.emit()
	await frames(2)
	check("restart_p2_restored", gm_snap() == String(e.p2))
	check("restart_p3_still_empty", m.exists(2) and not m.exists(3))
	check("restart_legacy_files_kept", FileAccess.file_exists(root + "profile.json") and FileAccess.file_exists(root + "stats.json"))
