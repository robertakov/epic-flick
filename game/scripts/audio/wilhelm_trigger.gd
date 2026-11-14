class_name WilhelmTrigger
extends RefCounted
## Rare comedic easter egg (REQUIRED, do not remove): when the PLAYER rises to ~30 m above the LOCAL ground surface,
## ONE 7% roll decides whether the Wilhelm scream plays.
##   * altitude = (terrain.height_at(x) - body.y) / px_per_meter of the active body (robot, or the flying jet head) -
##     the same measure as the MAX_HEIGHT_M star;
##   * the roll happens once when the altitude crosses HEIGHT_M (never per frame while staying above it);
##   * hysteresis: the trigger re-arms only after the altitude drops to REARM_M or lower, so threshold jitter or a dip
##     to 25 m cannot cause a second roll - only a genuinely separate high jump can;
##   * not tied to death, limb loss or impacts; reads positions only and never touches physics.
## Uses the audio mixer's private RNG (never the gameplay RNG).

const HEIGHT_M := 30.0
const REARM_M := 20.0
const PROBABILITY := 0.07   # v29: 10% -> 5%; v36: 5% -> 7% (user request); nothing else changed

var height_m := HEIGHT_M
var rearm_m := REARM_M
var probability := PROBABILITY
var armed := true
## counters for tests / debug
var rolls := 0
var screams := 0


static func altitude_m(terrain_y: float, body_y: float, px_per_meter: float) -> float:
	return (terrain_y - body_y) / maxf(px_per_meter, 0.001)


## Feed the current altitude (metres above the local ground). Returns true when the scream should play now.
func step(altitude: float, rng: RandomNumberGenerator) -> bool:
	if not is_finite(altitude):
		return false
	if not armed:
		if altitude <= rearm_m:
			armed = true
		return false
	if altitude < height_m:
		return false
	armed = false
	rolls += 1
	if rng.randf() < probability:
		screams += 1
		return true
	return false


func reset() -> void:
	armed = true
