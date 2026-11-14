extends Node
## v34 localization tests (debug only, not exported). Prints "AT|test loc_<name> PASS|FAIL <details>".
##   --scenario=loc_audit   string table / plural / Auto / glyph / hard-coded-text audit (headless ok)
##   --scenario=loc_fit     every player-facing screen in the --locale=<code> language: no clipped / off-screen / tofu
##                          text, no tiny text (needs -Window; with --shots=<dir> also saves the QA screenshots)
##   --scenario=loc_switch  Settings > Language: saved app-globally, scene rebuilt, same player back on Settings
var gm: GameManager
var at: Node
var passed := 0
var failed := 0
static var _sp := 0          # loc_switch spans scene reloads
static var _sf := 0
const MIN_PX := 14.0         # smallest acceptable on-screen font size (1280x720 canvas)
const PROFILES := "user://test/loc_profiles/"


func check(label: String, ok: bool, details := "") -> void:
	passed += int(ok); failed += int(not ok)
	print("AT|test loc_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run_all(which: String) -> void:
	at.set("max_time", 1.0e9)
	at.set("scenario_running", true)
	match which:
		"loc_audit":
			audit()
		"loc_fit":
			await fit()
		"loc_switch":
			await switch()
			return
	print("AT|tests passed=%d failed=%d" % [passed, failed])


# ---------------- audit ----------------

func audit() -> void:
	var keys := L.all_keys()
	var codes := L.codes()
	check("all_locales_listed", codes.size() == 13 and codes.has("pt_BR") and codes.has("zh_CN"), str(codes))
	# every key: every locale present and non-empty (plural keys: the forms that locale's rule needs)
	var missing := []
	var plural_bases := {}
	for k in keys:
		for suf in ["_one", "_few", "_many", "_other"]:
			if String(k).ends_with(suf):
				plural_bases[String(k).trim_suffix(suf)] = true
	for k in keys:
		var is_plural_form := false
		for b in plural_bases:
			if String(k).begins_with(b + "_") and String(k).trim_prefix(b + "_") in ["one", "few", "many", "other"]:
				is_plural_form = true
		if is_plural_form:
			continue
		for c in codes:
			if String(keys[k].get(c, "")).strip_edges() == "":
				missing.append("%s/%s" % [k, c])
	for b in plural_bases:
		for c in codes:
			for cat in _cats(c):
				if String(keys.get(b + "_" + cat, {}).get(c, "")).strip_edges() == "":
					missing.append("%s_%s/%s" % [b, cat, c])
	check("no_missing_or_empty_strings", missing.is_empty(), "%d keys, %d plural phrases, missing %s" % [keys.size(), plural_bases.size(), str(missing.slice(0, 8))])
	# every locale really loads into the TranslationServer
	var loaded := []
	for c in codes:
		L.apply(c)
		if L.locale() == c and L.t("MENU_SETTINGS") != "MENU_SETTINGS" and L.t("MENU_SETTINGS") == String(keys["MENU_SETTINGS"][c]):
			loaded.append(c)
	check("every_locale_loads", loaded.size() == codes.size(), "%d/%d" % [loaded.size(), codes.size()])
	_plural_tests()
	_auto_tests()
	_code_key_tests()
	_challenge_text_tests()
	_data_tests()
	_hardcoded_scan()
	_glyph_tests()
	L.apply("ru")


static func _cats(code: String) -> Array:
	match code.split("_")[0]:
		"ru", "uk", "pl":
			return ["one", "few", "many"]
		"zh", "ja", "ko":
			return ["other"]
	return ["one", "other"]


func _plural_tests() -> void:
	var cases := {
		"ru": {1: "one", 2: "few", 4: "few", 5: "many", 11: "many", 12: "many", 21: "one", 22: "few", 25: "many", 0: "many", 111: "many", 600: "many"},
		"uk": {1: "one", 3: "few", 7: "many", 14: "many", 31: "one", 44: "few"},
		"pl": {1: "one", 2: "few", 5: "many", 12: "many", 21: "many", 22: "few", 0: "many"},
		"fr": {0: "one", 1: "one", 2: "other"}, "pt_BR": {0: "one", 1: "one", 2: "other"},
		"en": {0: "other", 1: "one", 2: "other"}, "de": {1: "one", 5: "other"}, "tr": {1: "one", 3: "other"},
		"zh_CN": {1: "other", 2: "other"}, "ja": {1: "other"}, "ko": {5: "other"},
	}
	var bad := []
	for c in cases:
		for n in cases[c]:
			if L.category(n, c) != cases[c][n]:
				bad.append("%s %d -> %s" % [c, n, L.category(n, c)])
	check("plural_rules", bad.is_empty(), str(bad))
	var phrases := {"ru": {1: "1 монета", 2: "2 монеты", 5: "5 монет", 21: "21 монета", 600: "600 монет"},
		"pl": {1: "1 moneta", 2: "2 monety", 5: "5 monet", 22: "22 monety"}, "uk": {1: "1 монета", 3: "3 монети", 11: "11 монет"},
		"en": {0: "0 coins", 1: "1 coin", 600: "600 coins"}, "fr": {0: "0 pièce", 1: "1 pièce", 2: "2 pièces"},
		"zh_CN": {1: "1 金币", 600: "600 金币"}}
	var wrong := []
	for c in phrases:
		L.apply(c)
		for n in phrases[c]:
			var s := L.pf("COINS_N", n)
			if s != phrases[c][n]:
				wrong.append("%s %d '%s'" % [c, n, s])
	check("plural_phrases_whole_sentences", wrong.is_empty(), str(wrong))
	L.apply("ru")
	var cont := L.pf("CONT_CONFIRM_Q", 600)
	check("continue_confirm_russian_text", cont == "ПОТРАТИТЬ 600 МОНЕТ И ПРОДОЛЖИТЬ?", cont)


func _auto_tests() -> void:
	var cases := {"pt_PT": "pt_BR", "pt_BR": "pt_BR", "zh_TW": "zh_CN", "zh_CN": "zh_CN", "de_AT": "de", "uk_UA": "uk",
		"nl_NL": "en", "sv": "en", "ja_JP": "ja", "ko_KR": "ko", "es_MX": "es", "tr_TR": "tr", "ru_RU": "ru", "en_GB": "en", "pl_PL": "pl"}
	var bad := []
	for sys in cases:
		if L.resolve(L.AUTO, sys) != cases[sys]:
			bad.append("%s -> %s" % [sys, L.resolve(L.AUTO, sys)])
	check("auto_device_locale_else_english", bad.is_empty(), "device %s -> %s; %s" % [OS.get_locale(), L.resolve(L.AUTO), str(bad)])
	var s := SettingsStore.new("user://test/loc_settings_probe.json")
	var garbage := []
	for v in [null, 5, "xx", "", "Deutsch", ["de"]]:
		s.unrelated["language"] = v
		if s.language() != L.AUTO:
			garbage.append(str(v))
	s.unrelated.erase("language")
	var dflt := s.language()
	s.set_language("de")
	s.reset_to_defaults()
	check("language_setting_defaults_and_sanitizes", garbage.is_empty() and dflt == L.AUTO and s.language() == "de",
		"default %s, bad %s, after defaults-reset %s" % [dflt, str(garbage), s.language()])


## Every key the code asks for exists (literal L.t / L.f / L.pf / L.plural calls + the key tables).
func _code_key_tests() -> void:
	var re := RegEx.create_from_string("L\\.(t|f|pf|plural)\\(\"([A-Z0-9_]+)\"")
	var plural_re := RegEx.create_from_string("L\\.(pf|plural)\\(\"([A-Z0-9_]+)\"")
	var missing := []
	var used := {}
	for path in _scripts("res://scripts"):
		if path.ends_with("/loc.gd"):
			continue   # its doc comments show example calls
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			var k := m.get_string(2)
			used[k] = true
			if m.get_string(1) in ["pf", "plural"]:
				if not (L.has_key(k + "_other") or L.has_key(k + "_one")):
					missing.append(k + "(plural) " + path.get_file())
			elif not L.has_key(k):
				missing.append(k + " " + path.get_file())
	var tables := []
	tables.append_array(StarChallenges.SHORT_KEYS.values())
	tables.append_array(StarChallenges.CATEGORY_NAMES.values())
	for k in StarChallenges.DESCRIBE_KEYS.values():
		if not (k in StarChallenges.PLURAL_DESCRIBE):
			tables.append(k)
	tables.append_array(TutorialOverlay.PROMPTS.values())
	tables.append_array(TutorialOverlay.GATE_PROMPTS.values())
	for t in FlickPowerBar.TIERS.values():
		tables.append_array([t.short, t.title])
	for r in UIController.SETTING_ROWS:
		tables.append(r[1])
	for s in RobotSelectView.STATS:
		tables.append(s[1])
	for k in tables:
		used[k] = true
		if not L.has_key(String(k)):
			missing.append(String(k) + " (table)")
	for k in StarChallenges.PLURAL_DESCRIBE:
		used[k] = true
		if not L.has_key(k + "_other") and not L.has_key(k + "_one"):
			missing.append(k + " (plural table)")
	check("every_code_key_exists", missing.is_empty(), "%d keys referenced; missing %s" % [used.size(), str(missing)])


## Every challenge type in every locale: a real sentence (no "?", no raw key, no leftover {placeholder}).
func _challenge_text_tests() -> void:
	var samples := []
	for t in StarChallenges.TYPES:
		for n in [0, 1, 2, 3, 5, 21]:
			samples.append({"type": t, "m": 350, "n": n if (n > 0 or t in ["LIMB_LIMIT", "BAD_LANDING_LIMIT"]) else 1, "hp": 40,
				"pct": 60, "s": 3.5, "kmh": 70, "reward": 5})
	var bad := []
	for c in L.codes():
		L.apply(c)
		for ch in samples:
			for txt in [StarChallenges.describe(ch), StarChallenges.short(ch)]:
				if txt == "?" or txt.contains("{") or txt.contains("CH_") or txt.contains("CHS_") or txt.strip_edges() == "":
					bad.append("%s %s '%s'" % [c, ch.type, txt])
		if c != "ru" and c != "uk" and StarChallenges.describe({"type": "AIR_TIME", "s": 3.5}).contains("с"):
			pass
	L.apply("de")
	var de := StarChallenges.describe({"type": "NO_TOUCH_AND_WIN", "s": 3.5})
	L.apply("en")
	var en := StarChallenges.describe({"type": "NO_TOUCH_AND_WIN", "s": 3.5})
	L.apply("ru")
	var ru := StarChallenges.describe({"type": "GOOD_LANDING_STREAK", "n": 3})
	check("challenge_texts_every_locale", bad.is_empty() and de.contains("3,5") and en.contains("3.5") and ru == "3 приземления на ноги подряд",
		"%d samples x %d locales; de '%s', en '%s', ru '%s'; bad %s" % [samples.size(), L.codes().size(), de, en, ru, str(bad.slice(0, 5))])


## Names / titles / reasons that live in data files: every one maps to a key (so it is translated everywhere).
func _data_tests() -> void:
	var texts := {}
	for r in gm.catalog.robots:
		texts[r.display_name] = "robot"
		texts[r.description] = "robot description"
	for path in _files("res://config/skins", ".tres"):
		var res = load(path)
		if res and "display_name" in res:
			texts[res.display_name] = "skin"
	texts[SkinDefinition.new().display_name] = "skin default"
	for id in gm.campaign.order:
		var n: Dictionary = gm.campaign.node(id)
		texts[String(n.get("title", ""))] = "round title"
		for o in n.get("opponents", []):
			if typeof(o) == TYPE_DICTIONARY and o.has("name"):
				texts[String(o.name)] = "rival"
	for e in EnemyRoster.data().get("identities", {}):
		texts[EnemyRoster.display_name(String(e))] = "roster"
	for k in BiomeCatalog.ids():
		texts[BiomeCatalog.get_def(k).display_name] = "biome"
	for r in ["Голова приземлилась", "Робот остановился", "Упал в пропасть", "Робот провалился", "Голова улетела в пропасть",
			"Робот застрял", "Провалился", "Время вышло", "Остановился", "Застрял", "Артефакт Зоны"]:
		texts[r] = "reason"
	var unmapped := []
	L.apply("en")
	for t in texts:
		if String(t) == "":
			continue
		var out := L.data(String(t))
		if _has_cyrillic(out):
			unmapped.append("%s '%s'" % [texts[t], t])
	L.apply("ru")
	var same := true
	for t in texts:
		same = same and L.data(String(t)) == String(t)
	check("data_names_all_translated", unmapped.is_empty() and same and texts.size() > 60, "%d data texts; unmapped %s" % [texts.size(), str(unmapped.slice(0, 8))])


## No Cyrillic literal in game code except data texts that L.data() translates (debug + loc.gd excluded).
func _hardcoded_scan() -> void:
	var hits := []
	var count := 0
	for path in _scripts("res://scripts"):
		if path.contains("/debug/") or path.ends_with("/loc.gd"):
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			for lit in _literals(lines[i]):
				if not _has_cyrillic(lit):
					continue
				count += 1
				if not L.data_keys().has(lit):
					hits.append("%s:%d '%s'" % [path.get_file(), i + 1, lit])
	for path in _files("res://scenes", ".tscn"):
		var t := FileAccess.get_file_as_string(path)
		if _has_cyrillic(t):
			hits.append(path.get_file() + " (scene text)")
	check("no_hardcoded_player_text", hits.is_empty(), "%d Cyrillic literals, all data texts; offenders %s" % [count, str(hits.slice(0, 10))])


## Every character of every locale renders: the UI font (with the bundled CJK fallbacks) has it; CJK glyphs are
## guaranteed by the bundled Noto subsets (not by whatever the device ships).
func _glyph_tests() -> void:
	var font: Font = gm.ui.font
	var bundled := L.fallback_fonts()
	var tofu := {}
	var cjk_missing := {}
	var chars := 0
	for k in L.all_keys():
		var row: Dictionary = L.all_keys()[k]
		for c in row:
			var s := String(row[c])
			for i in s.length():
				var u := s.unicode_at(i)
				if u <= 32:
					continue
				chars += 1
				if not font.has_char(u):
					tofu["%s U+%04X" % [c, u]] = true
				if _is_cjk(u):
					var ok := false
					for f in bundled:
						ok = ok or f.has_char(u)
					if not ok:
						cjk_missing["%s %s" % [c, char(u)]] = true
	for l in L.LOCALES:
		var s := String(l[1])
		for i in s.length():
			if s.unicode_at(i) > 32 and not font.has_char(s.unicode_at(i)):
				tofu["endonym " + s] = true
	check("glyphs_every_locale_no_tofu", tofu.is_empty() and cjk_missing.is_empty() and bundled.size() == 4,
		"%d chars checked, bundled CJK fonts %d; tofu %s; cjk missing %s" % [chars, bundled.size(), str(tofu.keys().slice(0, 10)), str(cjk_missing.keys().slice(0, 10))])


static func _is_cjk(u: int) -> bool:
	return (u >= 0x2E80 and u <= 0x9FFF) or (u >= 0xAC00 and u <= 0xD7AF) or (u >= 0x3130 and u <= 0x318F) or (u >= 0xFF00 and u <= 0xFFEF)


static func _has_cyrillic(s: String) -> bool:
	for i in s.length():
		var u := s.unicode_at(i)
		if u >= 0x400 and u <= 0x4FF:
			return true
	return false


## String literals of one source line (stops at a # comment outside a string).
static func _literals(line: String) -> Array:
	var out := []
	var i := 0
	while i < line.length():
		var ch := line[i]
		if ch == "#":
			break
		if ch == "\"" or ch == "'":
			var q := ch
			var j := i + 1
			var buf := ""
			while j < line.length() and line[j] != q:
				if line[j] == "\\" and j + 1 < line.length():
					buf += line[j + 1]
					j += 2
					continue
				buf += line[j]
				j += 1
			out.append(buf)
			i = j + 1
			continue
		i += 1
	return out


static func _scripts(dir: String) -> Array:
	return _files(dir, ".gd")


static func _files(dir: String, ext: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files(dir.path_join(sub), ext))
	return out


# ---------------- fit / visual QA (one locale per process) ----------------

func _walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)
	return out


