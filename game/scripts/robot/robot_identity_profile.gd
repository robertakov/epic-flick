class_name RobotIdentityProfile
extends Resource
## Data-only presentation contract. Future armor decorations and sound have no six-piece limit.
@export var robot_id := "samurai"
@export var rattle := 0.0
@export var cadence := 18.0
@export var squash := 0.025
@export var settle_hz := 12.0
@export var recovery := 3.0
@export var particle_color := Color(0.7, 0.7, 0.6)
@export var particle_kind := "streak"
@export var particle_gain := 3.0
@export var impact_ring := false
@export var leg_exhaust := false
@export var sfx_family := "armor_clink"
@export var event_responses: Dictionary = {}
@export var decorative_parts: Array[Dictionary] = []
## Reserved for future tuning; current normalized gameplay feedback stays unchanged.
@export var haptic_multiplier := 1.0
@export var camera_multiplier := 1.0
static var _cache: Dictionary = {}
const EVENTS := ["IDLE", "AIRBORNE", "SPRING_COMPRESS", "SPRING_RELEASE", "GOOD_LANDING", "BAD_LANDING", "HARD_IMPACT", "CHARGED_LANDING", "FULL_CHARGE", "LIMB_LOST", "LOW_HP", "HEAD_HIT", "ROCKET_PHASE_START", "ROCKET_PHASE_ACTIVE", "DEATH"]

static func for_robot(id: String) -> RobotIdentityProfile:
	if not _cache.has(id):
		var path := "res://config/identity/%s.tres" % id
		_cache[id] = load(path) if ResourceLoader.exists(path) else load("res://config/identity/samurai.tres")
	return _cache[id]


func sound_hook(event: String) -> String:
	var response: Dictionary = event_responses.get(event, {})
	return sfx_family + "/" + String(response.get("sfx", event.to_lower()))
