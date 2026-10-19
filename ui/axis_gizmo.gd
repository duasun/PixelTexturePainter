extends Control
## Small camera-relative world-axis indicator; fixed-view buttons live beneath it.
var camera_basis := Basis.IDENTITY

func set_camera_basis(value: Basis) -> void:
	camera_basis = value
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var axes := [Vector3.RIGHT,Vector3.UP,Vector3.BACK]
	var colors := [Color("ed7970"),Color("8fdf8f"),Color("8cb9f5")]
	var labels := ["X","Y","Z"]
	var font := get_theme_default_font()
	for i in 3:
		var axis: Vector3 = axes[i]
		var offset := Vector2(axis.dot(camera_basis.x),-axis.dot(camera_basis.y)) * 34.0
		var color: Color = colors[i]
		draw_line(center-offset,center+offset,color.darkened(0.45),2.0)
		draw_circle(center-offset,3.0,color.darkened(0.45))
		draw_line(center,center+offset,color,3.0)
		draw_circle(center+offset,8.0,color)
		draw_string(font,center+offset+Vector2(-4,4),labels[i],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("202020"))
	draw_circle(center,3.0,Color.WHITE)
