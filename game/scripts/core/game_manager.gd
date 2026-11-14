class_name GameManager
extends Node2D
## Owns the attempt loop: MENU -> INTRO (hand flick) -> RUN -> ROCKET -> [WAIT] -> RESULT -> instant RETRY.
## Two modes: FREE RUN (endless, distance coins, personal record) and CAMPAIGN (race vs. AI shadow opponents on the
## same track; RaceManager + EnemyAI; rewards, unlocks, hidden adaptive difficulty).
## The world (terrain, background) is built once; retry only respawns the dynamic objects.
## Each finished attempt is recorded exactly once into the local StatsStore (user://stats.json).

signal run_started
signal run_finished(distance_m: float)

enum State { MENU, INTRO, RUN, ROCKET, RESULT, WAIT, OFFER }

## Shared base tuning (the original Samurai physics). Every robot = RobotDefinition multipliers on copies of these.
@export var robot_config: RobotConfig = preload("res://config/robot_samurai.tres")
@export var contact_config: ContactConfig = preload("res://config/contact_default.tres")
@export var damage_config: DamageConfig = preload("res://config/damage_default.tres")
@export var rocket_config: RocketConfig = preload("res://config/rocket_default.tres")
@export var level_config: LevelConfig = preload("res://config/level_01.tres")
@export var spin_config: SpinChargeConfig = preload("res://config/spin_charge_default.tres")
## Robot launch: speed and direction (degrees above horizontal, + = upwards) at the flick.
## launch_speed is the 100% reference (v0.8 value); the player setting "flick" scales it (default 110%).
@export var launch_speed := 1650.0
@export var launch_angle := 14.0
## Attempt ends if the robot (not yet a rocket) stays slower than this for stuck_time.
@export var stuck_speed := 55.0
@export var stuck_time := 2.5
@export var no_progress_time := 7.0
## Instant in-run restart button ("ЗАНОВО"). A future competitive mode (3 attempts, best counts) sets this
## to false: the button is hidden and restart_attempt() refuses.
@export var allow_instant_restart := true
## Ignore restart requests closer together than this (double taps / touch + emulated mouse).
@export var restart_debounce_ms := 250
## Economy / AI / adaptive tuning (data).
@export var economy: EconomyConfig = preload("res://config/economy_default.tres")
@export var ai_config: AIConfig = preload("res://config/ai_default.tres")
@export var adaptive_config: AdaptiveConfig = preload("res://config/adaptive_default.tres")
@export var campaign_path := "res://config/campaign/main.json"
## Time scale while the player waits for the opponents to finish (button: x3).
@export var wait_time_scale := 2.0   # v36: integer fast-forward factor (see set_sim_speed)

const STATS_PATH := "user://stats.json"
## Debug harness default: tests never touch the player's real statistics.
const TEST_STATS_PATH := "user://test/autotest_stats.json"
const SETTINGS_PATH := "user://settings.json"
const TEST_SETTINGS_PATH := "user://test/autotest_settings.json"
const PROFILE_PATH := "user://profile.json"
const TEST_PROFILE_PATH := "user://test/autotest_profile.json"

var tutorial: TutorialDirector
## v33: the launch flick really happened (state -> RUN), with the locked flick-bar tier (tutorial + tests listen).
signal flicked(tier: String, multiplier: float)
var tutorial_pending_destination := &"free"

var state := State.MENU
var input: InputRouter
var terrain: TerrainBuilder
var haptics: HapticFeedback
var fx: Fx
var hand: LaunchHand
var camera: CameraController
var ui: UIController
var background: Background
var dynamic: Node2D
var robot: RobotController
var rocket: RocketHead
var best_m := 0.0
var distance_m := 0.0
var attempts := 0
var robot_start := Vector2.ZERO
var _stuck := 0.0
var _max_x := 0.0
## v36 stuck detector (MotionWatch): backward travel is never 'stuck'.
var _watch := MotionWatch.new()
var _end_reason := ""
var stats: StatsStore
var audio: GameAudio
## v36 screen-space anomaly feedback (lightning / radiation noise) of the player's own anomaly hits.
var anomaly_flash: AnomalyFlash
var settings: SettingsStore
var _last_restart_ms := -100000
var _clock_ms := 0.0   # game-time clock for the restart debounce
## Seed of the current track. A new one every run (same seed = same track: future ghost races).
var track_seed := 0
var _seed_rng := RandomNumberGenerator.new()
var attempt: AttemptStats
var last_result := {}
var _attempt_saved := true
var _coins_earned := 0
var _cam_min_zoom := 0.34
var catalog: RobotCatalog
var profile: ProfileStore
## v31: the three save slots (null in the single-file debug harness) and the active one (0 = none chosen yet).
var profiles: ProfileManager
var active_slot := 0
## Definition of the robot of the current / next attempt.
var robot_def: RobotDefinition
var skins: SkinCatalog
## &"free" or &"campaign"
var mode := &"free"
var campaign: CampaignData
var node_id := ""
var race: RaceManager
var adaptive: AdaptiveDifficulty
var campaign_result := {}
## Distance of the player when their attempt ended (campaign: opponents may still be running).
var player_final_m := 0.0
## v32: this campaign attempt set a new global (profile) distance record.
var campaign_record := false
## v32 future online safety: a competitive mode ignores the artifact bonus and never offers a paid continue
## (the player's equipped preference is kept untouched). Always false in this release.
var competitive_mode := false
## v32 paid continue: offered at most once per attempt (only when affordable); _continue_used = it was bought.
var _continue_offered := false
var _continue_used := false
# A presentation can outlive its physics objects until queue_free/deferred callbacks flush.
# Eligibility and purchase belong to this live attempt, never just to a visible Control.
var achievements: AchievementSystem
var _run_epoch := 0
var _attempt_open := false
var _offer_epoch := -1
var _offer_attempt: AttemptStats
var _offer_accept: Callable
var _offer_decline: Callable
var _launch_trace_t := -1.0
## v32 secret artifact of this level (only on SecretArtifact.NODE_ID while undiscovered by the active profile).
var artifact_node: SecretArtifact
var _artifact_pending := false
## Players: always on. Debug harness: off unless --continue_offers or a test enables it (older suites play runs to
## the end and must never meet a paused offer).
var continue_offers_enabled := true
## v33: a NEW profile starts the tutorial right away. Debug harness: only with --auto_tutorial (older suites create
## slots and expect the menu).
var auto_tutorial_new_profile := true
var _offer_reason := ""
var _offer_prev_state := State.RUN
## Recent safe ground points of this attempt (x, newest last) for the continue respawn.
var _safe_xs: Array[float] = []
var _safe_clock := 0.0
var _debug_t := 0.0
var star_tracker: StarTracker
var stars_before: Array = []
var stars_new: Array = []
var star_coins := 0
var _star_node_id := ""
var _star_retry_t := 0.0
var _star_free_set_id := 0
var flick_tier := "NORMAL"
var flick_multiplier := 1.0
var require_flick_tap_in_autotest := false
## v30 biomes: the biome of the current / last run (one biome per level, never changed inside a run).
var biome: BiomeDef = BiomeCatalog.get_def(BiomeCatalog.GREEN)
var hazards: BiomeHazards
var biome_intros_shown := 0
## Test / QA hook: free runs in this biome ("" = Green Hills).
var debug_biome := ""
var debug_track_seed := -1          # tests only: force the next tracks' seed (-1 = normal random seed)
var _intro_hand_speed := 1.6


