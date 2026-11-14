class_name RobotSoundSet
extends RefCounted
## v37: per-robot sound identity (res://config/audio/robot_sound_sets.json). Gameplay code only reports
## authoritative events (landing, body hit, damage, detach, death, rocket ignition / burn-out / head bump) with their
## physical impact; this maps event -> family, intensity, layers and anti-spam. Audio only: reads no physics,
## writes nothing outside itself, and uses GameAudio's private RNG (never the gameplay RNG).
const PATH := "res://config/audio/robot_sound_sets.json"
const REPEAT_WINDOW := 0.6
const LOG_MAX := 512
static var _sets: Dictionary = {}
static var _loaded := false
## A/B / determinism tests: true = every robot uses the v27 bank profile path.
static var debug_disabled := false

var robot_id := ""
var cfg: Dictionary = {}
var audio: GameAudio
var owner_key := ""
var _last: Dictionary = {}      # key -> [clock, intensity]
var _repeat: Dictionary = {}    # event -> [clock, n]
## Test telemetry: [event, intensity, level] of every sound actually started (capped).
var fired: Array = []
## v39: 1.0 for the player, RobotAudioFeedback.NPC_ONESHOT_GAIN for rivals.
var gain_scale := 1.0
var suppressed := 0


static func config_for(id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		if data is Dictionary:
			_sets = data
	var c: Variant = _sets.get(id, {})
	return c if c is Dictionary else {}


## null when the robot has no v37 set (it keeps the v27 profile path).
static func for_robot(id: String, a: GameAudio, key: String) -> RobotSoundSet:
	if debug_disabled or a == null:
		return null
	var c := config_for(id)
	if c.is_empty():
		return null
	var s := RobotSoundSet.new()
	s.robot_id = id; s.cfg = c; s.audio = a; s.owner_key = key
	return s


func has(ev: String) -> bool:
	return (cfg.get("events", {}) as Dictionary).has(ev)


func spec(ev: String) -> Dictionary:
	return (cfg.get("events", {}) as Dictionary).get(ev, {})


func setting(name: String, fallback: Variant) -> Variant:
	return cfg.get(name, fallback)


## 0..1 from the physical impact (px/s); -1 = below the audible threshold.
func intensity(ev: String, impact: float) -> float:
	var e := spec(ev)
	var lo := float(e.get("min", 0.0))
	if impact < lo:
		return -1.0
	return clampf((impact - lo) / maxf(float(e.get("full", 1.0)) - lo, 0.001), 0.0, 1.0)


## Plays `ev` for a physical impact. Returns true when a sound started.
func trigger(ev: String, impact: float, point: Vector2) -> bool:
	var e := spec(ev)
	if e.is_empty():
		return false
	var i := intensity(ev, impact)
	if i < 0.0:
		return false
	var esc := String(e.get("escalate", ""))
	if esc != "" and intensity(esc, impact) >= 0.0:
		return trigger(esc, impact, point)
	var now := audio.clock
	var key := String(e.get("key", ev))
	var cd := float(e.get("cooldown", 0.12))
	if _last.has(key):
		var prev: Array = _last[key]
		if now - float(prev[0]) < cd and i < float(prev[1]) + float(cfg.get("break_through", 0.35)):
			suppressed += 1
			return false
	var r: Array = _repeat.get(ev, [-100.0, -1])
	var n := mini(int(r[1]) + 1, 4) if now - float(r[0]) < REPEAT_WINDOW else 0
	_repeat[ev] = [now, n]
	var g: Array = e.get("gain", [0.6, 1.0])
	var level := lerpf(float(g[0]), float(g[1]), i) * pow(float(e.get("repeat_duck", 0.82)), n) * gain_scale
	var pv := float(cfg.get("pitch_var", 0.025))
	if not audio.play_level(String(e.family), i, level, point, pv):
		return false
	_last[key] = [now, i]
	for layer in e.get("layers", []):
		if i >= float(layer.get("from", 0.0)):
			audio.play_level(String(layer.family), i, level * float(layer.get("gain", 1.0)), point, pv)
	if fired.size() < LOG_MAX:
		fired.append([ev, snappedf(i, 0.001), snappedf(level, 0.001)])
	return true


func count(ev: String) -> int:
	var n := 0
	for f in fired:
		n += int(f[0] == ev)
	return n
