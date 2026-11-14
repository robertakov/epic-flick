class_name BiomeChallenges
extends RefCounted
## Biome-aware campaign Star Challenges (v36: formal per-biome ELIGIBILITY + parameter rules).
## The authored values in config/campaign/stars.json are the Green Hills baseline. A level in a special biome gets:
##   1. ELIGIBILITY - EXCLUDED[biome][type] = reason: mechanically incompatible / absurd / balance-destroying there.
##      An excluded authored challenge is REPLACED deterministically (resolve()): another type of the same category
##      that is allowed in this biome and compatible with the round's other two challenges, its parameters taken from
##      the nearest authored round that uses that type (so the difficulty ramp is kept), then biome-adjusted.
##   2. PARAMETER RULES - RULES[biome][type] = {param: multiplier} (+ "pct+"/"hp+" offsets, "m_max"/"pct_max" caps).
## Applied ONCE when the campaign loads: same numbers on every device and every replay; map, pre-run card, HUD and
## result show the resolved values. Invariants: NO_TOUCH_AND_WIN stays 3.5 s, MAX_HEIGHT_M <= 30 m,
## SPEED_TARGET <= 100, every result passes StarChallenges.validate().
## v36 multipliers come from measured AI races per biome (reports/v36/CHALLENGE_COMPATIBILITY.md: mean metric in the
## biome / Green Hills, 40 races per biome, 5 robots), rounded conservatively; |ratio - 1| < ~0.1 -> unchanged.

const EXCLUDED := {
	# hard rule. (There is no achievement system yet; a future height achievement must also skip Jelly.)
	"jelly": {"MAX_HEIGHT_M": "jelly rebounds make huge heights trivial"},
	"heavy": {"LONG_JUMP": "1.6 g: one very long jump contradicts the biome's core mechanic",
		"CHARGED_LANDING_STREAK": "1.6 g flights are too short to build high charge twice in a row (0 of 40 AI races)"},
	"cavern": {"CHARGED_LANDING_STREAK": "the ceiling cuts flights short: repeated high-charge landings almost never happen (0 of 40 AI races)"},
	"zone": {"CHARGE_TARGET": "any electric anomaly sets the charge to 100 % at once (trivial)"},
}