func _ready() -> void:
	# v34: the language is applied before anything builds text (fonts, UI, track signs)
	_load_settings_store()
	_apply_language()
	input = InputRouter.new()
	input.name = "InputRouter"
	add_child(input)
	background = Background.new()
	add_child(background)
	terrain = TerrainBuilder.new()
	terrain.name = "Terrain"
	add_child(terrain)
	_seed_rng.randomize()
	track_seed = _pick_seed()
	BiomeRuntime.reset(get_world_2d().space, terrain)
	terrain.build(level_config, track_seed)
	hazards = BiomeHazards.new()
	hazards.name = "BiomeHazards"
	hazards.z_index = 9
	add_child(hazards)
	hazards.bodies_provider = _active_bodies
	hazards.teleported.connect(_on_teleported)
	hazards.anomaly_hit.connect(_on_anomaly_hit)
	hand = LaunchHand.new()
	hand.name = "LaunchHand"
	add_child(hand)
	dynamic = Node2D.new()
	dynamic.name = "Dynamic"
	dynamic.z_index = 10
	add_child(dynamic)
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	camera = CameraController.new()
	camera.name = "Camera"
	camera.terrain = terrain
	add_child(camera)
	camera.make_current()
	background.camera = camera
	fx.shake_requested.connect(camera.shake)
	haptics = HapticFeedback.new()
	add_child(haptics)
	fx.physical_feedback.connect(func(intensity: float) -> void: haptics.submit(intensity))
	audio = GameAudio.new()
	audio.name = "GameAudio"
	add_child(audio)
	audio.listener = camera
	anomaly_flash = AnomalyFlash.new()
	add_child(anomaly_flash)
	ui = UIController.new()
	add_child(ui)
	audio.bind_ui(ui)
	ui.robot_select._left.set_meta("audio_event","browse")
	ui.robot_select._right.set_meta("audio_event","browse")
	ui.robot_select._action.set_meta("audio_event", "") # real success routed by selection/purchase
	input.ui_blocker = ui.blocks_point
	input.hold_changed.connect(ui.set_holding)
	input.tapped.connect(_on_tap)
	ui.play_pressed.connect(func() -> void: request_mode(&"free"))
	ui.campaign_pressed.connect(func() -> void: request_mode(&"campaign"))
	ui.campaign_map.start_requested.connect(_on_node_start)
	ui.campaign_map.back_requested.connect(func() -> void: go_menu())
	ui.campaign_result.retry_requested.connect(start_run)
	ui.campaign_result.map_requested.connect(open_campaign_map)
	ui.campaign_result.next_requested.connect(_on_next_round)
	ui.race_hud.speed_up_requested.connect(func() -> void: set_sim_speed(SPEED_UP_FACTOR))
	ui.robot_select.skin_equip_requested.connect(func(rid: String, sid: String, on_mk2: bool) -> void:
		profile.equip_skin(rid, sid, on_mk2)
		_refresh_menu_robot())
	ui.robot_select.robot_focused.connect(func(rid: String) -> void:
		if profile and profile.is_owned(rid):
			profile.select(rid))
	ui.debug_toggled.connect(func(on: bool) -> void: _save_debug(on))
	ui.robot_select.play_requested.connect(_on_select_play)
	ui.robot_select.buy_requested.connect(_on_buy)
	ui.robot_select.back_requested.connect(_close_select)
	ui.retry_pressed.connect(start_run)
	ui.menu_pressed.connect(go_menu)
	ui.menu.visibility_changed.connect(_sync_menu_world_actors)
	hand.flicked.connect(_on_flick)
	_cam_min_zoom = camera.min_zoom
	# per-session copy: player settings change the spin speeds without touching the .tres on disk
	robot_config = robot_config.duplicate()
	contact_config = contact_config.duplicate(true)
	_open_settings()
	catalog = RobotCatalog.new()
	skins = SkinCatalog.new(catalog)
	campaign = CampaignData.load_file(campaign_path)
	var proot := _profiles_root()
	if proot != "":
		# v31: three player profiles. The legacy global save is imported once into PLAYER 1; until the player picks
		# a slot on the profile screen an in-memory placeholder (never written) stands in.
		profiles = ProfileManager.new(proot)
		profiles.migrate_legacy()
		_use_placeholder_profile()
	else:
		# debug harness without --profiles_root: the historical single-file stores (isolated test paths)
		_open_stats()
		_open_profile()
		profile.ensure_campaign_start(campaign.start_id)
		adaptive = AdaptiveDifficulty.new(adaptive_config, profile.adaptive)
	race = RaceManager.new()
	race.name = "RaceManager"
	race.gm = self
	add_child(race)
	ui.robot_select.skins = skins
	ui.setup_menu_jumper(catalog, robot_config)
	_bind_profile_ui()
	ui.robot_select.skin_hint = _skin_hint
	ui.robot_select.mk2_state = mk2_state
	ui.robot_select.mk2_buy_requested.connect(_on_buy_mk2)
	ui.robot_select.mk2_variant_requested.connect(_on_mk2_variant)
	ui.profile_chip_pressed.connect(open_profiles)
	ui.profiles_view.slot_chosen.connect(func(slot: int) -> void: activate_slot(slot))
	ui.profiles_view.delete_confirmed.connect(func(slot: int) -> void: delete_slot(slot))
	ui.profiles_view.back_requested.connect(close_profiles)
	ui.artifact_pressed.connect(func() -> void: toggle_artifact())
	ui.set_debug(_load_debug())
	ui.restart_enabled = allow_instant_restart
	ui.restart_pressed.connect(restart_attempt)
	ui.abandon_pressed.connect(abandon_run)
	ui.setting_changed.connect(set_setting)
	ui.settings_reset.connect(reset_settings)
	ui.language_chosen.connect(func(code: String) -> void: set_language(code))
	ui.sfx_volume_changed.connect(func(value: float) -> void:
		settings.unrelated["sfx_volume"]=clampf(value,0,100)
		settings.save()
		audio.set_volume(value))
	ui.biome_intro.instant = _is_autotest() and not Array(OS.get_cmdline_user_args()).has("--biome_intro")
	continue_offers_enabled = not _is_autotest() or Array(OS.get_cmdline_user_args()).has("--continue_offers")
	auto_tutorial_new_profile = not _is_autotest() or Array(OS.get_cmdline_user_args()).has("--auto_tutorial")
	ui.biome_intro.finished.connect(_on_biome_intro_done)
	hazards.fx = fx
	ui.awareness.confirmed.connect(func(kind: String) -> void:
		if kind=="campaign":
			_start_after_card(1.6)
		else:
			_start_tutorial(tutorial_pending_destination))
	ui.awareness.skipped.connect(func(kind: String) -> void:
		if kind=="campaign":
			abandon_run()
		else:
			profile.tutorial.handled=true
			profile.save()
			if tutorial_pending_destination==&"settings": ui.open_settings()
			else: request_mode(tutorial_pending_destination))
	ui.campaign_result.ceremony.star_shown.connect(func(_index: int) -> void: haptics.submit(0.9 if ui.campaign_result.ceremony.all_complete and ui.campaign_result.ceremony.animated.size()==ui.campaign_result.ceremony.fresh.size() else 0.65))
	ui.tutorial_pressed.connect(func() -> void: begin_tutorial(&"settings"))
	ui.tutorial_overlay=TutorialOverlay.new()
	ui.tutorial_overlay.gm=self
	ui.add_child(ui.tutorial_overlay)
	_spawn_robot()
	_frame_intro()
	ui.show_menu(best_m, stats.data)
	_refresh_menu_robot()
	_sync_menu_world_actors()
	ui.set_coins(profile.coins)
	ui.set_stars(int(profile.star_wallet.available))
	if profiles != null:
		if _resume_slot > 0 and profiles.exists(_resume_slot):
			activate_slot(_resume_slot)   # language reload: same player, back on Settings
		else:
			open_profiles()   # every launch starts on the profile screen (no silent auto-login)
	_resume_slot = 0
	if _resume_settings:
		_resume_settings = false
		ui.open_settings()
	achievements = AchievementSystem.new()
	achievements.name = "Achievements"
	add_child(achievements)
	ui.achievement_system = achievements
	achievements.setup(self)
	achievements.unlocked.connect(ui.achievement_toast.enqueue)
	achievements.changed.connect(func() -> void:
		if ui.achievements_view.visible: ui.achievements_view.refresh())
	if _is_autotest():
		var at: Node = load("res://scripts/debug/autotest.gd").new()
		at.set("gm", self)
		add_child(at)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("retry") and (state == State.RESULT or state == State.RUN or state == State.ROCKET):
		restart_attempt()


## Called instead of get_tree().quit() by Android Back in the menu (tests replace it).
var quit_handler: Callable = func() -> void: get_tree().quit()
const BACK_DEBOUNCE_MS := 350
var _last_back_ms := -100000


## Android Back: close the statistics panel, leave a run/result to the menu, quit only from the menu.
## App sent to background (Android onPause): freeze the attempt so nothing happens unseen; resume on return.
func _notification(what: int) -> void:
	if ui == null:
		return
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# v36.9 device fix (Galaxy S23, Android 16): ONE Back press can arrive as two go-back requests; the first
			# closed the campaign map, the second then quit from the menu. One physical press = one Back action.
			var now_ms := Time.get_ticks_msec()
			if OS.is_debug_build():
				print("BACK|%d|%d" % [now_ms, now_ms - _last_back_ms])   # adb logcat evidence on test builds
			if now_ms - _last_back_ms < BACK_DEBOUNCE_MS:
				return
			_last_back_ms = now_ms
			if ui.achievements_view and ui.achievements_view.visible:
				ui.achievements_view.visible = false
				return
			if ui.is_profiles_open():
				if ui.profiles_view.confirm_open():
					ui.profiles_view.cancel_delete()
				elif active_slot > 0:
					close_profiles()
				else:
					quit_handler.call()
			elif state == State.OFFER:
				if ui.continue_card.stage == "confirm":
					ui.continue_card._back_to_offer()   # Back cancels the spend, the offer stays
				else:
					decline_continue()
			elif ui.awareness.visible:
				ui.awareness.skip.pressed.emit()
			elif ui.is_robot_select_open():
				_close_select()
			elif ui.is_campaign_map_open():
				go_menu()
			elif ui.is_stats_open():
				ui.close_stats()
			elif ui.is_settings_open() and ui.language_picker.visible:
				ui.language_picker.visible = false
			elif ui.is_settings_open():
				ui.close_settings()
			elif state != State.MENU:
				abandon_run()
			else:
				quit_handler.call()
		NOTIFICATION_APPLICATION_PAUSED:
			input.reset()
			haptics.reset_pending()
			if state == State.INTRO or state == State.RUN or state == State.ROCKET or state == State.WAIT:
				get_tree().paused = true
		NOTIFICATION_APPLICATION_RESUMED:
			input.reset()
			get_tree().paused = state == State.OFFER   # an open continue offer stays paused


# ---------------- flow ----------------

## Abandon never calls completion/finalize: immediate earned Stars alone are saved by _clear_dynamic.
func abandon_run() -> void:
	if tutorial!=null:
		finish_tutorial(false,false)
		return
	var campaign_destination := mode == &"campaign"
	go_menu()
	if campaign_destination:
		open_campaign_map()


func go_menu() -> void:
	if tutorial!=null:
		finish_tutorial(false,false)
		return
	_invalidate_attempt()
	_end_rocket_skip()
	ui.show_rocket_hint(false)
	get_tree().paused = false
	set_sim_speed(1)
	state = State.MENU
	attempt = null
	_attempt_saved = true
	_end_reason = ""
	_coins_earned = 0
	race.clear()
	_restore_baseline()
	_spawn_robot()
	_frame_intro()
	ui.show_menu(best_m, stats.data)
	_refresh_menu_robot()
	_sync_menu_world_actors()
	ui.set_coins(profile.coins)
	ui.set_stars(int(profile.star_wallet.available))


func _refresh_menu_robot() -> void:
	if ui == null or catalog == null or profile == null:
		return
	var sel_def := _pick_robot()
	if sel_def == null:
		return
	var sk: SkinDefinition = skins.get_by_id(profile.equipped_skin(sel_def.id, player_mk2(sel_def))) if skins else null
	ui.set_menu_robot(sel_def, robot_config, sk, player_mk2(sel_def))


func _sync_menu_world_actors() -> void:
	var hide_world := (state == State.MENU and ui != null and ui.menu != null and ui.menu.visible)
	if is_instance_valid(robot):
		robot.visible = not hide_world
	if is_instance_valid(hand) and state == State.MENU:
		hand.visible = not hide_world


# ---------------- robots / shop ----------------

func _close_select() -> void:
	var cur := ui.robot_select.current()
	if cur != null and profile != null and profile.is_owned(cur.id):
		profile.select(cur.id)
		# v35: leaving the shop keeps the shown variant when it is playable (BASE always, MK2 only if owned)
		if cur.has_mk2() and (not ui.robot_select.viewing_mk2 or profile.owns_mk2(cur.id)):
			profile.set_mk2_selected(cur.id, ui.robot_select.viewing_mk2)
		_refresh_menu_robot()
	ui.close_robot_select()
	if mode == &"campaign" and state == State.MENU:
		open_campaign_map()
		return
	if state == State.MENU:
		# the menu robot shows the (possibly new) selection
		_spawn_robot()
		_frame_intro()
		ui.show_menu(best_m, stats.data)
		_refresh_menu_robot()
		_sync_menu_world_actors()
		ui.set_coins(profile.coins)
		ui.set_stars(int(profile.star_wallet.available))

