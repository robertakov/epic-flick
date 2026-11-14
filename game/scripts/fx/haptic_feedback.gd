class_name HapticFeedback
extends Node
## Discrete physical feedback, independent of the camera's final shake. No physics writes.
## Requests in one short burst merge into its strongest pulse, at most ten pulses/second.
var vibration_scale := 0.7
var _pending := 0.0
var _due := -1
var _last_pulse := -1000
signal pulse_sent(duration_ms: int, amplitude: float)

static func strengths(intensity: float, shake_setting: float, vibration_setting: float) -> Vector2:
	var k := clampf(intensity, 0.0, 1.0) if is_finite(intensity) else 0.0
	return Vector2(k * clampf(shake_setting, 0.0, 1.0), k * clampf(vibration_setting, 0.0, 1.0))

static func supported() -> bool:
	return OS.get_name() == "Android" and DisplayServer.get_name() != "headless"

static func recipe(intensity: float, setting: float) -> Dictionary:
	var strength := strengths(intensity,0.0,setting).y
	return {"amplitude":strength,"duration_ms":int(round(12 + 58 * strength)) if strength > 0 else 0}

func submit(intensity: float, now_ms := -1) -> void:
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	var k := recipe(intensity,vibration_scale)
	if k.amplitude <= 0:
		return
	_pending = maxf(_pending,float(k.amplitude))
	if _due < 0:
		_due = now + 25

## Returns the planned pulse for tests even on a desktop; only Android calls the OS.
func flush(now_ms: int) -> Dictionary:
	if _due < 0 or now_ms < _due:
		return {}
	var amplitude := _pending if vibration_scale > 0 else 0.0
	reset_pending()
	if amplitude <= 0 or now_ms - _last_pulse < 100:
		return {}
	_last_pulse = now_ms
	var pulse := {"amplitude":amplitude,"duration_ms":int(round(12+58*amplitude))}
	if supported() and not get_tree().paused:
		Input.vibrate_handheld(pulse.duration_ms,pulse.amplitude)
		pulse_sent.emit(pulse.duration_ms,pulse.amplitude)
	return pulse

func reset_pending() -> void:
	_pending = 0.0
	_due = -1

func _process(_dt: float) -> void:
	flush(Time.get_ticks_msec()) # real time: WAIT x3 cannot triple pulse frequency
