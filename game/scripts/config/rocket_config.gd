class_name RocketConfig
extends Resource
## Final jet-head phase.

## Initial speed added along the head's facing (its local up axis in world space).
@export var launch_impulse := 1500.0
## Thrust acceleration along the head's facing while the jet burns (px/s^2).
@export var thrust := 2300.0
@export var thrust_time := 1.15
## Fraction of the robot's velocity the head inherits.
@export var inherit_velocity := 0.6
@export var linear_damp := 0.06
## Strong angular damping keeps the chosen direction during the burn (no steering).
@export var angular_damp := 4.0
@export var bounce := 0.35
@export var friction := 0.6
@export var radius := 46.0
@export var mass := 0.6
## Attempt ends when the head is slower than end_speed for end_rest_time, or after max_time.
@export var end_speed := 45.0
@export var end_rest_time := 0.7
@export var max_time := 10.0