func open_robot_select() -> void:
	ui.menu.visible = false
	ui.robot_select.open(catalog, robot_config, profile.selected, profile.owned, profile.coins)


func _on_select_play(id: String) -> void:
	if not profile.select(id):
		return
	audio.common("confirm")
	robot_def = catalog.get_by_id(id)
	start_run()


## v35 MK2 ------------------------------------------------------------------------------------------------------
## Plays as MK2? The profile's choice; the debug harness can force it with --mk2 (balance A/B tests).
func player_mk2(def: RobotDefinition) -> bool:
	if def == null or not def.has_mk2():
		return false
	if _is_autotest() and Array(OS.get_cmdline_user_args()).has("--mk2"):
		return true
	return profile != null and profile.mk2_active(def.id)


## For the robot select view.
func mk2_state(def: RobotDefinition) -> Dictionary:
	var boss := ""
	var node: Dictionary = campaign.node(def.mk2_boss_node) if campaign and def.mk2_boss_node != "" else {}
	if not node.is_empty() and not (node.get("enemies", []) as Array).is_empty():
		boss = L.data(String(node.enemies[0].get("name", "")))
	return {"eligible": profile.mk2_eligible(def), "owned": profile.owns_mk2(def.id), "active": profile.mk2_active(def.id), "boss": boss}


func _on_buy_mk2(id: String) -> void:
	var def := catalog.get_by_id(id)
	var res := profile.buy_mk2(def)
	var note := ""
	match res:
		"ok":
			note = L.t("MK2_BOUGHT")
			audio.common("purchase")
			profile.select(id)
			_refresh_menu_robot()
		"coins":
			note = L.t("SHOP_NO_COINS")
	ui.robot_select.refresh_profile(profile.owned, profile.coins, note)
	ui.set_coins(profile.coins)


func _on_mk2_variant(id: String, on: bool) -> void:
	if profile.set_mk2_selected(id, on):
		_refresh_menu_robot()


func _on_buy(id: String) -> void:
	var res := profile.buy(catalog.get_by_id(id))
	var note: String = {"ok": L.t("SHOP_BOUGHT"), "coins": L.t("SHOP_NO_COINS"), "owned": "", "unknown": ""}[res]
	if res == "ok":
		audio.common("purchase")
		profile.select(id)
		_refresh_menu_robot()
	ui.robot_select.refresh_profile(profile.owned, profile.coins, note)
	ui.set_coins(profile.coins)
	ui.set_stars(int(profile.star_wallet.available))


## Robot for the next spawn: --robot=<id> (tests) or the player's selection.
func _pick_robot() -> RobotDefinition:
	if mode==&"tutorial":
		return catalog.get_by_id("samurai")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--robot="):
			var d := catalog.get_by_id(a.substr(8))
			if d:
				return d
	var sel := catalog.get_by_id(profile.selected)
	return sel if sel else catalog.robots[0]


# ---------------- campaign ----------------

func open_campaign_map() -> void:
	_invalidate_attempt()
	get_tree().paused = false
	set_sim_speed(1)
	mode = &"campaign"
	if state != State.MENU:
		state = State.MENU
		race.clear()
		_restore_baseline()
		_spawn_robot()
		_frame_intro()
	ui.show_menu(best_m, stats.data)
	ui.menu.visible = false
	ui.campaign_map.open(campaign, profile, catalog, skins)


func _on_node_start(id: String) -> void:
	if not (profile.is_unlocked(id) and campaign.is_playable(id)):
		return
	node_id = id
	mode = &"campaign"
	ui.campaign_map.visible = false
	ui.robot_select.open(catalog, robot_config, profile.selected, profile.owned, profile.coins)


func _on_next_round() -> void:
	var nx := campaign.main_next(node_id)
	if nx != "" and profile.is_unlocked(nx):
		node_id = nx
		start_run()


func _skin_hint(skin_id: String) -> String:
	for id in campaign.order:
		if String(campaign.node(id).get("reward_skin", "")) == skin_id:
			return L.t("SEL_SKIN_FIRST_WIN") % L.data(String(campaign.node(id).get("title", id)))
	return L.t("SEL_LOCKED")


## Effective AI skill modifier for a node (the hidden adaptive state; bounded).
func adaptive_modifier() -> float:
	return adaptive.modifier()


## Instant restart (HUD button "ЗАНОВО", R key, Retry): abandons the current attempt WITHOUT recording it and
## starts a fresh one through the normal start_run() path. Debounced; refused in the menu or when disabled.
func restart_attempt() -> bool:
	if tutorial!=null:
		return false # Training has checkpoint recovery and a visible Skip/Menu, no normal attempt restart.
	if not allow_instant_restart or state == State.MENU:
		return false
	var now := int(_clock_ms)
	if now - _last_restart_ms < restart_debounce_ms:
		return false
	_last_restart_ms = now
	start_run()
	return true


func start_run() -> void:
	_invalidate_attempt()
	get_tree().paused = false
	_end_rocket_skip()
	ui.show_rocket_hint(false)
	attempts += 1
	# every run gets a new track (unless a seed is forced for tests / future seeded races)
	set_sim_speed(1)
	track_seed = _pick_seed()
	# v30: the level's ONE biome, applied before the track is built (Green Hills = exact baseline)
	_apply_biome(_select_biome())
	terrain.reset(track_seed)
	hazards.reset(biome, terrain, track_seed)
	_spawn_robot()
	_star_node_id = node_id
	stars_before = profile.stars_of(node_id)
	stars_new = []
	campaign_record = false
	_continue_offered = false
	_continue_used = false
	artifact_node = null
	_artifact_pending = mode == &"campaign" and node_id == SecretArtifact.NODE_ID and not bool(profile.artifact.discovered)
	_safe_xs.clear()
	_safe_clock = 0.0
	ui.continue_card.cancel()
	star_coins = 0
	_star_retry_t = 0.0
	ui.star_hud.visible = mode in [&"campaign", &"free"]
	if mode == &"campaign":
		star_tracker = StarTracker.new(campaign.node(node_id).get("stars", []), stars_before)
		star_tracker.attach(robot, level_config.px_per_meter)
		star_tracker.star_completed.connect(_earn_star)
		ui.star_hud.setup(star_tracker)
	elif mode == &"free":
		var challenge_set := profile.prepare_free_set(robot_def.id, FreeChallenges.config())
		if not challenge_set.is_empty():
			_star_free_set_id = int(challenge_set.id)
			star_tracker = StarTracker.new(challenge_set.challenges, challenge_set.completed)
			star_tracker.attach(robot, level_config.px_per_meter)
			star_tracker.star_completed.connect(_earn_star)
			ui.star_hud.setup(star_tracker, true)
		else:
			ui.star_hud.visible = false
			push_warning("Free challenges unavailable: profile save/receipt validation failed")
	race.clear()
	if mode == &"campaign" and campaign.nodes.has(node_id):
		# opponents: same seed / terrain, same flick, AI quality = round skill + hidden adaptive modifier
		race.spawn(campaign.node(node_id).enemies, adaptive_modifier(), track_seed, ai_config)
	# fresh per-attempt counters (Retry never inherits anything from the previous attempt)
	attempt = AttemptStats.new("%d-%d" % [int(Time.get_unix_time_from_system() * 1000.0), attempts], spin_config.max_charge)
	_attempt_open = true
	attempt.attach(robot)
	attempt.seed = track_seed
	_attempt_saved = false
	_frame_intro()
	ui.show_hud()
	ui.set_health(robot.damage.max_health, robot.damage.max_health, true)
	ui.race_hud.visible = mode == &"campaign"
	if mode == &"campaign":
		ui.race_hud.setup(race.competitors.map(func(c: RaceManager.Competitor) -> String: return c.name),
			race.competitors.map(func(c: RaceManager.Competitor) -> Color: return c.color))
	ui.fade_hint(3.5)
	state = State.INTRO
	flick_tier = "NORMAL"
	flick_multiplier = 1.0
	if mode==&"campaign" or needs_biome_intro():
		# nothing may move or count behind a card (awareness / biome title); a restart stops the old flick
		hand.playing=false
		hand.visible=false
		if ui.flick_bar:
			ui.flick_bar.hide_immediate()
	if mode==&"campaign":
		ui.awareness.show_campaign(int(campaign.node(node_id).round),star_tracker.challenges,stars_before)
	else:
		_start_after_card(1.0 if attempts == 1 else 1.6)
	run_started.emit()


# ---------------- biomes ----------------

## Biome of the level about to start: the campaign node's fixed biome; free runs are Green Hills
## (debug / QA: --biome=<id>).
func _select_biome() -> BiomeDef:
	if mode == &"campaign" and campaign.nodes.has(node_id):
		return BiomeCatalog.get_def(String(campaign.node(node_id).get("biome", BiomeCatalog.GREEN)))
	if mode == &"free":
		if debug_biome != "":
			return BiomeCatalog.get_def(debug_biome)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--biome="):
				return BiomeCatalog.get_def(a.substr(8))
	return BiomeCatalog.get_def(BiomeCatalog.GREEN)


func _apply_biome(def: BiomeDef) -> void:
	biome = def
	terrain.set_biome(def)
	BiomeRuntime.activate(def, get_world_2d().space, terrain)


## Back to the exact Green Hills baseline (menu / map / tutorial): no biome state may leak anywhere.
func _restore_baseline() -> void:
	hazards.clear()
	if biome.id != BiomeCatalog.GREEN or BiomeRuntime.id() != BiomeCatalog.GREEN:
		_apply_biome(BiomeCatalog.get_def(BiomeCatalog.GREEN))
		terrain.reset(track_seed)


## Green Hills title only before campaign round 1; every special biome every time its level starts.
func needs_biome_intro() -> bool:
	if biome.special:
		return true
	return mode == &"campaign" and campaign.nodes.has(node_id) and int(campaign.node(node_id).get("round", 0)) == 1


