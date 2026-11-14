class_name ProfileManager
extends RefCounted
## v31: three independent player profiles (save slots) on top of the existing ProfileStore / StatsStore files.
##
## Layout (root = "user://" for players, a test folder for the debug harness):
##   <root>profiles/index.json          app-level: format version, legacy migration marker, last used slot
##   <root>profiles/.legacy_migrated    second, independent migration marker (survives a broken index.json)
##   <root>profiles/slot_N/slot.json    slot marker: the slot is occupied iff this file exists
##   <root>profiles/slot_N/profile.json ProfileStore of that player (coins, robots, campaign, stars, skins, tutorial...)
##   <root>profiles/slot_N/stats.json   StatsStore of that player (record, statistics, recent runs)
## Legacy (pre-v31, one global save): <root>profile.json, <root>stats.json, <root>progress.cfg (v0.1 best distance).
## They are COPIED once into slot 1 and never touched again (kept as the original backup); the two markers make the
## import one-time, so deleting PLAYER 1 later can never bring the old save back.
## Everything profile-specific lives in the slot folder: a future per-player system just adds a field to
## profile.json or another file next to it (see AI_HANDOFF v31).

const SLOTS := 3
const VERSION := 1
const LEGACY_FILES := ["profile.json", "stats.json", "progress.cfg"]

var root := "user://"
var index := {}
var last_migration := ""        # "", "migrated", "nothing", "already" (diagnostics / tests)


func _init(p_root := "user://") -> void:
	root = p_root if p_root.ends_with("/") else p_root + "/"
	DirAccess.make_dir_recursive_absolute(dir_path())
	_load_index()


# ---------------- paths ----------------

func dir_path() -> String:
	return root + "profiles"


func slot_dir(slot: int) -> String:
	return dir_path() + "/slot_%d" % slot


func profile_path(slot: int) -> String:
	return slot_dir(slot) + "/profile.json"


func stats_path(slot: int) -> String:
	return slot_dir(slot) + "/stats.json"


func _marker_path(slot: int) -> String:
	return slot_dir(slot) + "/slot.json"


func _index_path() -> String:
	return dir_path() + "/index.json"


func _flag_path() -> String:
	return dir_path() + "/.legacy_migrated"


static func valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOTS


static func slot_name(slot: int) -> String:
	return L.t("PROF_SLOT") % slot


# ---------------- slots ----------------

func exists(slot: int) -> bool:
	return valid_slot(slot) and FileAccess.file_exists(_marker_path(slot))


## Creates an empty slot (no-op for an occupied one). The profile / stats files are written by their stores.
func create(slot: int) -> bool:
	if not valid_slot(slot):
		return false
	if exists(slot):
		return true
	DirAccess.make_dir_recursive_absolute(slot_dir(slot))
	return _write_json(_marker_path(slot), {"version": VERSION, "slot": slot,
		"created": Time.get_datetime_string_from_system(false, true)})


## Deletes ONLY that slot's folder content. Other slots and the app-level index are untouched (except last_slot).
func delete(slot: int) -> bool:
	if not valid_slot(slot):
		return false
	var d := slot_dir(slot)
	var dir := DirAccess.open(d)
	if dir != null:
		# the marker goes first: a half-deleted slot reads as empty, never as a damaged occupied one
		if FileAccess.file_exists(_marker_path(slot)):
			dir.remove("slot.json")
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(d))
	if int(index.get("last_slot", 0)) == slot:
		index.last_slot = 0
		_save_index()
	return not exists(slot)


func last_slot() -> int:
	var s := int(index.get("last_slot", 0))
	return s if exists(s) else 0


## App-level UX data only (which card to highlight); never used to skip the profile screen.
func set_last_slot(slot: int) -> void:
	if valid_slot(slot) and int(index.get("last_slot", 0)) != slot:
		index.last_slot = slot
		_save_index()


## Short card summary straight from the slot files (read-only: never repairs / rewrites anything).
func summary(slot: int) -> Dictionary:
	var out := {"slot": slot, "name": slot_name(slot), "exists": exists(slot), "round": 0, "stars": 0, "coins": 0, "best_m": 0.0}
	if not out.exists:
		return out
	var p := _read_json(profile_path(slot))
	if typeof(p.get("coins")) in [TYPE_INT, TYPE_FLOAT]:
		out.coins = maxi(int(p.coins), 0)
	var cp = p.get("campaign", {})
	if typeof(cp) == TYPE_DICTIONARY:
		var best := 0
		var unlocked = cp.get("unlocked", [])
		if typeof(unlocked) == TYPE_ARRAY:
			for id in unlocked:
				var s := String(id)
				if s.begins_with("r") and s.substr(1).is_valid_int():
					best = maxi(best, int(s.substr(1)))
		out.round = maxi(best, 1)
		var stars = cp.get("stars", {})
		if typeof(stars) == TYPE_DICTIONARY:
			for id in stars:
				if typeof(stars[id]) == TYPE_ARRAY:
					for f in stars[id]:
						out.stars += int(f == true)
	else:
		out.round = 1
	var st := _read_json(stats_path(slot))
	if typeof(st.get("best_m")) in [TYPE_INT, TYPE_FLOAT]:
		out.best_m = maxf(float(st.best_m), 0.0)
	return out