## Visible Labels / Buttons of the whole UI: off-screen, overflowing, tiny or tofu text.
func _issues() -> Array:
	var out := []
	var vp := get_viewport().get_visible_rect()
	for n in _walk(gm.ui, []):
		if not (n is Label or n is Button) or not n.is_visible_in_tree():
			continue
		var txt: String = n.text
		if txt.strip_edges() == "" or n.modulate.a < 0.05:
			continue
		var font: Font = n.get_theme_font("font")
		var fs: int = n.get_theme_font_size("font_size")
		var sc: float = n.get_global_transform_with_canvas().get_scale().x
		var r: Rect2 = n.get_global_rect()
		var custom_drawn: bool = n is Button and n.get_theme_color("font_color").a < 0.05
		if custom_drawn:
			continue
		var tag := "%s '%s'" % [n.get_class(), txt.left(40).replace("\n", " / ")]
		if r.position.x < vp.position.x - 4 or r.end.x > vp.end.x + 4 or r.position.y < vp.position.y - 4 or r.end.y > vp.end.y + 4:
			out.append("offscreen " + tag + " " + str(r))
		if fs * sc < MIN_PX:
			out.append("tiny %.1fpx %s" % [fs * sc, tag])
		var widest := 0.0
		for line in txt.split("\n"):
			widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if n is Button:
			if widest > n.size.x - 4:
				out.append("button overflow %.0f>%.0f %s" % [widest, n.size.x, tag])
		elif n.autowrap_mode == TextServer.AUTOWRAP_OFF and not n.clip_text and widest > n.size.x + 6:
			out.append("label overflow %.0f>%.0f %s" % [widest, n.size.x, tag])
		for i in txt.length():
			var u := txt.unicode_at(i)
			if u > 32 and not font.has_char(u):
				out.append("tofu U+%04X %s" % [u, tag])
				break
	return out