func _start_after_card(hand_speed: float) -> void:
	if state != State.INTRO or not _attempt_open:
		return
	if needs_biome_intro() and tutorial == null:
		_intro_hand_speed = hand_speed
		biome_intros_shown += 1
		ui.biome_intro.show_biome(biome)
	else:
		_begin_flick_intro(hand_speed)


func _on_biome_intro_done(_skipped: bool) -> void:
	input.reset()               # the skip tap never reaches gameplay
	if state == State.INTRO:
		_begin_flick_intro(_intro_hand_speed)


## Bodies the biome hazards act on: the player's active piece and every running opponent piece.
func _active_bodies() -> Array:
	var out := []
	if state == State.ROCKET and is_instance_valid(rocket):
		out.append(rocket)
	elif state == State.RUN and is_instance_valid(robot) and robot.launched:
		out.append(robot)
	if mode == &"campaign":
		for c in race.competitors:
			if not c.finished:
				var p := c.piece()
				if p is RigidBody2D:
					out.append(p)
	return out


## v36 Exclusion-Zone anomaly feedback, PLAYER piece only (robot or its jet head; opponents never shake the screen).
## Vibration / camera shake / sound go through the normal channels, so the vibration, shake and volume settings apply.
##   electric: very strong short pulse, strong shake, discharge sound, big lightning arcs (peak + quick decay)
##   radiation: strong pulse + shake, Geiger burst, brief whole-screen radiation noise
##   gravity: noticeably weaker pulse + shake (the throw itself is the message)
const ANOMALY_FEEDBACK := {"electric": [1.0, 62.0, 0.32], "radiation": [0.85, 46.0, 0.38], "gravity": [0.45, 20.0, 0.22]}


func _on_anomaly_hit(body: RigidBody2D, kind: String, point: Vector2) -> void:
	var mine := (state == State.RUN and body == robot) or (state == State.ROCKET and body == rocket)
	if not mine or not ANOMALY_FEEDBACK.has(kind):
		return
	var f: Array = ANOMALY_FEEDBACK[kind]
	haptics.submit(float(f[0]))
	camera.shake(float(f[1]), float(f[2]))
	match kind:
		"electric":
			audio.play("common/anomaly_electric", 1.0, "anomaly_electric", 0.25, "SFX")
			anomaly_flash.electric(get_viewport().get_canvas_transform() * point)
		"radiation":
			audio.play("common/anomaly_geiger", 1.0, "anomaly_geiger", 0.4, "SFX")
			anomaly_flash.radiation()


func _on_teleported(body: RigidBody2D) -> void:
	if body != null and (body == robot or body == rocket):
		# v39: subtle warp cue for the player's own piece only (audio only; teleport itself is unchanged)
		audio.play("v39/portal_warp", 1.0, "portal_warp", 0.3, "Robot", body.global_position, 0.8)
	if star_tracker and (body == robot or body == rocket):
		star_tracker.on_teleport()


func _begin_flick_intro(hand_speed := 1.6) -> void:
	if state != State.INTRO or (tutorial == null and not _attempt_open):
		return
	var wait_tap := (not _is_autotest()) or require_flick_tap_in_autotest
	hand.hold_at_tension = wait_tap and tutorial == null
	if tutorial == null and ui.flick_bar:
		ui.flick_bar.begin(wait_tap)
	elif ui.flick_bar:
		ui.flick_bar.hide_immediate()
	hand.play(hand_speed)


func lock_flick_tier(tier_name: String) -> Dictionary:
	var res := {"tier": tier_name, "multiplier": FlickPowerBar.multiplier_for_tier(tier_name), "ratio": FlickPowerBar.ratio_for_tier(tier_name)}
	if ui and ui.flick_bar:
		res = ui.flick_bar.lock_tier(tier_name)
	flick_tier = String(res.tier)
	flick_multiplier = float(res.multiplier)
	input.reset()
	if state == State.INTRO and hand:
		hand.release_flick()
	return res


func lock_flick_ratio(ratio: float) -> Dictionary:
	var res := {"tier": FlickPowerBar.tier_for_ratio(ratio), "multiplier": FlickPowerBar.multiplier_for_tier(FlickPowerBar.tier_for_ratio(ratio)), "ratio": clampf(ratio, 0.0, 1.0)}
	if ui and ui.flick_bar:
		res = ui.flick_bar.lock_at_ratio(ratio)
	flick_tier = String(res.tier)
	flick_multiplier = float(res.multiplier)
	input.reset()
	if state == State.INTRO and hand:
		hand.release_flick()
	return res


## v34 rocket-head skip. The jet head is a real rigid body (terrain bounces, slopes, biome hazards), so its ending
## is not predicted analytically: a skip FAST-FORWARDS the authoritative simulation. physics_ticks_per_second and
## time_scale are raised by the same factor, which keeps every physics step exactly 1/120 s (measured) - the
## same steps run, only more of them per rendered frame - so distance, reason, records, stars, rewards and race are
## those of the natural flight. Restored before the normal _finish path runs.
const ROCKET_SKIP_FACTOR := 16
const ROCKET_SKIP_MIN_T := 0.7
var rocket_skipping := false
var _skip_saved := 1

## v36 fast-forward invariance (fairness fix). Before v36 the post-death wait (x2) and the race speed-up button (x3)
## only raised Engine.time_scale - Godot then integrates each physics step with time_scale / 120 s, i.e. 2-3x longer
## steps (springs, contacts, CCD, damping, AI all behave differently: competitors travelled farther while the player
## waited). Every speed-up now uses the rocket-skip scheme: physics_ticks_per_second, time_scale and
## max_physics_steps_per_frame are raised by the SAME integer factor, so every step is still exactly 1/120 s of
## simulated time - the same steps run, only more of them per rendered frame.
const SPEED_UP_FACTOR := 3
static var sim_speed := 1


static func set_sim_speed(factor: int) -> void:
	factor = maxi(factor, 1)
	sim_speed = factor
	Engine.physics_ticks_per_second = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 120)) * factor
	Engine.max_physics_steps_per_frame = int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8)) * factor
	Engine.time_scale = float(factor)


func can_skip_rocket() -> bool:
	return state == State.ROCKET and is_instance_valid(rocket) and not rocket.done and not rocket_skipping \
		and rocket.time >= ROCKET_SKIP_MIN_T and tutorial == null


func skip_rocket() -> bool:
	if not can_skip_rocket():
		return false
	rocket_skipping = true
	_skip_saved = sim_speed
	set_sim_speed(_skip_saved * ROCKET_SKIP_FACTOR)
	ui.show_rocket_hint(false)
	return true


func _end_rocket_skip() -> void:
	if not rocket_skipping:
		return
	rocket_skipping = false
	set_sim_speed(_skip_saved)


func _on_tap() -> void:
	if state == State.ROCKET:
		skip_rocket()
		return
	# v33: the tutorial uses the real flick bar too (it teaches the actual start control)
	if state == State.INTRO and (ui.awareness == null or not ui.awareness.visible):
		if ui.flick_bar and ui.flick_bar.active and not ui.flick_bar.locked:
			var res := ui.flick_bar.lock_current()
			flick_tier = String(res.tier)
			flick_multiplier = float(res.multiplier)
			audio.common("confirm", clampf((flick_multiplier - 0.75) / 0.45, 0.25, 1.0))
		input.reset()
		hand.release_flick()
	elif state == State.INTRO:
		hand.rush()


func _on_flick(tip: Vector2) -> void:
	if state != State.INTRO or ui.awareness.visible or (tutorial == null and not _attempt_open):
		return
	if ui.flick_bar and ui.flick_bar.active:
		if not ui.flick_bar.locked:
			var res := ui.flick_bar.lock_tier("NORMAL")
			flick_tier = String(res.tier)
			flick_multiplier = float(res.multiplier)
		else:
			flick_tier = ui.flick_bar.locked_tier
			flick_multiplier = ui.flick_bar.locked_multiplier
		ui.flick_bar.fade_out()
	else:
		flick_tier = "NORMAL"
		flick_multiplier = 1.0
		if ui.flick_bar:
			ui.flick_bar.hide_immediate()
	if not _is_autotest() or require_flick_tap_in_autotest:
		input.reset()
	state = State.RUN
	ui.star_hud.compact = true
	ui.star_hud.collapse_free()
	var dir := Vector2.RIGHT.rotated(-deg_to_rad(launch_angle))
	var v0_base := dir * launch_speed * settings.get_value("flick") / 100.0
	var v0_player := v0_base * (flick_multiplier if tutorial == null else 1.0)
	if tutorial!=null:
		# Controlled teaching throw on the practice slope (scaled by the real flick tier the player locked).
		v0_base=Vector2(420,-950)
		v0_player=v0_base*flick_multiplier
	if star_tracker:
		star_tracker.on_flick(flick_tier, flick_multiplier)
		_save_completed_stars()
	robot.launch(v0_player, robot.config.clockwise_rotation_speed * TAU)
	_launch_trace_t = 0.0
	_trace_run("launch")
	race.launch(v0_base, robot.config.clockwise_rotation_speed * TAU)
	audio.common("go", clampf((flick_multiplier - 0.75) / 0.45, 0.25, 1.0))
	fx.flick_impact(tip)
	camera.follow(robot)
	if tutorial!=null:
		camera.focus_practice(robot)
	_stuck = 0.0
	flicked.emit(flick_tier, flick_multiplier)


