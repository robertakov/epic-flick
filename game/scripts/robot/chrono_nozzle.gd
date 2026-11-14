class_name ChronoNozzle
extends Node2D
## v32: Chronobot's existing heel thruster pod drawn LARGER and clearer (same brass + ink style as the approved art;
## the art itself is untouched). It sits exactly on the pod of the deformed leg mesh: anchor in leg-texture pixels,
## mapped with the rigid boot transform of VideoRobotPart. Drawn in texture-pixel units (scale = mesh unit).
## The flame (LegExhaust) is placed at the nozzle mouth and only flashes briefly (RobotIdentityFeedback).

## Heel pod centres in the leg textures (assets/robots/rocket/leg_*.png).
const ANCHORS := {&"leg_l": Vector2(166, 208), &"leg_r": Vector2(28, 196)}
const RING_R := 18.0
const BELL := 39.0
## Extra size over the texture scale so the nozzle reads at phone gameplay zoom.
## v35: 1.3 -> 1.9 (visual only - tester: too small to read on a phone; no collider / thrust / momentum change).
const NOZZLE_SCALE := 1.9
const BRASS := Color(0.95, 0.66, 0.18)
const BRASS_HI := Color(1.0, 0.88, 0.5)
const BRASS_DARK := Color(0.62, 0.36, 0.1)
const INK := Color(0.1, 0.06, 0.04)

var side := &"leg_l"
var anchor := Vector2.ZERO


## anchors: per-visual heel pod positions (MK2 art: manifest "nozzle_anchors"), else the base ANCHORS.
func _init(p_side: StringName = &"leg_l", anchors := {}) -> void:
	side = p_side
	var a = anchors.get(String(side), null)
	anchor = Vector2(a[0], a[1]) if a is Array and a.size() >= 2 else ANCHORS.get(side, Vector2.ZERO)
	name = "ChronoNozzle"
	z_index = -1


## Follows the rigid boot of the leg mesh (call after VideoRobotPart.fit_limb).
func sync(part: VideoRobotPart) -> void:
	var end := RigData._v(part.geometry.end)
	position = (anchor - part._frame_shift() - end).rotated(part.terminal_rotation) * part.mesh_unit + part.mesh_end
	rotation = part.terminal_rotation
	scale = Vector2.ONE * part.mesh_unit * NOZZLE_SCALE
	queue_redraw()


## Nozzle mouth in the parent (LegVisual) space: where the flame starts.
func mouth() -> Vector2:
	return position + Vector2(0, BELL).rotated(rotation) * scale.x


func _draw() -> void:
	var bell := PackedVector2Array([Vector2(-10, 2), Vector2(10, 2), Vector2(20, BELL), Vector2(-20, BELL)])
	var ink := PackedVector2Array([Vector2(-13, 0), Vector2(13, 0), Vector2(24, BELL + 3), Vector2(-24, BELL + 3)])
	draw_colored_polygon(ink, INK)
	draw_colored_polygon(bell, BRASS)
	draw_colored_polygon(PackedVector2Array([Vector2(3, 2), Vector2(10, 2), Vector2(20, BELL), Vector2(10, BELL)]), BRASS_DARK)
	draw_line(Vector2(-6, 6), Vector2(-12, BELL - 3), BRASS_HI, 3.0)
	# dark mouth
	draw_set_transform(Vector2(0, BELL), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, 20.0, INK)
	draw_circle(Vector2.ZERO, 14.0, Color(0.28, 0.12, 0.05))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# mounting ring over the original pod (bigger, same look)
	draw_circle(Vector2.ZERO, RING_R + 3.0, INK)
	draw_circle(Vector2.ZERO, RING_R, BRASS)
	draw_circle(Vector2(-4, -4), RING_R * 0.45, BRASS_HI)
	draw_circle(Vector2.ZERO, RING_R * 0.38, BRASS_DARK)
	draw_circle(Vector2.ZERO, RING_R * 0.2, INK)
