class_name StatsStore
extends RefCounted
## Local, offline player statistics (JSON in user:// - works on Android and desktop).
##
## Robust by design:
##   * missing file      -> defaults (and a one-time import of the old v0.1 "progress.cfg" best distance)
##   * unreadable / bad JSON -> the file is kept as "<name>.corrupt" for inspection, defaults are used
##   * wrong / missing fields or an older version -> every field is validated and repaired individually
##   * saving writes "<name>.tmp" first and then swaps it in, so a crash mid-write cannot destroy the data
## One finished attempt is recorded exactly once (record_attempt() ignores a repeated attempt id).

const VERSION := 1
const RECENT_MAX := 10
const LEGACY_CFG := "user://progress.cfg"

var path := "user://stats.json"
var data := {}
var last_load_status := ""      # "ok", "missing", "corrupt", "repaired", "migrated"
var _saved_ids := {}
## Old v0.1 save to import the best distance from (only for the real player file; tests point it elsewhere).
var legacy_path := ""


func _init(p_path := "user://stats.json") -> void:
	path = p_path
	data = defaults()


static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"best_m": 0.0,
		"attempts": 0,
		"total_m": 0.0,
		"good_landings": 0,
		"bad_landings": 0,
		"best_attempt_charge": 0.0,   # highest spin charge reached in a single attempt (0..1)
		"full_charge_bounces": 0,     # landings that released a 100% charge
		"boosted_bounces": 0,         # landings that released any charge
		"total_time_s": 0.0,
		"recent": [],                 # newest first, max RECENT_MAX
	}


# ---------------- load ----------------

func load_data() -> void:
	data = defaults()
	if not FileAccess.file_exists(path):
		last_load_status = "missing"
		_import_legacy()
		return
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if text.strip_edges() == "" or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		last_load_status = "corrupt"
		_keep_corrupt_copy()
		return
	var repaired := _apply(json.data)
	last_load_status = "repaired" if repaired else "ok"


## Copies validated fields from `src` into data. Returns true if anything had to be fixed.
func _apply(src: Dictionary) -> bool:
	var fixed := int(src.get("version", 0)) != VERSION
	for key in ["best_m", "total_m", "total_time_s"]:
		var v = src.get(key)
		if _is_num(v) and float(v) >= 0.0 and is_finite(float(v)):
			data[key] = float(v)
		elif src.has(key):
			fixed = true
	for key in ["attempts", "good_landings", "bad_landings", "full_charge_bounces", "boosted_bounces"]:
		var v = src.get(key)
		if _is_num(v) and float(v) >= 0.0:
			data[key] = int(v)
		elif src.has(key):
			fixed = true
	var c = src.get("best_attempt_charge")
	if _is_num(c):
		data.best_attempt_charge = clampf(float(c), 0.0, 1.0)
	elif src.has("best_attempt_charge"):
		fixed = true
	var rec = src.get("recent")
	if typeof(rec) == TYPE_ARRAY:
		for e in rec:
			var clean := _clean_entry(e)
			if clean.is_empty():
				fixed = true
			elif data.recent.size() < RECENT_MAX:
				data.recent.append(clean)
	elif src.has("recent"):
		fixed = true
	# the record can never be below a stored result
	for e in data.recent:
		if e.distance_m > data.best_m:
			data.best_m = e.distance_m
			fixed = true
	return fixed