const RULES := {
	"moon": {   # 0.45 g: long flights, high jumps, much more air charge; head hits rarer
		"AIR_TIME": {"s": 1.5}, "LONG_JUMP": {"m": 1.4}, "MAX_HEIGHT_M": {"m": 1.5}, "CCW_TURNS": {"n": 1.25},
		"ROCKET_HEAD_DISTANCE": {"m": 1.2}, "DISTANCE": {"m": 1.15}, "CLEAN_SECTION": {"m": 1.25},
		"CHARGE_TARGET": {"pct+": 5}, "CHARGED_LANDING": {"pct+": 10}, "CHARGED_LANDING_STREAK": {"pct+": 10},
		"HEAD_LANDINGS": {"n": 0.6}, "SPEED_TARGET": {"kmh": 0.95}},
	"heavy": {  # SUPERGRAVITY 1.6 g + weaker rebound: short, low flights, little charge, shorter runs
		"AIR_TIME": {"s": 0.6}, "MAX_HEIGHT_M": {"m": 0.65}, "CCW_TURNS": {"n": 0.6}, "ROCKET_HEAD_DISTANCE": {"m": 0.7},
		"DISTANCE": {"m": 0.75}, "CLEAN_START": {"m": 0.75}, "LIMB_LIMIT": {"m": 0.75}, "SURVIVAL_HP": {"m": 0.75},
		"BAD_LANDING_LIMIT": {"m": 0.75}, "WIN_MARGIN_OVER": {"m": 0.75}, "CLEAN_SECTION": {"m": 0.85},
		"CHARGE_TARGET": {"pct_max": 50}, "CHARGED_LANDING": {"pct_max": 40}, "SPEED_TARGET": {"kmh": 1.1}},
	"chocolate": {  # sticky pools eat speed and momentum; charged landings a bit harder
		"SPEED_TARGET": {"kmh": 0.85}, "DISTANCE": {"m": 0.9}, "CLEAN_START": {"m": 0.9}, "LIMB_LIMIT": {"m": 0.9},
		"LONG_JUMP": {"m": 0.9}, "WIN_MARGIN_OVER": {"m": 0.85}, "HEAD_LANDINGS": {"n": 0.7},
		"CHARGED_LANDING": {"pct+": -10}, "CHARGED_LANDING_STREAK": {"pct+": -5}},
	"jelly": {  # huge rebounds: air a little easier, more charge, fewer head hits
		"AIR_TIME": {"s": 1.1}, "LONG_JUMP": {"m": 1.05}, "CLEAN_SECTION": {"m": 1.1}, "ROCKET_HEAD_DISTANCE": {"m": 1.2},
		"CHARGED_LANDING": {"pct+": 10}, "CHARGED_LANDING_STREAK": {"pct+": 5}, "HEAD_LANDINGS": {"n": 0.7}},
	"portal": {  # v36 portals: helpful exits throw the robot up and forward -> longer flights; teleports reset a flight
		"LONG_JUMP": {"m": 1.2}, "AIR_TIME": {"s": 1.1}, "CCW_TURNS": {"n": 1.2}, "CLEAN_START": {"m": 1.1},
		"HEAD_LANDINGS": {"n": 0.8}, "CHARGED_LANDING": {"pct+": 5}},
	"chasms": {  # a fall ends the run: survival / traversal itself is the challenge (bimodal distances)
		"DISTANCE": {"m": 0.75}, "CLEAN_START": {"m": 0.8}, "LIMB_LIMIT": {"m": 0.8}, "SURVIVAL_HP": {"m": 0.8},
		"BAD_LANDING_LIMIT": {"m": 0.8}, "CLEAN_SECTION": {"m": 0.8}, "ROCKET_HEAD_DISTANCE": {"m": 0.8},
		"WIN_MARGIN_OVER": {"m": 0.85}, "TOTAL_GOOD_LANDINGS": {"n": 0.85}, "CHARGED_LANDING": {"pct+": -5}},
	"cavern": {  # a real ceiling (v36 geometry): shorter runs, capped heights / flights, little charge
		"MAX_HEIGHT_M": {"m": 0.65, "m_max": 8}, "AIR_TIME": {"s": 0.7}, "LONG_JUMP": {"m": 0.85}, "CCW_TURNS": {"n": 0.7},
		"DISTANCE": {"m": 0.5}, "CLEAN_START": {"m": 0.8}, "LIMB_LIMIT": {"m": 0.5}, "SURVIVAL_HP": {"m": 0.5},
		"BAD_LANDING_LIMIT": {"m": 0.5}, "WIN_MARGIN_OVER": {"m": 0.5}, "CLEAN_SECTION": {"m": 0.45},
		"ROCKET_HEAD_DISTANCE": {"m": 0.45}, "GOOD_LANDING_STREAK": {"n": 0.6}, "TOTAL_GOOD_LANDINGS": {"n": 0.8},
		"CHARGE_TARGET": {"pct_max": 55}, "CHARGED_LANDING": {"pct_max": 40}},
	"zone": {  # anomalies damage / throw the robot; the electric one charges it
		"DISTANCE": {"m": 0.9}, "CLEAN_START": {"m": 0.85}, "LIMB_LIMIT": {"m": 0.85},
		"SURVIVAL_HP": {"m": 0.75, "hp+": -10}, "BAD_LANDING_LIMIT": {"m": 0.9}, "CLEAN_SECTION": {"m": 0.9},
		"WIN_MARGIN_OVER": {"m": 0.85}, "HEAD_LANDINGS": {"n": 0.7}, "CHARGED_LANDING": {"pct+": 5}},
}


static func is_allowed(type: String, biome_id: String) -> bool:
	return not EXCLUDED.get(biome_id, {}).has(type)


static func exclusion_reason(type: String, biome_id: String) -> String:
	return String(EXCLUDED.get(biome_id, {}).get(type, ""))


static func adjust(ch: Dictionary, biome_id: String) -> Dictionary:
	var out := ch.duplicate(true)
	var t := String(ch.get("type", ""))
	if t == "NO_TOUCH_AND_WIN":
		return out                                   # fixed 3.5 s, never biome-scaled
	var rule: Dictionary = RULES.get(biome_id, {}).get(t, {})
	if rule.is_empty():
		return out
	for key in rule:
		var k := String(key)
		var v = rule[key]
		if k.ends_with("+"):
			var p := k.trim_suffix("+")
			if out.has(p):
				out[p] = float(out[p]) + float(v)
		elif k.ends_with("_max"):
			var p2 := k.trim_suffix("_max")
			if out.has(p2):
				out[p2] = minf(float(out[p2]), float(v))
		elif out.has(k):
			out[k] = float(out[k]) * float(v)
	return _sanitize(out, ch)


