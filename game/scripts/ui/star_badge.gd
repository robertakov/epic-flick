class_name StarBadge
extends Control
var gold := false:
	set(value):
		gold=value
		queue_redraw()
var animation: Tween
func _ready() -> void:
	if custom_minimum_size==Vector2.ZERO: custom_minimum_size=Vector2(100,100)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var points := PackedVector2Array()
	var center := size*0.5
	var radius := minf(size.x,size.y)*0.44
	for i in 10:
		points.append(center+Vector2.UP.rotated(i*PI/5)*(radius if i%2==0 else radius*0.46))
	draw_colored_polygon(points,UIController.GOLD if gold else Color(0.62,0.59,0.52))
	points.append(points[0])
	draw_polyline(points,UIController.INK,4,true)
func pop() -> void:
	if animation: animation.kill()
	gold=true
	pivot_offset=size*0.5
	scale=Vector2(0.55,0.55)
	animation=create_tween()
	animation.tween_property(self,"scale",Vector2(1.18,1.18),0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	animation.tween_property(self,"scale",Vector2.ONE,0.16)

