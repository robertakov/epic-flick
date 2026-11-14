class_name MomentumRules
extends RefCounted
## v32 momentum: a skill-chain bonus to FORWARD speed, built by consecutive good feet landings.
## The state m (px/s) lives per robot in SpringContactController.momentum (0 at spawn). Per landing event:
##   update: clean feet (both/flat, both/sweet)      m = min(m + G, M)
##           acceptable two-feet (both/normal)       m = min(m + G * NORMAL_GAIN, M)
##           one foot (left / right)                 m unchanged
##           awkward (poor)                          m = m * POOR_KEEP
##           body / arm contact                      m = m * BODY_KEEP
##           head contact or impact >= SEVERE_IMPACT m = 0
##           soft (resting / rolling)                m unchanged
##   boost on every valid feet release (left / right / both) with m > 0, along the surface tangent pointing forward
##   (+x), never vertical:  b = m * clamp(1 - v_fwd / V, 0, 1)   (V = per-robot forward cap: diminishing returns,
##   no runaway; v_fwd <= 0 gets the full m). The result is then held to the existing release-speed guard.
## G = momentum_gain, M = momentum_max, V = momentum_forward_cap (ContactConfig, from RobotDefinition).

const NORMAL_GAIN := 0.4
const POOR_KEEP := 0.5
const BODY_KEEP := 0.2
const SEVERE_IMPACT := 900.0


static func update(m: float, event: Dictionary, gain: float, max_m: float) -> float:
	if not is_finite(m):
		m = 0.0
	var t := StringName(event.get("type", &""))
	var q := StringName(event.get("quality", &""))
	var out := m
	match t:
		&"both":
			out = m + gain * (1.0 if q in [&"flat", &"sweet"] else NORMAL_GAIN)
		&"left", &"right", &"soft":
			out = m
		&"poor":
			out = m * POOR_KEEP
		&"body":
			var head := StringName(event.get("charge_zone", &"")) == &"head" or StringName(event.get("first", &"")) == &"head"
			out = 0.0 if head or float(event.get("impact", 0.0)) >= SEVERE_IMPACT else m * BODY_KEEP
	return clampf(out, 0.0, maxf(max_m, 0.0)) if is_finite(out) else 0.0


static func boost(m: float, v_fwd: float, forward_cap: float) -> float:
	if not (is_finite(m) and is_finite(v_fwd)) or m <= 0.0 or forward_cap <= 0.0:
		return 0.0
	return m * clampf(1.0 - v_fwd / forward_cap, 0.0, 1.0)


## Forward unit tangent of a surface normal (always pointing to +x).
static func forward_tangent(n: Vector2) -> Vector2:
	var t := Vector2(-n.y, n.x)
	return t if t.x >= 0.0 else -t