## Campaign: everyone is done -> win / loss, rewards (first clear once, small decaying replay bonus), unlocks,
## hidden adaptive update (frontier rounds only - replays of cleared rounds never move it).
func _finish_campaign() -> void:
	_attempt_open = false
	_cancel_continue()
	set_sim_speed(1)
	state = State.RESULT
	ui.race_hud.show_waiting(false)
	var node := campaign.node(node_id)
	var best := race.best_distance()
	var won := player_final_m > best
	if star_tracker:
		star_tracker.on_race_result(won, player_final_m, best)
		_save_completed_stars()
		star_tracker.stop()
	var frontier := not profile.is_completed(node_id)
	var att := profile.count_attempt(node_id)
	var coins := 0
	var kind := ""
	var skin_name := ""
	if won:
		profile.complete(node_id, campaign.next_ids(node_id))
		if profile.claim_first_clear(node_id, int(node.reward_first)):
			coins = int(node.reward_first)
			kind = "first"
			var sid := String(node.get("reward_skin", ""))
			if sid != "" and profile.grant_skin(sid):
				var s := skins.get_by_id(sid)
				skin_name = s.display_name if s else sid
		elif not frontier:
			coins = economy.replay_reward(int(node.reward_first), profile.replay_wins(node_id))
			profile.add_replay_win(node_id, coins)
			kind = "replay"
	var mod_before := adaptive.modifier()
	if frontier:
		adaptive.record({"player_m": player_final_m, "best_enemy_m": best, "won": won, "attempts": att,
			"hp_ratio": robot.damage.health_ratio() if is_instance_valid(robot) else 0.0, "difficulty": node.difficulty})
		profile.adaptive = adaptive.state
	profile.save()
	var enemies := []
	for c in race.competitors:
		enemies.append({"name": c.name, "m": c.distance, "color": c.color, "robot": c.robot_id, "reason": c.reason,
			"skill": c.skill, "base_skill": c.base_skill})
	campaign_result = {"won": won, "node": node_id, "title": node.get("title", node_id), "player_m": player_final_m,
		"enemies": enemies, "best_enemy_m": best, "coins": coins, "coins_kind": kind, "skin_name": skin_name,
		"has_next": campaign.main_next(node_id) != "", "attempts": att, "frontier": frontier,
		"mod_before": mod_before, "mod_after": adaptive.modifier(),
		"stars_before": stars_before.duplicate(), "stars_new": stars_new.duplicate(), "star_coins": star_coins,
		"stars_available": int(profile.star_wallet.available), "stars_total": profile.total_stars(), "stars": node.get("stars", []),
		"flick_tier": flick_tier, "flick_multiplier": flick_multiplier, "record": campaign_record, "best_m": best_m}
	ui.set_coins(profile.coins)
	ui.set_stars(int(profile.star_wallet.available))
	audio.common("victory" if won else "defeat")
	if coins > 0: audio.common("coin")
	if skin_name != "": audio.common("unlock")
	ui.campaign_result.show_result(campaign_result)
	run_finished.emit(player_final_m)


func _finish(reason: String, source_epoch := -1) -> void:
	if source_epoch >= 0 and source_epoch != _run_epoch:
		return
	if tutorial!=null:
		tutorial.on_run_end()
		return
	# only a launched attempt can end (never record a menu / intro state, never twice)
	if not _attempt_open or (state != State.RUN and state != State.ROCKET):
		return
	_trace_run("end: " + reason)
	_end_rocket_skip()
	ui.show_rocket_hint(false)
	# v32: the first end of an attempt may be bought back once (paused offer; declining ends it normally)
	if _offer_continue(reason):
		return
	if achievements: achievements.finish_attempt()
	_attempt_open = false
	_cancel_continue()
	_end_reason = reason
	if star_tracker:
		star_tracker.finalize_contact()
		star_tracker.step(0.0, distance_m)
		_save_completed_stars()
		if mode == &"campaign":
			star_tracker.disconnect_robot()
		else:
			star_tracker.stop()
	if mode == &"campaign":
		player_final_m = distance_m
		# v32: the global (profile) distance record includes campaign attempts
		campaign_record = stats.submit_best(distance_m)
		if campaign_record:
			best_m = stats.best_m()
		if race.all_finished():
			_finish_campaign()
		else:
			# the player's attempt is over, the shadows still race: watch the leader (sped up), then the result
			state = State.WAIT
			set_sim_speed(int(wait_time_scale))
			var lead := race.leader_running()
			if lead:
				camera.follow(lead)
			ui.race_hud.show_waiting(true, L.t("RACE_WAITING") % int(distance_m))
		return
	state = State.RESULT
	# the attempt is over only now (head landed / robot stopped): record it once
	var record := false
	if attempt != null and not _attempt_saved:
		_attempt_saved = true
		var res := stats.record_attempt(attempt.to_dict(distance_m))
		record = res.record
		best_m = res.best_m
		_coins_earned = economy.free_run_coins(distance_m)
		profile.add_coins(_coins_earned)
	last_result = attempt.to_dict(distance_m) if attempt else {"distance_m": distance_m}
	last_result.merge({"best_m": best_m, "record": record, "reason": reason, "coins_earned": _coins_earned,
		"coins_total": profile.coins, "robot": robot_def.id if robot_def else ""}, true)
	if _coins_earned>0: audio.common("coin")
	if record: audio.common("record")
	ui.show_results(last_result)
	run_finished.emit(distance_m)


# ---------------- v32 secret artifact ----------------

## Bonus active = this profile found it, equipped it, and the mode is not competitive (the preference is kept).
func artifact_active() -> bool:
	return profile != null and bool(profile.artifact.discovered) and bool(profile.artifact.equipped) and not competitive_mode


func toggle_artifact() -> bool:
	var on := profile.set_artifact_equipped(not bool(profile.artifact.equipped))
	ui.set_artifact_state(bool(profile.artifact.discovered), on)
	return on


## Called while the track streams: the artifact appears once its spot exists (hazards there already generated).
func _step_artifact() -> void:
	if not _artifact_pending or terrain.end_x() < (SecretArtifact.X_M + SecretArtifact.SEARCH_M) * level_config.px_per_meter + 1500.0:
		return
	_artifact_pending = false
	artifact_node = SecretArtifact.new()
	artifact_node.gm = self
	var spot := SecretArtifact.place(terrain, hazards, level_config.px_per_meter)
	artifact_node.host = spot.node
	artifact_node.position = spot.pos
	artifact_node.collected.connect(_on_artifact_collected)
	dynamic.add_child(artifact_node)


func _on_artifact_collected() -> void:
	var p := artifact_node.global_position if is_instance_valid(artifact_node) else robot.global_position
	artifact_node = null
	if profile.discover_artifact():
		fx.star(p, 40.0, Color(1.0, 0.85, 0.3))
		fx.word(p + Vector2(0, -60), L.t("ARTIFACT_WORD"), Color(1.0, 0.85, 0.3), 56)
		audio.common("unlock")
		ui.set_artifact_state(true, bool(profile.artifact.equipped))


# ---------------- v32 paid continue ----------------

func continue_price() -> int:
	return maxi(int(economy.continue_price), 1)


## Offer only for a normal, non-competitive attempt that has not had its offer yet and only when affordable.
func can_offer_continue() -> bool:
	return _attempt_open and state in [State.RUN, State.ROCKET] and continue_offers_enabled and not _continue_used and not _continue_offered and not competitive_mode and tutorial == null and mode in [&"free", &"campaign"] \
		and attempt != null and profile.coins >= continue_price()


func _offer_continue(reason: String) -> bool:
	if not can_offer_continue():
		return false
	_continue_offered = true
	_offer_reason = reason
	_offer_prev_state = state
	_offer_epoch = _run_epoch
	_offer_attempt = attempt
	_offer_accept = _accept_offer_for.bind(_run_epoch, attempt)
	_offer_decline = _decline_offer_for.bind(_run_epoch, attempt)
	ui.continue_card.accepted.connect(_offer_accept)
	ui.continue_card.declined.connect(_offer_decline)
	state = State.OFFER
	input.reset()
	get_tree().paused = true   # everything waits (opponents too); the card runs with PROCESS_MODE_ALWAYS
	ui.continue_card.show_offer(continue_price(), profile.coins, reason)
	return true


## Player confirmed on the card: pay (saved first), then the same attempt goes on. Refused unless an offer is open
## and the coins are there; never spends anything otherwise.
func accept_continue() -> bool:
	if not _valid_continue() or _continue_used or profile.coins < continue_price():
		return false
	var price := continue_price()
	profile.coins -= price
	if not profile.save():
		profile.coins += price
		return false
	_continue_used = true
	_cancel_continue()
	get_tree().paused = false
	state = State.RUN
	_respawn_after_continue()
	ui.set_coins(profile.coins)
	audio.common("purchase")
	return true


## Player declined (or Back): the attempt ends exactly as it would have without the offer.
func decline_continue() -> void:
	if not _valid_continue():
		return
	var previous := _offer_prev_state
	var reason := _offer_reason
	_cancel_continue()
	get_tree().paused = false
	state = previous
	_finish(reason)


## One teardown for menu, map, restart and a new attempt. No profile/economy writes.
func _invalidate_attempt() -> void:
	if achievements: achievements.end_navigation()
	_run_epoch += 1
	_attempt_open = false
	_launch_trace_t = -1.0
	_cancel_continue()
	attempt = null
	_attempt_saved = true
	input.reset()
	hand.playing = false
	hand.hold_at_tension = false
	ui.biome_intro.cancel()


func _cancel_continue() -> void:
	_offer_epoch = -1
	_offer_attempt = null
	_offer_reason = ""
	_offer_prev_state = State.MENU
	var card := ui.continue_card
	if _offer_accept.is_valid() and card.accepted.is_connected(_offer_accept):
		card.accepted.disconnect(_offer_accept)
	if _offer_decline.is_valid() and card.declined.is_connected(_offer_decline):
		card.declined.disconnect(_offer_decline)
	_offer_accept = Callable()
	_offer_decline = Callable()
	card.cancel()


func _valid_continue() -> bool:
	return _attempt_open and state == State.OFFER and _offer_epoch == _run_epoch \
		and attempt != null and _offer_attempt == attempt and _continue_offered and ui.continue_card.visible


func _accept_offer_for(epoch: int, owner: AttemptStats) -> void:
	if epoch == _run_epoch and owner == attempt:
		accept_continue()


func _decline_offer_for(epoch: int, owner: AttemptStats) -> void:
	if epoch == _run_epoch and owner == attempt:
		decline_continue()


## Opt-in phone diagnostics: five title taps enable the existing debug overlay; read `RUN|` in adb logcat.
## No RNG, save writes, physics mutation or per-frame I/O; only launch, 0.25s sample and end.
func _trace_run(event: String) -> void:
	if not ui.debug_enabled and not Array(OS.get_cmdline_user_args()).has("--trace_runs"):
		return
	var data := {"event": event, "epoch": _run_epoch, "attempt": attempt.id if attempt else "",
		"state": state, "node": node_id, "seed": track_seed, "tier": flick_tier, "flick": settings.get_value("flick"),
		"holding": input.holding, "offer": ui.continue_card.visible}
	if is_instance_valid(robot):
		data.merge({"position": str(robot.position), "velocity": str(robot.linear_velocity), "freeze": robot.freeze,
			"sleeping": robot.sleeping, "launched": robot.launched, "contact": robot.contacts.any_contact,
			"ground_y": terrain.surface_y(robot.position.x)})
	print("RUN|" + JSON.stringify(data))


