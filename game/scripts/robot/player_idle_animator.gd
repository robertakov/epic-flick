class_name PlayerIdleAnimator
extends RefCounted
## Stateful procedural menu idle animator for the five playable characters:
##   - tin / rasta (Раста): relaxed body sway, sleepy/chill posture, occasional chill nod / sleepy droop / peace wave
##   - hopper / kenguru (Кенгуру): spring-leg compression/rebound, alert head & ear scans, boxer feints
##   - heavy / sumo (Сумоист): heavy breathing, grounded weight shifts, shiko leg stomp / belly breath / chest slap
##   - rocket / chronos (Хронос): clockwork escapement ticks, mechanical windup, time inspection, alarm chime
##   - samurai (Самурай): controlled calm martial stance, subtle spring poise, ready kata / honor bow / horizon scan
##
## Combines:
##   A) A continuous multi-harmonic base idle (using incommensurate frequencies so it never loops mechanically)
##   B) Randomized secondary idle actions with variable pauses (2.0..4.6 s) and no back-to-back repeats.
## Visual-only: never modifies gameplay physics, colliders, or stats.

const ACTIONS := {
	"rasta": ["chill_nod", "sleepy_droop", "peace_wave"],
	"kenguru": ["spring_hop", "ear_perk_scan", "boxer_feint"],
	"sumo": ["shiko_stomp", "belly_breath", "arm_slap"],
	"chronos": ["clockwork_windup", "time_inspect", "alarm_chime"],
	"samurai": ["ready_kata", "honor_bow", "horizon_check"],
}

const ACTION_DURATIONS := {
	"chill_nod": 2.1,
	"sleepy_droop": 2.5,
	"peace_wave": 2.2,
	"spring_hop": 1.85,
	"ear_perk_scan": 1.95,
	"boxer_feint": 1.75,
	"shiko_stomp": 2.35,
	"belly_breath": 2.4,
	"arm_slap": 1.9,
	"clockwork_windup": 2.2,
	"time_inspect": 2.0,
	"alarm_chime": 1.8,
	"ready_kata": 2.15,
	"honor_bow": 2.25,
	"horizon_check": 2.0,
}

var character_id := "rasta"
var time := 0.0
var current_action := ""
var action_time := 0.0
var action_duration := 0.0
var next_action_in := 2.4
var last_action := ""
var actions_triggered := 0
var action_history: Array[String] = []
var _rng := RandomNumberGenerator.new()


func setup(p_character_id: String, seed_val := 0) -> void:
	character_id = _normalize_id(p_character_id)
	time = 0.0
	current_action = ""
	action_time = 0.0
	action_duration = 0.0
	last_action = ""
	actions_triggered = 0
	action_history.clear()
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()
	next_action_in = _rng.randf_range(1.8, 3.2)


static func _normalize_id(raw_id: String) -> String:
	# v36: a colour-scheme visual animates exactly like its version
	if raw_id.find("__") > 0:
		raw_id = raw_id.substr(0, raw_id.find("__"))
	# v35: an MK2 visual animates exactly like its base character
	if raw_id.ends_with("_mk2"):
		raw_id = raw_id.trim_suffix("_mk2")
	match raw_id:
		"tin", "rasta":
			return "rasta"
		"hopper", "kenguru":
			return "kenguru"
		"heavy", "sumo":
			return "sumo"
		"rocket", "chronos":
			return "chronos"
		"samurai":
			return "samurai"
	return "rasta"


func step(dt: float) -> Dictionary:
	dt = clampf(dt, 0.0, 0.1)
	time += dt
	if current_action == "":
		next_action_in -= dt
		if next_action_in <= 0.0:
			_start_random_action()
	else:
		action_time += dt
		if action_time >= action_duration:
			current_action = ""
			action_time = 0.0
			action_duration = 0.0
			next_action_in = _rng.randf_range(2.1, 4.5)
	return compute_pose(character_id, time, current_action, action_time, action_duration)


func trigger_action(action_name: String) -> void:
	current_action = action_name
	action_time = 0.0
	action_duration = float(ACTION_DURATIONS.get(action_name, 2.0))
	last_action = action_name
	actions_triggered += 1
	action_history.append(action_name)


func _start_random_action() -> void:
	var pool: Array = ACTIONS.get(character_id, ACTIONS["rasta"])
	if pool.is_empty():
		next_action_in = 3.0
		return
	var candidates: Array[String] = []
	for a in pool:
		var s := String(a)
		if s != last_action or pool.size() == 1:
			candidates.append(s)
	var pick := candidates[_rng.randi_range(0, candidates.size() - 1)]
	trigger_action(pick)


