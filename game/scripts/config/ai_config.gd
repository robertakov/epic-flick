class_name AIConfig
extends Resource
## Enemy AI quality model. ONE controller for every opponent; difficulty = a skill value 0..1 (round data +
## hidden adaptive modifier) mapped to decision quality through these low/high pairs (value at skill 0 / skill 1).
## Nothing here touches physics: the AI only decides when to hold / release, like the player.

@export_group("Per-flight errors")
## Std-dev of the landing-angle error chosen for each flight (degrees).
@export var angle_error_deg := Vector2(44.0, 1.6)
## Std-dev of the relative error in the predicted time to touchdown (0.2 = 20%).
@export var timing_error := Vector2(0.24, 0.012)
## Chance per flight of a blunder (a huge orientation mistake: panic / misjudged spin).
@export var blunder_chance := Vector2(0.22, 0.005)
## Low skill judges the slope where it IS instead of where it will land (0 = perfect look-ahead).
@export var naive_slope_mix := Vector2(0.55, 0.0)

@export_group("Reactions")
## Delay between a decision and the actual press / release (s), randomised +-40% per decision.
@export var reaction_delay := Vector2(0.17, 0.026)
## How often the plan is recomputed in the air (s).
@export var replan_interval := Vector2(0.14, 0.04)
## Accepted planned landing-angle error when choosing the least-hold plan (radians).
@export var plan_tolerance := Vector2(0.34, 0.075)

@export_group("Variation")
## Per-attempt "form" (std-dev added to skill for the whole attempt): weak opponents sometimes have a great run,
## strong ones a bad one.
@export var form_spread := Vector2(0.11, 0.035)
## Default preferred lean vs. the slope normal (deg; ~10-34 = power bounce window).
@export var default_lean := 18.0

@export_group("Planner")
## Simulation step and hold-duration resolution of the planner (s). Coarse = cheap on Android.
@export var plan_dt := 0.025
@export var hold_step := 0.05
@export var max_lookahead := 3.0


## Errors shrink faster through the middle skills (ease-out): k = 1 - (1 - s)^skill_curve.
@export var skill_curve := 1.82


@export_group("Campaign distance consistency")
## Below the measured band: bound extreme mistakes while retaining ordinary imperfect play.
@export var protected_angle_scale := 0.14
@export var protected_timing_scale := 0.18
@export var protected_reaction_scale := 0.22
@export var protected_blunder_scale := 0.015
@export var protected_form_scale := 0.22
@export var protected_slope_scale := 0.25
@export var protected_tolerance_scale := 0.45
## Bounded natural long-run error spread, sampled normally; never a prescribed bad landing.
@export var long_run_angle_scale := 1.35
@export var long_run_timing_scale := 1.20
## Past the upper band, smoothly reduce precision by at most this skill amount (never a forced crash).
@export var long_run_skill_drop := 0.14


func at(pair: Vector2, skill: float) -> float:
	var k := 1.0 - pow(1.0 - clampf(skill, 0.0, 1.0), skill_curve)
	return lerpf(pair.x, pair.y, k)
