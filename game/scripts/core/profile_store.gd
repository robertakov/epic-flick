class_name ProfileStore
extends RefCounted
## Player progression (user://profile.json): coins, owned robots, selected robot, campaign progress and the hidden
## adaptive-difficulty state. Free in-game currency only.
## Same robustness rules as SettingsStore/StatsStore: missing -> defaults, broken -> kept as .corrupt + defaults,
## bad fields repaired one by one, writes via .tmp + rename. Starter robots are always owned.
## v1 -> v2 migration: v1 files (coins / owned / selected only) load unchanged; campaign + adaptive + skins start fresh.
## Skins are cosmetic: owned_skins = non-default skins the player has (default skins are always owned),
## equipped_skins = archetype id -> skin id.

const VERSION := 5
## Optional v36.5 extension; keeps the existing v5 wallet/migration semantics.
var achievements := AchievementState.defaults()
const SOURCE_CAMPAIGN := "CAMPAIGN"
const SOURCE_FREE_RUN := "FREE_RUN"
var star_wallet := default_wallet()
var free_run := {"sequence": 0, "set": {}}

## v32 secret Exclusion Zone artifact of THIS player: found once (tap), then optionally equipped (+15% whitelist).
static func default_artifact() -> Dictionary:
	return {"discovered": false, "equipped": false}
var artifact := default_artifact()

## Missing flags in old saves offer the skippable new tutorial once, preserving all progress.
var tutorial := {"handled": false, "completed": false}

var path := "user://profile.json"
var coins := 0
var owned: Array[String] = []
var selected := ""
var last_load_status := ""
var loaded_version := 0
## Campaign progress. node ids are strings from the campaign graph.
##   unlocked / completed / claimed: node id lists (claimed = first-clear reward paid)
##   replay_wins: id -> wins after the first clear (replay reward decay)
##   attempts: id -> finished attempts on that node (until its first clear)
var campaign := {}
## Hidden adaptive difficulty state (see AdaptiveDifficulty): never shown to the player.
var adaptive := {}
var owned_skins: Array[String] = []
## v35 MK2 (per profile): archetype ids whose MK2 was bought, and which archetypes currently play as MK2.
## Eligibility is NOT stored: it is derived from campaign completion (RobotDefinition.mk2_boss_node).
var mk2_owned: Array[String] = []
var mk2_selected := {}
var equipped_skins := {}
## Optional: skin id -> robot id of every known skin (validation on load / equip). Set by GameManager.
var skin_index := {}
var _starters: Array[String] = []
var _valid_ids: Array[String] = []


func _init(p_path := "user://profile.json", catalog: RobotCatalog = null, skins: SkinCatalog = null) -> void:
	path = p_path
	if skins:
		for s in skins.skins:
			skin_index[s.id] = s.robot_id
	if catalog:
		_starters = catalog.starter_ids()
		for d in catalog.robots:
			_valid_ids.append(d.id)
	reset()


static func default_campaign() -> Dictionary:
	return {"unlocked": [], "completed": [], "claimed": [], "replay_wins": {}, "attempts": {}, "stars": {}, "star_claimed": {}}


static func default_wallet() -> Dictionary:
	return {"earned": 0, "available": 0, "spent": 0, "sources": {}, "last_spend_reason": ""}


func reset() -> void:
	achievements = AchievementState.defaults()
	star_wallet = default_wallet()
	free_run = {"sequence": 0, "set": {}}
	tutorial = {"handled": false, "completed": false}
	artifact = default_artifact()
	coins = 0
	owned = _starters.duplicate()
	selected = _starters[0] if not _starters.is_empty() else ""
	campaign = default_campaign()
	adaptive = AdaptiveDifficulty.default_state()
	owned_skins = []
	equipped_skins = {}
	mk2_owned = []
	mk2_selected = {}