## Every 0.2 s while the robot stands on its feet on safe ground, remember that spot (respawn candidates).
func _track_safe(dt: float) -> void:
	_safe_clock += dt
	if _safe_clock < 0.2 or not is_instance_valid(robot):
		return
	_safe_clock = 0.0
	if not robot.contacts.any_leg_contact or robot.damage.rocket_fired or robot.damage.health <= 0.0:
		return
	var x := robot.global_position.x
	if is_finite(x) and respawn_ok(x) and (_safe_xs.is_empty() or x > _safe_xs[-1] + 40.0):
		_safe_xs.append(x)
		if _safe_xs.size() > 60:
			_safe_xs.pop_front()


## A respawn point: solid ground (not in / just before a chasm), away from anomalies and portals, past the ledge.
func respawn_ok(x: float) -> bool:
	if not is_finite(x) or x < terrain.ledge_end_x + 200.0 or terrain.gap_index(x) >= 0:
		return false
	for g in terrain.gaps:
		var lip := float(g[0])
		if lip > x and lip - x < 600.0:
			return false   # room to gain speed before the next gap
	var p := Vector2(x, terrain.surface_y(x) - 120.0)
	for a in hazards.anomalies + hazards.portals:
		if (a.pos as Vector2).distance_to(p) < 420.0:
			return false
	return true


## Latest remembered safe point (re-validated: hazards stream in), else search backwards from the furthest progress.
func pick_respawn_x() -> float:
	for i in range(_safe_xs.size() - 1, -1, -1):
		if respawn_ok(_safe_xs[i]):
			return _safe_xs[i]
	var x := minf(_max_x, terrain.end_x() - 400.0)
	for k in 200:
		if respawn_ok(x - k * 60.0):
			return x - k * 60.0
	return maxf(robot_start.x + 400.0, terrain.ledge_end_x + 300.0)


func _respawn_after_continue() -> void:
	var x := pick_respawn_x()
	if star_tracker:
		star_tracker.disconnect_robot()
	if is_instance_valid(robot):
		robot.queue_free()
	if is_instance_valid(rocket):
		rocket.queue_free()
	rocket = null
	robot = build_robot(robot_def, input, fx, profile.equipped_skin(robot_def.id, player_mk2(robot_def)), player_mk2(robot_def))
	robot.name = "Robot"
	var k: float = robot.config.rig_scale / 0.42
	var leg_reach: float = (13.3 + 54.0) * k + robot.contact_config.coil_rest_length
	robot.position = Vector2(x, terrain.surface_y(x) - (35.7 * k + leg_reach) + 4.0)
	dynamic.add_child(robot)
	ui.set_robot_art(robot.visual.rig, robot.config.visual_material)
	robot.damage.invulnerability_time = settings.get_value("invuln_s")
	robot.damage.restore_for_continue(economy.continue_hp_ratio, economy.continue_invuln_s)
	_wire_player_robot()
	robot.launch(MomentumRules.forward_tangent(terrain.normal_at(x)) * economy.continue_speed, 0.0)
	if attempt:
		attempt.attach(robot)
	if star_tracker:
		star_tracker.reattach(robot)
		star_tracker.on_continue(distance_m)
	ui.reset_modules()
	ui.set_health(robot.damage.health, robot.damage.max_health, true)
	camera.min_zoom = _cam_min_zoom
	camera.follow(robot)
	input.reset()
	_stuck = 0.0
	_watch = MotionWatch.new(no_progress_time)
	_watch.reset(robot.global_position)


# ---------------- spawning ----------------

func _clear_dynamic() -> void:
	if haptics:
		haptics.reset_pending()
	if fx:
		fx.reset_attempt()
	if star_tracker:
		_save_completed_stars()
		star_tracker.stop()
		star_tracker = null
	for c in dynamic.get_children():
		c.queue_free()
	robot = null
	rocket = null


## Builds (does not add) a robot of an archetype with the current shared rules / player settings.
## Gameplay = archetype stats (+ future modules); appearance = skin (cosmetic only).
func build_robot(def: RobotDefinition, router: InputRouter, fx_node: Node, skin_id := "", mk2 := false) -> RobotController:
	# v32: the equipped secret artifact is a runtime stat module of the PLAYER's robot only (never opponents)
	# v35 MK2: same archetype (rig / colliders / mass / size from the base definition) + its MK2 stat module + MK2 art
	mk2 = mk2 and def.has_mk2()
	var modules: Array = [def.mk2_module()] if mk2 else []
	if router == input and artifact_active():
		# v36: +15 displayed points on top of base (+ MK2) stats
		modules.append(SecretArtifact.module(ModuleDefinition.apply_all(def.base_stats(), modules), catalog))
	var cfgs := def.make_configs(robot_config, contact_config, damage_config, modules)
	if _is_autotest() and Array(OS.get_cmdline_user_args()).has("--no_momentum"):
		cfgs.contact.momentum_gain = 0.0   # debug harness only: A/B comparisons without the v32 momentum layer
	var skin := skins.get_by_id(skin_id) if skin_id != "" else null
	if skin == null or skin.robot_id != def.id:
		skin = skins.get_by_id(SkinDefinition.default_id(def.id))
	if skin:
		skin.apply_visual(cfgs.robot, def, mk2)   # v36: colour scheme of the BASE or MK2 version (cosmetic only)
	elif mk2:
		cfgs.robot.visual_id = def.mk2_visual_id
	var r := RobotController.new()
	r.config = cfgs.robot
	r.contact_config = cfgs.contact
	r.damage_config = cfgs.damage
	r.rocket_config = rocket_config
	r.spin_config = spin_config
	r.setup(router, fx_node)
	r.ready.connect(func() -> void:
		var feedback := RobotAudioFeedback.new()
		feedback.name="AudioFeedback"
		feedback.setup(r,audio,terrain)
		# Wilhelm easter egg is a PLAYER-only event (opponents never roll it)
		feedback.is_player = router == input
		feedback.px_per_meter = level_config.px_per_meter
		r.add_child(feedback))
	return r


func _spawn_robot() -> void:
	_clear_dynamic()
	input.reset()
	robot_def = _pick_robot()
	robot = build_robot(robot_def, input, fx, profile.equipped_skin(robot_def.id, player_mk2(robot_def)), player_mk2(robot_def))
	robot.name = "Robot"
	# robot_config already carries the player's spin speeds (apply_settings); invulnerability is per robot
	# stand on the ledge: sole of the boots on the ground
	var k: float = robot.config.rig_scale / 0.42
	var leg_reach: float = (13.3 + 54.0) * k + robot.contact_config.coil_rest_length
	robot_start = Vector2(-80.0, terrain.height_at(-80.0) - (35.7 * k + leg_reach) + 4.0)
	robot.position = robot_start
	dynamic.add_child(robot)
	ui.set_robot_art(robot.visual.rig, robot.config.visual_material)
	robot.damage.invulnerability_time = settings.get_value("invuln_s")
	# v34: the tutorial uses the real release controls (fixed physics) - fairness comes from its freeze gates and
	# practice setups (TutorialDirector), not from different spin speeds
	_wire_player_robot()
	_max_x = robot_start.x
	_watch = MotionWatch.new(no_progress_time)
	_watch.reset(robot_start)
	distance_m = 0.0
	hand.visible = true
	hand.playing = false
	hand.modulate.a = 1.0
	hand.sprite.texture = hand.frames[0]
	hand.aim_at(robot.global_position + Vector2(-58.0 * k, 8))
	_refresh_menu_robot()
	_sync_menu_world_actors()


## Signal hookup of the player's robot (spawn and v32 paid-continue respawn).
func _wire_player_robot() -> void:
	# every handler checks the source: the previous robot lives until the end of the frame after Retry /
	# Menu (queue_free) and its late signals must never touch the new attempt
	var r := robot
	var epoch := _run_epoch
	robot.limb_lost.connect(func(limb: StringName, _p: RigidBody2D) -> void:
		if epoch == _run_epoch and r == robot:
			_on_limb_lost(limb, _p))
	robot.charge_changed.connect(func(c: float) -> void:
		if epoch == _run_epoch and r == robot:
			_player_hud.call_deferred(r.get_instance_id(), epoch, false, c / spin_config.max_charge))
	robot.damaged.connect(func(_a: float, _z: StringName, hp: float, _i: Dictionary) -> void:
		if epoch == _run_epoch and r == robot:
			_player_hud.call_deferred(r.get_instance_id(), epoch, true, hp))
	robot.rocket_launched.connect(func(head: RigidBody2D) -> void:
		if epoch == _run_epoch and _attempt_open and r == robot and state == State.RUN:
			_on_rocket(head))


func _player_hud(source_id: int, epoch: int, health: bool, value: float) -> void:
	if epoch != _run_epoch or not is_instance_valid(robot) or source_id != robot.get_instance_id():
		return
	if health: ui.set_health(value, robot.damage.max_health)
	else: ui.set_charge(value)


func _frame_intro() -> void:
	camera.min_zoom = _cam_min_zoom
	var focus := robot.global_position + Vector2(-480, -60)
	camera.snap_intro(focus, 0.6)


func _on_limb_lost(limb: StringName, _part: RigidBody2D) -> void:
	ui.set_module(limb, false)


func _on_rocket(head: RigidBody2D) -> void:
	rocket = head as RocketHead
	state = State.ROCKET
	ui.set_module(&"head", false)
	ui.set_module(&"torso", false)
	camera.min_zoom = 0.3
	camera.follow(rocket)
	var epoch := _run_epoch
	rocket.finished.connect(func(h: RocketHead) -> void:
		if epoch == _run_epoch and _attempt_open and h == rocket and state == State.ROCKET:
			_finish("Голова приземлилась", epoch))



# ---------------- per-frame ----------------

func _process(dt: float) -> void:
	_clock_ms += dt * 1000.0
	camera.safe_margins = ui.safe_margins
	# v34: the skip prompt appears only once a skip is actually allowed (guard ROCKET_SKIP_MIN_T of head flight)
	var hint_on := can_skip_rocket()
	if hint_on != ui.rocket_hint_visible():
		ui.show_rocket_hint(hint_on)


