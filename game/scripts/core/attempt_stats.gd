class_name AttemptStats
extends RefCounted
## Per-attempt counters, fed only by existing robot signals (no gameplay influence).
## A fresh instance is created for every attempt, so Retry always starts from zero.
##   good landing = a classified spring landing on the feet (left / right / both)
##   bad landing  = poor leg contact or a torso / head / arm hit
##   soft contacts (resting, rolling) are not landings.

var id := ""
var landings := 0
var good := 0
var bad := 0
var max_charge := 0.0
var boosted := 0
var full_boosts := 0
var duration_s := 0.0
## Track seed of this attempt (same seed = same track; needed for future ghost races).
var seed := 0
var _charge_max := 1.0


func _init(p_id: String, charge_max := 1.0) -> void:
	id = p_id
	_charge_max = maxf(charge_max, 0.0001)


func attach(robot: RobotController) -> void:
	robot.landed.connect(_on_landed)
	robot.charge_changed.connect(func(c: float) -> void: max_charge = maxf(max_charge, clampf(c / _charge_max, 0.0, 1.0)))
	robot.charge_released.connect(func(c: float, _dv: Vector2, _i: Dictionary) -> void:
		boosted += 1
		if c >= 0.99:
			full_boosts += 1)


func _on_landed(info: Dictionary) -> void:
	match info.get("type", &""):
		&"left", &"right", &"both":
			landings += 1
			good += 1
		&"poor", &"body":
			landings += 1
			bad += 1


func to_dict(distance_m: float) -> Dictionary:
	return {"id": id, "seed": seed, "distance_m": maxf(distance_m, 0.0), "duration_s": duration_s, "landings": landings,
		"good": good, "bad": bad, "max_charge": max_charge, "boosted": boosted, "full_boosts": full_boosts}
