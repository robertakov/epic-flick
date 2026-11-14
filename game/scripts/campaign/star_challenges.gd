class_name StarChallenges
extends RefCounted
## Library of the reusable Star Challenge types (data-driven: a challenge is {"type": "...", <params>, "reward": coins}).
## Every campaign round has exactly 3 static challenges (config/campaign/stars.json, generated once by
## tools/gen_stars.py and then edited by hand). Stars never depend on the hidden adaptive difficulty.
##
## Categories (one challenge of each per round):
##   A progress / survival      B landing precision / consistency      C physics / charge / movement
## Definitions (good landing = feet: left / right / both; bad = poor leg contact or torso / head / arm hit;
## soft resting contacts are not landings):
##   DISTANCE {m}                    reach m metres
##   CLEAN_START {m}                 reach m with no limb lost before that point (later losses do not matter)
##   LIMB_LIMIT {m, n}               reach m with at most n limbs lost before that point
##   SURVIVAL_HP {m, hp}             reach m with at least hp % health at that point
##   BAD_LANDING_LIMIT {m, n}        reach m with at most n bad landings before that point
##   GOOD_LANDING_STREAK {n}         n good landings in a row (a bad landing resets)
##   TOTAL_GOOD_LANDINGS {n}         n good landings in one attempt
##   RECOVERY {n}                    n times: a bad landing immediately followed by a good one
##   CLEAN_SECTION {m}               m metres in a row without a bad landing (starts anywhere; robot only, not the jet head)
##   CHARGE_TARGET {pct}             spin charge reaches pct % once
##   CHARGED_LANDING {pct}           one good landing with at least pct % charge
##   CHARGED_LANDING_STREAK {n, pct} n good landings in a row, each with at least pct % (any other landing resets)
##   AIR_TIME {s}                    one continuous airborne period of s seconds (after the first touchdown)
##   LONG_JUMP {m}                   horizontal metres from leaving the ground to the next contact (after the first touchdown)
##   SPEED_TARGET {kmh}              natural robot speed (no jet head, not the flick flight) of kmh km/h

const TYPES := {
	"DISTANCE": {"cat": "A", "params": ["m"]},
	"CLEAN_START": {"cat": "A", "params": ["m"]},
	"LIMB_LIMIT": {"cat": "A", "params": ["m", "n"]},
	"SURVIVAL_HP": {"cat": "A", "params": ["m", "hp"]},
	"ROCKET_HEAD_DISTANCE": {"cat": "A", "params": ["m"]},
	"WIN_MARGIN_OVER": {"cat": "A", "params": ["m"]},
	"BAD_LANDING_LIMIT": {"cat": "B", "params": ["m", "n"]},
	"GOOD_LANDING_STREAK": {"cat": "B", "params": ["n"]},
	"TOTAL_GOOD_LANDINGS": {"cat": "B", "params": ["n"]},
	"RECOVERY": {"cat": "B", "params": ["n"]},
	"CLEAN_SECTION": {"cat": "B", "params": ["m"]},
	"HEAD_LANDINGS": {"cat": "B", "params": ["n"]},
	"NO_TOUCH_AND_WIN": {"cat": "B", "params": ["s"]},
	"CHARGE_TARGET": {"cat": "C", "params": ["pct"]},
	"CHARGED_LANDING": {"cat": "C", "params": ["pct"]},
	"CHARGED_LANDING_STREAK": {"cat": "C", "params": ["n", "pct"]},
	"AIR_TIME": {"cat": "C", "params": ["s"]},
	"LONG_JUMP": {"cat": "C", "params": ["m"]},
	"SPEED_TARGET": {"cat": "C", "params": ["kmh"]},
	"CCW_TURNS": {"cat": "C", "params": ["n"]},
	"MAX_HEIGHT_M": {"cat": "C", "params": ["m"]},
	"FLICK_MAX_POWER": {"cat": "C", "params": []},
	"FLICK_MIN_AND_WIN": {"cat": "C", "params": []},
}
## Category label keys (L.t(CATEGORY_NAMES[cat])).
const CATEGORY_NAMES := {"A": "CAT_A", "B": "CAT_B", "C": "CAT_C"}
const DESCRIBE_KEYS := {
	"DISTANCE": "CH_DISTANCE", "CLEAN_START": "CH_CLEAN_START", "LIMB_LIMIT": "CH_LIMB_LIMIT", "SURVIVAL_HP": "CH_SURVIVAL_HP",
	"ROCKET_HEAD_DISTANCE": "CH_ROCKET_HEAD", "WIN_MARGIN_OVER": "CH_WIN_MARGIN", "BAD_LANDING_LIMIT": "CH_BAD_LIMIT",
	"GOOD_LANDING_STREAK": "CH_GOOD_STREAK", "TOTAL_GOOD_LANDINGS": "CH_TOTAL_GOOD", "RECOVERY": "CH_RECOVERY",
	"CLEAN_SECTION": "CH_CLEAN_SECTION", "HEAD_LANDINGS": "CH_HEAD_LANDINGS", "NO_TOUCH_AND_WIN": "CH_NO_TOUCH",
	"CHARGE_TARGET": "CH_CHARGE", "CHARGED_LANDING": "CH_CHARGED_LANDING", "CHARGED_LANDING_STREAK": "CH_CHARGED_STREAK",
	"AIR_TIME": "CH_AIR_TIME", "LONG_JUMP": "CH_LONG_JUMP", "SPEED_TARGET": "CH_SPEED", "CCW_TURNS": "CH_CCW",
	"MAX_HEIGHT_M": "CH_HEIGHT", "FLICK_MAX_POWER": "CH_FLICK_MAX", "FLICK_MIN_AND_WIN": "CH_FLICK_MIN",
}
## Describe keys that are plural phrases (counted by "n").
const PLURAL_DESCRIBE := ["CH_LIMB_LIMIT", "CH_BAD_LIMIT", "CH_GOOD_STREAK", "CH_TOTAL_GOOD", "CH_RECOVERY", "CH_HEAD_LANDINGS",
	"CH_CHARGED_STREAK", "CH_CCW"]