## Track seed for the next run: forced with --track_seed=N (tests), otherwise random.
func _pick_seed() -> int:
	if debug_track_seed >= 0:
		return debug_track_seed
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track_seed="):
			return int(a.substr(13))
	return _seed_rng.randi() & 0x7fffffff


func _physics_process(dt: float) -> void:
	if _launch_trace_t >= 0.0 and state == State.RUN:
		_launch_trace_t += dt
		if _launch_trace_t >= 0.25:
			_launch_trace_t = -1.0
			_trace_run("launch+0.25s")
	if attempt != null and (state == State.RUN or state == State.ROCKET):
		attempt.duration_s += dt
	# stream the track ahead of the furthest of robot / jet head / camera; free chunks far behind
	var lead := camera.get_screen_center_position().x
	var cap := terrain.end_x() + 6000.0   # never stream towards a glitched (huge / non-finite) position
	if is_instance_valid(robot) and is_finite(robot.global_position.x) and robot.global_position.x < cap:
		lead = maxf(lead, robot.global_position.x)
	if is_instance_valid(rocket) and is_finite(rocket.global_position.x) and rocket.global_position.x < cap:
		lead = maxf(lead, rocket.global_position.x)
	if not is_finite(lead) or lead > cap:
		lead = minf(terrain.end_x(), cap)
	var behind := minf(lead, camera.get_screen_center_position().x)
	var racing := mode == &"campaign" and (state == State.RUN or state == State.ROCKET or state == State.WAIT)
	if racing and not race.competitors.is_empty():
		lead = maxf(lead, race.max_x())
		behind = minf(behind, race.min_running_x())
	terrain.ensure_ahead(lead, behind)
	_step_artifact()
	if racing:
		race.step(dt)
		var d := [distance_m if state != State.WAIT else player_final_m]
		var fin := [state == State.WAIT]
		for c in race.competitors:
			d.append(c.distance)
			fin.append(c.finished)
		ui.race_hud.update_distances(d, fin)
		if state == State.WAIT:
			if race.all_finished():
				_finish_campaign()
			else:
				var lead_piece := race.leader_running()
				if lead_piece and camera.target != lead_piece:
					camera.follow(lead_piece)
	_update_debug(dt)
	if tutorial!=null:
		return
	match state:
		State.RUN:
			if not is_instance_valid(robot):
				return
			_track(robot.global_position.x)
			_step_stars(dt)
			_track_safe(dt)
			_stuck = _watch.stopped(dt, robot.linear_velocity.length(), robot.angular_velocity, stuck_speed)
			if _stuck > stuck_time:
				_end_or_final("Робот остановился")
			if robot.global_position.y > terrain.fall_limit_y(robot.global_position.x):
				_finish("Упал в пропасть" if terrain.gap_index(robot.global_position.x) >= 0 else "Робот провалился")
			_check_progress(dt)
		State.ROCKET:
			if is_instance_valid(rocket):
				_track(rocket.global_position.x)
				_step_stars(dt)
				if rocket.global_position.y > terrain.fall_limit_y(rocket.global_position.x):
					_finish("Голова улетела в пропасть")


## A stopped robot normally ends the attempt - but a wrecked one (0 HP, no limbs) resting on its torso
## gets its final jet-head instead (DamageConfig.rocket_on_resting_torso).
func _end_or_final(reason: String) -> void:
	if is_instance_valid(robot) and robot.damage.health <= 0.0 and robot.damage.limbs_remaining.is_empty():
		robot.notify_resting()
		if robot.damage.rocket_fired:
			return
	_finish(reason)


## v36: "stuck" = genuine physical immobilisation (MotionWatch). Moving backward / flying / bouncing never counts,
## however much distance is lost; only a body confined in place (or an endless in-place loop) ends the attempt.
func _check_progress(dt: float) -> void:
	if _watch.step(dt, robot.global_position):
		_end_or_final("Робот застрял")


func _track(x: float) -> void:
	# a position outside the world can only come from a broken physics step: never let it become a result
	if not is_finite(x) or x > terrain.points[terrain.points.size() - 1].x + 20000.0:
		return
	_max_x = maxf(_max_x, x)
	distance_m = maxf(0.0, (_max_x - robot_start.x) / level_config.px_per_meter)
	ui.set_distance(distance_m)


# ---------------- persistence ----------------

## v34 language reload hand-over (static: survives reload_current_scene).
static var _resume_slot := 0
static var _resume_settings := false
static var language_reloads := 0


func _is_autotest() -> bool:
	return Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--autotest"))


## Real players: user://settings.json. Debug harness: a separate test file (fresh unless --keep_settings; a language
## reload inside a test keeps it).
func _load_settings_store() -> void:
	var path := SETTINGS_PATH
	if _is_autotest():
		path = TEST_SETTINGS_PATH
		var keep := false
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--settings_path="):
				path = a.substr(16)
			keep = keep or a == "--keep_settings"
		keep = keep or language_reloads > 0
		if not keep and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	settings = SettingsStore.new(path)
	settings.load_data()


func _open_settings() -> void:
	_apply_pre_v34_physics_debug()
	apply_settings()
	ui.set_settings_values(settings.values)
	ui.set_language_choice(settings.language())


## v34 localization. Players: the stored app-global choice ("auto" = device locale -> supported match, else English).
## Debug harness: Russian (the source language the older suites assert on) unless --locale=<code|auto>, or the
## stored choice after an in-test language reload.
func _apply_language() -> void:
	var choice := settings.language()
	if _is_autotest() and language_reloads == 0:
		choice = "ru"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--locale="):
				choice = a.substr(9)
	L.apply(choice)


## Settings > Language: saved at once, then the scene is rebuilt in the new language and the same player comes back
## to the Settings screen (all UI text is built from the active locale).
func set_language(choice: String) -> bool:
	if state != State.MENU or tutorial != null:
		return false
	if choice == settings.language():
		ui.set_language_choice(choice)
		return false
	settings.set_language(choice)
	settings.save()
	_save_active()
	L.apply(settings.language())
	_resume_slot = active_slot
	_resume_settings = true
	language_reloads += 1
	set_sim_speed(1)
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()
	return true


## Settings take effect immediately (spin speeds are read every physics step; invulnerability per robot).
func apply_settings() -> void:
	# Optional SFX key uses the store's existing preserved extras; no gameplay migration.
	var sfx_value = settings.unrelated.get("sfx_volume",75.0)
	var sfx := clampf(float(sfx_value),0,100) if typeof(sfx_value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(sfx_value)) else 75.0
	audio.set_volume(sfx)
	ui.set_sfx_volume(sfx)
	robot_config.clockwise_rotation_speed = settings.get_value("auto_rps")
	robot_config.counterclockwise_rotation_speed = settings.get_value("manual_rps")
	robot_config.auto_spin_accel = settings.get_value("spin_accel")
	robot_config.recovery_time = settings.get_value("recovery_s")
	robot_config.recovery_start_ratio = settings.get_value("recovery_pct") / 100.0
	contact_config.spring_power_scale = settings.get_value("spring_power") / 100.0
	contact_config.bounce_spin_scale = settings.get_value("bounce_spin") / 100.0
	camera.shake_scale = settings.get_value("shake") / 100.0
	haptics.vibration_scale = settings.get_value("vibration") / 100.0
	if haptics.vibration_scale <= 0:
		haptics.reset_pending()
	if is_instance_valid(robot):
		robot.damage.invulnerability_time = settings.get_value("invuln_s")
		robot.config.clockwise_rotation_speed = robot_config.clockwise_rotation_speed
		robot.config.counterclockwise_rotation_speed = robot_config.counterclockwise_rotation_speed
		robot.config.auto_spin_accel = robot_config.auto_spin_accel
		robot.config.recovery_time = robot_config.recovery_time
		robot.config.recovery_start_ratio = robot_config.recovery_start_ratio
		robot.contact_config.spring_power_scale = contact_config.spring_power_scale
		robot.contact_config.bounce_spin_scale = contact_config.bounce_spin_scale
		robot.spin_charge.base_cw_speed = robot_config.clockwise_rotation_speed


## Debug harness only (--pre_v34_physics): the v33 default physics, to prove a changed test number comes from the
## approved v34 release values and not from a regression. Never reachable outside --autotest.
const PRE_V34_PHYSICS := {"auto_rps": 0.8, "manual_rps": 1.0, "invuln_s": 0.5, "recovery_s": 0.5, "bounce_spin": 40.0, "spring_power": 150.0}


func _apply_pre_v34_physics_debug() -> void:
	if _is_autotest() and Array(OS.get_cmdline_user_args()).has("--pre_v34_physics"):
		for k in PRE_V34_PHYSICS:
			settings.debug_set_physics(k, PRE_V34_PHYSICS[k])


func set_setting(key: String, value: float) -> void:
	# v34: release physics are fixed; only the debug harness may sweep them (physics tests)
	if SettingsStore.is_fixed(key) and _is_autotest():
		settings.debug_set_physics(key, value)
	else:
		settings.set_value(key, value)
	settings.save()
	apply_settings()


func reset_settings() -> void:
	settings.unrelated["sfx_volume"]=75.0
	settings.reset_to_defaults()
	_apply_pre_v34_physics_debug()
	settings.save()
	apply_settings()
	ui.set_settings_values(settings.values)


## Real players: user://profile.json (coins, robots). Debug harness: a separate test file (fresh unless --keep_profile).
func _open_profile() -> void:
	var path := PROFILE_PATH
	if _is_autotest():
		path = TEST_PROFILE_PATH
		var keep := false
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--profile_path="):
				path = a.substr(15)
			keep = keep or a == "--keep_profile"
		if not keep and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	profile = ProfileStore.new(path, catalog)
	profile.load_data()


## Real players: user://stats.json. Debug harness: a separate test file (fresh unless --keep_stats).
func _open_stats() -> void:
	var path := STATS_PATH
	if _is_autotest():
		path = TEST_STATS_PATH
		var keep := false
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--stats_path="):
				path = a.substr(13)
			keep = keep or a == "--keep_stats"
		if not keep and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	stats = StatsStore.new(path)
	if path == STATS_PATH:
		stats.legacy_path = StatsStore.LEGACY_CFG
	stats.load_data()
	best_m = stats.best_m()


# ---------------- v31 player profiles (3 save slots) ----------------

## Players: "user://". Debug harness: only with --profiles_root=<dir> (otherwise the historical single-file stores).
func _profiles_root() -> String:
	if not _is_autotest():
		return "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profiles_root="):
			return a.substr(16)
	return ""