func _visit(screen: String) -> void:
	await frames(12)
	var issues := _issues()
	at.call("_shot", "loc_%s_%s" % [L.locale(), screen])
	check("fit_%s_%s" % [L.locale(), screen], issues.is_empty(), "%d issues %s" % [issues.size(), str(issues.slice(0, 6))])


func fit() -> void:
	var d := DirAccess.open("user://test")
	if d and d.dir_exists("loc_fit_profiles"):
		for f in DirAccess.get_files_at("user://test/loc_fit_profiles"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test/loc_fit_profiles/" + f))
	await frames(10)
	if gm.profiles:
		await _visit("profiles_empty")
		gm.activate_slot(1)
		await frames(6)
	gm.profile.coins = 12345
	gm.ui.set_coins(gm.profile.coins)
	gm.ui.show_menu(812.0, gm.stats.data)
	await _visit("menu")
	if gm.profiles:
		gm.open_profiles()
		await _visit("profiles")
		gm.close_profiles()
		await frames(4)
	gm.ui.open_settings()
	gm.ui._layout_settings()
	await _visit("settings")
	gm.ui.open_language_picker()
	await _visit("language_picker")
	gm.ui.language_picker.visible = false
	gm.ui.close_settings()
	gm.ui.open_stats()
	await _visit("stats")
	gm.ui.close_stats()
	gm.open_robot_select()
	await frames(6)
	var rs := gm.ui.robot_select
	for i in gm.catalog.robots.size():
		rs.index = i
		rs._refresh(true)
		await _visit("select_" + gm.catalog.robots[i].id)
	rs._note.text = L.pf("SEL_NEED", 4321)
	await _visit("select_need_coins")
	# v35 MK2 states: locked behind the boss (longest text), buyable, owned
	for id in ["hopper", "samurai"]:
		rs.index = gm.catalog.index_of(id)
		rs._refresh(true)
		rs.set_view_mk2(true)
		await _visit("select_mk2_locked_" + id)
	gm.profile.owned.append("samurai")
	gm.profile.campaign.completed.append("r40")
	rs.refresh_profile(gm.profile.owned, gm.profile.coins)
	rs.set_view_mk2(true)
	await _visit("select_mk2_buyable_samurai")
	gm.profile.mk2_owned.append("samurai")
	rs._refresh(false)
	await _visit("select_mk2_owned_samurai")
	gm.go_menu()
	await frames(4)
	gm.open_campaign_map()
	await _visit("campaign_map")
	gm.go_menu()
	await frames(4)
	gm.ui.campaign_result.show_result({"won": true, "title": "Босс: Медный Барон", "player_m": 812.0,
		"enemies": [{"name": "Барон фон Пружина", "m": 640.0, "color": Color(0.8, 0.3, 0.2)}, {"name": "Сенсей Гайко", "m": 702.0, "color": Color(0.2, 0.4, 0.8)}],
		"coins": 250, "coins_kind": "first", "skin_name": "Сёгун ночи", "has_next": true, "stars_before": [true, false, false],
		"stars_new": [1], "star_coins": 60, "stars_total": 123, "stars_available": 4})
	await frames(90)
	await _visit("campaign_result")
	gm.ui.campaign_result.visible = false
	gm.ui.show_results({"distance_m": 523.4, "best_m": 812.0, "record": false, "reason": "Голова улетела в пропасть", "landings": 21,
		"good": 12, "bad": 9, "max_charge": 0.83, "boosted": 4, "duration_s": 47.3, "coins_earned": 31, "coins_total": 12376})
	await frames(120)
	await _visit("free_result")
	gm.go_menu()
	await frames(4)
	gm.mode = &"free"
	gm.start_run()
	var t := 0
	while gm.state != GameManager.State.RUN and t < 900:
		await get_tree().physics_frame
		t += 1
	await frames(150)
	await _visit("free_run_hud")
	gm.ui.continue_card.show_offer(600, 12345, "Робот застрял")
	await _visit("continue_offer")
	gm.ui.continue_card._open_confirm()
	await _visit("continue_confirm")
	gm.ui.continue_card.visible = false
	gm.go_menu()
	await frames(6)
	gm.profile.tutorial = {"handled": false, "completed": false}
	gm.begin_tutorial(&"campaign")
	await frames(4)
	if gm.ui.awareness.visible:
		await _visit("tutorial_card")
		gm.ui.awareness.confirm.pressed.emit()
	await frames(40)
	await _visit("tutorial_flick")
	var ov := gm.ui.tutorial_overlay
	for s in [1, 2, 4, 5]:
		ov.show_step(s, true)
		await _visit("tutorial_gate_%d" % s)
	ov.skip.pressed.emit()
	await _visit("tutorial_skip_confirm")
	ov.confirm_no.pressed.emit()
	await frames(4)


# ---------------- language switch (runs across scene reloads) ----------------

func _c(label: String, ok: bool, details := "") -> void:
	_sp += int(ok); _sf += int(not ok)
	print("AT|test loc_%s %s %s" % [label, "PASS" if ok else "FAIL", details])


func _pick(code: String) -> void:
	gm.ui.open_language_picker()
	await frames(3)
	for b in gm.ui._language_options:
		if b.get_meta("language") == code:
			b.pressed.emit()
			return


func switch() -> void:
	await frames(10)
	match GameManager.language_reloads:
		0:
			for f in DirAccess.get_files_at(PROFILES):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILES + f))
			_c("switch_starts_russian", L.locale() == "ru" and gm.settings.language() == L.AUTO, L.locale())
			gm.activate_slot(1)
			gm.profile.coins = 777
			gm.profile.save()
			await frames(4)
			gm.ui.open_settings()
			await frames(4)
			print("AT|loc_switch choosing Deutsch")
			await _pick("de")
			await frames(100000)   # the scene reload frees this node; the next phase starts in the new scene
		1:
			var sf := FileAccess.get_file_as_string(gm.settings.path)
			var pf := FileAccess.get_file_as_string(gm.profiles.profile_path(1))
			_c("switch_applied_after_reload", L.locale() == "de" and gm.ui.language_button.text == "Deutsch" and gm.ui.is_settings_open(),
				"locale %s, button '%s', settings open %s" % [L.locale(), gm.ui.language_button.text, gm.ui.is_settings_open()])
			_c("switch_same_player_resumed", gm.active_slot == 1 and gm.profile.coins == 777 and not gm.ui.is_profiles_open(), "slot %d coins %d" % [gm.active_slot, gm.profile.coins])
			_c("switch_ui_rebuilt_in_new_language", gm.ui.restart_button.text == "↻ NOCHMAL" and gm.ui.continue_card.title.text == "LAUF FORTSETZEN?",
				"'%s' / '%s'" % [gm.ui.restart_button.text, gm.ui.continue_card.title.text])
			_c("switch_saved_app_global_not_in_profile", sf.contains("\"language\": \"de\"") and not pf.contains("language"), "")
			gm.ui.close_settings()
			gm.activate_slot(2)
			await frames(4)
			_c("switch_other_player_same_language", L.locale() == "de" and gm.active_slot == 2, L.locale())
			gm.ui.open_settings()
			await frames(4)
			await _pick(L.AUTO)
			await frames(100000)
		2:
			_c("switch_back_to_auto", gm.settings.language() == L.AUTO and L.locale() == L.resolve(L.AUTO) and gm.active_slot == 2 and gm.ui.is_settings_open(),
				"auto -> %s, slot %d" % [L.locale(), gm.active_slot])
			_c("switch_reloads_counted", GameManager.language_reloads == 2, str(GameManager.language_reloads))
			print("AT|tests passed=%d failed=%d" % [_sp, _sf])
			at.set("scenario_running", false)
