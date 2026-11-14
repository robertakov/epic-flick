class_name GameAudio
extends Node
## Bounded mixer, private RNG, lazy compressed streams. Never drives physics or haptics.
var bank: Dictionary = {}
var rng := RandomNumberGenerator.new()
var pools: Dictionary = {}
var cache: Dictionary = {}
var cache_order: Array[String] = []
var voices: Array[AudioStreamPlayer] = []
var loops: Dictionary = {}
var clock := 0.0
var cooldowns: Dictionary = {}
var counts: Dictionary = {}
var listener: Node2D
var test_silent := false
const COMPONENTS := {"launch":"body", "spring":"legs", "body":"body", "head":"head", "limb":"armor", "voice":"head", "head_launch":"propulsion", "rolling":"head", "flight":"propulsion", "leg_thrust":"legs"}
const COMMON_EVENTS := ["click","back","browse","confirm","module_install","module_remove","countdown","go","coin","purchase","unlock","star","all_stars","record","victory","defeat","energy","flight","wilhelm"]

func _ready() -> void:
	rng.randomize()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest"): test_silent=true
	bank = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/bank.json"))
	for bus in ["SFX","UI","Robot","Voice"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "Master" if bus=="SFX" else "SFX")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"),-5.0)
	# A final safety limiter, with conservative source/bus gain as the primary mix control.
	if AudioServer.get_bus_effect_count(0)==0:
		AudioServer.add_bus_effect(0,AudioEffectHardLimiter.new())
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p); voices.append(p)

func set_volume(percent: float) -> void:
	var value := clampf(percent,0.0,100.0)/100.0
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"),value<=0.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"),linear_to_db(maxf(value,.0001))-5.0)

func resolve(robot_id: String, event: String, overrides: Dictionary = {}, layers := false) -> String:
	var component: String = COMPONENTS.get(event,"")
	var installed: Dictionary = overrides.get(component,{})
	if installed.has(event): return String(installed[event])
	if event in ["energy","flight","wilhelm"]: return "common/"+event
	var profiles: Dictionary = bank.get("profiles",{})
	var profile: Dictionary = profiles.get(robot_id,{})
	return String(profile.get(event,"")) if not layers else ""

func choose(family: String, intensity := 1.0) -> Dictionary:
	var variants: Array = bank.get("banks",{}).get(family,[])
	if variants.is_empty(): return {}
	var eligible: Array[int] = []
	var last := int(pools.get(family,-1))
	for i in variants.size():
		if float(variants[i].tier)<=clampf(intensity+.3,0.0,1.0): eligible.append(i)
	if eligible.is_empty(): eligible.append(0)
	# Expand to two eligible entries so a low-energy pool also avoids immediate repeats.
	if eligible.size()==1 and variants.size()>1: eligible.append(1)
	if eligible.size()>1: eligible.erase(last)
	var index: int = eligible[rng.randi_range(0,eligible.size()-1)]
	pools[family]=index
	return variants[index]

func stream(clip: Dictionary) -> AudioStream:
	if clip.is_empty(): return null
	var path := String(clip.path)
	if cache.has(path):
		cache_order.erase(path); cache_order.append(path)
		return cache[path]
	if not ResourceLoader.exists(path): return null
	var value := load(path) as AudioStream
	if value==null: return null
	cache[path]=value; cache_order.append(path)
	if cache_order.size()>16: cache.erase(cache_order.pop_front())
	return value

func accept(key: String, cooldown: float) -> bool:
	if clock-float(cooldowns.get(key,-100.0))<cooldown: return false
	cooldowns[key]=clock
	if cooldowns.size()>128:
		for old in cooldowns.keys():
			if clock-float(cooldowns[old])>10.0: cooldowns.erase(old)
	return true

func attenuation(point: Vector2) -> float:
	if listener==null or point==Vector2.INF: return 1.0
	return clampf(1.0-listener.global_position.distance_to(point)/2200.0,0.0,1.0)

## v27: each robot's sonic identity is designed into its own samples (tools/audio/build_sound_bank.py), so the
## runtime no longer re-pitches whole banks; only the small intensity / anti-repetition pitch variation remains.
const ROBOT_PITCH := {"tin": 1.0, "hopper": 1.0, "heavy": 1.0, "rocket": 1.0, "samurai": 1.0}

func play(family: String, intensity := 1.0, key := "", cooldown := .08, bus := "Robot", point := Vector2.INF, gain := 1.0) -> bool:
	if family.is_empty() or not bank.get("banks",{}).has(family): return false
	if not accept(key if key!="" else family,cooldown): return false
	var clip := choose(family,intensity)
	var resource := stream(clip)
	if resource==null: return false
	counts[family]=int(counts.get(family,0))+1
	if test_silent: return true
	var spatial := attenuation(point)
	if spatial<=.01: return true
	var prefix := family.get_slice("/", 0)
	var base_pitch := float(ROBOT_PITCH.get(prefix, 1.0))
	var dyn_pitch := 0.97 + 0.06 * clampf(intensity, 0.0, 1.0)
	for p in voices:
		if not p.playing:
			p.stream=resource; p.bus=bus
			p.volume_db=linear_to_db(maxf(.001,(.26+.50*clampf(intensity,0,1))*gain*spatial))
			p.pitch_scale=clampf(base_pitch * dyn_pitch * rng.randf_range(.96,1.04), 0.75, 1.35)
			p.play(); return true
	return true # voice budget exhausted: drop rather than allocate

