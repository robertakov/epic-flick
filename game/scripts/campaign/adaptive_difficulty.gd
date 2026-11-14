class_name AdaptiveDifficulty
extends RefCounted
## Hidden player-skill estimate -> bounded AI skill modifier.
##
## Each finished attempt on the player's FRONTIER round (not yet cleared) becomes a performance score p in -1..1:
##   * close results (|margin| < close_margin, win or loss) score 0 -> a close loss never makes the game easier;
##   * clear wins score up to +1 (more with HP left, and with fewer attempts than the round's target);
##   * clear losses score down to -1.
## The score is smoothed with an EMA (one result moves it by `smoothing` of the gap), and the modifier is a
## continuous dead-banded map of the EMA into [-max_down, +max_up]. One lucky / unlucky attempt changes nearly
## nothing; a streak changes it gradually; it can never exceed its bounds. Replays of cleared rounds are ignored.

var cfg: AdaptiveConfig
var state := {}


func _init(p_cfg: AdaptiveConfig, p_state: Dictionary) -> void:
	cfg = p_cfg
	state = sanitize_state(p_state)


static func default_state() -> Dictionary:
	return {"ema": 0.0, "samples": 0}


static func sanitize_state(s: Dictionary) -> Dictionary:
	var out := default_state()
	var e = s.get("ema")
	if (typeof(e) == TYPE_FLOAT or typeof(e) == TYPE_INT) and is_finite(float(e)):
		out.ema = clampf(float(e), -1.0, 1.0)
	var n = s.get("samples")
	if (typeof(n) == TYPE_FLOAT or typeof(n) == TYPE_INT) and float(n) >= 0.0:
		out.samples = int(n)
	return out


## Score of one attempt. r: player_m, best_enemy_m, won, hp_ratio, attempts (on this round incl. this one),
## difficulty ("normal" / "hard" / "boss").
func score(r: Dictionary) -> float:
	var best: float = maxf(float(r.best_enemy_m), cfg.margin_floor_m)
	var margin: float = (float(r.player_m) - float(r.best_enemy_m)) / best
	var span := maxf(cfg.dominant_margin - cfg.close_margin, 0.01)
	var p := 0.0
	if absf(margin) >= cfg.close_margin:
		p = clampf((absf(margin) - cfg.close_margin) / span, 0.0, 1.0) * signf(margin)
	if bool(r.won):
		if p > 0.0:
			p *= (1.0 - cfg.hp_weight) + cfg.hp_weight * clampf(float(r.get("hp_ratio", 0.5)), 0.0, 1.0)
		var target: float = cfg.target_attempts.get(String(r.get("difficulty", "normal")), 3.0)
		var att := float(r.get("attempts", 1))
		# quicker than the target pushes up, much slower pushes down (never below "close")
		p += clampf((target - att) / target, -1.0, 0.6) * cfg.attempts_weight
	return clampf(p, -1.0, 1.0)


## Records one attempt and returns the new modifier.
func record(r: Dictionary) -> float:
	var p := score(r)
	state.ema = clampf(float(state.ema) + cfg.smoothing * (p - float(state.ema)), -1.0, 1.0)
	state.samples = int(state.samples) + 1
	return modifier()


func modifier() -> float:
	var e := float(state.ema)
	var a := absf(e)
	if a <= cfg.dead_band:
		return 0.0
	var k := (a - cfg.dead_band) / (1.0 - cfg.dead_band)
	return k * (cfg.max_up if e > 0.0 else -cfg.max_down)


func effective_skill(base: float) -> float:
	return clampf(base + modifier(), 0.0, 1.0)
