extends ConfirmationDialog
signal saved(image: Image)

func _ready() -> void:
	$Body/Dimensions/New.pressed.connect(func(): $Body/Canvas.new_canvas(int($Body/Dimensions/Width.value),int($Body/Dimensions/Height.value)))
	$Body/Tools/Clear.pressed.connect(func(): $Body/Canvas.new_canvas($Body/Canvas.image.get_width(),$Body/Canvas.image.get_height()))
	$Body/Tools/Ink.color_changed.connect(func(color: Color): $Body/Canvas.ink = color)
	confirmed.connect(func(): saved.emit($Body/Canvas.image.duplicate()))

func open_editor(source: Image, color: Color) -> void:
	$Body/Canvas.set_image(source)
	$Body/Dimensions/Width.set_value($Body/Canvas.image.get_width(),false)
	$Body/Dimensions/Height.set_value($Body/Canvas.image.get_height(),false)
	$Body/Tools/Ink.color = color
	$Body/Canvas.ink = color
	popup_centered()