const SHORT_KEYS := {
	"DISTANCE": "CHS_DISTANCE", "CLEAN_START": "CHS_CLEAN_START", "LIMB_LIMIT": "CHS_LIMB_LIMIT", "SURVIVAL_HP": "CHS_SURVIVAL_HP",
	"ROCKET_HEAD_DISTANCE": "CHS_ROCKET_HEAD", "WIN_MARGIN_OVER": "CHS_WIN_MARGIN", "BAD_LANDING_LIMIT": "CHS_BAD_LIMIT",
	"GOOD_LANDING_STREAK": "CHS_GOOD_STREAK", "TOTAL_GOOD_LANDINGS": "CHS_TOTAL_GOOD", "RECOVERY": "CHS_RECOVERY",
	"CLEAN_SECTION": "CHS_CLEAN_SECTION", "HEAD_LANDINGS": "CHS_HEAD_LANDINGS", "NO_TOUCH_AND_WIN": "CHS_NO_TOUCH",
	"CHARGE_TARGET": "CHS_CHARGE", "CHARGED_LANDING": "CHS_CHARGED_LANDING", "CHARGED_LANDING_STREAK": "CHS_CHARGED_STREAK",
	"AIR_TIME": "CHS_AIR_TIME", "LONG_JUMP": "CHS_LONG_JUMP", "SPEED_TARGET": "CHS_SPEED", "CCW_TURNS": "CHS_CCW",
	"MAX_HEIGHT_M": "CHS_HEIGHT", "FLICK_MAX_POWER": "CHS_FLICK_MAX", "FLICK_MIN_AND_WIN": "CHS_FLICK_MIN",
}
## Pairs that must not share a round (too similar or working against each other in one attempt).
const INCOMPATIBLE := [
	["GOOD_LANDING_STREAK", "CHARGED_LANDING_STREAK"],
	["CLEAN_START", "SURVIVAL_HP"],
	["TOTAL_GOOD_LANDINGS", "CHARGED_LANDING_STREAK"],
	["FLICK_MAX_POWER", "FLICK_MIN_AND_WIN"],
	["CLEAN_START", "ROCKET_HEAD_DISTANCE"],
	["SURVIVAL_HP", "ROCKET_HEAD_DISTANCE"],
	["BAD_LANDING_LIMIT", "ROCKET_HEAD_DISTANCE"],
	["CLEAN_START", "HEAD_LANDINGS"],
	["BAD_LANDING_LIMIT", "HEAD_LANDINGS"],
]