func load_data() -> void:
	reset()
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
	achievements = AchievementState.sanitize(src.get("achievements", {}))
	loaded_version = int(src.get("version", 0)) if _num(src.get("version")) else 0
	var fixed := loaded_version != VERSION
	var c = src.get("coins")
	if _num(c) and is_finite(float(c)) and float(c) >= 0.0:
		coins = int(c)
	elif src.has("coins"):
		fixed = true
	var o = src.get("owned")
	if typeof(o) == TYPE_ARRAY:
		for id in o:
			if typeof(id) == TYPE_STRING and (_valid_ids.is_empty() or _valid_ids.has(id)):
				if not owned.has(id):
					owned.append(id)
			else:
				fixed = true
	elif src.has("owned"):
		fixed = true
	var s = src.get("selected")
	if typeof(s) == TYPE_STRING and owned.has(s):
		selected = s
	elif src.has("selected"):
		fixed = true
	var cp = src.get("campaign")
	if typeof(cp) == TYPE_DICTIONARY:
		for key in ["unlocked", "completed", "claimed"]:
			var arr = cp.get(key)
			if typeof(arr) == TYPE_ARRAY:
				for id in arr:
					if typeof(id) == TYPE_STRING and not campaign[key].has(id):
						campaign[key].append(id)
					elif typeof(id) != TYPE_STRING:
						fixed = true
			elif cp.has(key):
				fixed = true
		for key in ["replay_wins", "attempts"]:
			var d = cp.get(key)
			if typeof(d) == TYPE_DICTIONARY:
				for id in d:
					if typeof(id) == TYPE_STRING and _num(d[id]) and float(d[id]) >= 0.0:
						campaign[key][id] = int(d[id])
					else:
						fixed = true
			elif cp.has(key):
				fixed = true
		for key in ["stars", "star_claimed"]:
			var rows = cp.get(key, {})
			if typeof(rows) == TYPE_DICTIONARY:
				for id in rows:
					if not _star_node(String(id)) or typeof(rows[id]) != TYPE_ARRAY:
						fixed = true
						continue
					var flags := [false, false, false]
					for i in mini(3, rows[id].size()):
						if typeof(rows[id][i]) == TYPE_BOOL:
							flags[i] = rows[id][i]
						else:
							fixed = true
					campaign[key][id] = flags
			else:
				fixed = true
		# Repair either half of an earned/paid record conservatively: retain ownership,
		# never replay a payment whose claim flag or owned flag survived.
		for id in campaign.stars.keys() + campaign.star_claimed.keys():
			var flags := [false, false, false]
			for i in 3:
				flags[i] = bool(campaign.stars.get(id, [false, false, false])[i]) or bool(campaign.star_claimed.get(id, [false, false, false])[i])
			campaign.stars[id] = flags.duplicate()
			campaign.star_claimed[id] = flags.duplicate()
		if campaign.completed.has("r40") and not campaign.unlocked.has("r41"):
			campaign.unlocked.append("r41")
	elif src.has("campaign"):
		fixed = true
	var os = src.get("owned_skins")
	if typeof(os) == TYPE_ARRAY:
		for id in os:
			if typeof(id) == TYPE_STRING and (skin_index.is_empty() or skin_index.has(id)) and not owned_skins.has(id):
				owned_skins.append(id)
			else:
				fixed = true
	elif src.has("owned_skins"):
		fixed = true
	var es = src.get("equipped_skins")
	if typeof(es) == TYPE_DICTIONARY:
		for rid in es:
			var sid = es[rid]
			if typeof(rid) == TYPE_STRING and typeof(sid) == TYPE_STRING and owns_skin(sid) and (skin_index.is_empty() or skin_index.get(sid, "") == String(rid).trim_suffix("_mk2")):
				equipped_skins[rid] = sid
			else:
				fixed = true
	elif src.has("equipped_skins"):
		fixed = true
	# v35 MK2 (optional keys: older saves simply have none)
	var mo = src.get("mk2_owned")
	if typeof(mo) == TYPE_ARRAY:
		for id in mo:
			if typeof(id) == TYPE_STRING and (_valid_ids.is_empty() or _valid_ids.has(id)) and owned.has(id) and not mk2_owned.has(id):
				mk2_owned.append(id)
			else:
				fixed = true
	elif src.has("mk2_owned"):
		fixed = true
	var ms = src.get("mk2_selected")
	if typeof(ms) == TYPE_DICTIONARY:
		for id in ms:
			if typeof(id) == TYPE_STRING and typeof(ms[id]) == TYPE_BOOL and mk2_owned.has(id):
				mk2_selected[id] = ms[id]
			else:
				fixed = true
	elif src.has("mk2_selected"):
		fixed = true
	var ad = src.get("adaptive")
	if typeof(ad) == TYPE_DICTIONARY:
		adaptive = AdaptiveDifficulty.sanitize_state(ad)
	elif src.has("adaptive"):
		fixed = true
	var tut = src.get("tutorial",{})
	if typeof(tut)==TYPE_DICTIONARY:
		for key in ["handled","completed"]:
			if typeof(tut.get(key))==TYPE_BOOL:
				tutorial[key]=tut[key]
			elif tut.has(key):
				fixed=true
		if tutorial.completed:
			tutorial.handled=true
	else:
		fixed=true
	var art = src.get("artifact", {})
	if typeof(art) == TYPE_DICTIONARY:
		artifact.discovered = art.get("discovered", false) == true
		# equipped only makes sense once discovered
		artifact.equipped = artifact.discovered and art.get("equipped", false) == true
	else:
		fixed = true

	# Historical ownership is credited only by the versioned migration, never on v5 reload.
	if loaded_version < 5:
		_credit_stars(total_stars(), SOURCE_CAMPAIGN)
	else:
		var wallet = src.get("star_wallet", {})
		if typeof(wallet) == TYPE_DICTIONARY:
			var earned := _safe_int(wallet.get("earned", 0))
			var spent := mini(earned, _safe_int(wallet.get("spent", 0)))
			star_wallet.earned = earned
			star_wallet.spent = spent
			star_wallet.available = earned - spent
			var sources = wallet.get("sources", {})
			if typeof(sources) == TYPE_DICTIONARY:
				for source in sources:
					if typeof(source) == TYPE_STRING and source.length() <= 64:
						star_wallet.sources[source] = _safe_int(sources[source])
			star_wallet.last_spend_reason = String(wallet.get("last_spend_reason", "")).left(160)
			fixed = fixed or star_wallet != wallet
		else:
			fixed = true # Malformed v5 wallet does not replay historical grants.
		var fr = src.get("free_run", {})
		if typeof(fr) == TYPE_DICTIONARY:
			free_run.sequence = _safe_int(fr.get("sequence", 0))
			if typeof(fr.get("set", {})) == TYPE_DICTIONARY:
				free_run.set = fr.get("set", {}).duplicate(true)
				if FreeChallenges.valid_set(free_run.set):
					free_run.sequence = maxi(int(free_run.sequence), int(free_run.set.id))
	last_load_status = "repaired" if fixed else "ok"
	if loaded_version < 5:
		if not save():
			last_load_status = "migration_save_failed"