# ---------------- legacy migration ----------------

func migrated() -> bool:
	return bool(index.get("legacy_migrated", false)) or FileAccess.file_exists(_flag_path())


## One-time import of the pre-v31 global save into PLAYER 1. Safe to call on every launch.
##   * already done (either marker)         -> nothing
##   * no legacy files                      -> markers only (a later legacy file is NOT imported: it can't exist
##                                             legitimately after v31, the game never writes it again)
##   * legacy files + slot 1 empty          -> copy them into slot 1, verify, then write both markers
##   * legacy files + slot 1 already exists -> slot 1 is kept (never overwritten), markers only
## The legacy files themselves are never modified or deleted.
func migrate_legacy() -> String:
	if migrated():
		if not bool(index.get("legacy_migrated", false)):
			index.legacy_migrated = true
			_save_index()
		last_migration = "already"
		return last_migration
	var found: Array = []
	for f in LEGACY_FILES:
		if FileAccess.file_exists(root + f):
			found.append(f)
	var result := "nothing"
	if not found.is_empty() and not exists(1):
		DirAccess.make_dir_recursive_absolute(slot_dir(1))
		var ok := true
		if found.has("profile.json"):
			ok = ok and _copy_verified(root + "profile.json", profile_path(1))
		if found.has("stats.json"):
			ok = ok and _copy_verified(root + "stats.json", stats_path(1))
		elif found.has("progress.cfg"):
			# v0.1 save: only a best distance -> converted by StatsStore's own legacy import
			var st := StatsStore.new(stats_path(1))
			st.legacy_path = root + "progress.cfg"
			st.load_data()
			ok = ok and st.save()
		if not ok:
			# leave no half slot behind; the markers are not written, so the next launch retries
			for f in ["profile.json", "stats.json", "profile.json.tmp", "stats.json.tmp"]:
				if FileAccess.file_exists(slot_dir(1) + "/" + f):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_dir(1) + "/" + f))
			last_migration = "failed"
			return last_migration
		_write_json(_marker_path(1), {"version": VERSION, "slot": 1, "migrated_from": found,
			"created": Time.get_datetime_string_from_system(false, true)})
		index.last_slot = 1
		result = "migrated"
	elif not found.is_empty():
		result = "slot1_kept"
	index.legacy_migrated = true
	index.legacy_result = result
	index.legacy_files = found
	index.migrated_at = Time.get_datetime_string_from_system(false, true)
	_save_index()
	var f := FileAccess.open(_flag_path(), FileAccess.WRITE)
	if f:
		f.store_string(result)
		f.close()
	last_migration = result
	return result


func _copy_verified(src: String, dst: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(src)
	var tmp := dst + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	if FileAccess.get_file_as_bytes(tmp) != bytes:
		return false
	var dir := DirAccess.open(dst.get_base_dir())
	return dir != null and dir.rename(tmp.get_file(), dst.get_file()) == OK


# ---------------- index (app-level) ----------------

func _load_index() -> void:
	index = {"version": VERSION, "legacy_migrated": false, "last_slot": 0}
	var p := _index_path()
	if not FileAccess.file_exists(p):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		var dir := DirAccess.open(dir_path())
		if dir:
			dir.copy(p, p + ".corrupt")
		return
	var src: Dictionary = json.data
	index.legacy_migrated = src.get("legacy_migrated", false) == true
	if typeof(src.get("last_slot")) in [TYPE_INT, TYPE_FLOAT] and valid_slot(int(src.last_slot)):
		index.last_slot = int(src.last_slot)
	for k in ["legacy_result", "legacy_files", "migrated_at"]:
		if src.has(k):
			index[k] = src[k]


func _save_index() -> bool:
	index.version = VERSION
	return _write_json(_index_path(), index)


## Atomic JSON write: .tmp, then rename over the destination (a failed write keeps the old file).
func _write_json(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	return dir != null and dir.rename(tmp.get_file(), path.get_file()) == OK


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data