## v36: the three challenges of a round in `biome_id`: excluded types replaced, all adjusted.
## pool: type -> [[round_index, authored_challenge], ...] of the whole campaign (baseline values).
## allowed: optional Callable(types: Array) -> bool - the campaign's own set rules (unique triplets, at most one
## type shared with the previous round); a replacement must keep them.
static func resolve(rows: Array, biome_id: String, round_index: int, pool: Dictionary, allowed := Callable()) -> Array:
	var out := []
	var types := rows.map(func(c: Dictionary) -> String: return String(c.type))
	for i in rows.size():
		var ch: Dictionary = rows[i]
		var t := String(ch.type)
		if is_allowed(t, biome_id):
			out.append(adjust(ch, biome_id))
			continue
		var rep := replacement(ch, i, types, biome_id, round_index, pool, allowed)
		if bool(rep.get("rules_ok", true)) or not allowed.is_valid():
			rep.erase("rules_ok")
			types[i] = String(rep.type)
			out.append(adjust(rep, biome_id))
			continue
		# no single replacement keeps the campaign's set rules (every combination with the other two is already a
		# round): also swap ONE other slot, deterministic order (slot, then candidates as in replacement())
		var done := false
		for j in rows.size():
			if j == i or done:
				continue
			var other: Dictionary = rows[j]
			for cj in candidates(other, j, types, biome_id, pool):
				var t2 := types.duplicate()
				t2[j] = cj
				var rep_i := replacement(ch, i, t2, biome_id, round_index, pool, allowed)
				if bool(rep_i.get("rules_ok", false)):
					rep_i.erase("rules_ok")
					var rep_j := _instance(cj, other, round_index, pool)
					types = t2
					types[i] = String(rep_i.type)
					# j may already be in `out` (j < i): rebuild that entry
					if j < out.size():
						out[j] = adjust(rep_j, biome_id)
					else:
						rows = rows.duplicate()
						rows[j] = rep_j
					out.append(adjust(rep_i, biome_id))
					done = true
					break
		if not done:
			rep.erase("rules_ok")
			types[i] = String(rep.type)
			out.append(adjust(rep, biome_id))
	return out


## Allowed same-category candidates for rows[slot] given the round's other types (sorted, deterministic).
static func candidates(ch: Dictionary, slot: int, types: Array, biome_id: String, pool: Dictionary) -> Array[String]:
	var cat := StarChallenges.category(ch)
	var cands: Array[String] = []
	for t in StarChallenges.TYPES:
		if StarChallenges.TYPES[t].cat != cat or t == String(ch.type) or not is_allowed(t, biome_id) or types.has(t) or not pool.has(t):
			continue
		var ok := true
		for pair in StarChallenges.INCOMPATIBLE:
			for j in types.size():
				if j != slot and ((pair[0] == t and pair[1] == types[j]) or (pair[1] == t and pair[0] == types[j])):
					ok = false
		if ok:
			cands.append(t)
	cands.sort()
	return cands


## The authored instance of `type` nearest to round_index (keeps the difficulty ramp), marked as a replacement.
static func _instance(type: String, original: Dictionary, round_index: int, pool: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1 << 30
	for e in pool[type]:
		var dist := absi(int(e[0]) - round_index)
		if dist < best_d:
			best_d = dist
			best = e[1]
	var rep := (best as Dictionary).duplicate(true)
	rep["reward"] = original.get("reward", rep.get("reward", 0))
	rep["replaced"] = String(original.type)
	return rep


## Deterministic replacement for rows[slot] (same category, allowed, not used by the round, compatible).
## rules_ok in the result: false when no candidate satisfied `allowed` (resolve() then also swaps another slot).
static func replacement(ch: Dictionary, slot: int, types: Array, biome_id: String, round_index: int, pool: Dictionary, allowed := Callable()) -> Dictionary:
	var cands := candidates(ch, slot, types, biome_id, pool)
	if cands.is_empty():
		var keep := ch.duplicate(true)
		keep["rules_ok"] = false
		return keep
	# deterministic start, then the first candidate the campaign rules accept (falls back to the start pick)
	var start := posmod(hash([round_index, slot, biome_id, "replace"]), cands.size())
	var pick: String = cands[start]
	var ok := not allowed.is_valid()
	for k in cands.size():
		var c: String = cands[(start + k) % cands.size()]
		var trial := types.duplicate()
		trial[slot] = c
		if not allowed.is_valid() or allowed.call(trial):
			pick = c
			ok = true
			break
	var rep := _instance(pick, ch, round_index, pool)
	rep["rules_ok"] = ok
	return rep


## Same number style as the authored data: metres / km/h / % in steps of 5 (small metres: whole),
## counts whole and >= 1, seconds to 0.1; hard caps respected.
static func _sanitize(out: Dictionary, base: Dictionary) -> Dictionary:
	for k in out:
		if k == "type" or k == "reward" or k == "replaced" or typeof(out[k]) not in [TYPE_FLOAT, TYPE_INT]:
			continue
		var v := float(out[k])
		match String(k):
			"m":
				v = maxf(v, 3.0)
				v = float(5 * int(round(v / 5.0))) if v >= 20.0 else round(v)
				if out.type == "MAX_HEIGHT_M":
					v = minf(v, StarChallenges.MAX_HEIGHT_CAP_M)
			"kmh":
				v = minf(float(5 * int(round(v / 5.0))), StarChallenges.SPEED_CAP_KMH)
			"pct":
				v = clampf(float(5 * int(round(v / 5.0))), 5.0, 100.0)
			"hp":
				v = clampf(float(5 * int(round(v / 5.0))), 30.0, 100.0)
			"n":
				var min_n := 0.0 if String(out.type) in ["LIMB_LIMIT", "BAD_LANDING_LIMIT"] else 1.0
				v = maxf(round(v), min_n)
			"s":
				v = maxf(snappedf(v, 0.1), 0.5)
		out[k] = int(v) if typeof(base.get(k)) == TYPE_INT and is_equal_approx(v, round(v)) else v
	return out