static func _safe_int(v) -> int:
	return int(clampf(float(v), 0.0, 1000000000.0)) if _num(v) and is_finite(float(v)) else 0



static func _num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func save() -> bool:
	if path == "":
		return true   # v31: in-memory placeholder while no player profile is active (profile screen): never written
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": VERSION, "coins": coins, "owned": owned, "selected": selected,
		"star_wallet": star_wallet, "free_run": free_run, "tutorial": tutorial, "campaign": campaign, "adaptive": adaptive, "owned_skins": owned_skins, "equipped_skins": equipped_skins,
		"achievements": achievements, "artifact": artifact, "mk2_owned": mk2_owned, "mk2_selected": mk2_selected}, "\t"))
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		return false
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	# Replace the destination directly; a failed rename must leave the old profile available.
	return dir.rename(tmp.get_file(), path.get_file()) == OK


func is_owned(id: String) -> bool:
	return owned.has(id)


## Buys a robot. Returns "ok", "owned", "coins" (not enough) or "unknown".
func buy(def: RobotDefinition) -> String:
	if def == null:
		return "unknown"
	if owned.has(def.id):
		return "owned"
	if coins < def.price:
		return "coins"
	coins -= def.price
	owned.append(def.id)
	save()
	return "ok"


## v35 MK2: purchasable once the archetype's boss node is completed in THIS profile.
func mk2_eligible(def: RobotDefinition) -> bool:
	return def != null and def.has_mk2() and def.mk2_boss_node != "" and is_completed(def.mk2_boss_node)


func owns_mk2(id: String) -> bool:
	return mk2_owned.has(id)


## Plays as MK2 right now (owned AND chosen; base and MK2 stay independently selectable).
func mk2_active(id: String) -> bool:
	return owns_mk2(id) and bool(mk2_selected.get(id, false))


## Buys an MK2. Returns "ok", "owned", "locked" (boss not beaten), "base" (archetype not owned), "price" (no
## approved price - not for sale), "coins" (not enough), "unknown". Coins change ONLY on "ok", exactly once.
func buy_mk2(def: RobotDefinition) -> String:
	if def == null or not def.has_mk2():
		return "unknown"
	if mk2_owned.has(def.id):
		return "owned"
	if not owned.has(def.id):
		return "base"
	if not mk2_eligible(def):
		return "locked"
	if not def.mk2_purchasable():
		return "price"
	if coins < def.mk2_price:
		return "coins"
	coins -= def.mk2_price
	mk2_owned.append(def.id)
	mk2_selected[def.id] = true
	save()
	return "ok"