func _bind_profile_ui() -> void:
	if achievements: achievements.bind_profile(profile)
	ui.robot_select.owns_skin = profile.owns_skin
	ui.robot_select.equipped_of = profile.equipped_skin
	ui.set_artifact_state(bool(profile.artifact.discovered), bool(profile.artifact.equipped))
	ui.set_profile_chip(ProfileManager.slot_name(active_slot) if active_slot > 0 else "", profiles != null)


## No player active (boot / after deleting the active one): in-memory defaults, ProfileStore/StatsStore("") never
## write anything, so nothing can land in a slot by accident.
func _use_placeholder_profile() -> void:
	active_slot = 0
	profile = ProfileStore.new("", catalog)
	profile.ensure_campaign_start(campaign.start_id)
	stats = StatsStore.new("")
	best_m = 0.0
	adaptive = AdaptiveDifficulty.new(adaptive_config, profile.adaptive)


func _load_slot(slot: int) -> void:
	profile = ProfileStore.new(profiles.profile_path(slot), catalog)
	profile.load_data()
	profile.ensure_campaign_start(campaign.start_id)
	stats = StatsStore.new(profiles.stats_path(slot))
	stats.load_data()
	best_m = stats.best_m()
	adaptive = AdaptiveDifficulty.new(adaptive_config, profile.adaptive)
	active_slot = slot
	# per-player session context: nothing of the previous player carries over
	mode = &"free"
	node_id = ""
	robot_def = null
	stars_before = []
	_star_free_set_id = 0
	tutorial_pending_destination = &"free"


## Writes the active player's stores (before switching / deleting another slot / leaving the profile screen).
func _save_active() -> void:
	if profiles == null or active_slot <= 0 or not profiles.exists(active_slot):
		return
	profile.adaptive = adaptive.state
	profile.save()
	stats.save()


## Profile screen: only from the main menu (never mid-run, never inside the tutorial).
func open_profiles() -> bool:
	if profiles == null or state != State.MENU or tutorial != null:
		return false
	_save_active()
	ui.open_profiles(profile_summaries(), active_slot, active_slot > 0)
	return true


func close_profiles() -> void:
	if active_slot <= 0:
		return   # a player has to be chosen first
	ui.close_profiles()
	go_menu()


func profile_summaries() -> Array:
	var out := []
	for s in range(1, ProfileManager.SLOTS + 1):
		out.append(profiles.summary(s))
	return out


## Choose a slot: an occupied one loads exactly its data, an empty one starts a brand-new player at zero.
func activate_slot(slot: int) -> bool:
	if profiles == null or not ProfileManager.valid_slot(slot) or state != State.MENU or tutorial != null:
		return false
	_save_active()
	var fresh := not profiles.exists(slot)
	if fresh and not profiles.create(slot):
		return false
	_load_slot(slot)
	if fresh:
		profile.save()
		stats.save()
	profiles.set_last_slot(slot)
	_bind_profile_ui()
	ui.close_profiles()
	go_menu()
	# v33: a brand-new player goes straight into the interactive tutorial (skippable inside, with confirmation);
	# it ends on the campaign map
	if fresh and auto_tutorial_new_profile and not profile.tutorial.handled:
		_start_tutorial(&"campaign")
	return true


## Delete one slot (the profile screen asks for confirmation first). Deleting the active player leaves it at once:
## the placeholder takes over BEFORE the files go, so no later save can recreate them.
func delete_slot(slot: int) -> bool:
	if profiles == null or not profiles.exists(slot) or state != State.MENU or tutorial != null:
		return false
	if slot == active_slot:
		_use_placeholder_profile()
		_bind_profile_ui()
	var ok := profiles.delete(slot)
	go_menu()
	ui.open_profiles(profile_summaries(), active_slot, active_slot > 0)
	return ok

# ---------------- AI / balance debug overlay (hidden: 5 taps on the menu title, or --ai_debug) ----------------

const DEBUG_PATH := "user://debug.cfg"


func _load_debug() -> bool:
	if Array(OS.get_cmdline_user_args()).has("--ai_debug"):
		return true
	var cf := ConfigFile.new()
	return cf.load(DEBUG_PATH) == OK and bool(cf.get_value("debug", "ai_overlay", false))


func _save_debug(on: bool) -> void:
	if _is_autotest():
		return
	var cf := ConfigFile.new()
	cf.set_value("debug", "ai_overlay", on)
	cf.save(DEBUG_PATH)


func _update_debug(dt: float) -> void:
	if not ui.debug_enabled:
		return
	_debug_t += dt
	if _debug_t < 0.2:
		return
	_debug_t = 0.0
	var lines := []
	lines.append("mode=%s state=%s seed=%d  player=%.1f m (final %.1f)" % [mode, State.keys()[state], track_seed, distance_m, player_final_m])
	lines.append("adaptive: ema=%.3f modifier=%+.3f samples=%d" % [adaptive.state.ema, adaptive.modifier(), adaptive.state.samples])
	if mode == &"campaign" and campaign.nodes.has(node_id):
		var n := campaign.node(node_id)
		lines.append("node=%s (%s) attempts=%d completed=%s reward=%d" % [node_id, n.difficulty, profile.attempts_on(node_id),
			profile.is_completed(node_id), int(n.reward_first)])
		for c in race.competitors:
			var a: Dictionary = c.ai.debug if is_instance_valid(c.ai) else {}
			lines.append("#%d %s [%s] %.1f m %s | skill base %.2f eff %.2f form %+.2f" % [c.index, c.name, c.robot_id, c.distance,
				("FIN:" + c.reason) if c.finished else "run", c.base_skill, c.skill, a.get("form", 0.0)])
			lines.append("   %s hold=%s flight=%d blunders=%d lean_err=%+.0f° tau_bias=%+.2f tau=%.2f/%.2f target=%.0f° plan_err=%.0f°" % [
				a.get("state", "-"), a.get("hold", false), a.get("flight", 0), c.ai.blunders if is_instance_valid(c.ai) else 0,
				a.get("lean_err", 0.0), a.get("tau_bias", 0.0), a.get("tau", 0.0), a.get("tau_true", 0.0), a.get("target_deg", 0.0),
				a.get("plan_err_deg", 0.0)])
	ui.debug_label.text = "\n".join(lines)


func _step_stars(dt: float) -> void:
	if star_tracker:
		var active_body: Node2D = rocket if (state == State.ROCKET and is_instance_valid(rocket)) else (robot if is_instance_valid(robot) else null)
		if active_body != null and is_finite(active_body.global_position.x) and is_finite(active_body.global_position.y):
			var h_m := maxf(0.0, (terrain.surface_y(active_body.global_position.x) - active_body.global_position.y) / level_config.px_per_meter)
			star_tracker.sample_height(h_m)
		if state == State.RUN or state == State.ROCKET:
			star_tracker.sample_no_touch(dt, input != null and input.holding, state == State.ROCKET)
		star_tracker.step(dt, distance_m)
		_star_retry_t += dt
		if _star_retry_t >= 1.0:
			_star_retry_t = 0.0
			_save_completed_stars()

func _save_completed_stars() -> void:
	if star_tracker:
		for i in star_tracker.status.size():
			if star_tracker.status[i] == 1 and not star_tracker.owned[i]:
				_earn_star(i)

func _earn_star(i: int) -> void:
	if star_tracker == null:
		return
	var result := profile.earn_free_star(_star_free_set_id, i) if ui.star_hud.free_mode else profile.earn_star(_star_node_id, i, StarChallenges.reward(star_tracker.challenges[i]))
	if result.new:
		star_tracker.owned[i] = true
		if not ui.star_hud.free_mode:
			stars_new.append(i)
			star_coins += int(result.paid)
		audio.common("all_stars" if not star_tracker.owned.has(false) else "star")
		ui.star_hud.earned(i, int(result.paid))
		haptics.submit(0.6)
		if ui.star_hud.free_mode and not star_tracker.owned.has(false):
			star_tracker.stop() # Challenges never end Free Run; completed telemetry is no longer needed.
		ui.set_coins(profile.coins)
		ui.set_stars(int(profile.star_wallet.available))


## Intercept only the user's menu action, never app startup or internal normal retry/start_run.
func request_mode(requested: StringName) -> void:
	if not profile.tutorial.handled:
		begin_tutorial(requested)
	elif requested==&"campaign":
		open_campaign_map()
	else:
		mode=&"free"
		open_robot_select()

func begin_tutorial(destination: StringName) -> void:
	if tutorial!=null or ui.awareness.visible:
		return
	tutorial_pending_destination=destination
	ui.close_settings()
	ui.awareness.show_tutorial()

func _start_tutorial(destination: StringName) -> void:
	if tutorial!=null:
		return
	get_tree().paused=false
	set_sim_speed(1)
	profile.tutorial.handled=true
	profile.save()
	mode=&"tutorial"
	state=State.MENU
	race.clear()
	attempt=null
	_attempt_saved=true
	hazards.clear()
	_apply_biome(BiomeCatalog.get_def(BiomeCatalog.GREEN))
	terrain.build_training()
	_spawn_robot()
	_frame_intro()
	ui.show_hud()
	ui.star_hud.visible=false
	ui.race_hud.visible=false
	ui.restart_button.visible=false
	ui.hint.visible=false
	camera.practice_framing=true
	ui.set_health(robot.damage.max_health,robot.damage.max_health,true)
	state=State.INTRO
	tutorial=TutorialDirector.new()
	tutorial.gm=self
	tutorial.destination=destination
	add_child(tutorial)
	# v33: the first lesson is the REAL start: the hand waits at tension, the player taps the flick bar
	hand.hold_at_tension = true
	if ui.flick_bar:
		ui.flick_bar.begin(true)
	hand.play(1.6)

func finish_tutorial(completed: bool, continue_destination: bool) -> void:
	if tutorial==null:
		return
	var destination := tutorial.destination
	var old := tutorial
	tutorial=null
	camera.practice_framing=false
	old.stop()
	old.queue_free()
	profile.tutorial.handled=true
	profile.tutorial.completed=profile.tutorial.completed or completed
	profile.save()
	mode=&"free"
	terrain.reset(_pick_seed())
	go_menu()
	if destination==&"settings":
		ui.open_settings()
	elif continue_destination:
		request_mode(destination)
