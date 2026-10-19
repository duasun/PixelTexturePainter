extends ConfirmationDialog
signal saved(name: String, image: Image)

func _ready() -> void:
	$Body/Dimensions/New.pressed.connect(func(): $Body/Canvas.new_canvas(int($Body/Dimensions/Width.value),int($Body/Dimensions/Height.value)))
	$Body/Tools/Clear.pressed.connect(func(): $Body/Canvas.new_canvas($Body/Canvas.image.get_width(),$Body/Canvas.image.get_height()))
	confirmed.connect(func(): saved.emit($Body/Tools/Name.text,$Body/Canvas.image.duplicate()))

func open_editor() -> void:
	$Body/Canvas.new_canvas(int($Body/Dimensions/Width.value),int($Body/Dimensions/Height.value))
	$Body/Canvas.ink = Color.WHITE
	$Body/Tools/Name.text = "My brush"
	popup_centered()
