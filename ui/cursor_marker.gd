extends Control
var point := Vector2(-10000,-10000)

func show_at(position_in_view: Vector2) -> void:
	point = position_in_view
	queue_redraw()

func _draw() -> void:
	# Constant screen-space locator remains visible even when one texel is subpixel.
	var marks := PackedVector2Array([point-Vector2(14,0),point-Vector2(7,0),point+Vector2(7,0),point+Vector2(14,0),point-Vector2(0,14),point-Vector2(0,7),point+Vector2(0,7),point+Vector2(0,14)])
	draw_multiline(marks,Color.BLACK,3.0)
	draw_multiline(marks,Color("ffbe61"),1.0)
