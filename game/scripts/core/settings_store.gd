class_name SettingsStore
extends RefCounted
## Player settings (user://settings.json). Every value is clamped to its range and snapped to its step on load
## and on change; a missing / broken / outdated file falls back to defaults (broken file kept as .corrupt).

const VERSION := 2
const GAMEPLAY_TUNING_VERSION := 1
var gameplay_tuning_version := GAMEPLAY_TUNING_VERSION
var unrelated := {}

## key -> [min, max, step, default]
const SPEC := {
	"auto_rps": [0.25, 2.5, 0.05, 0.9],      # automatic clockwise spin when the screen is released (rev/s)
	"manual_rps": [0.25, 2.0, 0.05, 1.1],   # counter-clockwise spin while the screen is held (rev/s)
	"invuln_s": [0.1, 2.0, 0.05, 0.7],       # invulnerability after a hit (s)
	"shake": [0.0, 100.0, 5.0, 90.0],         # screen shake strength (%), 0 = off
	"vibration": [0.0, 100.0, 5.0, 100.0],     # Android discrete impact pulses (%), independent of shake
	"flick": [50.0, 200.0, 5.0, 200.0],       # initial flick strength (% of the v0.8 launch speed)
	"spin_accel": [0.0, 0.5, 0.05, 0.3],      # auto spin +rev/s per completed automatic turn (v36: 0.4 -> 0.3)
	"recovery_s": [0.0, 1.0, 0.05, 0.7],      # auto-spin recovery after a manual correction (s)
	"recovery_pct": [0.0, 100.0, 5.0, 25.0],  # recovery start speed, % of the auto speed before the hold
	"spring_power": [75.0, 200.0, 5.0, 200.0], # spring return energy, relative to v12
	"bounce_spin": [0.0, 100.0, 5.0, 0.0],   # angular response of ground contacts (% of v0.9.1 physics)
}

## v34 RELEASE GAMEPLAY BASELINE (phone-tested, approved): fixed, not player-adjustable. Old saves, set_value and
## "ПО УМОЛЧАНИЮ" can never change them. Only the debug harness may override them (debug_set_physics) for tests.
const FIXED := {
	"auto_rps": 0.9, "manual_rps": 1.1, "invuln_s": 0.7, "flick": 200.0,
	"spin_accel": 0.3, "recovery_s": 0.7, "recovery_pct": 25.0, "bounce_spin": 0.0, "spring_power": 200.0,
}
## Presentation / accessibility settings that stay player-adjustable (defaults = the approved phone values).
const USER_DEFAULTS := {"shake": 90.0, "vibration": 100.0}

var path := "user://settings.json"
var values := {}
var last_load_status := ""


static func is_fixed(key: String) -> bool:
	return FIXED.has(key)


func _init(p_path := "user://settings.json") -> void:
	path = p_path
	reset_to_defaults()


static func spec(key: String) -> Array:
	return SPEC[key]


static func sanitize(key: String, v) -> float:
	var s: Array = SPEC[key]
	if not (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) or not is_finite(float(v)):
		return s[3]
	var x := clampf(float(v), s[0], s[1])
	# snap to the step grid that starts at min (0.25 + n*0.05 ...)
	x = s[0] + roundf((x - s[0]) / s[2]) * s[2]
	return snappedf(clampf(x, s[0], s[1]), 0.0001)


func reset_to_defaults() -> void:
	for k in SPEC:
		values[k] = float(FIXED[k]) if FIXED.has(k) else float(USER_DEFAULTS.get(k, SPEC[k][3]))


func get_value(key: String) -> float:
	return values[key]


## Returns the stored (clamped + snapped) value. Fixed release physics are refused (stay at FIXED).
func set_value(key: String, v: float) -> float:
	if FIXED.has(key):
		values[key] = float(FIXED[key])
		return values[key]
	values[key] = sanitize(key, v)
	return values[key]


## Debug harness only (GameManager allows it in autotest): physics sweeps in tests. Never persisted as player data
## because load_data() re-forces FIXED.
func debug_set_physics(key: String, v: float) -> float:
	values[key] = sanitize(key, v)
	return values[key]


## v34: app-global language choice ("auto" or a supported locale code), stored next to the other settings (never
## in a profile). Unknown / broken values read as "auto". "ПО УМОЛЧАНИЮ" does not touch it.
func language() -> String:
	var v = unrelated.get("language", L.AUTO)
	if typeof(v) == TYPE_STRING and (v == L.AUTO or v in L.codes()):
		return v
	return L.AUTO


func set_language(choice: String) -> void:
	unrelated["language"] = choice if (choice == L.AUTO or choice in L.codes()) else L.AUTO


func load_data() -> void:
	unrelated = {}
	gameplay_tuning_version = GAMEPLAY_TUNING_VERSION
	reset_to_defaults()
	if not FileAccess.file_exists(path):
		last_load_status = "missing"
		return
	var json := JSON.new()
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "" or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		last_load_status = "corrupt"
		var dir := DirAccess.open(path.get_base_dir())
		if dir:
			dir.copy(path, path + ".corrupt")
		return
	var src: Dictionary = json.data
	var fixed := int(src.get("version", 0)) != VERSION
	for key in src:
		if not SPEC.has(key) and key not in ["version", "gameplay_tuning_version"]:
			unrelated[key] = src[key]
	var tuning = src.get("gameplay_tuning_version",0)
	var old_tuning := int(tuning) if typeof(tuning) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(tuning)) else 0
	for k in SPEC:
		if src.has(k):
			var clean := sanitize(k, src[k])
			if typeof(src[k]) not in [TYPE_FLOAT, TYPE_INT] or not is_equal_approx(clean, float(src[k])):
				fixed = true
			values[k] = clean
	# v34: release physics are fixed - stored custom values (old builds) can never override them
	for k in FIXED:
		if not is_equal_approx(float(values[k]), float(FIXED[k])):
			fixed = true
		values[k] = float(FIXED[k])
	last_load_status = "repaired" if fixed else "ok"
	if old_tuning < GAMEPLAY_TUNING_VERSION:
		# Explicit product migration: only the eleven defined gameplay values are forced once.
		reset_to_defaults()
		last_load_status = "migrated" if save() else "migration_save_failed"


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	var out := unrelated.duplicate(true)
	out.merge(values,true)
	out["gameplay_tuning_version"] = gameplay_tuning_version
	out["version"] = VERSION
	f.store_string(JSON.stringify(out, "\t"))
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		return false
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	return dir.rename(tmp.get_file(), path.get_file()) == OK