## Chooses BASE (false) or MK2 (true) for an archetype; MK2 only if owned.
func set_mk2_selected(id: String, on: bool) -> bool:
	if on and not mk2_owned.has(id):
		return false
	mk2_selected[id] = on
	save()
	return true


func select(id: String) -> bool:
	if not owned.has(id):
		return false
	selected = id
	save()
	return true


func add_coins(n: int) -> void:
	coins = maxi(coins + maxi(n, 0), 0)
	save()


# ---------------- campaign ----------------

## The start node is always unlocked.
func ensure_campaign_start(start_id: String) -> void:
	if start_id != "" and not campaign.unlocked.has(start_id):
		campaign.unlocked.append(start_id)


func is_unlocked(id: String) -> bool:
	return campaign.unlocked.has(id)


func is_completed(id: String) -> bool:
	return campaign.completed.has(id)


func attempts_on(id: String) -> int:
	return int(campaign.attempts.get(id, 0))


func count_attempt(id: String) -> int:
	if is_completed(id):
		return attempts_on(id)
	campaign.attempts[id] = attempts_on(id) + 1
	return campaign.attempts[id]


## Win on a node: marks it completed and unlocks its successors. Returns true on the FIRST completion.
func complete(id: String, next_ids: Array) -> bool:
	var first: bool = not campaign.completed.has(id)
	if first:
		campaign.completed.append(id)
	for n in next_ids:
		if not campaign.unlocked.has(n):
			campaign.unlocked.append(n)
	save()
	return first


## Pays the first-clear reward exactly once per node. Returns true if it was paid now.
func claim_first_clear(id: String, amount: int) -> bool:
	if campaign.claimed.has(id):
		return false
	campaign.claimed.append(id)
	coins += maxi(amount, 0)
	save()
	return true


func replay_wins(id: String) -> int:
	return int(campaign.replay_wins.get(id, 0))


func add_replay_win(id: String, reward: int) -> void:
	campaign.replay_wins[id] = replay_wins(id) + 1
	coins += maxi(reward, 0)
	save()

# ---------------- v32 secret artifact ----------------

## Permanent discovery (first time only). Returns true when it was found now.
func discover_artifact() -> bool:
	if bool(artifact.discovered):
		return false
	artifact.discovered = true
	save()
	return true


## Equip / unequip: only after discovery. Returns the resulting equipped state.
func set_artifact_equipped(on: bool) -> bool:
	if not bool(artifact.discovered):
		return false
	artifact.equipped = on
	save()
	return bool(artifact.equipped)


# ---------------- skins (cosmetic) ----------------

func owns_skin(skin_id: String) -> bool:
	return skin_id.ends_with("_default") or owned_skins.has(skin_id)


## Grants a skin permanently. Returns true only the first time (rewards can never be granted twice).
func grant_skin(skin_id: String) -> bool:
	if owns_skin(skin_id):
		return false
	owned_skins.append(skin_id)
	save()
	return true


## v36: the colour scheme belongs to the version - BASE under "<id>", MK2 under "<id>_mk2" (older saves only have
## base keys: their MK2 simply starts on the default scheme).
static func skin_key(robot_id: String, mk2 := false) -> String:
	return robot_id + ("_mk2" if mk2 else "")


## Equips an owned skin of that archetype for the BASE or MK2 version.
func equip_skin(robot_id: String, skin_id: String, mk2 := false) -> bool:
	if not owns_skin(skin_id):
		return false
	if not skin_index.is_empty() and skin_index.get(skin_id, "") != robot_id:
		return false
	equipped_skins[skin_key(robot_id, mk2)] = skin_id
	save()
	return true


func equipped_skin(robot_id: String, mk2 := false) -> String:
	return String(equipped_skins.get(skin_key(robot_id, mk2), robot_id + "_default"))


# ---------------- permanent optional stars ----------------
static func _star_node(id: String) -> bool:
	return id.begins_with("r") and id.substr(1).is_valid_int() and int(id.substr(1)) >= 1 and int(id.substr(1)) <= 100 and id == "r%d" % int(id.substr(1))

func stars_of(id: String) -> Array:
	return campaign.stars.get(id, [false, false, false]).duplicate()