## Hard caps (design rule): no campaign challenge may ever require more height or speed than this.
## Mirrored in tools/gen_campaign_100.py and tools/gen_stars.py; CampaignData rejects stars.json values above them.
const MAX_HEIGHT_CAP_M := 30.0
const SPEED_CAP_KMH := 100.0


static func category(ch: Dictionary) -> String:
	return String(TYPES.get(String(ch.get("type", "")), {}).get("cat", "?"))


static func p(ch: Dictionary, key: String) -> float:
	return float(ch.get(key, 0.0))


static func pi_(ch: Dictionary, key: String) -> int:
	return int(round(float(ch.get(key, 0.0))))


## "" if the challenge is well formed, else the problem.
static func validate(ch: Dictionary) -> String:
	var t := String(ch.get("type", ""))
	if not TYPES.has(t):
		return "unknown type '%s'" % t
	for k in TYPES[t].params:
		var v = ch.get(k)
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return "%s: missing number '%s'" % [t, k]
		if not is_finite(float(v)) or float(v) < 0.0 or (k != "n" and float(v) <= 0.0):
			return "%s: bad %s=%s" % [t, k, v]
	if ch.has("pct") and p(ch, "pct") > 100.0:
		return "%s: pct > 100" % t
	if ch.has("hp") and p(ch, "hp") > 100.0:
		return "%s: hp > 100" % t
	if ch.has("n") and (p(ch, "n") != floor(p(ch, "n")) or (t not in ["LIMB_LIMIT", "BAD_LANDING_LIMIT"] and p(ch, "n") < 1)):
		return "%s: invalid count" % t
	if ch.has("n") and t == "LIMB_LIMIT" and p(ch, "n") > 3:
		return "limb limit must preserve at least one limb"
	if t == "NO_TOUCH_AND_WIN" and not is_equal_approx(p(ch, "s"), 3.5):
		return "NO_TOUCH_AND_WIN must always be 3.5 seconds"
	if t == "MAX_HEIGHT_M" and p(ch, "m") > MAX_HEIGHT_CAP_M:
		return "MAX_HEIGHT_M above the hard cap of %d m" % int(MAX_HEIGHT_CAP_M)
	if t == "SPEED_TARGET" and p(ch, "kmh") > SPEED_CAP_KMH:
		return "SPEED_TARGET above the hard cap of %d" % int(SPEED_CAP_KMH)
	var rw = ch.get("reward")
	if (typeof(rw) != TYPE_INT and typeof(rw) != TYPE_FLOAT) or not is_finite(float(rw)) or float(rw) < 0 or float(rw) != floor(float(rw)):
		return "invalid reward"
	return ""


static func plural(n: int, one: String, few: String, many: String) -> String:
	var a := absi(n) % 100
	if a >= 11 and a <= 14:
		return many
	match a % 10:
		1:
			return one
		2, 3, 4:
			return few
	return many


## Full readable description (map / before the round / result), whole localized phrase per type (L keys CH_*).
static func describe(ch: Dictionary) -> String:
	var n := pi_(ch, "n")
	var args := {"m": pi_(ch, "m"), "n": n, "hp": pi_(ch, "hp"), "pct": pi_(ch, "pct"), "kmh": pi_(ch, "kmh"), "s": _sec(p(ch, "s"))}
	var t := String(ch.get("type", ""))
	if t == "BAD_LANDING_LIMIT" and n == 0:
		return L.f("CH_BAD_ZERO", args)
	if DESCRIBE_KEYS.has(t):
		var k: String = DESCRIBE_KEYS[t]
		return L.pf(k, n, args) if k in PLURAL_DESCRIBE else L.f(k, args)
	return "?"


## Compact text for the in-run indicator (L keys CHS_*).
static func short(ch: Dictionary) -> String:
	var args := {"m": pi_(ch, "m"), "n": pi_(ch, "n"), "hp": pi_(ch, "hp"), "pct": pi_(ch, "pct"), "kmh": pi_(ch, "kmh"), "s": _sec(p(ch, "s"))}
	var t := String(ch.get("type", ""))
	if SHORT_KEYS.has(t):
		return L.f(SHORT_KEYS[t], args)
	return "?"


static func _sec(s: float) -> String:
	return L.dec(s)


## Coins of a challenge (one-time).
static func reward(ch: Dictionary) -> int:
	return maxi(int(ch.get("reward", 0)), 0)