static func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _clean_entry(e) -> Dictionary:
	if typeof(e) != TYPE_DICTIONARY or not _is_num(e.get("distance_m")):
		return {}
	var d := float(e.distance_m)
	if d < 0.0 or not is_finite(d):
		return {}
	return {
		"distance_m": d,
		"duration_s": maxf(float(e.get("duration_s", 0.0)) if _is_num(e.get("duration_s")) else 0.0, 0.0),
		"landings": maxi(int(e.get("landings", 0)) if _is_num(e.get("landings")) else 0, 0),
		"good": maxi(int(e.get("good", 0)) if _is_num(e.get("good")) else 0, 0),
		"bad": maxi(int(e.get("bad", 0)) if _is_num(e.get("bad")) else 0, 0),
		"max_charge": clampf(float(e.get("max_charge", 0.0)) if _is_num(e.get("max_charge")) else 0.0, 0.0, 1.0),
		"boosted": maxi(int(e.get("boosted", 0)) if _is_num(e.get("boosted")) else 0, 0),
		"record": bool(e.get("record", false)),
		"seed": int(e.get("seed", 0)) if _is_num(e.get("seed")) else 0,
		"time": str(e.get("time", "")),
	}


func _keep_corrupt_copy() -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir:
		dir.copy(path, path + ".corrupt")


func _import_legacy() -> void:
	if legacy_path == "" or not FileAccess.file_exists(legacy_path):
		return
	var cf := ConfigFile.new()
	if cf.load(legacy_path) == OK:
		var b = cf.get_value("progress", "best_m", 0.0)
		if _is_num(b) and float(b) > 0.0:
			data.best_m = float(b)
			last_load_status = "migrated"


# ---------------- save ----------------

func save() -> bool:
	if path == "":
		return true   # v31: in-memory placeholder while no player profile is active: never written
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("StatsStore: cannot write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


# ---------------- recording ----------------

## Records a finished attempt once. attempt: id (unique per attempt), distance_m, duration_s, landings,
## good, bad, max_charge, boosted, full_boosts. Returns {"record": bool, "best_m": float, "saved": bool}.
func record_attempt(attempt: Dictionary) -> Dictionary:
	var id := str(attempt.get("id", ""))
	if id != "" and _saved_ids.has(id):
		return {"record": false, "best_m": data.best_m, "saved": false, "duplicate": true}
	_saved_ids[id] = true
	var d := maxf(float(attempt.get("distance_m", 0.0)), 0.0)
	var record := d > float(data.best_m) + 0.0001
	if record:
		data.best_m = d
	data.attempts = int(data.attempts) + 1
	data.total_m = float(data.total_m) + d
	data.total_time_s = float(data.total_time_s) + maxf(float(attempt.get("duration_s", 0.0)), 0.0)
	data.good_landings = int(data.good_landings) + int(attempt.get("good", 0))
	data.bad_landings = int(data.bad_landings) + int(attempt.get("bad", 0))
	data.boosted_bounces = int(data.boosted_bounces) + int(attempt.get("boosted", 0))
	data.full_charge_bounces = int(data.full_charge_bounces) + int(attempt.get("full_boosts", 0))
	data.best_attempt_charge = maxf(float(data.best_attempt_charge), clampf(float(attempt.get("max_charge", 0.0)), 0.0, 1.0))
	var entry := _clean_entry({"distance_m": d, "duration_s": attempt.get("duration_s", 0.0),
		"landings": attempt.get("landings", 0), "good": attempt.get("good", 0), "bad": attempt.get("bad", 0),
		"max_charge": attempt.get("max_charge", 0.0), "boosted": attempt.get("boosted", 0), "record": record,
		"seed": attempt.get("seed", 0),
		"time": Time.get_datetime_string_from_system(false, true)})
	data.recent.push_front(entry)
	while data.recent.size() > RECENT_MAX:
		data.recent.pop_back()
	var ok := save()
	return {"record": record, "best_m": data.best_m, "saved": ok}


## v32: the GLOBAL distance record counts every normal mode. Campaign attempts only offer their distance here
## (record only: campaign runs are not added to the Free Run statistics). Returns true on a new record.
func submit_best(distance_m: float) -> bool:
	var d := maxf(distance_m, 0.0)
	if not is_finite(d) or d <= float(data.best_m) + 0.0001:
		return false
	data.best_m = d
	save()
	return true


func best_m() -> float:
	return float(data.best_m)