func has_star(id: String, index: int) -> bool:
	return index >= 0 and index < 3 and bool(stars_of(id)[index])

func total_stars() -> int:
	var total := 0
	for id in campaign.stars:
		for flag in campaign.stars[id]:
			total += int(bool(flag))
	return total

## One save contains both ownership and coins. Roll back on failed save so callers can retry.
func earn_star(id: String, index: int, reward: int) -> Dictionary:
	if not _star_node(id) or index < 0 or index >= 3 or has_star(id, index):
		return {"new": false, "paid": 0, "saved": true}
	var old_campaign := campaign.duplicate(true)
	var old_coins := coins
	var old_wallet := star_wallet.duplicate(true)
	var flags := stars_of(id)
	var claims: Array = campaign.star_claimed.get(id, [false, false, false]).duplicate()
	var paid := 0 if claims[index] else maxi(0, reward)
	flags[index] = true
	claims[index] = true
	campaign.stars[id] = flags
	campaign.star_claimed[id] = claims
	coins += paid
	var credited := _credit_stars(1, SOURCE_CAMPAIGN)
	if not credited or not save():
		campaign = old_campaign
		coins = old_coins
		star_wallet = old_wallet
		return {"new": false, "paid": 0, "saved": false}
	return {"new": true, "paid": paid, "saved": true}


# ---------------- spendable stars ----------------
# All credit operations use this helper inside the same save as their ownership receipt.
func _credit_stars(amount: int, source: String) -> bool:
	if amount <= 0 or source.strip_edges().is_empty() or source.length() > 64 or int(star_wallet.earned) + amount > 1000000000:
		return false
	star_wallet.earned += amount
	star_wallet.available += amount
	star_wallet.sources[source] = int(star_wallet.sources.get(source, 0)) + amount
	return true

func earn_stars(amount: int, source: String) -> bool:
	var before := star_wallet.duplicate(true)
	if not _credit_stars(amount, source):
		return false
	if save():
		return true
	star_wallet = before
	return false

func can_spend_stars(amount: int) -> bool:
	return amount > 0 and amount <= int(star_wallet.available)

func spend_stars(amount: int, reason: String) -> bool:
	if not can_spend_stars(amount) or reason.strip_edges().is_empty():
		return false
	var before := star_wallet.duplicate(true)
	star_wallet.available -= amount
	star_wallet.spent += amount
	star_wallet.last_spend_reason = reason.left(160)
	if save():
		return true
	star_wallet = before
	return false

## Creation/refresh is durable BEFORE attaching a tracker. Switching robots does not reroll.
func prepare_free_set(robot_id: String, config: Dictionary) -> Dictionary:
	var current: Dictionary = free_run.set
	if not current.is_empty() and not FreeChallenges.valid_set(current):
		return {} # Fail closed on corrupt receipts; never silently reroll paid objectives.
	var all_done: bool = not current.is_empty() and not current.completed.has(false)
	if not current.is_empty() and not (all_done and config.get("refresh_policy", "all_completed") == "all_completed"):
		return current.duplicate(true)
	if int(free_run.sequence) >= 1000000000:
		return {}
	var before := free_run.duplicate(true)
	free_run.sequence += 1
	var seed_value := int(Time.get_unix_time_from_system() * 1000) ^ randi() ^ int(free_run.sequence)
	free_run.set = FreeChallenges.generate(robot_id, seed_value, int(free_run.sequence), config)
	if not FreeChallenges.valid_set(free_run.set) or not save():
		free_run = before
		return {}
	return free_run.set.duplicate(true)

## Set ID + index + completion flag is a bounded receipt; obsolete IDs never pay.
func earn_free_star(set_id: int, index: int) -> Dictionary:
	var current: Dictionary = free_run.set
	if not FreeChallenges.valid_set(current) or int(current.id) != set_id or index < 0 or index >= 3 or current.completed[index]:
		return {"new": false, "paid": 0, "saved": true}
	var before := free_run.duplicate(true)
	var wallet := star_wallet.duplicate(true)
	var done: int = current.completed.count(true)
	var amount := int(current.reward_per_objective) if done < int(current.max_rewarded_objectives) else 0
	current.completed[index] = true
	if (amount > 0 and not _credit_stars(amount, SOURCE_FREE_RUN)) or not save():
		free_run = before
		star_wallet = wallet
		return {"new": false, "paid": 0, "saved": false}
	return {"new": true, "paid": amount, "saved": true}
