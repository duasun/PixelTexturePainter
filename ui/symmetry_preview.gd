extends Control
var points := PackedVector2Array()

func show_points(value: PackedVector2Array) -> void:
	points = value
	queue_redraw()

func _draw() -> void:
	for point in points:
		draw_arc(point,8.0,0.0,TAU,24,Color(0.02,0.02,0.02,0.95),3.0)
		draw_arc(point,8.0,0.0,TAU,24,Color(0.9,0.65,0.25,0.95),1.5)
		draw_line(point+Vector2(-12,0),point+Vector2(12,0),Color(0.9,0.65,0.25,0.9),1.0)
		draw_line(point+Vector2(0,-12),point+Vector2(0,12),Color(0.9,0.65,0.25,0.9),1.0)
