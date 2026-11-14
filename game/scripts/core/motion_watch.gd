class_name MotionWatch
extends RefCounted
## v36 stuck detector (player and race opponents use the same rules).
## HARD RULE: moving backward is NOT being stuck. A robot may roll / fly / bounce backward and lose any distance and
## stays a valid run. Missing new maximum distance alone never ends an attempt.
##   stopped()  - near-zero linear speed AND near-zero spin for stuck_time (the existing "Робот остановился" rule;
##                v36: real rotation also counts as movement)
##   step()     - "stuck" = genuine physical immobilisation: the body stays inside a CONFINE_PX box (wedged /
##                jittering in place) for no_progress_time. Any translation (falling, flying, bouncing, rolling
##                backward) leaves the box and resets it.
##                Endless-loop guard (softlock only): LOOP_NO_RECORD_S without any new distance AND the body confined to
##                LOOP_PX for the whole LOOP_WINDOW (e.g. pogoing forever in one pit). Backward travel of more than
##                LOOP_PX can never trigger it.

const SAMPLE_DT := 0.1
const CONFINE_WINDOW := 2.0
const CONFINE_PX := 60.0
const LOOP_WINDOW := 10.0
const LOOP_PX := 600.0
const LOOP_NO_RECORD_S := 45.0
const PROGRESS_PX := 150.0
const SPIN_MOVING := 1.5          # rad/s: a body turning faster than this is moving

var no_progress_time := 7.0
var confined_time := 0.0
var since_record := 0.0
var stopped_time := 0.0
var _t := 0.0
var _next := 0.0
var _samples: Array = []          # [t, Vector2]
var _best_x := -INF


func _init(p_no_progress_time := 7.0) -> void:
	no_progress_time = p_no_progress_time


func reset(pos: Vector2) -> void:
	confined_time = 0.0
	since_record = 0.0
	stopped_time = 0.0
	_t = 0.0
	_next = 0.0
	_samples.clear()
	_best_x = pos.x


## Existing stop rule; returns the accumulated stopped time.
func stopped(dt: float, speed: float, spin: float, stuck_speed: float) -> float:
	if speed < stuck_speed and absf(spin) < SPIN_MOVING:
		stopped_time += dt
	else:
		stopped_time = 0.0
	return stopped_time


## Returns true when the body is genuinely stuck (see header).
func step(dt: float, pos: Vector2) -> bool:
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return false
	_t += dt
	if pos.x > _best_x + PROGRESS_PX:
		_best_x = pos.x
		since_record = 0.0
	else:
		since_record += dt
	if _t >= _next:
		_next = _t + SAMPLE_DT
		_samples.append([_t, pos])
		while not _samples.is_empty() and float(_samples[0][0]) < _t - LOOP_WINDOW - SAMPLE_DT:
			_samples.pop_front()
	if _extent(CONFINE_WINDOW) < CONFINE_PX:
		confined_time += dt
	else:
		confined_time = 0.0
	if confined_time > no_progress_time:
		return true
	return since_record > LOOP_NO_RECORD_S and _extent(LOOP_WINDOW) < LOOP_PX


## Largest side of the bounding box of the samples of the last `window` s (INF until the window is filled).
func _extent(window: float) -> float:
	if _samples.is_empty() or _t < window:
		return INF
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var p: Vector2 = Vector2.ZERO
	for s in _samples:
		if float(s[0]) < _t - window:
			continue
		p = s[1]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return maxf(hi.x - lo.x, hi.y - lo.y)
