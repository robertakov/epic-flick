class_name LevelConfig
extends Resource
## Procedural-but-deterministic track description.

@export var seed := 8812
## Track length after the launch ledge (px). 100 px = 1 m.
@export var length := 52000.0
@export var ledge_length := 2200.0
## Height drop right after the ledge (cliff into the slope).
@export var cliff_drop := 260.0
## Extra downhill tilt added to every track segment (degrees). Tilts the whole profile, so bumps, dips and
## rises keep their shape relative to the slope. 0 = original v0.1-v0.5 track.
@export var slope_bias_deg := 8.0
## Safety clamp for the steepest segment after the bias (degrees).
@export var max_segment_deg := 60.0
## Feature weights: name -> weight. See TerrainBuilder for meaning.
@export var feature_weights := {
	"gentle": 3.0, "steep": 2.2, "flat": 1.2, "rise": 1.4, "dip": 1.6, "bump": 1.6, "kink": 1.2, "ramp": 0.8,
}
## Control point spacing for the spline (px).
@export var sample_step := 20.0
@export var runout_length := 6000.0
@export var px_per_meter := 100.0