## v37 RobotSoundSet path: the set already decided cooldown / layering; `intensity` picks the tier, `level` is the
## linear gain (set + repeat ducking), pitch varies by +-pitch_var only (audio RNG, never gameplay).
func play_level(family: String, intensity: float, level: float, point := Vector2.INF, pitch_var := 0.025, bus := "Robot") -> bool:
	if family.is_empty() or not bank.get("banks",{}).has(family): return false
	var resource := stream(choose(family,intensity))
	if resource==null: return false
	counts[family]=int(counts.get(family,0))+1
	if test_silent: return true
	var spatial := attenuation(point)
	if spatial<=.01: return true
	for p in voices:
		if not p.playing:
			p.stream=resource; p.bus=bus
			p.volume_db=linear_to_db(maxf(.001,level*spatial))
			p.pitch_scale=clampf(rng.randf_range(1.0-pitch_var,1.0+pitch_var),0.8,1.25)
			p.play(); return true
	return true # voice budget exhausted: drop rather than allocate

func common(event: String, intensity := 1.0) -> bool:
	return play("common/"+event,intensity,"ui:"+event,.10,"UI")

const MAX_LOOPS := 8

func loop_target(key: String, family: String, strength: float, point: Vector2, gain := 1.0) -> void:
	if family.is_empty(): strength=0.0
	if strength<=.015:
		if loops.has(key): loops[key].target=0.0
		return
	if not loops.has(key):
		# v39: 8 loop players; quiet rival loops (gain < .5) may use at most 5 so the player always has room
		if loops.size()>=(MAX_LOOPS-3 if gain<.5 else MAX_LOOPS): return
		var resource := stream(choose(family,strength))
		if resource==null: return
		resource=resource.duplicate()
		if resource is AudioStreamOggVorbis: resource.loop=true
		elif resource is AudioStreamWAV:
			# v27 bank: 16-bit WAV masters imported as QOA; loops are authored seamless (cross-faded ends)
			var w := resource as AudioStreamWAV
			w.loop_mode=AudioStreamWAV.LOOP_FORWARD;w.loop_begin=0;w.loop_end=int(w.get_length()*w.mix_rate)
		var p := AudioStreamPlayer.new(); p.stream=resource; p.bus="Robot"; p.volume_db=-60
		add_child(p)
		if not test_silent: p.play()
		loops[key]={"player":p,"level":0.0,"target":0.0,"strength":strength,"point":point,"touched":clock}
	loops[key].target=strength*.45*attenuation(point)*gain
	loops[key].strength=strength; loops[key].point=point; loops[key].touched=clock

func stop_owner(prefix: String) -> void:
	for key in loops.keys():
		if String(key).begins_with(prefix):
			loops[key].player.queue_free(); loops.erase(key)

func _process(dt: float) -> void:
	var real_dt := dt/maxf(Engine.time_scale,.01)
	clock+=real_dt
	for key in loops.keys():
		var state: Dictionary = loops[key]
		if clock-float(state.touched)>.2: state.target=0.0
		state.level=move_toward(float(state.level),float(state.target),real_dt*2.5)
		state.player.volume_db=linear_to_db(maxf(.001,float(state.level)))
		state.player.pitch_scale=.94+.12*float(state.strength)
		if state.target==0.0 and state.level<.001:
			state.player.queue_free(); loops.erase(key)

func ui_event(button: BaseButton) -> String:
	var text := String(button.get("text")) if button is Button else ""
	if button.has_meta("audio_event"): return String(button.get_meta("audio_event"))
	if text.contains(L.t("UI_BACK")) or text.contains(L.t("UI_DONE")) or text.contains(L.t("UI_MENU")) or text.contains(L.t("UI_CLOSE")) or text.contains(L.t("UI_CANCEL")): return "back"
	if text.contains(L.t("UI_BUY")): return "" # success is routed by the real transaction
	if text.contains(L.t("UI_START")) or text.contains(L.t("UI_PLAY")) or text.contains(L.t("UI_BEGIN")): return "confirm"
	return "click"

func bind_ui(root: Node) -> void:
	for child in root.get_children(): bind_ui(child)
	if root is BaseButton and not root.has_meta("audio_bound"):
		root.set_meta("audio_bound",true)
		root.pressed.connect(func() -> void:
			var event := ui_event(root)
			if event!="": common(event))
