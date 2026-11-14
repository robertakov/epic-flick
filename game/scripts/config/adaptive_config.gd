class_name AdaptiveConfig
extends Resource
## Hidden adaptive difficulty tuning. The modifier only changes AI decision quality (skill), never physics.

## Smoothing of the recent-performance average (EMA weight of one new result).
@export var smoothing := 0.18
## |average| below this = "about right" -> no change (also gives hysteresis around 0).
@export var dead_band := 0.22
## Bounds of the skill modifier (skill is 0..1; rounds span ~0.10..0.97).
@export var max_up := 0.12
@export var max_down := 0.12
## Margin = (player - best opponent) / max(best opponent, margin_floor_m). |margin| below close_margin = close
## result (win or loss) -> neutral. dominant_margin = a full-strength signal.
@export var close_margin := 0.12
@export var dominant_margin := 0.5
@export var margin_floor_m := 60.0
## Wins: how much remaining HP strengthens the "dominant" signal (0 = ignored).
@export var hp_weight := 0.3
## Wins: attempts needed vs. the round's target attempts (fewer = stronger player). Weight of that signal.
@export var attempts_weight := 0.35
## Per-difficulty target attempts (matches the design targets).
@export var target_attempts := {"normal": 3.0, "hard": 4.5, "boss": 7.0}
