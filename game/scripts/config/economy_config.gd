class_name EconomyConfig
extends Resource
## Coin economy (free in-game currency only, no real money). All numbers here; campaign first-clear rewards live
## per node in the campaign JSON.

## Free Run: coins = floor(distance_m / meters_per_coin)  (5 -> 500 m = 100 coins).
@export var meters_per_coin := 5.0
## Campaign attempts give NO distance coins (Free Run is the repeatable distance source).
@export var campaign_distance_coins := false
## Replaying an already cleared round and winning again: fraction of its first-clear reward...
@export var replay_reward_fraction := 0.1
## ...halved (x decay) for every further replay win of the same round -> farming dries up quickly.
@export var replay_reward_decay := 0.5
@export var replay_reward_min := 1

## v32 PAID CONTINUE (one per attempt, offered only when affordable, explicit confirmation). Deliberately expensive:
## 600 = a whole Kengurobot, ~3 km of Free Run coins, or several mid-campaign first clears.
@export var continue_price := 600
## HP after the continue as a fraction of max: just above the first limb threshold (0.75) so the robot is whole.
@export var continue_hp_ratio := 0.8
## Spawn protection after the continue (s), on top of "no damage before the first airborne moment".
@export var continue_invuln_s := 2.5
## Gentle forward speed along the slope at the respawn point (px/s) - never a fatal velocity.
@export var continue_speed := 520.0


func free_run_coins(distance_m: float) -> int:
	return int(floor(maxf(distance_m, 0.0) / maxf(meters_per_coin, 0.001)))


## Reward for the n-th (0-based) replay win of a round whose first clear paid `first_clear`.
func replay_reward(first_clear: int, replay_wins_before: int) -> int:
	var v := float(first_clear) * replay_reward_fraction * pow(replay_reward_decay, replay_wins_before)
	return int(floor(v)) if v >= float(replay_reward_min) else 0
