extends VBoxContainer
signal load_requested
signal apply_requested
signal settings_changed
signal transform_committed
var source: Image

func _ready() -> void:
	$Load.pressed.connect(func(): load_requested.emit())
	$Apply.pressed.connect(func(): apply_requested.emit())
	$Rotate.pressed.connect(func(): $Angle.set_value(wrapf($Angle.value + 90, -180, 180)); transform_committed.emit())
	$Angle.value_changed.connect(func(_v: float): _preview())
	for field in ["Angle", "Scale", "OffsetX", "OffsetY"]:
		get_node(field).value_changed.connect(func(_v: float): settings_changed.emit())
		get_node(field).value_committed.connect(func(_v: float): transform_committed.emit())

func set_editing_pattern(on: bool) -> void:
	$Apply.text = "Update selected pattern layer" if on else "Create pattern fill layer"
	$Hint.text = "Change direction, scale or offset; release to preview.\nManual paint on this layer stays above the pattern." if on else "Select faces → set direction → create.\nOr click a model face with Texture tool."

func settings() -> Dictionary:
	return {"angle": $Angle.value, "scale": $Scale.value / 100.0,
		"offset": Vector2($OffsetX.value, $OffsetY.value)}

func set_source(image: Image, title: String) -> void:
	source = image
	if image == null:
		$Name.text = "No texture loaded"
		$Preview/Texture.texture = null
		return
	$Name.text = "%s · %d × %d" % [title, image.get_width(), image.get_height()]
	$Preview/Texture.texture = ImageTexture.create_from_image(image)
	_preview()

func restore_settings(saved_settings: Dictionary) -> void:
	$Angle.set_value(float(saved_settings.get("angle", 0)), false)
	$Scale.set_value(float(saved_settings.get("scale", 1)) * 100, false)
	$OffsetX.set_value(float(saved_settings.get("offset_x", 0)), false)
	$OffsetY.set_value(float(saved_settings.get("offset_y", 0)), false)
	_preview()

func _preview() -> void:
	var rect: TextureRect = $Preview/Texture
	rect.pivot_offset = rect.size * 0.5
	rect.rotation_degrees = $Angle.value