static func compute_pose(char_id: String, t: float, act := "", act_t := 0.0, act_dur := 2.0) -> Dictionary:
	var cid := _normalize_id(char_id)
	# v27: all five robots (Samurobot included) are PNG-modular rigs and share the rigid-proportion reference pose.
	# The legacy wide-motion table below is kept only for the classic (non-PNG) rig fallback.
	if RobotArtLibrary.visual_profile(cid).get("png_modular", false) or cid != "samurai":
		return _png_reference_pose(cid,t,act,act_t,act_dur)
	var pose := {
		"body_pos": Vector2.ZERO,
		"body_rot": 0.0,
		"body_scale": Vector2.ONE,
		"head_angle": 0.0,
		"head_bob": Vector2.ZERO,
		"arm_l_offset": Vector2.ZERO,
		"arm_r_offset": Vector2.ZERO,
		"foot_l_offset": Vector2.ZERO,
		"foot_r_offset": Vector2.ZERO,
		"foot_l_rot": 0.0,
		"foot_r_rot": 0.0,
		"rig_rot": 0.0,
		"expression": &"neutral",
		"action": act,
	}

	# ---------------- A) Continuous character-specific base idle ----------------
	match cid:
		"rasta":
			# Relaxed body sway, sleepy/chill posture, loose hanging arms, gentle knee-spring dip
			var w1 := t * TAU * 0.56
			var w2 := t * TAU * 0.89
			var sway := sin(w1) * 0.75 + sin(w2 * 0.5) * 0.25
			var breath := sin(w2)
			pose.body_pos = Vector2(sway * 10.5, 4.0 + breath * 5.5 + absf(sway) * 2.5)
			pose.body_rot = sway * 0.065 - 0.025
			pose.body_scale = Vector2(1.0 - breath * 0.018, 1.0 + breath * 0.022)
			pose.head_angle = -sway * 0.11 + 0.04 * cos(w1) - 0.03
			pose.head_bob = Vector2(sway * 3.0, 2.0 + breath * 2.5)
			pose.arm_l_offset = Vector2(-4.0 + sway * 6.0, 5.0 + sin(w1 - 0.6) * 5.0)
			pose.arm_r_offset = Vector2(4.0 + sway * 6.0, 5.0 + cos(w1 - 0.4) * 5.0)
			pose.foot_l_rot = -sway * 0.025
			pose.foot_r_rot = -sway * 0.025
			pose.rig_rot = sway * 0.022
			pose.expression = &"neutral"

		"kenguru":
			# Subtle spring-leg compression/rebound, athletic forward poise, alert head micro-turns
			var w1 := t * TAU * 1.28
			var w2 := t * TAU * 0.79
			var bounce := sin(w1) * 0.7 + sin(w2 * 2.0) * 0.3
			var lean := sin(w2)
			pose.body_pos = Vector2(lean * 6.5 + 3.0, -9.5 * maxf(0.0, bounce) + 6.5 * maxf(0.0, -bounce))
			pose.body_rot = 0.055 + lean * 0.045 - bounce * 0.03
			pose.body_scale = Vector2(1.0 - bounce * 0.022, 1.0 + bounce * 0.025)
			pose.head_angle = -pose.body_rot * 0.6 + sin(w2 * 1.5) * 0.09
			pose.head_bob = Vector2(lean * 3.0, -bounce * 3.2)
			# Ready agile paws
			pose.arm_l_offset = Vector2(-6.0 + lean * 4.0, -10.0 - bounce * 7.0)
			pose.arm_r_offset = Vector2(8.0 + lean * 4.0, -12.0 + bounce * 6.0)
			pose.foot_l_rot = -0.02 * bounce
			pose.foot_r_rot = 0.02 * bounce
			pose.rig_rot = 0.02 * lean
			pose.expression = &"determined" if sin(w2) > 0.35 else &"neutral"

		"sumo":
			# Heavy grounded breathing, slow weight shifts between feet, massive presence
			var w_breath := t * TAU * 0.62
			var w_shift := t * TAU * 0.39
			var breath := sin(w_breath)
			var shift := sin(w_shift)
			var settle := absf(cos(w_shift))
			pose.body_pos = Vector2(shift * 11.0, 5.5 - breath * 5.0 + settle * 4.0)
			pose.body_rot = shift * 0.055
			pose.body_scale = Vector2(1.0 + breath * 0.038, 1.0 + breath * 0.024)
			pose.head_angle = -shift * 0.07 - breath * 0.035
			pose.head_bob = Vector2(shift * 2.5, -breath * 2.5)
			pose.arm_l_offset = Vector2(-10.0 - breath * 6.0 + shift * 4.0, -6.0 * breath + 4.0)
			pose.arm_r_offset = Vector2(10.0 + breath * 6.0 + shift * 4.0, -6.0 * breath + 4.0)
			pose.foot_l_offset = Vector2(-3.0, 0.0)
			pose.foot_r_offset = Vector2(3.0, 0.0)
			pose.rig_rot = shift * 0.018
			pose.expression = &"determined"

		"chronos":
			# Subtle clockwork mechanical motion, quantized escapement micro-ticks + smooth balance wheel
			var w1 := t * TAU * 0.95
			var tick_phase: float = floorf(t * 6.0) / 6.0
			var tick_pulse: float = exp(-fmod(t * 6.0, 1.0) * 5.5)
			var tick_dir: float = 1.0 if int(floorf(t * 6.0)) % 2 == 0 else -1.0
			var balance := sin(w1)
			pose.body_pos = Vector2(balance * 5.5, -5.0 * cos(w1 * 2.0) - tick_pulse * 1.8)
			pose.body_rot = balance * 0.045 + tick_dir * tick_pulse * 0.018
			pose.body_scale = Vector2(1.0 + 0.015 * sin(w1 * 2.0), 1.0 - 0.015 * sin(w1 * 2.0))
			pose.head_angle = sin(tick_phase * TAU * 0.5) * 0.085 + tick_dir * tick_pulse * 0.045
			pose.head_bob = Vector2(balance * 2.5, -tick_pulse * 2.5)
			pose.arm_l_offset = Vector2(-5.0 + cos(tick_phase * TAU) * 6.0, -8.0 * sin(w1) + tick_pulse * 3.0)
			pose.arm_r_offset = Vector2(5.0 - cos(tick_phase * TAU) * 6.0, 8.0 * sin(w1) - tick_pulse * 3.0)
			pose.rig_rot = balance * 0.016
			pose.expression = &"neutral"

		"samurai":
			# Controlled calm stance, disciplined breathing, subtle spring poise
			var w1 := t * TAU * 0.72
			var w2 := t * TAU * 0.43
			var breath := sin(w1)
			var poise := sin(w2)
			pose.body_pos = Vector2(poise * 4.5, -5.5 * breath + 2.0)
			pose.body_rot = poise * 0.032
			pose.body_scale = Vector2(1.0 + breath * 0.016, 1.0 - breath * 0.012)
			pose.head_angle = -poise * 0.045 - breath * 0.025
			pose.head_bob = Vector2(poise * 1.5, -breath * 2.0)
			pose.arm_l_offset = Vector2(-6.0 + poise * 3.0, -5.0 * breath)
			pose.arm_r_offset = Vector2(6.0 + poise * 3.0, -5.0 * breath)
			pose.rig_rot = poise * 0.014
			pose.expression = &"determined"

	# ---------------- B) Occasional secondary idle actions ----------------
	if act != "" and act_dur > 0.0:
		var u := clampf(act_t / act_dur, 0.0, 1.0)
		var env := sin(u * PI)
		var env_smooth := smoothstep(0.0, 0.22, u) * (1.0 - smoothstep(0.78, 1.0, u))
		match act:
			# --- RASTA ---
			"chill_nod":
				var groove := sin(u * TAU * 2.0)
				pose.body_pos += Vector2(groove * 11.0, absf(groove) * 9.0) * env
				pose.body_rot += groove * 0.09 * env
				pose.head_angle += sin(u * TAU * 2.0 - 0.5) * 0.24 * env
				pose.head_bob += Vector2(groove * 5.0, 6.5 * absf(groove)) * env
				pose.arm_l_offset += Vector2(-12.0, -14.0 * maxf(0.0, groove)) * env
				pose.arm_r_offset += Vector2(12.0, -14.0 * maxf(0.0, -groove)) * env
				pose.expression = &"happy"
			"sleepy_droop":
				if u < 0.68:
					var d := smoothstep(0.0, 0.68, u)
					pose.body_pos += Vector2(-4.0, 14.0) * d
					pose.body_rot += -0.08 * d
					pose.head_angle += 0.26 * d
					pose.head_bob += Vector2(4.0, 8.0) * d
					pose.arm_l_offset += Vector2(0.0, 12.0) * d
					pose.arm_r_offset += Vector2(0.0, 12.0) * d
					pose.expression = &"neutral"
				else:
					var w := (u - 0.68) / 0.32
					var shake := sin(w * TAU * 3.0) * (1.0 - w)
					pose.body_pos += Vector2(0.0, -8.0 * (1.0 - w))
					pose.head_angle += shake * 0.28
					pose.arm_l_offset += Vector2(-10.0, -14.0) * (1.0 - w)
					pose.arm_r_offset += Vector2(10.0, -14.0) * (1.0 - w)
					pose.expression = &"scared" if w < 0.45 else &"happy"
			"peace_wave":
				var wave := sin(u * TAU * 3.0)
				pose.body_pos += Vector2(-7.0, -4.0) * env_smooth
				pose.body_rot += -0.07 * env_smooth
				pose.head_angle += (-0.14 + wave * 0.06) * env_smooth
				pose.arm_r_offset += Vector2(24.0 + wave * 10.0, -34.0 + absf(wave) * 5.0) * env_smooth
				pose.arm_l_offset += Vector2(-8.0, 6.0) * env_smooth
				pose.expression = &"happy"

			# --- KENGURU ---
			"spring_hop":
				var hop_wave := sin(u * TAU * 2.0)
				var lift := -22.0 * maxf(0.0, hop_wave) + 14.0 * maxf(0.0, -hop_wave)
				pose.body_pos += Vector2(4.0 * hop_wave, lift) * env
				pose.body_rot += -0.08 * hop_wave * env
				pose.body_scale = Vector2(
					pose.body_scale.x * (1.0 - lift * 0.002 * env),
					pose.body_scale.y * (1.0 + lift * 0.002 * env)
				)
				pose.head_angle += 0.14 * hop_wave * env
				pose.arm_l_offset += Vector2(-10.0, -18.0 * maxf(0.0, hop_wave)) * env
				pose.arm_r_offset += Vector2(10.0, -18.0 * maxf(0.0, hop_wave)) * env
				var tap := -10.0 * maxf(0.0, hop_wave) * env
				pose.foot_l_offset += Vector2(0.0, tap * 0.6)
				pose.foot_r_offset += Vector2(0.0, tap)
				pose.foot_r_rot += -0.10 * maxf(0.0, hop_wave) * env
				pose.expression = &"happy"
			"ear_perk_scan":
				var look := sin(u * TAU * 1.5)
				pose.body_pos += Vector2(look * 8.0, -10.0) * env_smooth
				pose.body_rot += look * 0.08 * env_smooth
				# Sharp alert head & ear perk left-then-right
				pose.head_angle += look * 0.28 * env_smooth
				pose.head_bob += Vector2(look * 6.5, -6.0) * env_smooth
				pose.arm_l_offset += Vector2(-8.0, -14.0) * env_smooth
				pose.arm_r_offset += Vector2(8.0, -14.0) * env_smooth
				pose.expression = &"determined"
			"boxer_feint":
				var jab1 := maxf(0.0, sin(u * TAU * 2.0))
				var jab2 := maxf(0.0, -sin(u * TAU * 2.0))
				pose.body_pos += Vector2(10.0 * (jab1 - jab2 * 0.5), -6.0 * (jab1 + jab2)) * env
				pose.body_rot += (0.11 * jab1 - 0.08 * jab2) * env
				pose.head_angle += (-0.12 * jab1 + 0.10 * jab2) * env
				pose.arm_l_offset += Vector2(-22.0 * jab1, -24.0 * jab1) * env
				pose.arm_r_offset += Vector2(26.0 * jab2, -26.0 * jab2) * env
				pose.expression = &"determined"

			# --- SUMO ---
			"shiko_stomp":
				if u < 0.55:
					var lift_u := sin((u / 0.55) * PI)
					pose.body_pos += Vector2(-14.0 * lift_u, -8.0 * lift_u)
					pose.body_rot += -0.12 * lift_u
					pose.head_angle += 0.10 * lift_u
					pose.arm_l_offset += Vector2(-14.0, -12.0) * lift_u
					pose.arm_r_offset += Vector2(18.0, -22.0) * lift_u
					pose.foot_r_offset += Vector2(10.0 * lift_u, -24.0 * lift_u)
					pose.foot_r_rot += -0.22 * lift_u
					pose.expression = &"determined"
				else:
					var stomp_u := (u - 0.55) / 0.45
					var impact := sin(stomp_u * PI)
					pose.body_pos += Vector2(4.0 * impact, 16.0 * impact)
					pose.body_scale = Vector2(
						pose.body_scale.x * (1.0 + 0.075 * impact),
						pose.body_scale.y * (1.0 - 0.065 * impact)
					)
					pose.head_bob += Vector2(0.0, 6.0 * impact)
					pose.arm_l_offset += Vector2(-18.0 * impact, 8.0 * impact)
					pose.arm_r_offset += Vector2(18.0 * impact, 8.0 * impact)
					pose.expression = &"angry"
			"belly_breath":
				var swell := sin(u * PI)
				pose.body_pos += Vector2(0.0, -10.0 * swell)
				pose.body_scale = Vector2(
					pose.body_scale.x * (1.0 + 0.085 * swell),
					pose.body_scale.y * (1.0 + 0.055 * swell)
				)
				pose.head_angle += -0.09 * swell
				pose.head_bob += Vector2(0.0, -5.0 * swell)
				pose.arm_l_offset += Vector2(-22.0 * swell, -16.0 * swell)
				pose.arm_r_offset += Vector2(22.0 * swell, -16.0 * swell)
				pose.expression = &"happy" if u > 0.5 else &"determined"
			"arm_slap":
				var slap := sin(u * TAU * 2.5)
				pose.body_pos += Vector2(slap * 6.0, 7.0 * env)
				pose.head_angle += slap * 0.10 * env
				pose.arm_l_offset += Vector2(14.0 * maxf(0.0, slap) - 12.0 * maxf(0.0, -slap), -16.0 * absf(slap)) * env
				pose.arm_r_offset += Vector2(-14.0 * maxf(0.0, -slap) + 12.0 * maxf(0.0, slap), -16.0 * absf(slap)) * env
				pose.expression = &"angry"

			# --- CHRONOS ---
			"clockwork_windup":
				if u < 0.65:
					var steps: float = floorf((u / 0.65) * 4.0) / 4.0
					pose.body_pos += Vector2(-8.0 * steps, 6.0 * steps)
					pose.body_rot += -0.14 * steps
					pose.head_angle += 0.22 * steps
					pose.arm_l_offset += Vector2(-14.0 * steps, -18.0 * steps)
					pose.arm_r_offset += Vector2(14.0 * steps, 14.0 * steps)
					pose.expression = &"determined"
				else:
					var rel := (u - 0.65) / 0.35
					var spin_osc := sin(rel * TAU * 3.0) * (1.0 - rel)
					pose.body_pos += Vector2(spin_osc * 10.0, -12.0 * (1.0 - rel))
					pose.body_rot += spin_osc * 0.16
					pose.head_angle += -spin_osc * 0.28
					pose.arm_l_offset += Vector2(-18.0 * spin_osc, -22.0 * (1.0 - rel))
					pose.arm_r_offset += Vector2(18.0 * spin_osc, -22.0 * (1.0 - rel))
					pose.expression = &"happy"
			"time_inspect":
				pose.body_pos += Vector2(12.0, 4.0) * env_smooth
				pose.body_rot += 0.11 * env_smooth
				pose.head_angle += (0.24 + 0.08 * sin(u * TAU * 2.0)) * env_smooth
				pose.head_bob += Vector2(7.0, -3.0) * env_smooth
				pose.arm_r_offset += Vector2(20.0, -28.0) * env_smooth
				pose.arm_l_offset += Vector2(-10.0, 6.0) * env_smooth
				pose.expression = &"scared" if u < 0.55 else &"happy"
			"alarm_chime":
				var ring := sin(u * TAU * 8.0) * env
				pose.body_pos += Vector2(ring * 4.0, -9.0 * env)
				pose.head_angle += ring * 0.26
				pose.head_bob += Vector2(ring * 6.0, -5.0 * env)
				pose.arm_l_offset += Vector2(-16.0 - ring * 8.0, -24.0 * env)
				pose.arm_r_offset += Vector2(16.0 + ring * 8.0, -24.0 * env)
				pose.expression = &"happy"

			# --- SAMURAI ---
			"ready_kata":
				pose.body_pos += Vector2(8.0, 12.0) * env_smooth
				pose.body_rot += 0.085 * env_smooth
				pose.head_angle += -0.11 * env_smooth
				pose.arm_l_offset += Vector2(-16.0, -22.0) * env_smooth
				pose.arm_r_offset += Vector2(20.0, -18.0) * env_smooth
				pose.foot_l_offset += Vector2(-4.0, 0.0) * env_smooth
				pose.foot_r_offset += Vector2(4.0, 0.0) * env_smooth
				pose.expression = &"angry" if u > 0.25 and u < 0.75 else &"determined"
			"honor_bow":
				pose.body_pos += Vector2(6.0, 9.0) * env_smooth
				pose.body_rot += 0.14 * env_smooth
				pose.head_angle += 0.18 * env_smooth
				pose.head_bob += Vector2(4.0, 6.0) * env_smooth
				pose.arm_l_offset += Vector2(4.0, 8.0) * env_smooth
				pose.arm_r_offset += Vector2(-4.0, 8.0) * env_smooth
				pose.expression = &"neutral"
			"horizon_check":
				var scan := sin(u * PI)
				pose.body_pos += Vector2(7.0, -8.0) * scan
				pose.body_rot += 0.05 * scan
				pose.head_angle += (-0.16 + 0.08 * cos(u * TAU)) * scan
				pose.head_bob += Vector2(5.0, -4.0) * scan
				pose.arm_r_offset += Vector2(16.0, -24.0) * scan
				pose.expression = &"determined"

	return pose

