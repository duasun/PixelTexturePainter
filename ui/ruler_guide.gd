extends Control
## A screen-space guide for a Shift-constrained stroke in either viewport.
var start := Vector2.ZERO
var finish := Vector2.ZERO
var active := false

func set_segment(first: Vector2, last: Vector2, enabled: bool) -> void:
	start = first
	finish = last
	active = enabled
	queue_redraw()

func _draw() -> void:
	if not active: return
	draw_line(start,finish,Color(0.03,0.03,0.03,0.9),5.0)
	draw_line(start,finish,Color(1.0,0.65,0.2,1.0),2.0)
	draw_circle(start,3.0,Color.WHITE)
	draw_circle(finish,3.0,Color.WHITE)