## PNG proportions stay rigid. Reference clips guide cadence/acting; feet stay planted between small accents.
static func _png_reference_pose(id: String,t: float,act: String,u_time: float,duration: float) -> Dictionary:
	var speed: float={"rasta":.28,"kenguru":.78,"sumo":.22,"chronos":.48,"samurai":.36}[id]
	var phase := t*TAU*speed
	var sway := sin(phase)
	var env := sin(clampf(u_time/maxf(duration,.01),0,1)*PI) if act!="" else 0.0
	var mass := .45 if id=="sumo" else 1.0
	var body := Vector2(sway*2.5*mass,sin(phase*1.4)*1.5*mass)
	var angle := sway*.022
	var left := Vector2(sway*1.5,sin(phase-.4)*2)*mass
	var right := Vector2(sway*1.5,sin(phase+.4)*2)*mass
	var expression := &"neutral"
	if id=="kenguru":
		body.y-=maxf(sin(phase),0)*3+env*2
		angle+=sin(phase*.6)*.025
		left+=Vector2(-3,-5)*env;right+=Vector2(3,-4)*env
		expression=&"happy" if act=="spring_hop" else &"neutral"
	elif id=="rasta":
		angle+=.018+env*.025
		body.y+=env*2
		right+=Vector2(3,-4)*env if act=="peace_wave" else Vector2.ZERO
	elif id=="sumo":
		body.x+=env*1.5;body.y+=env*1.5
		left+=Vector2(-2,1)*env;right+=Vector2(2,1)*env
		expression=&"angry" if act=="arm_slap" else &"neutral"
	elif id=="chronos":
		var tick := (1.0 if int(t*2)%2==0 else -1.0)*exp(-fmod(t*2,1)*9)
		angle+=tick*.009+env*.035
		right+=Vector2(2,-5)*env if act=="time_inspect" else Vector2.ZERO
		expression=&"determined" if act=="time_inspect" else &"neutral"
	elif id=="samurai":
		# Samurobot: disciplined stillness, then crisp accents (kata guard, a short bow, a horizon glance)
		var still := 1.0 - env
		body*=.6+.4*still;angle*=.6
		if act=="ready_kata":
			body+=Vector2(2,3)*env;angle-=.03*env
			left+=Vector2(-3,-6)*env;right+=Vector2(4,-5)*env
			expression=&"angry" if env>.5 else &"neutral"
		elif act=="honor_bow":
			body.y+=2.5*env;angle+=.11*env
			expression=&"neutral"
		elif act=="horizon_check":
			angle-=.04*env
			expression=&"determined"
	return {"body_pos":body,"body_rot":sway*.008*mass,"body_scale":Vector2.ONE,
		"head_angle":angle,"head_bob":Vector2.ZERO,"arm_l_offset":left,"arm_r_offset":right,
		"foot_l_offset":Vector2.ZERO,"foot_r_offset":Vector2.ZERO,"foot_l_rot":0.0,"foot_r_rot":0.0,
		"rig_rot":0.0,"expression":expression,"action":act}
